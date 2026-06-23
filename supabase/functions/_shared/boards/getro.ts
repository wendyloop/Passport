// Getro-hosted portfolio job boards (Accel, Index, General Catalyst, Insight,
// Craft, etc.). Every Getro board — both *.getro.com subdomains and custom
// domains like jobs.accel.com — exposes the same public JSON API on the same
// host:
//   GET {board_url}/api/jobs?per_page=200&page=N
//
// The jobs payload includes a nested `company` object with name/domain/logo
// plus a per-job apply URL we can run through classifyApplyURL to resolve the
// ATS provider + token. We dedupe companies by domain (falling back to name).

import { fetchJSON } from "../ats/http.ts";
import { classifyApplyURL } from "../ats/classify.ts";
import type { FundRow } from "../ats/models.ts";
import type { DiscoveredCompany } from "./models.ts";

type GetroJobsResponse = {
  meta?: { total_count?: number; total_pages?: number; current_page?: number };
  jobs?: GetroJob[];
};

type GetroJob = {
  id?: number | string;
  url?: string;         // apply / posting URL — fed to classifyApplyURL
  title?: string;
  company?: GetroCompany;
};

type GetroCompany = {
  id?: number | string;
  name?: string;
  domain?: string;
  website_url?: string;
  logo_url?: string;
  stage?: string;
  team_size?: string;
  topics?: string[];
  industry_tags?: string[];
};

const PER_PAGE = 200;
const MAX_PAGES = 50;

export async function crawlGetro(fund: FundRow): Promise<DiscoveredCompany[]> {
  if (!fund.board_url) return [];

  // Companies keyed by domain → first occurrence wins, later jobs only fill
  // in ATS coords if still missing.
  const byKey = new Map<string, DiscoveredCompany>();

  for (let page = 1; page <= MAX_PAGES; page++) {
    const url = `${stripTrailingSlash(fund.board_url)}/api/jobs?per_page=${PER_PAGE}&page=${page}`;
    let payload: GetroJobsResponse;
    try {
      payload = await fetchJSON<GetroJobsResponse>(url);
    } catch (error) {
      // Boards that don't expose the public API surface as 404 — surface the
      // error so the orchestrator can record it against the fund.
      throw new Error(`Getro fetch failed for ${fund.slug} page ${page}: ${(error as Error).message}`);
    }

    const jobs = payload.jobs ?? [];
    if (jobs.length === 0) break;

    for (const job of jobs) {
      const company = job.company;
      if (!company?.name) continue;

      const domain = normalizeDomain(company.domain ?? company.website_url ?? null);
      const key = domain ?? company.name.toLowerCase().trim();

      const resolution = classifyApplyURL(job.url ?? null);

      const existing = byKey.get(key);
      if (existing) {
        // Backfill ATS coords from a later job if we didn't have them yet.
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
        headcount: company.team_size ?? null,
        industry: firstNonEmpty(company.industry_tags, company.topics),
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

function firstNonEmpty(...lists: Array<string[] | undefined>): string | null {
  for (const list of lists) {
    if (list && list.length > 0) return list[0];
  }
  return null;
}
