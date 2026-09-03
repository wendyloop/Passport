// S-1: prompt construction for application-answer suggestions.
//
// Pure logic on purpose — every export here is deterministic and covered by
// shared_test.ts. The network calls live in suggest-application-answer.
//
// Three modes, chosen by how close the candidate has already come to
// answering this question before:
//
//   reuse    similarity >= REUSE_FLOOR       no LLM call at all
//   adapt    ADAPT_FLOOR <= sim < REUSE      rewrite their own prior answer
//   generate similarity < ADAPT_FLOOR        cold draft from resume + voice
//
// Most repeat applicants land in the top two rows after ~10 applications.
// The corpus does the work; the model handles the tail.

export const REUSE_FLOOR = 0.85;
export const ADAPT_FLOOR = 0.60;

export type AnswerMode = "reuse" | "adapt" | "generate";

export function pickMode(similarity: number | null | undefined): AnswerMode {
  if (typeof similarity !== "number" || Number.isNaN(similarity)) return "generate";
  if (similarity >= REUSE_FLOOR) return "reuse";
  if (similarity >= ADAPT_FLOOR) return "adapt";
  return "generate";
}

// ---------------------------------------------------------------------------
// Voice samples
// ---------------------------------------------------------------------------

export type PriorAnswer = {
  id?: string;
  question_text: string;
  answer: string;
  source?: string | null;
  updated_at?: string | null;
};

// ANTI-SLOP INVARIANT. Only text the candidate wrote or corrected is allowed
// to shape future output. Admitting 'generated' rows here would feed the
// model its own prose as a style exemplar, and every answer converges on one
// synthetic voice within a few months. The DB index backing this filter is
// partial on exactly these two values.
const VOICE_SOURCES = new Set(["human", "edited"]);

// Long enough to carry voice, short enough that three of them plus a resume
// still leave room for the answer.
const VOICE_MIN_CHARS = 120;
const VOICE_MAX_CHARS = 1200;
const VOICE_SAMPLE_COUNT = 3;

export function selectVoiceSamples(
  rows: PriorAnswer[],
  excludeId?: string | null,
): PriorAnswer[] {
  return rows
    .filter((r) => VOICE_SOURCES.has((r.source ?? "human").trim()))
    .filter((r) => !excludeId || r.id !== excludeId)
    .filter((r) => {
      const len = (r.answer ?? "").trim().length;
      return len >= VOICE_MIN_CHARS && len <= VOICE_MAX_CHARS;
    })
    .sort((a, b) => (b.updated_at ?? "").localeCompare(a.updated_at ?? ""))
    .slice(0, VOICE_SAMPLE_COUNT);
}

// ---------------------------------------------------------------------------
// Length targeting
// ---------------------------------------------------------------------------

// ATS char limits are hard truncation, so aim under. 10% headroom absorbs the
// difference between our word estimate and the model's actual output.
export function targetWordCount(charLimit?: number | null): number {
  if (typeof charLimit === "number" && charLimit > 0) {
    return Math.max(40, Math.floor((charLimit * 0.9) / 6));
  }
  return 150;
}

// ---------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------

const GROUNDING = `GROUNDING
- Use only facts present in CANDIDATE_RESUME and CANDIDATE_PROFILE.
- Never invent employers, job titles, dates, metrics, schools, degrees, or skills.
- If the question asks for something the resume does not support, write around it
  honestly and name the gap in missing_info. Do not fabricate to fill it.`;

const VOICE = `VOICE
- Match VOICE_SAMPLES: sentence length, formality, first-person density, whether
  this person uses numbers, whether they use contractions.
- If VOICE_SAMPLES is empty, write plainly and concretely.`;

const STYLE = `STYLE
- Answer the question asked. Do not restate it.
- Banned phrases: "excited to", "passionate about", "thrilled", "leverage",
  "delve", "tapestry", "in today's fast-paced", "I believe my skills align".
- No em-dashes. Plain prose. No bullet points unless the question asks for a list.
- Specifics beat adjectives. One concrete detail from the resume outweighs three
  sentences of enthusiasm.`;

export function generateSystemPrompt(): string {
  return `You help a job applicant answer an application question in their own voice.

${GROUNDING}

${VOICE}

${STYLE}

LENGTH
- Target TARGET_WORDS words. If CHAR_LIMIT is given, stay under it.`;
}

export function adaptSystemPrompt(): string {
  return `The applicant already answered a similar question. Adapt their existing
answer to the new question and role.

- Preserve as much of the original wording as possible. This is their voice and
  it has already been submitted to real employers.
- Change only what is company-specific, role-specific, or newly asked for.
- Never introduce facts absent from both PRIOR_ANSWER and CANDIDATE_RESUME.
- If PRIOR_ANSWER already answers NEW_QUESTION well, return it unchanged and set
  changed to false.

${STYLE}

LENGTH
- Target TARGET_WORDS words. If CHAR_LIMIT is given, stay under it.`;
}

export type JobContext = {
  title?: string | null;
  company?: string | null;
  description?: string | null;
  location?: string | null;
};

export type AnswerPromptInput = {
  question: string;
  charLimit?: number | null;
  job: JobContext;
  resume: unknown;
  profile: unknown;
  voiceSamples: PriorAnswer[];
  prior?: PriorAnswer | null;
};

// Job descriptions run to tens of thousands of characters on enterprise ATS.
// The first few thousand carry the requirements; the rest is boilerplate,
// benefits, and EEO text.
const JD_MAX_CHARS = 6000;

export function buildUserPrompt(input: AnswerPromptInput): string {
  const payload: Record<string, unknown> = {
    QUESTION: input.question,
    CHAR_LIMIT: input.charLimit ?? null,
    TARGET_WORDS: targetWordCount(input.charLimit),
    JOB: {
      title: input.job.title ?? null,
      company: input.job.company ?? null,
      location: input.job.location ?? null,
      description: truncate(input.job.description, JD_MAX_CHARS),
    },
    CANDIDATE_RESUME: input.resume ?? null,
    CANDIDATE_PROFILE: input.profile ?? null,
    VOICE_SAMPLES: input.voiceSamples.map((v) => ({
      question: v.question_text,
      answer: v.answer,
    })),
  };
  if (input.prior) {
    payload.PRIOR_QUESTION = input.prior.question_text;
    payload.PRIOR_ANSWER = input.prior.answer;
  }
  return JSON.stringify(payload, null, 2);
}

export function truncate(text: string | null | undefined, max: number): string | null {
  if (!text) return null;
  const t = text.trim();
  if (t.length <= max) return t;
  return t.slice(0, max) + "\n[truncated]";
}

// ---------------------------------------------------------------------------
// Response schemas (strict:true — every key required, additionalProperties off)
// ---------------------------------------------------------------------------

export const GENERATE_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: ["answer", "facts_used", "confidence", "missing_info"],
  properties: {
    answer: { type: "string" },
    facts_used: { type: "array", items: { type: "string" } },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    // Nullable so the model can say "nothing missing" without inventing a gap.
    missing_info: { type: ["string", "null"] },
  },
};

export const ADAPT_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: ["answer", "changed", "change_summary"],
  properties: {
    answer: { type: "string" },
    changed: { type: "boolean" },
    change_summary: { type: "string" },
  },
};

// ---------------------------------------------------------------------------
// Output guard
// ---------------------------------------------------------------------------

// A hard truncation at CHAR_LIMIT would cut mid-sentence, which reads worse
// than a slightly short answer. Trim to the last sentence boundary that fits,
// and only fall back to a hard cut when there is no boundary to find.
export function enforceCharLimit(answer: string, charLimit?: number | null): string {
  const text = (answer ?? "").trim();
  if (typeof charLimit !== "number" || charLimit <= 0 || text.length <= charLimit) {
    return text;
  }
  const clipped = text.slice(0, charLimit);
  const lastStop = Math.max(
    clipped.lastIndexOf(". "),
    clipped.lastIndexOf("! "),
    clipped.lastIndexOf("? "),
  );
  if (lastStop > charLimit * 0.5) return clipped.slice(0, lastStop + 1).trim();
  return clipped.trim();
}
