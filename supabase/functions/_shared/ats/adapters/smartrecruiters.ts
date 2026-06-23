// SmartRecruiters public postings API.
//   GET https://api.smartrecruiters.com/v1/companies/{token}/postings?limit=100&offset=N
//
// Paginated. Each page returns `content: [...]` with totalFound + offset/limit.
// The list response is sparse — JD body lives on a per-posting detail endpoint:
//   GET https://api.smartrecruiters.com/v1/companies/{token}/postings/{id}
// We fetch the detail in parallel (bounded concurrency) to populate the
// description.

import { fetchJSON } from "../http.ts";
import { pMap } from "../http.ts";
import {
  computeContentHash,
  extractFirstEmail,
  parseCompensation,
  sanitizeISODate,
  stripHTML,
} from "../compensation.ts";
import { deriveApplyFlow } from "../classify.ts";
import type { AdapterFetchInput, AdapterFetchResult, NormalizedJob } from "../models.ts";

type SmartRecruitersListResponse = {
  offset?: number;
  limit?: number;
  totalFound?: number;
  content?: SmartRecruitersPosting[];
};

type SmartRecruitersPosting = {
  id?: string;
  uuid?: string;
  name?: string;
  ref?: string;
  refNumber?: string;
  releasedDate?: string;
  postingUrl?: string;
  applyUrl?: string;
  location?: {
    city?: string;
    region?: string;
    country?: string;
    remote?: boolean;
  };
  industry?: { id?: string; label?: string };
  function?: { id?: string; label?: string };
  department?: { id?: string; label?: string };
  typeOfEmployment?: { id?: string; label?: string };
  experienceLevel?: { id?: string; label?: string };
};

type SmartRecruitersDetailResponse = SmartRecruitersPosting & {
  jobAd?: {
    sections?: {
      jobDescription?: { title?: string; text?: string };
      qualifications?: { title?: string; text?: string };
      additionalInformation?: { title?: string; text?: string };
    };
  };
};

const PAGE_SIZE = 100;
const DETAIL_CONCURRENCY = 4;

export async function fetchSmartRecruiters(input: AdapterFetchInput): Promise<AdapterFetchResult> {
  const token = encodeURIComponent(input.ats_token);
  const listings: SmartRecruitersPosting[] = [];
  let offset = 0;
  // Safety bound: never page past 5000 jobs (50 pages). Almost no MVP-scale
  // company is anywhere near this.
  for (let page = 0; page < 50; page++) {
    const url = `https://api.smartrecruiters.com/v1/companies/${token}/postings?limit=${PAGE_SIZE}&offset=${offset}`;
    const response = await fetchJSON<SmartRecruitersListResponse>(url);
    const content = response.content ?? [];
    listings.push(...content);
    if (content.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }

  const normalized = await pMap(listings, DETAIL_CONCURRENCY, async (posting) => {
    if (!posting.id) return null;
    let detail: SmartRecruitersDetailResponse = posting;
    try {
      detail = await fetchJSON<SmartRecruitersDetailResponse>(
        `https://api.smartrecruiters.com/v1/companies/${token}/postings/${encodeURIComponent(posting.id)}`,
      );
    } catch {
      // Detail-fetch failures aren't fatal — we still upsert with whatever
      // the list response gave us.
    }
    return normalizeSmartRecruitersPosting(input.ats_token, detail);
  });

  return { jobs: normalized.filter((j): j is NormalizedJob => j !== null) };
}

async function normalizeSmartRecruitersPosting(
  token: string,
  posting: SmartRecruitersDetailResponse,
): Promise<NormalizedJob> {
  const title = posting.name?.trim() || null;
  const listingURL = posting.postingUrl ??
    `https://jobs.smartrecruiters.com/${token}/${posting.id}`;
  const applyURL = posting.applyUrl ?? listingURL;

  const descriptionRaw = [
    posting.jobAd?.sections?.jobDescription?.text,
    posting.jobAd?.sections?.qualifications?.text,
    posting.jobAd?.sections?.additionalInformation?.text,
  ].filter(Boolean).join("\n\n") || null;
  const description = stripHTML(descriptionRaw);

  const location = formatSmartRecruitersLocation(posting.location);
  const category = posting.function?.label ?? posting.department?.label ?? null;
  const employmentType = posting.typeOfEmployment?.label ?? null;
  const postedAt = sanitizeISODate(posting.releasedDate);

  // SmartRecruiters does not expose compensation in v1.
  const compensationText = null;
  const compensation = parseCompensation(compensationText);

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
    source_ats: "smartrecruiters",
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

function formatSmartRecruitersLocation(location: SmartRecruitersPosting["location"]): string | null {
  if (!location) return null;
  if (location.remote) return "Remote";
  const parts = [location.city, location.region, location.country]
    .filter((p): p is string => !!p && p.trim().length > 0);
  return parts.length > 0 ? parts.join(", ") : null;
}
