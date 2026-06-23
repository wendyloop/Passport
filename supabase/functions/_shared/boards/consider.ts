// Consider.com portfolio job boards (a16z, Sequoia, Greylock, Lightspeed,
// Bessemer, Kleiner Perkins, NEA). Each board is served from the fund's own
// domain but proxies through Consider's API:
//   GET {board_url}/api-v2/jobs?per_page=200&page=N
//
// Jobs include a nested `company` object and a per-job `apply_url` we feed to
// classifyApplyURL. Pagination via `meta.total_pages`.

import { fetchJSON } from "../ats/http.ts";
import { classifyApplyURL } from "../ats/classify.ts";
import type { FundRow } from "../ats/models.ts";
import type { DiscoveredCompany } from "./models.ts";

type ConsiderJobsResponse = {
  meta?: { total_count?: number; total_pages?: number; current_page?: number };
  jobs?: ConsiderJob[];
};

type ConsiderJob = {
  id?: number | string;
  apply_url?: string;
  url?: string;
  title?: string;
  company?: ConsiderCompany;
};

type ConsiderCompany = {
  id?: number | string;
  name?: string;
  domain?: string;
  website?: string;
  logo_url?: string;
  stage?: string;
  size?: string;
  headcount?: string;
  industry?: string;
  industries?: string[];
};

const PER_PAGE = 200;
const MAX_PAGES = 50;

export async function crawlConsider(fund: FundRow): Promise<DiscoveredCompany[]> {
  if (!fund.board_url) return [];

  const byKey = new Map<string, DiscoveredCompany>();

  for (let page = 1; page <= MAX_PAGES; page++) {
    const url = `${stripTrailingSlash(fund.board_url)}/api-v2/jobs?per_page=${PER_PAGE}&page=${page}`;
    let payload: ConsiderJobsResponse;
    try {
      payload = await fetchJSON<ConsiderJobsResponse>(url);
    } catch (error) {
      throw new Error(`Consider fetch failed for ${fund.slug} page ${page}: ${(error as Error).message}`);
    }

    const jobs = payload.jobs ?? [];
    if (jobs.length === 0) break;

    for (const job of jobs) {
      const company = job.company;
      if (!company?.name) continue;

      const domain = normalizeDomain(company.domain ?? company.website ?? null);
      const key = domain ?? company.name.toLowerCase().trim();
      const applyURL = job.apply_url ?? job.url ?? null;
      const resolution = classifyApplyURL(applyURL);

      const existing = byKey.get(key);
      if (existing) {
        if (!existing.ats_type && resolution) {
          existing.ats_type = resolution.ats_type;
          existing.ats_token = resolution.ats_token;
        }
        continue;
      }

      byKey.set(key, {
        name: company.name.trim(),
        domain,
        logo_url: company.logo_url ?? null,
        ats_type: resolution?.ats_type ?? null,
        ats_token: resolution?.ats_token ?? null,
        stage: company.stage ?? null,
        headcount: company.headcount ?? company.size ?? null,
        industry: company.industry ?? company.industries?.[0] ?? null,
        source_board: fund.slug,
      });
    }

    const totalPages = payload.meta?.total_pages ?? null;
    if (totalPages != null && page >= totalPages) break;
    if (jobs.length < PER_PAGE) break;
  }

  return Array.from(byKey.values());
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
