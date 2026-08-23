// Lever public postings API.
//   GET https://api.lever.co/v0/postings/{token}?mode=json
//
// Returns plain JSON array. Richest of the supported ATSes — `applyUrl`,
// `hostedUrl`, structured `salaryRange`, `commitment`, and `categories`.

import { fetchJSON } from "../http.ts";
import {
  computeContentHash,
  extractFirstEmail,
  parseCompensation,
  sanitizeCompensation,
  sanitizeISODate,
  stripHTML,
} from "../compensation.ts";
import { deriveApplyFlow } from "../classify.ts";
import type { AdapterFetchInput, AdapterFetchResult, NormalizedJob } from "../models.ts";

type LeverPosting = {
  id?: string;
  text?: string;
  hostedUrl?: string;
  applyUrl?: string;
  createdAt?: number; // ms epoch
  categories?: {
    commitment?: string;
    department?: string;
    location?: string;
    team?: string;
  };
  descriptionPlain?: string;
  description?: string; // HTML
  salaryRange?: {
    min?: number;
    max?: number;
    currency?: string;
    interval?: string;
  };
};

export async function fetchLever(input: AdapterFetchInput): Promise<AdapterFetchResult> {
  const url = `https://api.lever.co/v0/postings/${encodeURIComponent(input.ats_token)}?mode=json`;
  const postings = await fetchJSON<LeverPosting[]>(url);

  const jobs: NormalizedJob[] = [];
  for (const posting of postings ?? []) {
    if (!posting.id) continue;
    jobs.push(await normalizeLeverPosting(posting));
  }

  return { jobs };
}

async function normalizeLeverPosting(posting: LeverPosting): Promise<NormalizedJob> {
  const descriptionRaw = posting.description ?? null;
  const description = posting.descriptionPlain?.trim() ||
    stripHTML(descriptionRaw);
  const title = posting.text?.trim() || null;
  const listingURL = posting.hostedUrl ?? null;
  const applyURL = posting.applyUrl ?? listingURL;

  const employmentType = posting.categories?.commitment ?? null;
  const category = posting.categories?.team ?? posting.categories?.department ?? null;
  const location = posting.categories?.location ?? null;

  const compensationText = formatLeverSalary(posting.salaryRange);
  // Lever provides structured values; prefer those over re-parsing.
  const compensation = posting.salaryRange
    ? leverSalaryToParsed(posting.salaryRange)
    : parseCompensation(compensationText);

  const postedAt = posting.createdAt
    ? sanitizeISODate(new Date(posting.createdAt).toISOString())
    : null;

  const externalId = posting.id!;

  const contentHash = await computeContentHash([
    title,
    description,
    listingURL,
    applyURL,
    location,
    category,
    employmentType,
    compensationText,
    postedAt,
  ]);

  return {
    source_ats: "lever",
    external_id: externalId,
    title,
    listing_url: listingURL,
    apply_url: applyURL,
    apply_flow: deriveApplyFlow(applyURL),
    compensation_text: compensationText,
    compensation,
    location,
    category,
    employment_type: employmentType,
    posted_at: postedAt,
    description,
    description_raw: descriptionRaw,
    contact_email_on_posting: extractFirstEmail(description),
    content_hash: contentHash,
  };
}

// Structured salaryRange, so it skips the free-text parser — and with it
// that parser's plausibility floor. Run it through sanitizeCompensation
// explicitly; Lever echoes employer typos the same way every board does.
function leverSalaryToParsed(range: NonNullable<LeverPosting["salaryRange"]>) {
  const currency = (range.currency ?? "USD").toUpperCase();
  if (currency !== "USD") {
    return { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null };
  }
  const interval = (range.interval ?? "year").toLowerCase();
  const isHourly = /hour|hr/.test(interval);
  return sanitizeCompensation({
    min_annual: isHourly ? null : range.min ?? null,
    max_annual: isHourly ? null : range.max ?? null,
    min_hourly: isHourly ? range.min ?? null : null,
    max_hourly: isHourly ? range.max ?? null : null,
  });
}

function formatLeverSalary(range: LeverPosting["salaryRange"]): string | null {
  if (!range) return null;
  const currency = range.currency ?? "USD";
  const interval = range.interval ?? "year";
  if (range.min != null && range.max != null) {
    return `${currency} ${range.min.toLocaleString("en-US")} – ${range.max.toLocaleString("en-US")} / ${interval}`;
  }
  if (range.min != null) return `${currency} ${range.min.toLocaleString("en-US")} / ${interval}`;
  if (range.max != null) return `${currency} ${range.max.toLocaleString("en-US")} / ${interval}`;
  return null;
}
