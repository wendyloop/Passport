// Getro's per-job endpoint — the JD body the crawl never sees.
//
// ingest-jobs reads the board's *search* endpoint, which returns ~20 jobs per
// request and carries no description: only a `has_description` boolean. The
// text lives behind a second, per-job endpoint:
//
//   GET https://api.getro.com/api/v1/jobs/{job_id}?collection_id={collection}
//
// That per-job cost (1 request per job, versus 1 per 20) is why the crawl
// can't fetch it inline — see enrich-descriptions for the budget split.
//
// Why this matters more than the ATS adapters: 15,760 of the ~16.2k
// description-less jobs came from Getro funds, and Getro holds descriptions
// for postings our ATS adapters can never reach — Workday, Oracle, LinkedIn
// and bare careers pages. Measured on a 400-job random sample: 83% carry a
// real description.
//
// The same response also settles whether the posting is still open, which the
// board-driven expiry sweep in ingest-jobs currently cannot (it only closes
// jobs when a fund drains fully in one run, which the big funds never do).

import { fetchJSON } from "../ats/http.ts";
import { stripHTML } from "../ats/compensation.ts";

const API_BASE = "https://api.getro.com/api/v1/jobs";

// Shorter than the ATS default: this runs once per job, so a slow tail costs
// the whole batch rather than one company.
const FETCH_TIMEOUT_MS = 8_000;

// Below this a "description" is a stub — a one-line "apply on our site"
// pointer — not a JD worth showing in the feed.
const MIN_DESCRIPTION_CHARS = 80;

export type GetroJobDetail = {
  id?: number;
  status?: string | null;
  visibility?: string | null;
  closed_at?: string | null;
  deactivated_at?: string | null;
  description?: string | null;
};

export type GetroOutcome =
  | { kind: "expire"; reason: string }
  | { kind: "describe"; description: string; description_raw: string }
  | { kind: "skip"; reason: string };

export function getroJobDetailURL(jobId: string, collectionId: string): string {
  return `${API_BASE}/${encodeURIComponent(jobId)}?collection_id=${encodeURIComponent(collectionId)}`;
}

export async function fetchGetroJobDetail(
  jobId: string,
  collectionId: string,
): Promise<GetroJobDetail> {
  return await fetchJSON<GetroJobDetail>(
    getroJobDetailURL(jobId, collectionId),
    { timeoutMs: FETCH_TIMEOUT_MS },
  );
}

/**
 * Decide what a job's Getro record says to do with it.
 *
 * Closed-ness is checked first and independently of the description: 73% of
 * the sample was already deactivated, and filling in a JD for a posting no
 * one can apply to would make dead jobs *visible* — strictly worse than
 * leaving them blank, since the feed hides description-less jobs today.
 *
 * Any of four independent signals means closed. Getro sets them together in
 * practice, but treating "active" as the only safe state means a schema
 * change on their side degrades to skipping, never to publishing a dead job.
 */
export function classifyGetroDetail(detail: GetroJobDetail): GetroOutcome {
  if (detail.closed_at) return { kind: "expire", reason: "closed_at" };
  if (detail.deactivated_at) return { kind: "expire", reason: "deactivated_at" };
  if (detail.visibility && detail.visibility !== "visible") {
    return { kind: "expire", reason: `visibility=${detail.visibility}` };
  }
  if (detail.status && detail.status !== "active") {
    return { kind: "expire", reason: `status=${detail.status}` };
  }
  if (!detail.status) return { kind: "skip", reason: "no_status" };

  const raw = detail.description ?? null;
  const text = stripHTML(raw);
  if (!raw || !text || text.length < MIN_DESCRIPTION_CHARS) {
    return { kind: "skip", reason: "no_description" };
  }
  return { kind: "describe", description: text, description_raw: raw };
}
