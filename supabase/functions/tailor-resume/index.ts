// S-4: rewrite a resume for one posting.
//
// The base resume is never touched. The result is a row in resume_versions —
// one per (base resume, job) — so a bad tailoring pass can never cost anyone
// the document they actually uploaded.
//
// Three things happen after the model returns, in order, and all three matter:
//   1. checkFabrication verifies the output against the source. Instructions
//      are not a guarantee, and this is a document a person sends to an
//      employer under their own name.
//   2. applyOverrides puts the candidate's own rewrites back on top, so an
//      edit they made once is not quietly re-generated away.
//   3. the version is upserted, replacing any earlier tailoring for this job.

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse } from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { callStructured } from "../_shared/openai.ts";
import { selectResume } from "../_shared/resume_select.ts";
import { truncate } from "../_shared/answer_prompts.ts";
import {
  applyOverrides,
  bulletKey,
  checkFabrication,
  type SourceEmployer,
  TAILOR_SCHEMA,
  tailorSystemPrompt,
  type TailoredResume,
} from "../_shared/resume_tailor.ts";

type RequestBody = { jobId: string; resumeId?: string | null };

const JD_MAX_CHARS = 8000;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonResponse({ error: "Unauthorized" }, 401);

    const body = (await request.json().catch(() => ({}))) as RequestBody;
    const jobId = body.jobId?.trim();
    if (!jobId) return jsonResponse({ error: "jobId is required" }, 400);

    const admin = createAdminClient();

    if (!(await configFlag(admin, "resume_tailoring_enabled", true))) {
      return jsonResponse({ available: false, reason: "disabled" });
    }

    const { data: job, error: jobError } = await admin
      .from("jobs")
      .select("id, title, company_name, description")
      .eq("id", jobId)
      .maybeSingle();
    if (jobError) throw jobError;
    if (!job) return jsonResponse({ error: "Job not found" }, 404);

    const resume = await selectResume<{
      id: string;
      parsed_json: Record<string, unknown> | null;
      bullet_overrides: Record<string, string> | null;
    }>(admin, user.id, {
      columns: "id, parsed_json, bullet_overrides",
      requestedId: body.resumeId,
      requireParsed: true,
    });
    if (!resume?.parsed_json) {
      return jsonResponse({ available: false, reason: "no_resume" });
    }

    const sourceEmployers = (resume.parsed_json.employers ?? []) as SourceEmployer[];
    const hasBullets = sourceEmployers.some((e) => (e.bullets ?? []).length > 0);
    if (!hasBullets) {
      // Parsed before S-4, or a resume with no bullet points at all. Nothing
      // to rewrite, and a "tailored" resume that only reorders skills would
      // misrepresent what happened.
      return jsonResponse({ available: false, reason: "no_bullets" });
    }

    // Keys are computed here, not by the model. Asking it to hash would be
    // asking it to be a hash function, and a wrong key silently orphans the
    // candidate's overrides.
    const keyed = sourceEmployers.map((e) => ({
      company: e.company ?? "",
      title: e.title ?? "",
      bullets: (e.bullets ?? []).filter((b) => b?.trim()).map((b) => ({
        key: bulletKey(b),
        text: b,
      })),
    }));

    let tailored: TailoredResume;
    try {
      tailored = await callStructured<TailoredResume>({
        systemPrompt: tailorSystemPrompt(),
        userPrompt: JSON.stringify({
          JOB: {
            title: job.title,
            company: job.company_name,
            description: truncate(job.description, JD_MAX_CHARS),
          },
          RESUME: {
            skills: resume.parsed_json.skills ?? [],
            education: resume.parsed_json.education ?? [],
            employment: keyed,
          },
        }, null, 2),
        schemaName: "tailored_resume",
        schema: TAILOR_SCHEMA,
        maxOutputTokens: 3500,
      });
    } catch (error) {
      console.error("tailor failed", jobId, error);
      return jsonResponse({ available: false, reason: "tailor_failed" });
    }

    const audit = checkFabrication(tailored, sourceEmployers);
    if (!audit.ok) {
      // Refused, not repaired. A resume with an invented employer or an
      // inflated title is the single worst thing this product could produce,
      // and there is no partial version of it worth shipping.
      console.error("tailor rejected for fabrication", jobId, JSON.stringify({
        added: audit.addedEmployers,
        titles: audit.changedTitles,
        invented: audit.inventedBullets.length,
      }));
      return jsonResponse({
        available: false,
        reason: "fabrication_detected",
        detail: {
          addedEmployers: audit.addedEmployers,
          changedTitles: audit.changedTitles,
          inventedBullets: audit.inventedBullets.length,
        },
      });
    }

    const withOverrides = applyOverrides(tailored, resume.bullet_overrides);

    const { data: version, error: versionError } = await admin
      .from("resume_versions")
      .upsert(
        {
          profile_id: user.id,
          base_resume_id: resume.id,
          job_id: jobId,
          label: `${job.company_name} — ${job.title}`.slice(0, 120),
          content: withOverrides,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "base_resume_id,job_id" },
      )
      .select("id")
      .single();
    if (versionError) throw versionError;

    return jsonResponse({
      available: true,
      versionId: version.id,
      content: withOverrides,
      keywordsCovered: tailored.keywords_covered ?? [],
      keywordsStillMissing: tailored.keywords_still_missing ?? [],
      // Reported, not blocked — omitting an irrelevant role is a legitimate
      // tailoring decision, but the candidate should know it happened.
      droppedEmployers: audit.droppedEmployers,
      needsReview: true,
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

async function configFlag(
  admin: ReturnType<typeof createAdminClient>,
  key: string,
  fallback: boolean,
): Promise<boolean> {
  const { data } = await admin
    .from("app_config")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  if (data?.value == null) return fallback;
  return String(data.value).toLowerCase() !== "false";
}
