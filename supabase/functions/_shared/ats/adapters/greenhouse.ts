// Greenhouse public job board API.
//   Jobs:  GET https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true
//   Board: GET https://boards-api.greenhouse.io/v1/boards/{token}
//
// Apply URL = absolute_url (Greenhouse hosts the apply form on the same page
// as the listing). Description arrives as HTML in `content`.

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

type GreenhouseListResponse = {
  jobs: Array<GreenhouseJob>;
};

type GreenhouseBoardResponse = {
  name?: string | null;
};

type GreenhouseJob = {
  id: number;
  internal_job_id?: number;
  title?: string;
  absolute_url?: string;
  updated_at?: string;
  first_published?: string;
  location?: { name?: string };
  metadata?: Array<{ name?: string; value?: string | string[] | null }>;
  departments?: Array<{ name?: string }>;
  offices?: Array<{ name?: string }>;
  content?: string; // HTML
  pay_input_ranges?: Array<{
    min_cents?: number;
    max_cents?: number;
    currency_type?: string;
    interval?: string;
  }>;
};

export async function fetchGreenhouse(input: AdapterFetchInput): Promise<AdapterFetchResult> {
  const base = `https://boards-api.greenhouse.io/v1/boards/${encodeURIComponent(input.ats_token)}`;
  const [listResponse, boardResponse] = await Promise.all([
    fetchJSON<GreenhouseListResponse>(`${base}/jobs?content=true`),
    fetchJSON<GreenhouseBoardResponse>(base).catch(() => ({}) as GreenhouseBoardResponse),
  ]);

  const jobs: NormalizedJob[] = [];
  for (const job of listResponse.jobs ?? []) {
    if (!job.id) continue;
    jobs.push(await normalizeGreenhouseJob(job));
  }

  return {
    jobs,
    company_name_from_source: boardResponse?.name ?? null,
  };
}

async function normalizeGreenhouseJob(job: GreenhouseJob): Promise<NormalizedJob> {
  const descriptionRaw = job.content ?? null;
  const description = stripHTML(descriptionRaw);
  const title = job.title?.trim() || null;
  const listingURL = job.absolute_url ?? null;
  const applyURL = listingURL;

  const employmentTypeMetadata = job.metadata?.find((m) =>
    typeof m.name === "string" && /employment/i.test(m.name)
  );
  const employmentType = stringOrNull(employmentTypeMetadata?.value);

  const category = job.departments?.[0]?.name ?? null;

  const payRange = job.pay_input_ranges?.[0];
  const compensationText = formatGreenhousePayRange(payRange);
  const compensation = parseCompensation(compensationText);

  const postedAt = sanitizeISODate(job.first_published ?? job.updated_at);

  const externalId = String(job.id);

  const contentHash = await computeContentHash([
    title,
    description,
    listingURL,
    applyURL,
    job.location?.name ?? null,
    category,
    employmentType,
    compensationText,
    postedAt,
  ]);

  return {
    source_ats: "greenhouse",
    external_id: externalId,
    title,
    listing_url: listingURL,
    apply_url: applyURL,
    apply_flow: deriveApplyFlow(applyURL),
    compensation_text: compensationText,
    compensation,
    location: job.location?.name ?? null,
    category,
    employment_type: employmentType,
    posted_at: postedAt,
    description,
    description_raw: descriptionRaw,
    contact_email_on_posting: extractFirstEmail(description),
    content_hash: contentHash,
  };
}

function formatGreenhousePayRange(range: GreenhouseJob["pay_input_ranges"] extends Array<infer T> ? T | undefined : never): string | null {
  if (!range) return null;
  const min = range.min_cents != null ? range.min_cents / 100 : null;
  const max = range.max_cents != null ? range.max_cents / 100 : null;
  if (min == null && max == null) return null;
  const currency = range.currency_type ?? "USD";
  const interval = range.interval ?? "year";
  if (min != null && max != null) return `${currency} ${formatMoney(min)} – ${formatMoney(max)} / ${interval}`;
  return `${currency} ${formatMoney(min ?? max ?? 0)} / ${interval}`;
}

function formatMoney(n: number): string {
  return n >= 1000 ? `${Math.round(n).toLocaleString("en-US")}` : `${n}`;
}

function stringOrNull(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (Array.isArray(value)) {
    const first = value.find((v) => typeof v === "string" && v.trim());
    return typeof first === "string" ? first.trim() : null;
  }
  return null;
}
