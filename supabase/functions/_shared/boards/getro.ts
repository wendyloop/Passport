// Getro adapter — Accel, Index, General Catalyst, Insight, Craft.
//
// Endpoint: POST https://api.getro.com/api/v2/collections/<id>/search/jobs
//   body:   { hitsPerPage: N, page: M }
//   reply:  { results: { jobs: [...], count: N } }
//
// Each job payload includes the apply URL plus an embedded `organization`
// blob (name, logo, stage, head_count, industry_tags). It does NOT include
// the company's domain — that field stays null and the orchestrator falls
// back to (source_board, board_external_id) for dedup.
//
// Pagination is numeric, 0-indexed. We persist the next page number as
// the cursor; on drain we return null so the orchestrator clears it.

import { postJSON } from "../http.ts";
import type {
  AdapterInput,
  AdapterResult,
  BoardCompany,
  BoardJob,
} from "./types.ts";

const API_BASE = "https://api.getro.com/api/v2/collections";
// Getro hard-caps responses at 20 jobs per page; larger hitsPerPage values
// are silently ignored. Setting this to the actual cap is essential — if it's
// higher, the "short last page" drain heuristic fires on page 0.
const HITS_PER_PAGE = 20;
const FETCH_TIMEOUT_MS = 20_000;

type GetroSearchResponse = {
  results?: {
    jobs?: GetroJob[];
    count?: number;
  };
};

type GetroJob = {
  id?: number | string;
  title?: string;
  url?: string;
  searchable_locations?: string[];
  locations?: Array<{ name?: string }>;
  created_at?: number; // unix seconds
  compensation_amount_min_cents?: number | null;
  compensation_amount_max_cents?: number | null;
  compensation_currency?: string | null;
  compensation_period?: string | null;
  work_mode?: string | null;
  seniority?: string | null;
  source?: string;
  organization?: {
    id?: number | string;
    slug?: string;
    name?: string;
    logo_url?: string | null;
    stage?: string | null;
    head_count?: number | null;
    industry_tags?: string[] | null;
  };
};

export async function getroAdapter(input: AdapterInput): Promise<AdapterResult> {
  const { fund, startCursor, budgetMs } = input;
  if (!fund.external_collection_id) {
    throw new Error(
      `Getro fund ${fund.slug} missing external_collection_id (collection number from api.getro.com)`,
    );
  }

  const url = `${API_BASE}/${encodeURIComponent(fund.external_collection_id)}/search/jobs`;
  const startedAt = Date.now();
  let page = parseStartCursor(startCursor);

  // Companies are deduped within this batch by board_external_id so the
  // orchestrator only has to upsert each once.
  const companies = new Map<string, BoardCompany>();
  const jobs: BoardJob[] = [];

  let pagesCompleted = 0;
  let drained = false;

  for (let safety = 0; safety < 5_000; safety++) {
    if (Date.now() - startedAt > budgetMs) {
      console.log(JSON.stringify({
        event: "getro_budget_reached",
        fund_slug: fund.slug,
        page,
        pages_completed: pagesCompleted,
        jobs_collected: jobs.length,
      }));
      break;
    }

    let payload: GetroSearchResponse;
    try {
      // TODO(deferred): use _shared/ats/http.ts fetchWithRetry instead of the
      // plain postJSON — it adds 5xx/429 backoff. Board crawl is cron and
      // resumes from its cursor next run, so transient failures are cheap;
      // low priority. Effort: small. See docs/DEFERRED_WORK.md.
      payload = await postJSON<GetroSearchResponse>(url, { hitsPerPage: HITS_PER_PAGE, page }, FETCH_TIMEOUT_MS);
    } catch (error) {
      throw new Error(`Getro fetch failed for ${fund.slug} page ${page}: ${(error as Error).message}`);
    }

    const batch = payload.results?.jobs ?? [];
    if (batch.length === 0) {
      drained = true;
      break;
    }

    for (const raw of batch) {
      const org = raw.organization;
      const orgId = org?.id != null ? String(org.id) : (org?.slug ?? null);
      const applyUrl = raw.url;
      const jobId = raw.id != null ? String(raw.id) : null;
      if (!orgId || !org?.name || !applyUrl || !jobId) continue;

      if (!companies.has(orgId)) {
        companies.set(orgId, {
          board_external_id: orgId,
          name: org.name.trim(),
          domain: null,
          logo_url: org.logo_url ?? null,
          stage: org.stage ?? null,
          headcount: org.head_count != null ? String(org.head_count) : null,
          industry: org.industry_tags?.[0] ?? null,
        });
      }

      jobs.push({
        board_external_id: jobId,
        company_board_external_id: orgId,
        apply_url: applyUrl,
        title: raw.title ?? null,
        location: pickLocation(raw),
        posted_at: raw.created_at ? new Date(raw.created_at * 1000).toISOString() : null,
        compensation_text: null,
        compensation: parseGetroComp(raw),
        employment_type: null,
      });
    }

    pagesCompleted += 1;
    page += 1;
    if (batch.length < HITS_PER_PAGE) {
      // Last page is short of full → no more pages. Saves one wasted call.
      drained = true;
      break;
    }
  }

  return {
    companies: Array.from(companies.values()),
    jobs,
    nextCursor: drained ? null : String(page),
    pages: pagesCompleted,
  };
}

function parseStartCursor(cursor: string | null): number {
  if (!cursor) return 0;
  const parsed = Number.parseInt(cursor, 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function pickLocation(job: GetroJob): string | null {
  const named = job.locations?.find((l) => l.name)?.name;
  if (named) return named;
  return job.searchable_locations?.[0] ?? null;
}

function parseGetroComp(job: GetroJob) {
  const period = (job.compensation_period ?? "").toLowerCase();
  const minCents = job.compensation_amount_min_cents ?? null;
  const maxCents = job.compensation_amount_max_cents ?? null;
  const min = minCents != null ? minCents / 100 : null;
  const max = maxCents != null ? maxCents / 100 : null;
  if (period.includes("hour")) {
    return { min_annual: null, max_annual: null, min_hourly: min, max_hourly: max };
  }
  if (period.includes("year") || period.includes("annual")) {
    return { min_annual: min, max_annual: max, min_hourly: null, max_hourly: null };
  }
  // Unknown period — drop, don't guess.
  return { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null };
}
