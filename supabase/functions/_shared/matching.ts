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
  employers?: Array<{ company?: string; title?: string }>;
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
export function mapSimilarityToScore(similarity: number, floor: number, ceiling: number): number {
  if (!(ceiling > floor)) return 0;
  const normalized = (similarity - floor) / (ceiling - floor);
  return Math.round(Math.max(0, Math.min(1, normalized)) * 100);
}
