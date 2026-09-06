// Workday public career-site API.
//   List:   POST https://{host}/wday/cxs/{tenant}/{site}/jobs
//           {"appliedFacets":{},"limit":20,"offset":N,"searchText":"…"}
//   Detail: GET  https://{host}/wday/cxs/{tenant}/{site}{externalPath}
//
// Unauthenticated, like the other five. Three things make it different:
//
// 1. THE ADDRESS IS A TRIPLE. tenant + datacenter host + career site. The
//    shard (wd1/wd3/wd5) is not derivable from the tenant, and the site is
//    not derivable from anything — guessing "RBCCareers" for RBC returns 404.
//    Both have to be read off a real posting URL, which is why slug probing
//    (C-2) cannot reach Workday and the seed lists can.
//
// 2. limit IS CAPPED AT 20, silently. Asking for 100 returns an empty page
//    with a null total rather than an error, so a naive port of the
//    SmartRecruiters paging loop would quietly fetch nothing.
//
// 3. THE LIST RESPONSE IS SPARSE — title, path, location, and a relative
//    "Posted 17 Days Ago" string. No description, no compensation, no real
//    date. Those live on a per-posting detail call, so a full crawl of one
//    enterprise board is 20+ list calls plus one call PER JOB. Boeing alone
//    returns 435 postings for "intern". Hence includeDetails: crawl-companies
//    passes false and takes the cheap wide pass, and enrich-descriptions —
//    which already exists to fill JD bodies for board-ingested rows — does the
//    expensive targeted one later.
//
// Workday does support SERVER-SIDE SEARCH, which none of the other five do.
// That is what keeps this affordable: the early-career filter moves into the
// request instead of downloading a 3,000-job board to keep 40 postings.

import { fetchJSON, pMap } from "../http.ts";
import { computeContentHash, sanitizeISODate, stripHTML } from "../compensation.ts";
import { deriveApplyFlow } from "../classify.ts";
import type { AdapterFetchInput, AdapterFetchResult, NormalizedJob } from "../models.ts";

// Workday silently ignores anything larger and returns an empty page.
const PAGE_SIZE = 20;
// Per search term. 15 × 20 = 300 postings, past which a term is too broad to
// be an early-career query anyway.
const MAX_PAGES_PER_TERM = 15;
const DETAIL_CONCURRENCY = 4;

type WorkdayListResponse = {
  total?: number;
  jobPostings?: Array<{
    title?: string;
    externalPath?: string;
    locationsText?: string;
    postedOn?: string;
    bulletFields?: string[];
  }>;
};

type WorkdayDetail = {
  jobPostingInfo?: {
    title?: string;
    jobDescription?: string;
    startDate?: string;
    timeType?: string;
    location?: string;
    externalUrl?: string;
    jobPostingId?: string;
    jobReqId?: string;
  };
};

export async function fetchWorkday(input: AdapterFetchInput): Promise<AdapterFetchResult> {
  const tenant = input.ats_token;
  const host = input.ats_host;
  const site = input.ats_site;
  if (!host || !site) {
    throw new Error(`workday adapter needs ats_host and ats_site (tenant "${tenant}")`);
  }

  const base = `https://${host}/wday/cxs/${encodeURIComponent(tenant)}/${encodeURIComponent(site)}`;
  // One empty search returns the whole board; callers that want less pass
  // terms. Deduped across terms because "intern" and "graduate" overlap.
  const terms = input.search?.length ? input.search : [""];
  const byPath = new Map<string, NonNullable<WorkdayListResponse["jobPostings"]>[number]>();

  for (const term of terms) {
    for (let page = 0; page < MAX_PAGES_PER_TERM; page++) {
      const response = await fetchJSON<WorkdayListResponse>(`${base}/jobs`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          appliedFacets: {},
          limit: PAGE_SIZE,
          offset: page * PAGE_SIZE,
          searchText: term,
        }),
      });
      const postings = response.jobPostings ?? [];
      for (const posting of postings) {
        if (posting.externalPath) byPath.set(posting.externalPath, posting);
      }
      if (postings.length < PAGE_SIZE) break;
    }
  }

  const listings = [...byPath.values()];
  const includeDetails = input.includeDetails !== false;

  const normalized = await pMap(listings, DETAIL_CONCURRENCY, async (posting) => {
    const path = posting.externalPath!;
    // The public URL drops the /wday/cxs/{tenant} prefix the API uses.
    const publicURL = `https://${host}/${site}${path}`;
    // bulletFields carries the requisition id (JR2026522576) — stable across
    // title edits, unlike the slugified path.
    const externalId = posting.bulletFields?.[0]?.trim() || path;

    let description: string | null = null;
    let postedAt: string | null = null;
    let employmentType: string | null = null;

    if (includeDetails) {
      try {
        const detail = await fetchJSON<WorkdayDetail>(`${base}${path}`);
        const info = detail.jobPostingInfo ?? {};
        description = info.jobDescription ? stripHTML(info.jobDescription) : null;
        // startDate is a real ISO date; the list's "Posted 17 Days Ago" is not
        // parseable into one.
        postedAt = sanitizeISODate(info.startDate);
        employmentType = info.timeType ?? null;
      } catch {
        // Not fatal. A posting with no description still belongs in the feed,
        // and enrich-descriptions retries later.
      }
    }

    const job: NormalizedJob = {
      source_ats: "workday",
      external_id: externalId,
      title: posting.title?.trim() ?? null,
      listing_url: publicURL,
      apply_url: publicURL,
      apply_flow: deriveApplyFlow(publicURL),
      compensation_text: null,
      // Workday exposes compensation only as free text inside the JD, if at
      // all. Parsing it out of the description is enrich-descriptions' job,
      // not the adapter's.
      compensation: { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
      location: posting.locationsText?.trim() ?? null,
      category: null,
      employment_type: employmentType,
      posted_at: postedAt,
      description,
      description_raw: null,
      contact_email_on_posting: null,
      content_hash: await computeContentHash([
        posting.title ?? "",
        posting.locationsText ?? "",
        description ?? "",
      ]),
    };
    return job;
  });

  return { jobs: normalized.filter((job): job is NormalizedJob => job !== null && !!job.title) };
}
