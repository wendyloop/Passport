// S-3: a cover letter for one job.
//
// Same context bundle as suggest-application-answer — job, resume, profile,
// and the candidate's own prior writing as voice samples — through a prompt
// that prescribes the three-paragraph shape recruiters expect.
//
// Voice samples prefer prior LETTERS over prior essay answers: a letter and a
// screening answer are different registers, and mixing them produces a draft
// that reads like neither.
//
// Not cached. A letter names the company in its first sentence, so there is
// nothing to reuse across jobs; only the voice carries over.

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse } from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { callStructured } from "../_shared/openai.ts";
import {
  buildCoverLetterPrompt,
  COVER_LETTER_SCHEMA,
  coverLetterLooksGeneric,
  coverLetterSystemPrompt,
  type PriorAnswer,
  selectVoiceSamples,
  VOICE_SAMPLE_COUNT,
} from "../_shared/answer_prompts.ts";

type RequestBody = { jobId: string };

const VOICE_FETCH_LIMIT = 25;

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

    if (!(await configFlag(admin, "cover_letters_enabled", true))) {
      return jsonResponse({ available: false, reason: "disabled" });
    }

    const { data: job, error: jobError } = await admin
      .from("jobs")
      .select("id, title, company_name, location, description")
      .eq("id", jobId)
      .maybeSingle();
    if (jobError) throw jobError;
    if (!job) return jsonResponse({ error: "Job not found" }, 404);

    const [resume, profile, voiceSamples] = await Promise.all([
      loadResume(admin, user.id),
      loadProfile(admin, user.id),
      loadVoiceSamples(admin, user.id),
    ]);

    // A letter grounded in nothing is a letter about nothing. Better to say so
    // than to emit three paragraphs of enthusiasm with no evidence in them.
    if (!resume) {
      return jsonResponse({ available: false, reason: "no_resume" });
    }

    const context = {
      job: {
        title: job.title,
        company: job.company_name,
        location: job.location,
        description: job.description,
      },
      resume,
      profile,
      voiceSamples,
    };

    let draft: { body: string; opening_hook: string; facts_used: string[] };
    try {
      draft = await callStructured<{
        body: string;
        opening_hook: string;
        facts_used: string[];
      }>({
        systemPrompt: coverLetterSystemPrompt(),
        userPrompt: buildCoverLetterPrompt(context),
        schemaName: "cover_letter",
        schema: COVER_LETTER_SCHEMA,
        maxOutputTokens: 900,
      });
    } catch (error) {
      console.error("cover letter draft failed", jobId, error);
      return jsonResponse({ available: false, reason: "draft_failed" });
    }

    const letter = (draft.body ?? "").trim();
    if (!letter) {
      return jsonResponse({ available: false, reason: "empty_draft" });
    }

    // One retry-free quality gate. A letter that opens with a banned phrase or
    // never names the company is generic, which is the single failure this
    // feature exists to avoid — shipping it would be worse than shipping
    // nothing, because the candidate might send it.
    if (coverLetterLooksGeneric(letter, job.company_name)) {
      console.error("cover letter rejected as generic", jobId);
      return jsonResponse({ available: false, reason: "generic_draft" });
    }

    // Stored as 'generated'. It becomes 'edited' — and therefore a voice
    // sample — only once the candidate changes it and saves.
    const { data: saved, error: saveError } = await admin
      .from("candidate_cover_letters")
      .insert({
        candidate_profile_id: user.id,
        job_id: jobId,
        body: letter,
        source: "generated",
      })
      .select("id")
      .single();
    if (saveError) console.error("cover letter save failed", saveError);

    return jsonResponse({
      available: true,
      id: saved?.id ?? null,
      body: letter,
      openingHook: draft.opening_hook ?? null,
      factsUsed: draft.facts_used ?? [],
      needsReview: true,
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

async function loadResume(admin: ReturnType<typeof createAdminClient>, profileId: string) {
  const { data } = await admin
    .from("resume_uploads")
    .select("parsed_json")
    .eq("profile_id", profileId)
    .not("parsed_json", "is", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data?.parsed_json ?? null;
}

async function loadProfile(admin: ReturnType<typeof createAdminClient>, profileId: string) {
  const [{ data: base }, { data: seeker }] = await Promise.all([
    admin.from("profiles").select("full_name").eq("id", profileId).maybeSingle(),
    admin
      .from("job_seeker_profiles")
      .select("school_name, dream_role, city, linkedin_url, github_url, portfolio_url")
      .eq("profile_id", profileId)
      .maybeSingle(),
  ]);
  return {
    fullName: base?.full_name ?? null,
    schoolName: seeker?.school_name ?? null,
    dreamRole: seeker?.dream_role ?? null,
    city: seeker?.city ?? null,
    links: {
      linkedin: seeker?.linkedin_url ?? null,
      github: seeker?.github_url ?? null,
      portfolio: seeker?.portfolio_url ?? null,
    },
  };
}

// Prior LETTERS are the better exemplar for a letter — a screening answer is
// a different register, and mixing the two produces a draft that reads like
// neither. selectVoiceSamples sorts by recency, so the preference cannot be
// expressed by concatenation order; it is done here instead, by filling from
// letters first and only topping up from answers when there are too few.
async function loadVoiceSamples(
  admin: ReturnType<typeof createAdminClient>,
  profileId: string,
): Promise<PriorAnswer[]> {
  const [{ data: letters }, { data: answers }] = await Promise.all([
    admin
      .from("candidate_cover_letters")
      .select("id, body, source, updated_at")
      .eq("candidate_profile_id", profileId)
      .in("source", ["human", "edited"])
      .order("updated_at", { ascending: false })
      .limit(VOICE_FETCH_LIMIT),
    admin
      .from("candidate_essay_answers")
      .select("id, question_text, answer, source, updated_at")
      .eq("candidate_profile_id", profileId)
      .in("source", ["human", "edited"])
      .order("updated_at", { ascending: false })
      .limit(VOICE_FETCH_LIMIT),
  ]);

  const letterRows: PriorAnswer[] = (letters ?? []).map((l) => ({
    id: l.id,
    question_text: "cover letter",
    answer: l.body,
    source: l.source,
    updated_at: l.updated_at,
  }));

  const fromLetters = selectVoiceSamples(letterRows);
  const shortfall = VOICE_SAMPLE_COUNT - fromLetters.length;
  if (shortfall <= 0) return fromLetters;

  const fromAnswers = selectVoiceSamples((answers ?? []) as PriorAnswer[]).slice(0, shortfall);
  return [...fromLetters, ...fromAnswers];
}

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
