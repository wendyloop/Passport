// Title-keyword job_function classification for board/ATS jobs, which arrive
// with no function metadata. Imperfect by design — it exists so the app's
// function filters match something. Mirrors the SQL backfill in migration
// 20260709120000_pipeline_rescue.sql; keep the two in sync.

export type JobFunction =
  | "engineering" | "design" | "product" | "science" | "sales" | "marketing"
  | "support" | "operations" | "hr" | "finance" | "legal";

const RULES: Array<[JobFunction, RegExp]> = [
  ["engineering", /software|backend|frontend|full.?stack|platform engineer|infrastructure|devops|sre|site reliab|mobile engineer|ios |android|embedded|firmware|security engineer|data engineer|ml engineer|machine learning|ai engineer|research engineer|hardware|electrical engineer|mechanical engineer|qa engineer|test engineer/],
  ["science", /data scien|data analy|analytics|research scien|applied scien|quantitative/],
  ["product", /product manager|product owner|technical program|program manager|head of product|product lead/],
  ["design", /designer|design lead|\bux\b|\bui designer|user experience|user interface|brand design/],
  ["sales", /sales|account exec|account manager|business develop|\bbdr\b|\bsdr\b|revenue|partnership/],
  ["marketing", /marketing|growth|content|brand manager|\bseo\b|social media|community manager/],
  ["support", /customer success|customer support|support engineer|solutions engineer|implementation|technical account/],
  ["hr", /recruit|talent|people ops|people partner|\bhr\b|human resources/],
  ["finance", /finance|accounting|controller|fp&a|treasury|payroll/],
  ["legal", /legal|counsel|compliance|regulatory|paralegal/],
  ["operations", /operations|\bops\b|chief of staff|office manager|executive assistant|logistics|supply chain/],
];

export function classifyTitle(title: string | null | undefined): JobFunction | null {
  if (!title) return null;
  const lower = title.toLowerCase();
  for (const [fn, pattern] of RULES) {
    if (pattern.test(lower)) return fn;
  }
  return null;
}

// ── Experience level ────────────────────────────────────────────────
// Title-based first pass; generate-carousel's LLM refines from the full JD
// for the ~59% of titles that carry no level signal. Mirrors the SQL
// backfill in migration 20260709130000_experience_work_mode.sql.

export type ExperienceLevel = "intern" | "entry" | "mid" | "senior" | "staff" | "exec";

const EXPERIENCE_RULES: Array<[ExperienceLevel, RegExp]> = [
  // Order matters: intern/entry markers beat seniority words ("Senior
  // Software Engineering Intern" is an internship).
  ["intern", /\bintern(ship)?s?\b|\bco-?op\b/],
  ["entry", /\bjunior\b|\bjr\.?\b|entry.level|new grad|university grad|graduate program|graduate scheme|early.career|\bapprentice\b|\btrainee\b/],
  ["exec", /\bdirector\b|\bvp\b|vice president|head of|\bchief\b|\bc[tefo]o\b|\bpresident\b|founding/],
  ["staff", /\bprincipal\b|\bstaff\b|distinguished|\barchitect\b|\bfellow\b/],
  ["senior", /\bsenior\b|\bsr\.?\b|\blead\b/],
];

export function classifyExperience(title: string | null | undefined): ExperienceLevel | null {
  if (!title) return null;
  const lower = title.toLowerCase();
  for (const [level, pattern] of EXPERIENCE_RULES) {
    if (pattern.test(lower)) return level;
  }
  return null; // unknown ≠ mid — don't fabricate a level from silence
}

// ── Work mode ───────────────────────────────────────────────────────
// From the location string only; absence of a signal means unknown, not
// onsite. The LLM refines from the JD body during carousel generation.

export type WorkMode = "remote" | "hybrid" | "onsite";

export function classifyWorkMode(location: string | null | undefined): WorkMode | null {
  if (!location) return null;
  const lower = location.toLowerCase();
  if (/\bhybrid\b/.test(lower)) return "hybrid";
  if (/\bremote\b|\bwork from home\b|\bwfh\b|\bdistributed\b/.test(lower)) return "remote";
  if (/\bon-?site\b|\bin.office\b/.test(lower)) return "onsite";
  return null;
}
