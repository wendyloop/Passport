// Resume↔job matching (M-E/M-F): embedding-text builders and the raw-cosine
// → 0-100 score mapping. One score everywhere — the feed's fit ranking and
// the founder-email gate must never disagree. Pure helpers, covered by
// shared_test.ts.

export type JobEmbeddingSource = {
  title: string | null;
  job_function: string | null;
  company_name: string | null;
  company_stage?: string | null;
  compensation_min_annual?: number | null;
  compensation_max_annual?: number | null;
  description: string | null;
};

const MAX_DESCRIPTION_CHARS = 6000;

// 65% of board rows have no description yet; embed what we have and tag the
// row so the gate can exempt coarse embeddings while ranking still uses them.
export function buildJobEmbeddingText(job: JobEmbeddingSource): { text: string; quality: "full" | "title_only" } {
  const parts: string[] = [];
  if (job.title?.trim()) parts.push(job.title.trim());
  if (job.job_function?.trim()) parts.push(`function: ${job.job_function.trim()}`);
  if (job.company_name?.trim()) parts.push(`company: ${job.company_name.trim()}`);
  if (job.company_stage?.trim()) parts.push(`stage: ${job.company_stage.trim()}`);
  if (job.compensation_min_annual || job.compensation_max_annual) {
    parts.push(`compensation: ${job.compensation_min_annual ?? ""}-${job.compensation_max_annual ?? ""} annual`);
  }
  const description = job.description?.trim();
  if (description) parts.push(description.slice(0, MAX_DESCRIPTION_CHARS));
  return { text: parts.join("\n"), quality: description ? "full" : "title_only" };
}

export type ResumeEmbeddingSource = {
  current_title?: string;
  current_company?: string;
  years_experience?: string;
  field_of_study?: string;
  employers?: Array<{ company?: string; title?: string; bullets?: string[] }>;
  education?: Array<{ school?: string; degree?: string; field_of_study?: string }>;
  skills?: string[];
};

export function buildResumeEmbeddingText(parsed: ResumeEmbeddingSource): string {
  const parts: string[] = [];
  if (parsed.current_title?.trim()) parts.push(`current: ${parsed.current_title.trim()} at ${parsed.current_company?.trim() ?? ""}`.trim());
  if (parsed.years_experience?.trim()) parts.push(`years of experience: ${parsed.years_experience.trim()}`);
  const employers = (parsed.employers ?? [])
    .map((e) => [e.title?.trim(), e.company?.trim()].filter(Boolean).join(" at "))
    .filter(Boolean);
  if (employers.length) parts.push(`experience: ${employers.join("; ")}`);
  // S-4: bullets say what the person actually DID, which is what a job
  // description mostly describes. Titles and companies alone leave the resume
  // embedding thin next to the JD it is compared against. Capped so one
  // verbose role cannot crowd out the rest of the document.
  const bullets = (parsed.employers ?? [])
    .flatMap((e) => (e.bullets ?? []).map((b) => b?.trim()).filter(Boolean))
    .slice(0, 40);
  if (bullets.length) parts.push(`work: ${bullets.join(" ")}`);
  const education = (parsed.education ?? [])
    .map((e) => [e.degree?.trim(), e.field_of_study?.trim(), e.school?.trim()].filter(Boolean).join(" "))
    .filter(Boolean);
  if (education.length) parts.push(`education: ${education.join("; ")}`);
  const skills = (parsed.skills ?? []).map((s) => s.trim()).filter(Boolean);
  if (skills.length) parts.push(`skills: ${skills.join(", ")}`);
  return parts.join("\n");
}

// Raw cosine similarity clusters ~0.3-0.7 for this model; map through a
// tunable floor/ceiling (app_config) so "50" means a plausible fit. The SQL
// RPC job_match_scores mirrors this formula exactly.
//
// TODO(deferred): S-2b — floor 0.20 / ceiling 0.75 are UNVALIDATED GUESSES,
// and the scores they produce are already live: AppSessionStore reorders the
// feed by MatchFit.bucket (70/50 on the mapped score), so a mis-set floor
// silently promotes the wrong jobs. Nothing is broken and nothing is blocked
// from shipping; the ranking is simply unverified, and
// founder_email_require_match cannot be turned on until it is.
//
// Calibrate on ~50 real resume/job pairs — a data problem, not a code one.
// Re-embed every resume FIRST: S-4 added bullets to buildResumeEmbeddingText
// below, so any embedding written before 2026-09-02 came from a text builder
// that no longer exists. parse-resume rewrites the embedding on every parse,
// so reparseResume (which reads stored parsed_text, no re-upload) is the
// whole migration.
export function mapSimilarityToScore(similarity: number, floor: number, ceiling: number): number {
  if (!(ceiling > floor)) return 0;
  const normalized = (similarity - floor) / (ceiling - floor);
  return Math.round(Math.max(0, Math.min(1, normalized)) * 100);
}
