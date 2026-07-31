// Title-keyword job_function classification for board/ATS jobs, which arrive
// with no function metadata. Imperfect by design — it exists so the app's
// function filters match something. v2 (2026-07-30) broadened the rules
// after 40% of the live catalog matched nothing (bare "Engineer" titles,
// "Accountant", "Solutions Architect"…); v4 (2026-07-30) fixed the starved
// product bucket (product now runs first, senior PM titles match, and
// "Head of ProductION" manufacturing titles land in operations). Mirrors
// the SQL backfills in migrations 20260709120000, 20260730120000/131000 and
// 20260730160000; keep them in sync. The LLM pass in generate-carousel
// refines from the full JD for whatever the title alone can't place.

export type JobFunction =
  | "engineering" | "design" | "product" | "science" | "sales" | "marketing"
  | "support" | "operations" | "hr" | "finance" | "legal"
  | "program_management" | "clinical";

// Optional third element: an exclusion regex — the rule only fires when the
// title does NOT match it (expressible in Postgres too, unlike lookaheads).
const RULES: Array<[JobFunction, RegExp, RegExp?]> = [
  // v4: product runs FIRST — "Product Manager, Infrastructure" was leaking
  // to engineering via the tech keywords. \b keeps "Head of ProductION"
  // (manufacturing) out; the exclusion keeps PMM/product-design out of
  // product so their own rules below still claim them.
  ["product", /product manager|product owner|product management|product lead|head of product\b|(director|vp|svp) of product\b|chief product officer/, /product (marketing|design)/],
  ["engineering", /software|backend|frontend|full.?stack|platform engineer|infrastructure|devops|sre|site reliab|mobile engineer|ios |android|embedded|firmware|security engineer|data engineer|ml engineer|machine learning|ai engineer|research engineer|hardware|electrical engineer|mechanical engineer|qa engineer|test engineer/],
  ["science", /data scien|data analy|analytics|research scien|applied scien|quantitative|\bscientist\b/],
  ["design", /designer|design lead|\bux\b|\bui designer|user experience|user interface|brand design|graphic|illustrator|creative director/],
  // v3: project/program management is its own section (product decision
  // 2026-07-30) — before the team rules below so every PM flavor lands here.
  ["program_management", /program manager|project manager|technical program|program lead|scrum master|\bpmo\b/],
  // v3: clinical roles at healthcare startups. MUST run before legal —
  // /counsel/ would otherwise eat "counselor".
  ["clinical", /nurse|physician|clinician|clinical|therapist|therapy\b|psycholog|psychiatr|counselor|dental|dentist|pharmac|paramedic|medical assistant|medical director|behavior technician|\brn\b|endocrinolog|cardiolog|dermatolog|patholog|radiolog|oncolog|pediatric|primary care|urgent care|telehealth|dietitian|nutritionist|midwife|phlebotom|health information|caregiver|home health|veterinar/],
  ["sales", /sales|account exec|account manager|account develop|account represent|business develop|\bbdr\b|\bsdr\b|revenue|partnership|appointment setter/],
  ["marketing", /marketing|growth|content|brand manager|\bseo\b|social media|community manager|communications/],
  ["support", /customer success|customer support|support engineer|solutions engineer|solutions architect|solutions consultant|implementation|technical account|help ?desk|customer experience|engagement manager|deployment strategist|domain consultant|client solutions|delivery lead/],
  ["hr", /recruit|talent|people ops|people partner|\bhr\b|human resources/],
  ["finance", /finance|accounting|accountant|controller|fp&a|treasury|payroll|bookkeep|billing|\btax\b|accounts payable|accounts receivable/],
  ["legal", /legal|counsel|compliance|regulatory|paralegal|contracts manager/],
  // v2 generic catch-alls, deliberately LAST before operations: "Sales
  // Engineer"/"Solutions Architect" already matched their real teams above;
  // whatever still says engineer/developer is engineering.
  ["engineering", /\bengineer(ing)?\b|\bdeveloper\b|\barchitect\b/],
  // v4: manufacturing/production ops ("Head of Production, Missiles") —
  // formerly a product false-positive via the missing word boundary.
  ["operations", /operations|\bops\b|chief of staff|office manager|executive assistant|logistics|supply chain|production\b|manufactur/],
];

export function classifyTitle(title: string | null | undefined): JobFunction | null {
  if (!title) return null;
  const lower = title.toLowerCase();
  for (const [fn, pattern, exclude] of RULES) {
    if (pattern.test(lower) && !exclude?.test(lower)) return fn;
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
