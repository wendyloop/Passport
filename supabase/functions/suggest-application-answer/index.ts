// S-1: one suggested answer for one application question.
//
// Picks its own mode by how close the candidate has already come to answering
// this before (see _shared/answer_prompts.ts):
//
//   reuse    — their prior answer, verbatim. No LLM call, no cost.
//   adapt    — their prior answer, rewritten for this role. Preserves voice.
//   generate — a cold draft grounded in resume + their own writing samples.
//
// match-essay-answer is deliberately left alone: it stays the pure-retrieval
// endpoint, so retrieval-only remains available (older clients, and a free
// tier if tiering ever returns).
//
// Fails soft everywhere. If the model errors, the config flag is off, or the
// daily cap is hit, this returns mode:"none" with a null answer and the
// candidate simply writes their own — the same experience as before S-1.

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse } from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { embedText, normalizeQuestion, toPgVector } from "../_shared/openai_embeddings.ts";
import { callStructured } from "../_shared/openai.ts";
import {
  ADAPT_FLOOR,
  ADAPT_SCHEMA,
  adaptSystemPrompt,
  type AnswerMode,
  buildUserPrompt,
  enforceCharLimit,
  GENERATE_SCHEMA,
  generateSystemPrompt,
  pickMode,
  type PriorAnswer,
  selectVoiceSamples,
} from "../_shared/answer_prompts.ts";

type RequestBody = {
  question: string;
  jobId?: string | null;
  // The form's own maxlength, when the bridge can read one off the textarea.
  charLimit?: number | null;
};

type PriorRow = {
  id: string;
  question_text: string;
  answer: string;
  similarity: number;
  source_job_id: string | null;
  updated_at: string;
};

// Voice samples are pulled newest-first and filtered in TS; 25 is plenty to
// find three that clear the length window.
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
    const question = body.question?.trim();
    if (!question) return jsonResponse({ error: "question is required" }, 400);

    const questionNorm = normalizeQuestion(question);
    if (!questionNorm) return jsonResponse({ error: "question is required" }, 400);

    const admin = createAdminClient();

    // ---- 1. Closest prior answer, at the ADAPT floor so one lookup serves
    // both reuse and adapt.
    const embedding = await embedText(question);
    const { data: matchData, error: matchError } = await admin.rpc("match_candidate_essay", {
      p_profile_id: user.id,
      p_embedding: toPgVector(embedding),
      p_min_score: ADAPT_FLOOR,
      p_limit: 1,
    });
    if (matchError) throw matchError;
    const prior = (Array.isArray(matchData) ? matchData[0] : null) as PriorRow | null;

    const mode = pickMode(prior?.similarity);

    // ---- 2. Reuse costs nothing and needs no context. Take it and leave.
    if (mode === "reuse" && prior) {
      await recordSuggestion(admin, {
        profileId: user.id,
        question,
        questionNorm,
        answer: prior.answer,
        mode: "reuse",
        sourceAnswerId: prior.id,
        jobId: body.jobId ?? null,
      });
      return jsonResponse({
        mode: "reuse",
        answer: prior.answer,
        priorQuestion: prior.question_text,
        similarity: prior.similarity,
        needsReview: false,
      });
    }

    // ---- 3. Everything past here costs an LLM call. Both guards fail soft.
    if (!(await configFlag(admin, "ai_answers_enabled", true))) {
      return jsonResponse({ mode: "none", answer: null, reason: "disabled" });
    }
    if (await overDailyCap(admin, user.id)) {
      return jsonResponse({ mode: "none", answer: null, reason: "daily_cap" });
    }

    // ---- 4. Context: job, resume, profile, voice.
    const [job, resume, profile, voiceRows] = await Promise.all([
      loadJob(admin, body.jobId),
      loadResume(admin, user.id),
      loadProfile(admin, user.id),
      loadVoiceRows(admin, user.id),
    ]);

    const voiceSamples = selectVoiceSamples(voiceRows, prior?.id ?? null);

    const promptInput = {
      question,
      charLimit: body.charLimit ?? null,
      job,
      resume,
      profile,
      voiceSamples,
      prior: mode === "adapt" && prior
        ? { question_text: prior.question_text, answer: prior.answer }
        : null,
    };

    // ---- 5. Draft it.
    let answer: string;
    let extras: Record<string, unknown>;
    try {
      if (mode === "adapt") {
        const out = await callStructured<{
          answer: string;
          changed: boolean;
          change_summary: string;
        }>({
          systemPrompt: adaptSystemPrompt(),
          userPrompt: buildUserPrompt(promptInput),
          schemaName: "adapted_answer",
          schema: ADAPT_SCHEMA,
          maxOutputTokens: 900,
        });
        answer = out.answer;
        extras = { changed: out.changed, changeSummary: out.change_summary };
      } else {
        const out = await callStructured<{
          answer: string;
          facts_used: string[];
          confidence: string;
          missing_info: string | null;
        }>({
          systemPrompt: generateSystemPrompt(),
          userPrompt: buildUserPrompt(promptInput),
          schemaName: "generated_answer",
          schema: GENERATE_SCHEMA,
          maxOutputTokens: 900,
        });
        answer = out.answer;
        extras = {
          factsUsed: out.facts_used,
          confidence: out.confidence,
          missingInfo: out.missing_info,
        };
      }
    } catch (error) {
      // Deliberately NOT falling back to the prior answer here. At an adapt-
      // range similarity it may be answering a materially different question,
      // and a plausible-but-wrong answer dropped into a live application is
      // worse than an empty box.
      console.error("suggest-application-answer draft failed", error);
      return jsonResponse({ mode: "none", answer: null, reason: "draft_failed" });
    }

    const trimmed = enforceCharLimit(answer, body.charLimit);
    if (!trimmed) {
      return jsonResponse({ mode: "none", answer: null, reason: "empty_draft" });
    }

    await recordSuggestion(admin, {
      profileId: user.id,
      question,
      questionNorm,
      answer: trimmed,
      mode,
      sourceAnswerId: mode === "adapt" ? prior?.id ?? null : null,
      jobId: body.jobId ?? null,
    });

    return jsonResponse({
      mode,
      answer: trimmed,
      // The client shows a review banner on anything a model touched. Prior
      // answers are the candidate's own words and need no such warning.
      needsReview: true,
      priorQuestion: mode === "adapt" ? prior?.question_text ?? null : null,
      similarity: prior?.similarity ?? null,
      ...extras,
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

// ---------------------------------------------------------------------------
// Context loaders — each returns null rather than throwing, so a missing
// resume or an unknown job degrades the draft instead of failing the request.
// ---------------------------------------------------------------------------

async function loadJob(admin: ReturnType<typeof createAdminClient>, jobId?: string | null) {
  if (!jobId) return {};
  const { data } = await admin
    .from("jobs")
    .select("title, company_name, location, description")
    .eq("id", jobId)
    .maybeSingle();
  return {
    title: data?.title ?? null,
    company: data?.company_name ?? null,
    location: data?.location ?? null,
    description: data?.description ?? null,
  };
}

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

// Only rows the candidate wrote or corrected — the partial index on
// (candidate_profile_id, updated_at desc) where source in ('human','edited')
// backs exactly this query. selectVoiceSamples re-checks in TS so the
// invariant holds even if a caller widens the filter.
async function loadVoiceRows(
  admin: ReturnType<typeof createAdminClient>,
  profileId: string,
): Promise<PriorAnswer[]> {
  const { data } = await admin
    .from("candidate_essay_answers")
    .select("id, question_text, answer, source, updated_at")
    .eq("candidate_profile_id", profileId)
    .in("source", ["human", "edited"])
    .order("updated_at", { ascending: false })
    .limit(VOICE_FETCH_LIMIT);
  return (data ?? []) as PriorAnswer[];
}

// ---------------------------------------------------------------------------
// Bookkeeping
// ---------------------------------------------------------------------------

async function recordSuggestion(
  admin: ReturnType<typeof createAdminClient>,
  input: {
    profileId: string;
    question: string;
    questionNorm: string;
    answer: string;
    mode: AnswerMode;
    sourceAnswerId: string | null;
    jobId: string | null;
  },
) {
  // Best-effort. The suggestion log drives provenance stamping and prompt
  // tuning; neither is worth failing a live application over.
  const { error } = await admin.from("candidate_answer_suggestions").insert({
    candidate_profile_id: input.profileId,
    question_text: input.question,
    question_norm: input.questionNorm,
    suggested_answer: input.answer,
    mode: input.mode,
    source_answer_id: input.sourceAnswerId,
    job_id: input.jobId,
  });
  if (error) console.error("suggestion log write failed", error);
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

// Counts only modes that cost money. 'reuse' is free and must never be capped.
async function overDailyCap(
  admin: ReturnType<typeof createAdminClient>,
  profileId: string,
): Promise<boolean> {
  const { data: configRow } = await admin
    .from("app_config")
    .select("value")
    .eq("key", "ai_answers_daily_cap")
    .maybeSingle();
  const cap = Number(configRow?.value);
  if (!Number.isFinite(cap) || cap <= 0) return false;

  const startOfUTCDay = new Date();
  startOfUTCDay.setUTCHours(0, 0, 0, 0);

  const { count, error } = await admin
    .from("candidate_answer_suggestions")
    .select("id", { count: "exact", head: true })
    .eq("candidate_profile_id", profileId)
    .neq("mode", "reuse")
    .gte("created_at", startOfUTCDay.toISOString());
  if (error) return false;   // fail open; a counting error must not block work
  return (count ?? 0) >= cap;
}
