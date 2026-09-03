// S-2: matching a job's requirement terms against a candidate's resume.
//
// Pure logic — every export here is deterministic and covered by
// shared_test.ts. The model call that extracts terms from a JD lives in
// resume-job-keywords; only the diff lives here.
//
// The output is deliberately explainable. An embedding similarity of "62"
// tells a candidate nothing they can act on; "you have 7 of these 10 things,
// and Kubernetes is one of the 3 you don't" tells them what to do next.

export type KeywordImportance = "required" | "preferred";
export type KeywordKind = "skill" | "tool" | "credential" | "domain";

export type JobKeyword = {
  term: string;
  kind?: KeywordKind;
  importance?: KeywordImportance;
};

export type KeywordVerdict = JobKeyword & { covered: boolean };

export type KeywordGap = {
  coverage: number;          // 0-100, weighted
  covered: KeywordVerdict[];
  missing: KeywordVerdict[];
  requiredTotal: number;
  requiredCovered: number;
};

// A "required" term counts for more than a "preferred" one, so a resume that
// misses three nice-to-haves scores far better than one missing three
// must-haves. Simplify tells users to aim for 70%; that number only means
// something if the weighting reflects what actually gets people screened out.
const WEIGHT_REQUIRED = 2;
const WEIGHT_PREFERRED = 1;

function weightOf(k: JobKeyword): number {
  return k.importance === "preferred" ? WEIGHT_PREFERRED : WEIGHT_REQUIRED;
}

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

// Punctuation is stripped rather than spaced out so "Node.js" collapses to
// "nodejs" and matches a resume writing "NodeJS" or "node.js". The cost is
// that "C++" and "C#" would collapse to "c" — they are special-cased below
// before this runs.
const SYMBOL_ALIASES: Array<[RegExp, string]> = [
  [/\bc\+\+/gi, "cplusplus"],
  [/\bc#/gi, "csharp"],
  [/\bf#/gi, "fsharp"],
  // ".js" fuses into the preceding word so "Node.js" becomes one token and
  // reaches the alias table as "nodejs". Left as two tokens it can never
  // match a resume that writes plain "Node", which is most of them.
  [/\.js\b/gi, "js"],
  // ".NET" gets a LEADING SPACE instead, because it appears both bare and as
  // a suffix: fusing would turn "ASP.NET" into "aspdotnet", matching neither
  // ".NET" nor "ASP.NET".
  [/\.net\b/gi, " dotnet"],
  [/\bgo\s*lang\b/gi, "golang"],
];

export function normalizeText(input: string | null | undefined): string {
  if (!input) return "";
  let text = String(input);
  for (const [pattern, replacement] of SYMBOL_ALIASES) {
    text = text.replace(pattern, replacement);
  }
  return text
    .toLowerCase()
    .replace(/[‘’']/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// Terms that mean the same thing under different names. Kept small and
// hand-checked: a wrong alias silently marks a missing skill as covered,
// which is the one failure mode that actively misleads a candidate.
const TERM_ALIASES: Record<string, string[]> = {
  postgresql: ["postgres"],
  postgres: ["postgresql"],
  javascript: ["js"],
  typescript: ["ts"],
  kubernetes: ["k8s"],
  k8s: ["kubernetes"],
  "amazon web services": ["aws"],
  aws: ["amazon web services"],
  "google cloud platform": ["gcp", "google cloud"],
  gcp: ["google cloud platform", "google cloud"],
  "machine learning": ["ml"],
  "natural language processing": ["nlp"],
  "continuous integration": ["ci", "ci cd"],
  reactjs: ["react"],
  react: ["reactjs"],
  nodejs: ["node"],
  node: ["nodejs"],
};

// Very light stemming: plural and gerund forms only. Deliberately not a real
// stemmer — aggressive stemming collapses distinct skills ("analysis" and
// "analytics" are not the same requirement) and the false positives are worse
// than the misses.
function variantsOf(term: string): string[] {
  const base = normalizeText(term);
  if (!base) return [];
  const out = new Set<string>([base]);
  for (const alias of TERM_ALIASES[base] ?? []) out.add(normalizeText(alias));
  for (const v of [...out]) {
    if (v.endsWith("s") && v.length > 3) out.add(v.slice(0, -1));
    else out.add(v + "s");
  }
  return [...out].filter(Boolean);
}

// ---------------------------------------------------------------------------
// The haystack
// ---------------------------------------------------------------------------

export type ResumeSource = {
  parsedText?: string | null;
  parsedJson?: Record<string, unknown> | null;
};

// Everything the candidate's resume says, flattened to one normalized string.
// parsed_text (the real document) is the good surface; parsed_json is the
// fallback for resumes parsed before parsed_text existed, and it carries at
// most 30 skills plus titles — so a null parsed_text means more terms read as
// missing than truly are. Callers surface that with `resumeTextAvailable`.
export function buildResumeHaystack(source: ResumeSource): string {
  const parts: string[] = [];
  if (source.parsedText?.trim()) parts.push(source.parsedText);

  const json = source.parsedJson ?? {};
  const push = (v: unknown) => {
    if (typeof v === "string" && v.trim()) parts.push(v);
  };
  push(json.current_title);
  push(json.current_company);
  push(json.highest_degree);
  push(json.field_of_study);
  push(json.school);
  for (const s of asArray(json.skills)) push(s);
  for (const e of asArray(json.employers)) {
    if (e && typeof e === "object") {
      push((e as Record<string, unknown>).title);
      push((e as Record<string, unknown>).company);
    }
  }
  for (const e of asArray(json.education)) {
    if (e && typeof e === "object") {
      push((e as Record<string, unknown>).degree);
      push((e as Record<string, unknown>).field_of_study);
      push((e as Record<string, unknown>).school);
    }
  }
  // Padded with spaces so word-boundary checks work at both ends.
  return ` ${normalizeText(parts.join(" "))} `;
}

function asArray(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

// ---------------------------------------------------------------------------
// The diff
// ---------------------------------------------------------------------------

// Whole-token match only. A substring test would count "java" as covered by a
// resume that only says "javascript", which is exactly the false positive
// that makes these tools untrustworthy.
export function haystackContains(haystack: string, term: string): boolean {
  for (const variant of variantsOf(term)) {
    if (haystack.includes(` ${variant} `)) return true;
  }
  return false;
}

export function diffKeywords(keywords: JobKeyword[], source: ResumeSource): KeywordGap {
  const haystack = buildResumeHaystack(source);

  const covered: KeywordVerdict[] = [];
  const missing: KeywordVerdict[] = [];
  let earned = 0;
  let total = 0;
  let requiredTotal = 0;
  let requiredCovered = 0;

  // One term can arrive twice from the model under different casing; dedupe on
  // the normalized form so it is not double-weighted.
  const seen = new Set<string>();

  for (const keyword of keywords) {
    const term = keyword.term?.trim();
    if (!term) continue;
    const key = normalizeText(term);
    if (!key || seen.has(key)) continue;
    seen.add(key);

    const isCovered = haystackContains(haystack, term);
    const weight = weightOf(keyword);
    total += weight;
    if (keyword.importance !== "preferred") {
      requiredTotal += 1;
      if (isCovered) requiredCovered += 1;
    }
    if (isCovered) {
      earned += weight;
      covered.push({ ...keyword, term, covered: true });
    } else {
      missing.push({ ...keyword, term, covered: false });
    }
  }

  return {
    // No extracted terms means no opinion. Reporting 0% for a job whose
    // description we could not read would read as "you are a terrible fit".
    coverage: total === 0 ? 0 : Math.round((earned / total) * 100),
    covered,
    missing,
    requiredTotal,
    requiredCovered,
  };
}

// Missing required terms first, then preferred: a candidate skimming this list
// should hit the things that get them screened out before the nice-to-haves.
export function rankMissing(missing: KeywordVerdict[]): KeywordVerdict[] {
  return [...missing].sort((a, b) => {
    const aReq = a.importance !== "preferred" ? 0 : 1;
    const bReq = b.importance !== "preferred" ? 0 : 1;
    if (aReq !== bReq) return aReq - bReq;
    return a.term.localeCompare(b.term);
  });
}
