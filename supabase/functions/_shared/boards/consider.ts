// Consider adapter — a16z, Sequoia, Greylock, Lightspeed, Bessemer,
// Kleiner Perkins, NEA.
//
// Endpoint: POST {board_url}/api-boards/search-jobs
//   body: { meta: { size, sequence? }, board: { id, isParent: true },
//           query: { promoteFeatured: true }, grouped: true }
//   reply: { jobs: [{ company, jobs: [...], numMatchingJobs }],
//            meta: { size, sequence }, total }
//
// Each job payload carries both the apply URL AND full company info
// (companyDomain, companyLogos, companyId), so Consider gives us strictly
// more company metadata than Getro per row. Pagination is via the opaque
// `meta.sequence` cursor returned by the API.

import { fetchJSON } from "../http.ts";
import type {
  AdapterInput,
  AdapterResult,
  BoardCompany,
  BoardJob,
} from "./types.ts";

const PAGE_SIZE = 25;
const MAX_PAGES = 200;
const FETCH_TIMEOUT_MS = 20_000;

type ConsiderResponse = {
  jobs?: ConsiderGroup[];
  meta?: { size?: number; sequence?: string | null };
  total?: number;
};

type ConsiderGroup = {
  company?: Record<string, unknown>;
  jobs?: ConsiderJob[];
  numMatchingJobs?: number;
};

type ConsiderJob = {
  applyUrl?: string;
  url?: string;
  jobId?: string;
  title?: string;
  locations?: Array<{ name?: string; label?: string }>;
  timeStamp?: number; // ms or s — we accept either and normalize
  postedAt?: string;
  employmentType?: string;
  compensation?: string;
  companyId?: string;
  companyName?: string;
  companySlug?: string;
  companyDomain?: string;
  companyStaffCount?: number;
  companyLogos?: {
    manual?: { url?: string };
    linkedin?: { url?: string };
  };
  stages?: Array<{ value?: string; label?: string }>;
  markets?: Array<{ value?: string; label?: string }>;
  jobFunctions?: Array<{ value?: string; label?: string }>;
  fundingLV?: { value?: string; label?: string };
};

export async function considerAdapter(input: AdapterInput): Promise<AdapterResult> {
  const { fund, startCursor, budgetMs } = input;
  if (!fund.board_url) {
    throw new Error(`Consider fund ${fund.slug} missing board_url`);
  }
  if (!fund.external_collection_id) {
    throw new Error(
      `Consider fund ${fund.slug} missing external_collection_id (board id like "sequoia-capital")`,
    );
  }

  const url = `${stripTrailingSlash(fund.board_url)}/api-boards/search-jobs`;
  const boardId = fund.external_collection_id;
  const startedAt = Date.now();

  // Companies deduped within this batch by board_external_id (companyId,
  // or slug/domain/name fallback when companyId is missing).
  const companies = new Map<string, BoardCompany>();
  const jobs: BoardJob[] = [];

  let sequence: string | null = startCursor ?? null;
  let lastSequence: string | null = sequence;
  let pagesCompleted = 0;
  let drained = false;

  for (let page = 1; page <= MAX_PAGES; page++) {
    if (Date.now() - startedAt > budgetMs) {
      console.log(JSON.stringify({
        event: "consider_budget_reached",
        fund_slug: fund.slug,
        pages_completed: pagesCompleted,
        companies_so_far: companies.size,
        jobs_so_far: jobs.length,
        cursor: lastSequence,
      }));
      break;
    }

    const body: Record<string, unknown> = {
      meta: sequence ? { size: PAGE_SIZE, sequence } : { size: PAGE_SIZE },
      board: { id: boardId, isParent: true },
      query: { promoteFeatured: true },
      grouped: true,
    };

    let payload: ConsiderResponse;
    try {
      payload = await fetchJSON<ConsiderResponse>(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        timeoutMs: FETCH_TIMEOUT_MS,
      });
    } catch (error) {
      throw new Error(`Consider fetch failed for ${fund.slug} page ${page}: ${(error as Error).message}`);
    }

    const groups = payload.jobs ?? [];
    if (groups.length === 0) {
      drained = true;
      break;
    }

    let newJobsThisPage = 0;

    for (const group of groups) {
      const groupJobs = group.jobs ?? [];
      if (groupJobs.length === 0) continue;

      for (const raw of groupJobs) {
        const applyUrl = raw.applyUrl ?? raw.url;
        const jobId = raw.jobId ?? null;
        const orgId = raw.companyId ?? raw.companySlug ?? raw.companyDomain ?? raw.companyName ?? null;
        if (!applyUrl || !jobId || !orgId || !raw.companyName) continue;

        if (!companies.has(orgId)) {
          companies.set(orgId, {
            board_external_id: orgId,
            name: raw.companyName.trim(),
            domain: normalizeDomain(raw.companyDomain ?? null),
            logo_url: raw.companyLogos?.manual?.url ?? raw.companyLogos?.linkedin?.url ?? null,
            stage: raw.stages?.[0]?.label ?? raw.fundingLV?.label ?? null,
            headcount: raw.companyStaffCount != null ? String(raw.companyStaffCount) : null,
            industry: raw.markets?.[0]?.label ?? raw.jobFunctions?.[0]?.label ?? null,
          });
        }

        jobs.push({
          board_external_id: jobId,
          company_board_external_id: orgId,
          apply_url: applyUrl,
          title: raw.title ?? null,
          location: pickLocation(raw),
          posted_at: pickPostedAt(raw),
          compensation_text: raw.compensation ?? null,
          compensation: { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
          employment_type: raw.employmentType ?? null,
        });
        newJobsThisPage += 1;
      }
    }

    pagesCompleted += 1;
    sequence = payload.meta?.sequence ?? null;
    lastSequence = sequence;
    if (!sequence) {
      drained = true;
      break;
    }
    if (newJobsThisPage === 0) {
      // Some boards keep returning a non-null cursor forever once exhausted.
      // No new content this page → treat as drained.
      drained = true;
      break;
    }
  }

  return {
    companies: Array.from(companies.values()),
    jobs,
    nextCursor: drained ? null : lastSequence,
    pages: pagesCompleted,
  };
}

function pickLocation(job: ConsiderJob): string | null {
  const first = job.locations?.[0];
  return first?.name ?? first?.label ?? null;
}

function pickPostedAt(job: ConsiderJob): string | null {
  if (job.postedAt) return job.postedAt;
  if (job.timeStamp == null) return null;
  // Some boards return seconds, some ms. Heuristic: ms is > 10^12.
  const ms = job.timeStamp > 1e12 ? job.timeStamp : job.timeStamp * 1000;
  const d = new Date(ms);
  return Number.isFinite(d.getTime()) ? d.toISOString() : null;
}


function stripTrailingSlash(url: string): string {
  return url.endsWith("/") ? url.slice(0, -1) : url;
}

function normalizeDomain(raw: string | null): string | null {
  if (!raw) return null;
  const trimmed = raw.trim().toLowerCase();
  if (!trimmed) return null;
  try {
    const withScheme = trimmed.startsWith("http") ? trimmed : `https://${trimmed}`;
    const host = new URL(withScheme).hostname;
    return host.startsWith("www.") ? host.slice(4) : host;
  } catch {
    return trimmed.replace(/^www\./, "");
  }
}
