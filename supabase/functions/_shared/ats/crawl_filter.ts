// C-8: what the direct company crawler keeps, and which companies it visits
// first.
//
// The filter is the load-bearing half. Crawling one enterprise board for 40
// internships would otherwise ingest ~3,000 postings, and 99.8% of active jobs
// carry a generated carousel — job volume IS spend. So the pivot is enforced
// before insert rather than at read time.

import { classifyExperience } from "../title_classify.ts";
import type { NormalizedJob } from "./models.ts";

// Titles that classifyExperience cannot bucket but that early-career hiring
// uses constantly. Deliberately narrow: each of these is a term of art, not a
// word that shows up in senior titles.
// WORD-BOUNDED, not substring. A plain `includes("intern")` matches "Internal
// Auditor" and "International Tax" — a dry run against Stripe's and
// Anthropic's live boards returned 24 "early-career" jobs and every one was
// an Internal/International false positive. Same lesson as the EEO patterns
// in ATSAutofillPolicy, where \brace\b must not fire on "embrace".
const EARLY_CAREER_HINTS: RegExp[] = [
  "intern", "internship", "co-?op",
  "new grad(uate)?", "university grad(uate)?", "campus",
  "graduate program", "graduate scheme", "rotational",
  "apprentice", "trainee", "entry[ -]level",
  "early[ -]career", "student",
  // Banking, law and consulting name their entry programmes this way and
  // never say "intern": "2027 Summer Analyst Program". The qualifier is
  // load-bearing — a bare "analyst" would keep every Data Analyst opening.
  "summer analyst", "summer associate", "summer program",
].map((pattern) => new RegExp(`\\b${pattern}s?\\b`, "i"));

/// Keep a posting only if it is plausibly early career.
///
/// classifyExperience is the primary signal — it already returns "intern" and
/// "entry" and its ordering puts intern/entry markers ahead of seniority words,
/// so "Senior Software Engineering Intern" reads as an internship. The hint
/// list catches titles it returns null for, which is the majority of
/// enterprise phrasing ("2027 Summer Analyst Program").
///
/// Anything it can classify as mid/senior/staff/exec is dropped outright: a
/// crawl that keeps those defeats the point of crawling at all.
export function keepForEarlyCareerFeed(job: NormalizedJob): boolean {
  const title = job.title?.trim();
  if (!title) return false;

  const level = classifyExperience(title);
  if (level === "intern" || level === "entry") return true;
  // A confident non-early classification is a rejection, not an invitation to
  // go looking for hints — "Senior Engineer, Student Products" must not be
  // kept because it contains "student".
  if (level) return false;

  return EARLY_CAREER_HINTS.some((hint) => hint.test(title));
}

type CompanyRow = {
  id: string;
  name: string | null;
  ats_type: string | null;
  ats_token: string | null;
  last_crawled_at: string | null;
};

type Admin = { from: (table: string) => any };

/// Companies already known to post early-career roles go first.
///
/// 679 of 3,111 companies have ever posted an intern or entry role, and they
/// are by far the likeliest to do so again. Ordering by that costs one query
/// and front-loads the yield, which matters because the run budget caps each
/// pass at ~25 companies.
export async function crawlPriority(
  admin: Admin,
  companies: CompanyRow[],
): Promise<CompanyRow[]> {
  if (companies.length === 0) return companies;

  const { data } = await admin
    .from("jobs")
    .select("company_id")
    .in("company_id", companies.map((c) => c.id))
    .in("experience_level", ["intern", "entry"]);

  const proven = new Set((data ?? []).map((r: { company_id: string }) => r.company_id));
  // Stable partition rather than a sort: within each group the caller's
  // least-recently-crawled ordering is preserved, so no company can starve.
  return [
    ...companies.filter((c) => proven.has(c.id)),
    ...companies.filter((c) => !proven.has(c.id)),
  ];
}
