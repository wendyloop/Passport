// Resume parser.
//
// Replaces the v0 regex parser. Given raw resume text we:
//   1. Call gpt-4o-mini with a strict JSON schema to extract canonical
//      profile fields + structured education/employment history.
//   2. Persist the full structured blob to resume_uploads.parsed_json.
//   3. Back-fill the legacy resume_uploads.parsed_school_name +
//      parsed_employers columns so apply-to-job (which still reads them)
//      keeps working.
//   4. Upsert canonical fields into candidate_field_history with the
//      `canon:` prefix. From there the autofill plumbing
//      (get-prefill-profile → iOS bridge) treats resume-derived fields
//      identically to fields captured from prior applications: newest
//      non-empty wins.
//
// We deliberately do NOT touch job_seeker_profiles or job_seeker_employers
// here anymore. Those reads in apply-to-job are legacy; once that function
// migrates to read from candidate_field_history this parser can drop the
// legacy column back-fill too.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { canonLabel, type CanonicalKey } from "../_shared/profile_fields.ts";
import { jsonResponse } from "../_shared/http.ts";
import { callStructured } from "../_shared/openai.ts";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const OPENAI_TIMEOUT_MS = 20_000;

type ParsedResume = {
  first_name: string;
  last_name: string;
  email: string;
  phone: string;
  city: string;
  state: string;
  country: string;
  linkedin_url: string;
  github_url: string;
  portfolio_url: string;
  current_title: string;
  current_company: string;
  years_experience: string;        // string so the model can return "" cleanly
  highest_degree: string;
  school: string;
  graduation_year: string;
  field_of_study: string;
  work_authorization: string;
  employers: Array<{
    company: string;
    title: string;
    start_date: string;
    end_date: string;
    is_current: boolean;
  }>;
  education: Array<{
    school: string;
    degree: string;
    field_of_study: string;
    graduation_year: string;
  }>;
  skills: string[];
};

// Which parsed_json keys flow into candidate_field_history under canon:*.
// Education/employment arrays and skills stay in parsed_json only — they're
// structured and don't map to a single ATS input.
// `as const satisfies` narrows keys to the literals ParsedResume actually
// has, so parsed[key] stays typed (CanonicalKey also holds non-resume keys
// like full_name).
const CANONICAL_FROM_PARSED = [
  "first_name",
  "last_name",
  "email",
  "phone",
  "city",
  "state",
  "country",
  "linkedin_url",
  "github_url",
  "portfolio_url",
  "current_title",
  "current_company",
  "years_experience",
  "highest_degree",
  "school",
  "graduation_year",
  "field_of_study",
  "work_authorization",
] as const satisfies readonly CanonicalKey[];

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const adminClient = createAdminClient();
    const { data: { user }, error: authError } = await userClient.auth.getUser();

    if (authError || !user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body = await request.json().catch(() => ({}));
    const resumeId = body.resumeId as string | undefined;
    const rawText = (body.rawText as string | undefined)?.trim() ?? "";

    if (!resumeId) {
      return jsonResponse({ error: "resumeId is required" }, 400);
    }

    // No text → mark for manual review; don't burn an LLM call on nothing.
    if (!rawText || !OPENAI_API_KEY) {
      const { error: updateError } = await adminClient
        .from("resume_uploads")
        .update({ parse_status: "pending_manual_review" })
        .eq("id", resumeId)
        .eq("profile_id", user.id);
      if (updateError) throw updateError;
      return jsonResponse({
        resumeId,
        parseStatus: "pending_manual_review",
        reason: rawText ? "no openai key" : "no resume text",
      });
    }

    let parsed: ParsedResume;
    try {
      parsed = await extractWithLLM(rawText);
    } catch (error) {
      // Persist the failure so retries can find it; don't crash the upload flow.
      await adminClient
        .from("resume_uploads")
        .update({ parse_status: "failed" })
        .eq("id", resumeId)
        .eq("profile_id", user.id);
      throw error;
    }

    const legacySchool = parsed.education[0]?.school || parsed.school || null;
    const legacyEmployers = parsed.employers
      .map((e) => e.company?.trim())
      .filter((c): c is string => !!c)
      .slice(0, 5);

    const { data: resume, error: resumeError } = await adminClient
      .from("resume_uploads")
      .update({
        parse_status: "parsed",
        parsed_school_name: legacySchool,
        parsed_employers: legacyEmployers,
        parsed_json: parsed,
      })
      .eq("id", resumeId)
      .eq("profile_id", user.id)
      .select("profile_id")
      .single();

    if (resumeError) throw resumeError;

    // Push canonical fields into the autofill table. Empty strings are
    // intentionally filtered — we never want to overwrite a good value with
    // a missing one.
    const historyRows = CANONICAL_FROM_PARSED
      .map((key) => ({ key, value: (parsed[key] as string | undefined)?.trim() ?? "" }))
      .filter((row) => row.value.length > 0)
      .map((row) => ({
        candidate_profile_id: resume.profile_id,
        field_label: canonLabel(row.key),
        field_value: row.value,
        updated_at: new Date().toISOString(),
      }));

    if (historyRows.length > 0) {
      const { error: historyError } = await adminClient
        .from("candidate_field_history")
        .upsert(historyRows, { onConflict: "candidate_profile_id,field_label" });
      if (historyError) throw historyError;
    }

    return jsonResponse({
      resumeId,
      parseStatus: "parsed",
      canonicalFieldsWritten: historyRows.length,
      employers: legacyEmployers,
      school: legacySchool,
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

async function extractWithLLM(rawText: string): Promise<ParsedResume> {
  const systemPrompt =
    "You extract structured profile data from a job seeker's resume. " +
    "Use ONLY information present in the resume — never invent emails, " +
    "phone numbers, dates, or degrees. If a field isn't in the resume, " +
    "return an empty string (or empty array). years_experience is an " +
    "integer-as-string ('5'), graduation_year is YYYY. Dates in employers/" +
    "education are YYYY-MM or YYYY when month is unknown. is_current is " +
    "true only if the resume explicitly says Present/Current. Return JSON.";

  return await callStructured<ParsedResume>({
    systemPrompt,
    userPrompt: rawText.slice(0, 24_000),
    schemaName: "parsed_resume",
    schema: SCHEMA,
    maxOutputTokens: 1500,
    timeoutMs: OPENAI_TIMEOUT_MS,
  });
}

// JSON schema mirrors ParsedResume exactly. strict:true requires every key
// to be present and additionalProperties:false; the model returns "" for
// unknown strings and [] for unknown arrays per the system prompt.
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "first_name", "last_name", "email", "phone",
    "city", "state", "country",
    "linkedin_url", "github_url", "portfolio_url",
    "current_title", "current_company", "years_experience",
    "highest_degree", "school", "graduation_year", "field_of_study",
    "work_authorization",
    "employers", "education", "skills",
  ],
  properties: {
    first_name:         { type: "string" },
    last_name:          { type: "string" },
    email:              { type: "string" },
    phone:              { type: "string" },
    city:               { type: "string" },
    state:              { type: "string" },
    country:            { type: "string" },
    linkedin_url:       { type: "string" },
    github_url:         { type: "string" },
    portfolio_url:      { type: "string" },
    current_title:      { type: "string" },
    current_company:    { type: "string" },
    years_experience:   { type: "string" },
    highest_degree:     { type: "string" },
    school:             { type: "string" },
    graduation_year:    { type: "string" },
    field_of_study:     { type: "string" },
    work_authorization: { type: "string" },
    employers: {
      type: "array",
      maxItems: 10,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["company", "title", "start_date", "end_date", "is_current"],
        properties: {
          company:    { type: "string" },
          title:      { type: "string" },
          start_date: { type: "string" },
          end_date:   { type: "string" },
          is_current: { type: "boolean" },
        },
      },
    },
    education: {
      type: "array",
      maxItems: 5,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["school", "degree", "field_of_study", "graduation_year"],
        properties: {
          school:          { type: "string" },
          degree:          { type: "string" },
          field_of_study:  { type: "string" },
          graduation_year: { type: "string" },
        },
      },
    },
    skills: {
      type: "array",
      maxItems: 30,
      items: { type: "string" },
    },
  },
} as const;
