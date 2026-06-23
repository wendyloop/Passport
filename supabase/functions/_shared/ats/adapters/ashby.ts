// Ashby public job-board API.
//   GET https://api.ashbyhq.com/posting-api/job-board/{token}?includeCompensation=true
//
// Returns { jobs: [...] }. Provides applyUrl, jobUrl, employmentType,
// publishedAt (ISO), descriptionPlain/Html, compensationTierSummary.

import { fetchJSON } from "../http.ts";
import {
  computeContentHash,
  extractFirstEmail,
  parseCompensation,
  sanitizeISODate,
  stripHTML,
} from "../compensation.ts";
import { deriveApplyFlow } from "../classify.ts";
import type { AdapterFetchInput, AdapterFetchResult, NormalizedJob } from "../models.ts";

type AshbyResponse = {
  jobs?: AshbyJob[];
};

type AshbyJob = {
  id?: string;
  title?: string;
  jobUrl?: string;
  applyUrl?: string;
  employmentType?: string;
  location?: string;
  secondaryLocations?: Array<{ location?: string }>;
  department?: string;
  team?: string;
  publishedAt?: string;
  descriptionPlain?: string;
  descriptionHtml?: string;
  compensationTierSummary?: string;
};

export async function fetchAshby(input: AdapterFetchInput): Promise<AdapterFetchResult> {
  const url = `https://api.ashbyhq.com/posting-api/job-board/${encodeURIComponent(input.ats_token)}?includeCompensation=true`;
  const response = await fetchJSON<AshbyResponse>(url);

  const jobs: NormalizedJob[] = [];
  for (const job of response.jobs ?? []) {
    if (!job.id) continue;
    jobs.push(await normalizeAshbyJob(job));
  }

  return { jobs };
}

async function normalizeAshbyJob(job: AshbyJob): Promise<NormalizedJob> {
  const descriptionRaw = job.descriptionHtml ?? null;
  const description = job.descriptionPlain?.trim() || stripHTML(descriptionRaw);
  const title = job.title?.trim() || null;
  const listingURL = job.jobUrl ?? null;
  const applyURL = job.applyUrl ?? listingURL;

  const locations = [job.location, ...(job.secondaryLocations?.map((s) => s.location) ?? [])]
    .filter((l): l is string => !!l && l.trim().length > 0);
  const location = locations[0] ?? null;

  const compensationText = job.compensationTierSummary?.trim() || null;
  const compensation = parseCompensation(compensationText);

  const postedAt = sanitizeISODate(job.publishedAt);
  const category = job.team ?? job.department ?? null;

  const externalId = job.id!;

  const contentHash = await computeContentHash([
    title,
    description,
    listingURL,
    applyURL,
    location,
    category,
    job.employmentType ?? null,
    compensationText,
    postedAt,
  ]);

  return {
    source_ats: "ashby",
    external_id: externalId,
    title,
    listing_url: listingURL,
    apply_url: applyURL,
    apply_flow: deriveApplyFlow(applyURL),
    compensation_text: compensationText,
    compensation,
    location,
    category,
    employment_type: job.employmentType ?? null,
    posted_at: postedAt,
    description,
    description_raw: descriptionRaw,
    contact_email_on_posting: extractFirstEmail(description),
    content_hash: contentHash,
  };
}
