// Pitch carousel generation.
//
// For each active job without a current carousel (or whose source hash
// changed), produce a 3–6 slide carousel:
//   1. Compute source_hash from job + company + lead fund fields. Skip if
//      it matches the stored carousel's source_hash.
//   2. If the JD has a description → one OpenAI structured-output call to
//      extract {hook, blurb, responsibilities, requirements, perks}.
//      Else → skip the LLM and use rule-based content (title as hook,
//      first sentence as blurb when present, empty arrays).
//   3. Assemble fixed slide types per the spec; 3 minimum (cover +
//      about_company + details), 6 maximum.
//   4. Pick a theme deterministically from company_id, biased by industry.
//   5. Upsert by job_id (write-replace; regen is intentional).
//
// Cost & throughput: gpt-4o-mini at ~$0.00015/job. We process MAX_PER_RUN
// sequentially per invocation to keep memory low (same reason
// enrich-descriptions caps at 30). One daily cron run handles steady-state.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { pickTheme } from "../_shared/themes.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";
import { callStructured } from "../_shared/openai.ts";
import { insertFounderContacts } from "../_shared/contacts.ts";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";

const RUN_BUDGET_MS = 50_000;
const MAX_PER_RUN = 30;
// Each OpenAI call hits a per-request CPU/memory cost on the worker plus a
// ~2s round trip. Sequential is intentional — concurrent calls have crashed
// our edge functions today via WORKER_RESOURCE_LIMIT.
const OPENAI_TIMEOUT_MS = 15_000;

type RequestBody = { job_id?: string };

type JobRow = {
  id: string;
  company_id: string | null;
  experience_level: string | null;
  work_mode: string | null;
  job_function: string | null;
  company_name: string | null;
  title: string | null;
  description: string | null;
  location: string | null;
  compensation_text: string | null;
  compensation_min_annual: number | null;
  compensation_max_annual: number | null;
  compensation_min_hourly: number | null;
  compensation_max_hourly: number | null;
  employment_type: string | null;
  apply_url: string | null;
};

type CompanyRow = {
  id: string;
  name: string;
  domain: string | null;
  stage: string | null;
  industry: string | null;
};

type LLMContent = {
  hook: string;
  company_blurb: string;
  youd_line: string;
  experience_level: string;
  work_mode: string;
  // Free role classification riding the carousel call — fills the 40% of
  // titles the regex can't place, so the feed's role filters work.
  job_function: string;
  responsibilities: string[];
  requirements: string[];
  perks: string[];
  // Free founder extraction riding the carousel call — JDs sometimes name
  // founders ("work directly with our co-founder Jane…"). Feeds
  // company_contacts; never affects slides.
  founders: Array<{
    full_name: string;
    role_title: string | null;
    confidence: number;
  }>;
};

type Slide =
  | {
      type: "cover";
      order: number;
      company: string;
      role: string;
      hook: string;
      location?: string;
      compensation?: string;
      youd_line?: string;
      experience?: string;
      work_mode?: string;
    }
  | {
      type: "about_company";
      order: number;
      company: string;
      blurb: string;
      stage?: string;
      industry?: string;
      backed_by?: string;
    }
  | { type: "role"; order: number; bullets: string[] }
  | { type: "requirements"; order: number; bullets: string[] }
  | { type: "perks"; order: number; bullets: string[] }
  | { type: "founder"; order: number; name: string; role_title?: string }
  | {
      type: "details";
      order: number;
      location?: string;
      compensation?: string;
      employment_type?: string;
    };

type Outcome = {
  job_id: string;
  status: "generated" | "fallback" | "skipped" | "error";
  theme_id: string | null;
  slide_count: number | null;
  error: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const body: RequestBody = await request.json().catch(() => ({}));
  const admin = createAdminClient();

  // Selection via the get_jobs_needing_carousel queue RPC: jobs with no
  // carousel, or edited since their carousel was generated, description-
  // bearing first. The previous approach (90 most-recently-seen jobs)
  // wedged permanently once that window was covered — every run from
  // 2026-06-29 to 2026-07-09 processed zero jobs while 11k+ sat waiting.
  // The source-hash re-check below stays as the final skip guard.
  let candidateIds: string[];
  if (body.job_id) {
    candidateIds = [body.job_id];
  } else {
    const { data: queue, error: queueError } = await admin.rpc("get_jobs_needing_carousel", {
      p_limit: MAX_PER_RUN * 3, // overfetch — some skip on hash match
    });
    if (queueError) return jsonError(`carousel queue failed: ${queueError.message}`);
    candidateIds = ((queue ?? []) as Array<{ id: string }>).map((r) => r.id);
  }

  if (candidateIds.length === 0) {
    return jsonResponse({
      summary: { event: "generate_carousel_run", processed: 0, generated: 0, fallback: 0, skipped: 0, errored: 0 },
      outcomes: [],
    });
  }

  const { data: jobs, error: jobsError } = await admin
    .from("jobs")
    .select(
      "id, company_id, company_name, title, description, location, compensation_text, compensation_min_annual, compensation_max_annual, compensation_min_hourly, compensation_max_hourly, employment_type, apply_url, experience_level, work_mode, job_function",
    )
    .in("id", candidateIds)
    .eq("is_active", true)
    .not("company_id", "is", null);
  if (jobsError) return jsonError(`load jobs failed: ${jobsError.message}`);

  // Restore the queue's priority order (description-bearing first) — the
  // .in() fetch returns rows in arbitrary order.
  const rank = new Map(candidateIds.map((id, i) => [id, i]));
  const jobRows = ((jobs ?? []) as JobRow[])
    .sort((a, b) => (rank.get(a.id) ?? 0) - (rank.get(b.id) ?? 0));
  if (jobRows.length === 0) {
    return jsonResponse({
      summary: { event: "generate_carousel_run", processed: 0, generated: 0, fallback: 0, skipped: 0, errored: 0 },
      outcomes: [],
    });
  }

  // Bulk-load existing carousels and companies in one trip each.
  const jobIds = jobRows.map((j) => j.id);
  const companyIds = Array.from(new Set(jobRows.map((j) => j.company_id).filter(Boolean) as string[]));

  const [carouselsRes, companiesRes, fundsRes, contactsRes] = await Promise.all([
    admin.from("carousels").select("job_id, source_hash").in("job_id", jobIds),
    admin.from("companies").select("id, name, domain, stage, industry").in("id", companyIds),
    admin
      .from("company_funds")
      .select("company_id, funds(name)")
      .in("company_id", companyIds),
    admin
      .from("company_contacts")
      .select("company_id, full_name, first_name, role_title, source, email_status, confidence")
      .in("company_id", companyIds)
      .not("full_name", "is", null)
      .not("email_status", "in", "(bounced,suppressed)"),
  ]);

  if (carouselsRes.error) return jsonError(`load carousels failed: ${carouselsRes.error.message}`);
  if (companiesRes.error) return jsonError(`load companies failed: ${companiesRes.error.message}`);
  if (fundsRes.error) return jsonError(`load funds failed: ${fundsRes.error.message}`);
  if (contactsRes.error) return jsonError(`load contacts failed: ${contactsRes.error.message}`);

  // Best named contact per company for the founder slide: verified posting
  // emails first, then confidence. Companies at big-co stages don't get a
  // founder slide — the founder-pitch path is gated off for them client-side
  // (F8), so the slide would dead-end.
  type ContactRow = {
    company_id: string;
    full_name: string;
    first_name: string | null;
    role_title: string | null;
    source: string;
    email_status: string;
    confidence: number | null;
  };
  const bestContactByCompany = new Map<string, ContactRow>();
  for (const contact of (contactsRes.data ?? []) as ContactRow[]) {
    const current = bestContactByCompany.get(contact.company_id);
    if (!current || contactRank(contact) < contactRank(current)) {
      bestContactByCompany.set(contact.company_id, contact);
    }
  }

  const existingHashByJobId = new Map<string, string>();
  for (const row of (carouselsRes.data ?? []) as Array<{ job_id: string; source_hash: string }>) {
    existingHashByJobId.set(row.job_id, row.source_hash);
  }

  const companyById = new Map<string, CompanyRow>();
  for (const c of (companiesRes.data ?? []) as CompanyRow[]) companyById.set(c.id, c);

  // First fund linked per company becomes the "Backed by" chip. Stable
  // order isn't critical — most companies are linked to one fund anyway.
  const firstFundByCompanyId = new Map<string, string>();
  for (const row of (fundsRes.data ?? []) as Array<{ company_id: string; funds: { name?: string } | null }>) {
    if (firstFundByCompanyId.has(row.company_id)) continue;
    const name = row.funds?.name;
    if (name) firstFundByCompanyId.set(row.company_id, name);
  }

  const outcomes: Outcome[] = [];
  const startedAt = Date.now();
  let processed = 0;

  for (const job of jobRows) {
    if (processed >= MAX_PER_RUN) break;
    if (!body.job_id && Date.now() - startedAt > RUN_BUDGET_MS) break;

    const company = job.company_id ? companyById.get(job.company_id) : null;
    if (!company) {
      outcomes.push({ job_id: job.id, status: "skipped", theme_id: null, slide_count: null, error: "company missing" });
      continue;
    }
    const fundName = firstFundByCompanyId.get(company.id) ?? null;
    const founderContact = bestContactByCompany.get(company.id) ?? null;
    const founder = founderContact
      ? { full_name: founderContact.full_name, role_title: founderContact.role_title }
      : null;

    const sourceHash = await computeSourceHash(job, company, fundName, founder?.full_name ?? null);
    if (existingHashByJobId.get(job.id) === sourceHash) {
      // DB-P1-5: content unchanged — refresh generated_at so this job
      // actually leaves the needs-carousel queue instead of re-surfacing in
      // the same 90-job window every 30-minute run.
      await admin
        .from("carousels")
        .update({ generated_at: new Date().toISOString() })
        .eq("job_id", job.id);
      outcomes.push({ job_id: job.id, status: "skipped", theme_id: null, slide_count: null, error: null });
      continue;
    }

    processed += 1;

    let llmContent: LLMContent | null = null;
    let llmError: string | null = null;
    if (job.description && job.description.trim().length > 0 && OPENAI_API_KEY) {
      try {
        llmContent = await extractWithLLM(job);
      } catch (error) {
        llmError = (error as Error).message;
      }
    }

    const usedFallback = !llmContent;
    const content = llmContent ?? fallbackContent(job);
    const slides = assembleSlides(job, company, fundName, content, founder);
    const themeId = pickTheme(company.id, company.industry);

    // Backfill experience_level/work_mode/job_function on the job from the
    // LLM (it read the full JD; the ingest pass only saw the title). Fill
    // nulls only, and
    // do it BEFORE the carousel upsert: jobs.updated_at bumps on update, and
    // the queue RPC treats updated_at > carousels.generated_at as "needs
    // regeneration" — updating after the upsert would loop this job forever.
    if (llmContent) {
      const jobPatch: Record<string, string> = {};
      if (!job.experience_level && llmContent.experience_level) {
        jobPatch.experience_level = llmContent.experience_level;
      }
      if (!job.work_mode && llmContent.work_mode) {
        jobPatch.work_mode = llmContent.work_mode;
      }
      const validFunctions = new Set([
        "engineering", "design", "product", "science", "sales", "marketing",
        "support", "operations", "hr", "finance", "legal",
      ]);
      if (!job.job_function && validFunctions.has(llmContent.job_function)) {
        jobPatch.job_function = llmContent.job_function;
      }
      if (Object.keys(jobPatch).length > 0) {
        const { error: patchError } = await admin.from("jobs").update(jobPatch).eq("id", job.id);
        if (patchError) {
          console.error(JSON.stringify({
            event: "job_classifier_backfill_failed",
            job_id: job.id,
            error: patchError.message,
          }));
        }
      }
    }

    const { error: upsertError } = await admin
      .from("carousels")
      .upsert(
        {
          job_id: job.id,
          theme_id: themeId,
          slide_count: slides.length,
          content: slides,
          source_hash: sourceHash,
          status: usedFallback ? "fallback" : "generated",
          generated_at: new Date().toISOString(),
        },
        { onConflict: "job_id" },
      );

    if (upsertError) {
      outcomes.push({
        job_id: job.id,
        status: "error",
        theme_id: themeId,
        slide_count: slides.length,
        error: upsertError.message,
      });
      continue;
    }

    // Tier-1 founder contacts (free — extracted by the same LLM call).
    // Failure-isolated: a contact insert problem never fails the carousel.
    if (llmContent && llmContent.founders.length > 0) {
      try {
        await insertFounderContacts(admin, {
          companyId: company.id,
          domain: company.domain,
          founders: llmContent.founders,
          source: "llm_job_listing",
        });
      } catch (error) {
        console.error(JSON.stringify({
          event: "founder_contact_insert_failed",
          company_id: company.id,
          job_id: job.id,
          error: (error as Error).message,
        }));
      }
    }

    outcomes.push({
      job_id: job.id,
      status: usedFallback ? "fallback" : "generated",
      theme_id: themeId,
      slide_count: slides.length,
      error: llmError,
    });
  }

  const summary = {
    event: "generate_carousel_run",
    processed,
    generated: outcomes.filter((o) => o.status === "generated").length,
    fallback: outcomes.filter((o) => o.status === "fallback").length,
    skipped: outcomes.filter((o) => o.status === "skipped").length,
    errored: outcomes.filter((o) => o.status === "error").length,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));
  await recordPipelineRun(admin, "generate-carousel", startedAt, summary, summary.errored);

  return jsonResponse({ summary, outcomes });
});

function compensationDisplay(job: JobRow): string | null {
  if (job.compensation_text) return job.compensation_text;
  const fmt = (n: number) => `$${Math.round(n / 1000)}k`;
  if (job.compensation_min_annual && job.compensation_max_annual) {
    return `${fmt(job.compensation_min_annual)}–${fmt(job.compensation_max_annual)}`;
  }
  if (job.compensation_min_hourly && job.compensation_max_hourly) {
    return `$${job.compensation_min_hourly}–$${job.compensation_max_hourly}/hr`;
  }
  return null;
}

function employmentDisplay(raw: string | null): string | null {
  if (!raw) return null;
  if (raw === "full_time") return "Full-time";
  if (raw === "part_time") return "Part-time";
  if (raw === "contract") return "Contract";
  return raw;
}

const BIG_CO_STAGES = new Set(["1000+ employees", "acquisition", "ipo"]);

function contactRank(c: { source: string; email_status: string; confidence: number | null }): number {
  // Lower is better: verified posting emails, then verified anything, then
  // by confidence descending.
  if (c.source === "posting_email") return 0;
  if (c.email_status === "verified") return 1;
  return 2 + (1 - (c.confidence ?? 0));
}

function assembleSlides(
  job: JobRow,
  company: CompanyRow,
  fundName: string | null,
  content: LLMContent,
  founder: { full_name: string; role_title: string | null } | null,
): Slide[] {
  const slides: Slide[] = [];
  const comp = compensationDisplay(job);
  const employment = employmentDisplay(job.employment_type);

  slides.push({
    type: "cover",
    order: slides.length + 1,
    company: company.name,
    role: job.title ?? "Open role",
    hook: content.hook || (job.title ?? "Open role"),
    ...(job.location ? { location: job.location } : {}),
    ...(comp ? { compensation: comp } : {}),
    ...(content.youd_line ? { youd_line: content.youd_line } : {}),
    // LLM (reads the full JD) wins over the title-keyword pass for display.
    ...((content.experience_level || job.experience_level)
      ? { experience: (content.experience_level || job.experience_level) as string }
      : {}),
    ...((content.work_mode || job.work_mode)
      ? { work_mode: (content.work_mode || job.work_mode) as string }
      : {}),
  });

  slides.push({
    type: "about_company",
    order: slides.length + 1,
    company: company.name,
    blurb: content.company_blurb || "",
    ...(company.stage ? { stage: company.stage } : {}),
    ...(company.industry ? { industry: company.industry } : {}),
    ...(fundName ? { backed_by: fundName } : {}),
  });

  if (content.responsibilities.length > 0) {
    slides.push({ type: "role", order: slides.length + 1, bullets: content.responsibilities });
  }

  if (content.requirements.length > 0) {
    slides.push({ type: "requirements", order: slides.length + 1, bullets: content.requirements });
  }

  // Perks were extracted by the LLM all along but never emitted. Old app
  // builds decode this as an unknown slide and skip it safely.
  if (content.perks.length > 0) {
    slides.push({ type: "perks", order: slides.length + 1, bullets: content.perks });
  }

  // Founder slide (F7): only for startup-stage companies — the pitch CTA is
  // gated off for big-cos client-side, so the slide would dead-end there.
  if (founder && !BIG_CO_STAGES.has(company.stage ?? "")) {
    slides.push({
      type: "founder",
      order: slides.length + 1,
      name: founder.full_name,
      ...(founder.role_title ? { role_title: founder.role_title } : {}),
    });
  }

  // Always emit the details slide — the schema requires a 3-slide minimum
  // (cover + about_company + details). When all three sub-fields are missing
  // the slide still renders as a "Tap to apply" footer.
  slides.push({
    type: "details",
    order: slides.length + 1,
    ...(job.location ? { location: job.location } : {}),
    ...(comp ? { compensation: comp } : {}),
    ...(employment ? { employment_type: employment } : {}),
  });

  return slides;
}

function fallbackContent(job: JobRow): LLMContent {
  const blurb = job.description ? firstSentence(job.description) : "";
  return {
    hook: job.title ?? "Open role",
    company_blurb: blurb,
    youd_line: "",
    experience_level: "",
    job_function: "",
    work_mode: "",
    responsibilities: [],
    requirements: [],
    perks: [],
    founders: [],
  };
}

function firstSentence(text: string): string {
  const clean = text.replace(/\s+/g, " ").trim();
  const match = clean.match(/^[^.!?]{20,200}[.!?]/);
  return match ? match[0].trim() : clean.slice(0, 160);
}

async function computeSourceHash(
  job: JobRow,
  company: CompanyRow,
  fundName: string | null,
  founderName: string | null,
): Promise<string> {
  const payload = JSON.stringify({
    // Format version: bump to force regeneration of every carousel when the
    // slide structure changes (v2 = perks slide; v3 = fact-first cover
    // fields + casual voice; v4 = founder slide). Regen drains at
    // MAX_PER_RUN/day via cron; invoke the function manually in a loop to
    // drain faster after deploying a bump.
    v: 4,
    t: job.title,
    d: job.description,
    l: job.location,
    c: job.compensation_text,
    cmina: job.compensation_min_annual,
    cmaxa: job.compensation_max_annual,
    cminh: job.compensation_min_hourly,
    cmaxh: job.compensation_max_hourly,
    et: job.employment_type,
    cn: company.name,
    cs: company.stage,
    ci: company.industry,
    f: fundName,
    fo: founderName,
  });
  const data = new TextEncoder().encode(payload);
  const hashBuf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function extractWithLLM(job: JobRow): Promise<LLMContent> {
  const systemPrompt =
    "You write short, swipeable job carousels for a Gen Z job app. " +
    "Voice: like texting a friend about a cool job you spotted — warm, direct, " +
    "second person, contractions, sentence case, zero corporate speak. " +
    "BANNED words/phrases: synergy, fast-paced environment, rockstar, ninja, guru, " +
    "self-starter, wear many hats, dynamic, passionate, leverage, stakeholders, " +
    "best-in-class, cutting-edge, mission-critical. " +
    "Rules: use ONLY information present in the input. Never invent facts, perks, or numbers. " +
    "If something isn't supported by the input, return an empty string or array. " +
    "Respect every length limit. Short beats complete. No hashtags. At most one emoji total across all fields. " +
    "hook: one intriguing line about the role, no title repeat. " +
    "company_blurb: what the company does, one plain sentence, ONLY if the JD says so. " +
    "youd_line: one line starting with the word you'd, describing the single most concrete thing " +
    "this person would actually do (e.g. you'd own the mobile app end to end). " +
    "experience_level: how senior this role reads from the requirements — one of " +
    "intern, entry, mid, senior, staff, exec — or empty string if the JD doesn't say. " +
    "entry means 0-2 years or new grad friendly; mid means 2-5 years. " +
    "work_mode: remote, hybrid, or onsite ONLY if the JD states it; else empty string. " +
    "job_function: which team this role belongs to — one of engineering, design, product, science, " +
    "sales, marketing, support, operations, hr, finance, legal — pick the closest fit from the title " +
    "and JD; empty string only when the role genuinely fits none (e.g. drivers, retail floor staff). " +
    "responsibilities: what they'd actually do, short punchy phrases. " +
    "requirements: the few things that genuinely matter, not the full wishlist. " +
    "founders: people the JD explicitly names as founder, co-founder, or CEO of THIS company — " +
    "never guess from context, never include hiring managers or team leads; empty array when none are named. " +
    "confidence: 0-1, how explicit the naming is. " +
    "Return only JSON.";

  const userPrompt = JSON.stringify({
    company: job.company_name,
    role: job.title,
    location: job.location,
    compensation: compensationDisplay(job),
    employment_type: job.employment_type,
    job_description: job.description,
  });

  const parsed = await callStructured<LLMContent>({
    systemPrompt,
    userPrompt,
    schemaName: "carousel_content",
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["hook", "company_blurb", "youd_line", "experience_level", "work_mode", "job_function", "responsibilities", "requirements", "perks", "founders"],
      properties: {
        hook: { type: "string", maxLength: 70 },
        company_blurb: { type: "string", maxLength: 120 },
        youd_line: { type: "string", maxLength: 80 },
        experience_level: { type: "string", enum: ["intern", "entry", "mid", "senior", "staff", "exec", ""] },
        work_mode: { type: "string", enum: ["remote", "hybrid", "onsite", ""] },
        job_function: { type: "string", enum: ["engineering", "design", "product", "science", "sales", "marketing", "support", "operations", "hr", "finance", "legal", ""] },
        responsibilities: { type: "array", maxItems: 4, items: { type: "string", maxLength: 70 } },
        requirements: { type: "array", maxItems: 4, items: { type: "string", maxLength: 60 } },
        perks: { type: "array", maxItems: 3, items: { type: "string", maxLength: 50 } },
        founders: {
          type: "array",
          maxItems: 3,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["full_name", "role_title", "confidence"],
            properties: {
              full_name: { type: "string", maxLength: 80 },
              role_title: { type: ["string", "null"], maxLength: 60 },
              confidence: { type: "number" },
            },
          },
        },
      },
    },
    maxOutputTokens: 700,
    timeoutMs: OPENAI_TIMEOUT_MS,
  });
  return {
    hook: (parsed.hook ?? "").trim(),
    company_blurb: (parsed.company_blurb ?? "").trim(),
    youd_line: (parsed.youd_line ?? "").trim(),
    experience_level: (parsed.experience_level ?? "").trim(),
    work_mode: (parsed.work_mode ?? "").trim(),
    responsibilities: (parsed.responsibilities ?? []).map((s) => s.trim()).filter(Boolean),
    requirements: (parsed.requirements ?? []).map((s) => s.trim()).filter(Boolean),
    perks: (parsed.perks ?? []).map((s) => s.trim()).filter(Boolean),
    founders: (parsed.founders ?? []).filter((f) => f.full_name?.trim()),
  };
}
