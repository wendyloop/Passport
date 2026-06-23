// Recruitee public offers API.
//   GET https://{token}.recruitee.com/api/offers/
//
// Returns { offers: [...] }. Description and requirements are HTML.

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

type RecruiteeResponse = {
  offers?: RecruiteeOffer[];
};

type RecruiteeOffer = {
  id?: number;
  slug?: string;
  title?: string;
  description?: string; // HTML
  requirements?: string; // HTML
  location?: string;
  city?: string;
  country?: string;
  remote?: boolean;
  department?: string;
  employment_type_code?: string;
  category?: string;
  published_at?: string;
  careers_url?: string;
  careers_apply_url?: string;
  salary?: {
    min?: number;
    max?: number;
    currency?: string;
    period?: string;
  };
};

export async function fetchRecruitee(input: AdapterFetchInput): Promise<AdapterFetchResult> {
  const url = `https://${encodeURIComponent(input.ats_token)}.recruitee.com/api/offers/`;
  const response = await fetchJSON<RecruiteeResponse>(url);

  const jobs: NormalizedJob[] = [];
  for (const offer of response.offers ?? []) {
    if (!offer.id) continue;
    jobs.push(await normalizeRecruiteeOffer(offer));
  }

  return { jobs };
}

async function normalizeRecruiteeOffer(offer: RecruiteeOffer): Promise<NormalizedJob> {
  const descriptionRaw = [offer.description, offer.requirements]
    .filter(Boolean)
    .join("\n\n") || null;
  const description = stripHTML(descriptionRaw);
  const title = offer.title?.trim() || null;
  const listingURL = offer.careers_url ?? null;
  const applyURL = offer.careers_apply_url ?? listingURL;

  const location = offer.remote
    ? "Remote"
    : offer.location ?? joinLocation(offer.city, offer.country);

  const compensationText = formatRecruiteeSalary(offer.salary);
  const compensation = parseCompensation(compensationText);

  const postedAt = sanitizeISODate(offer.published_at);
  const category = offer.department ?? offer.category ?? null;

  const externalId = String(offer.id);

  const contentHash = await computeContentHash([
    title,
    description,
    listingURL,
    applyURL,
    location,
    category,
    offer.employment_type_code ?? null,
    compensationText,
    postedAt,
  ]);

  return {
    source_ats: "recruitee",
    external_id: externalId,
    title,
    listing_url: listingURL,
    apply_url: applyURL,
    apply_flow: deriveApplyFlow(applyURL),
    compensation_text: compensationText,
    compensation,
    location,
    category,
    employment_type: offer.employment_type_code ?? null,
    posted_at: postedAt,
    description,
    description_raw: descriptionRaw,
    contact_email_on_posting: extractFirstEmail(description),
    content_hash: contentHash,
  };
}

function joinLocation(city: string | undefined, country: string | undefined): string | null {
  const parts = [city, country].filter((p): p is string => !!p && p.trim().length > 0);
  return parts.length > 0 ? parts.join(", ") : null;
}

function formatRecruiteeSalary(salary: RecruiteeOffer["salary"]): string | null {
  if (!salary) return null;
  const currency = salary.currency ?? "USD";
  const period = salary.period ?? "year";
  if (salary.min != null && salary.max != null) {
    return `${currency} ${salary.min.toLocaleString("en-US")} – ${salary.max.toLocaleString("en-US")} / ${period}`;
  }
  if (salary.min != null) return `${currency} ${salary.min.toLocaleString("en-US")} / ${period}`;
  if (salary.max != null) return `${currency} ${salary.max.toLocaleString("en-US")} / ${period}`;
  return null;
}
