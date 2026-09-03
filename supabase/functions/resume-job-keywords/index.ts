// S-2: what this job asks for, and what the candidate's resume shows.
//
// Requirement terms are a property of the job, so they are extracted once by
// the first candidate to open it and cached in job_keywords forever after.
// The per-candidate half — the diff — is pure and free (_shared/keyword_match).
//
// Returns an EXPLAINABLE score. The embedding-based job_match_scores RPC is a
// better similarity measure but says nothing a candidate can act on; this one
// names the terms. They answer different questions and both are worth having.

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse } from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { selectResume } from "../_shared/resume_select.ts";
import { callStructured } from "../_shared/openai.ts";
import { computeContentHash } from "../_shared/ats/compensation.ts";
import {
  diffKeywords,
  type JobKeyword,
  rankMissing,
} from "../_shared/keyword_match.ts";

type RequestBody = { jobId: string };

// Below this a description is a stub — a title and a "click to apply", which
// several boards emit. Extracting from it produces confident nonsense.
const MIN_DESCRIPTION_CHARS = 200;

// Enough to cover a thorough requirements section without turning the gap
// list into homework. Most JDs yield 8-15 real terms.
const MAX_KEYWORDS = 20;

const EXTRACTION_SYSTEM_PROMPT =
  `Extract the concrete requirements a recruiter or ATS would screen this ` +
  `application on.

INCLUDE: technical skills, tools, languages, frameworks, platforms, ` +
`certifications, degrees, and domain expertise that the posting actually names.

EXCLUDE: soft skills ("team player", "strong communicator", "self-starter"), ` +
`company benefits, EEO boilerplate, and anything that is not a checkable ` +
`qualification. These are not screened on and listing them as gaps wastes the ` +
`candidate's attention.

Mark importance "required" only when the posting frames it as a must ` +
`("required", "must have", "X+ years of"). Everything framed as a plus, ` +
`bonus, or nice-to-have is "preferred".

Use the posting's own wording for term, but drop qualifiers: "5+ years of ` +
`Python" becomes "Python". Prefer the common name over an abbreviation the ` +
`posting invented. Return at most ${MAX_KEYWORDS} terms, most important first.`;

const EXTRACTION_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: ["keywords"],
  properties: {
    keywords: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["term", "kind", "importance"],
        properties: {
          term: { type: "string" },
          kind: { type: "string", enum: ["skill", "tool", "credential", "domain"] },
          importance: { type: "string", enum: ["required", "preferred"] },
        },
      },
    },
  },
};

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

    const { data: job, error: jobError } = await admin
      .from("jobs")
      .select("id, description")
      .eq("id", jobId)
      .maybeSingle();
    if (jobError) throw jobError;
    if (!job) return jsonResponse({ error: "Job not found" }, 404);

    const description = (job.description ?? "").trim();
    if (description.length < MIN_DESCRIPTION_CHARS) {
      // Roughly 16k jobs in this corpus have no usable description. Saying so
      // is honest; scoring them 0% would read as "you are a terrible fit".
      return jsonResponse({ available: false, reason: "no_description" });
    }

    const keywords = await loadOrExtractKeywords(admin, jobId, description);
    if (!keywords) {
      return jsonResponse({ available: false, reason: "extraction_failed" });
    }

    const resume = await selectResume<{
      parsed_json: Record<string, unknown> | null;
      parsed_text: string | null;
    }>(
      admin,
      user.id,
      { columns: "parsed_json, parsed_text", requireParsed: true },
    );

    if (!resume) {
      return jsonResponse({ available: false, reason: "no_resume" });
    }

    const gap = diffKeywords(keywords, {
      parsedText: resume.parsed_text,
      parsedJson: resume.parsed_json,
    });

    return jsonResponse({
      available: true,
      coverage: gap.coverage,
      requiredTotal: gap.requiredTotal,
      requiredCovered: gap.requiredCovered,
      covered: gap.covered.map((k) => k.term),
      missing: rankMissing(gap.missing).map((k) => ({
        term: k.term,
        importance: k.importance ?? "required",
      })),
      // False for resumes parsed before parsed_text existed. Those match
      // against ~30 extracted skills only, so the gap list over-reports and
      // the client should say "re-upload for a better read" rather than
      // present the number as authoritative.
      resumeTextAvailable: Boolean(resume.parsed_text?.trim()),
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

// Cache read, then extract-and-store on a miss. The hash guard matters: a
// re-scraped posting changes wording, and keywords from the old text would
// quietly mis-score every candidate who opened it afterwards.
async function loadOrExtractKeywords(
  admin: ReturnType<typeof createAdminClient>,
  jobId: string,
  description: string,
): Promise<JobKeyword[] | null> {
  const hash = await computeContentHash([description]);

  const { data: cached } = await admin
    .from("job_keywords")
    .select("keywords, description_hash")
    .eq("job_id", jobId)
    .maybeSingle();

  if (cached?.description_hash === hash && Array.isArray(cached.keywords)) {
    return cached.keywords as JobKeyword[];
  }

  let extracted: { keywords: JobKeyword[] };
  try {
    extracted = await callStructured<{ keywords: JobKeyword[] }>({
      systemPrompt: EXTRACTION_SYSTEM_PROMPT,
      // JDs run to tens of thousands of characters on enterprise ATS; the
      // requirements sit near the top and the tail is benefits and EEO text.
      userPrompt: description.slice(0, 12_000),
      schemaName: "job_keywords",
      schema: EXTRACTION_SCHEMA,
      maxOutputTokens: 700,
    });
  } catch (error) {
    console.error("keyword extraction failed", jobId, error);
    return null;
  }

  const keywords = (extracted.keywords ?? []).slice(0, MAX_KEYWORDS);

  // Best-effort cache write. A failure here costs one repeated extraction on
  // the next open, not a wrong answer.
  const { error: writeError } = await admin
    .from("job_keywords")
    .upsert(
      {
        job_id: jobId,
        keywords,
        description_hash: hash,
        model: Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini",
        updated_at: new Date().toISOString(),
      },
      { onConflict: "job_id" },
    );
  if (writeError) console.error("job_keywords cache write failed", writeError);

  return keywords;
}
