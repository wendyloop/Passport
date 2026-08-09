// Work at a Startup adapter — YC's official job board.
//
// Shape differs from Getro/Consider: WaaS has no search API and its public
// listing pages are teasers (~28 rows, no pagination), so enumeration is
// company-by-company. Every page embeds its server props as a JSON blob in
// `data-page`, which is what we parse — no HTML scraping.
//
//   1. GET {external_collection_id}  → yc-oss hiring list (public, keyless,
//      refreshed daily): ~1,490 YC companies currently hiring, each with a
//      slug that matches its WaaS page.
//   2. GET /companies/{slug}  → company metadata (domain, teamSize, batch,
//      industry, logo), FOUNDERS, and the company's full job list.
//   3. GET /jobs/{id}         → that job's descriptionHtml.
//
// Step 3 is why this board matters: descriptions arrive at ingest time, so
// WaaS jobs are carousel-ready immediately and never enter the
// enrich-descriptions queue (which can't reach WaaS at all).
//
// The cursor is the last company slug processed — the orchestrator resumes
// from the next one, so one crawl spreads across many budget-limited runs.
// Requests carry an honest scout22 user-agent; WaaS requires an explicit
// `Accept: text/html` (a request without one gets 406).

import type {
  AdapterInput,
  AdapterResult,
  BoardCompany,
  BoardJob,
} from "./types.ts";

const USER_AGENT = "scout22-jobbot/1.0 (+https://tryscout22.com)";
const ORIGIN_FALLBACK = "https://www.workatastartup.com";
const HIRING_LIST_FALLBACK = "https://yc-oss.github.io/api/companies/hiring.json";
const FETCH_TIMEOUT_MS = 15_000;
// Politeness gap between page fetches — WaaS is a small startup's site.
const REQUEST_DELAY_MS = 250;
// Hard ceiling per run regardless of budget, so one fund can't monopolize
// an ingest cycle shared with the other boards.
const MAX_COMPANIES_PER_RUN = 40;

type YCListEntry = { slug?: string; name?: string };

type WaaSFounder = {
  name?: string;
  bio?: string;
  linkedin?: string;
};

type WaaSCompanyJob = {
  id?: number;
  title?: string;
  location?: string;
  jobType?: string;
  salaryRange?: string | null;
  minExperience?: string | null;
};

type WaaSCompany = {
  name?: string;
  slug?: string;
  batch?: string;
  description?: string;
  logoUrl?: string;
  url?: string;
  location?: string;
  teamSize?: number;
  industry?: string;
  founders?: WaaSFounder[];
  jobs?: WaaSCompanyJob[];
};

// Founders ride out alongside companies; ingest-jobs hands them to the
// existing company_contacts pipeline (source 'yc_directory').
export type WaaSCompanyFounders = {
  company_board_external_id: string;
  founders: Array<{ full_name: string; role_title: string | null }>;
};

export type WaaSResult = AdapterResult & { founders: WaaSCompanyFounders[] };

export async function workAtAStartupAdapter(input: AdapterInput): Promise<WaaSResult> {
  const { fund, startCursor, budgetMs } = input;
  const origin = stripTrailingSlash(fund.board_url ?? ORIGIN_FALLBACK);
  const listURL = fund.external_collection_id ?? HIRING_LIST_FALLBACK;
  const startedAt = Date.now();

  const slugs = await fetchHiringSlugs(listURL);
  if (slugs.length === 0) {
    throw new Error(`WaaS hiring list ${listURL} returned no companies`);
  }

  // Resume after the last slug we finished. A slug that vanished from the
  // list (company stopped hiring) restarts the sweep rather than stalling.
  const resumeAt = startCursor ? slugs.indexOf(startCursor) + 1 : 0;
  const startIndex = resumeAt > 0 && resumeAt < slugs.length ? resumeAt : 0;

  const companies: BoardCompany[] = [];
  const jobs: BoardJob[] = [];
  const founders: WaaSCompanyFounders[] = [];

  let lastSlug: string | null = startCursor ?? null;
  let processed = 0;
  let index = startIndex;

  for (; index < slugs.length; index++) {
    if (processed >= MAX_COMPANIES_PER_RUN) break;
    if (Date.now() - startedAt > budgetMs) break;

    const slug = slugs[index];
    let company: WaaSCompany | null;
    try {
      company = await fetchCompany(origin, slug);
    } catch (error) {
      // One dead company page must not abort the sweep — log, skip, advance
      // the cursor so the next run doesn't retry the same broken slug.
      console.log(JSON.stringify({
        event: "waas_company_fetch_failed",
        slug,
        error: (error as Error).message,
      }));
      lastSlug = slug;
      processed += 1;
      continue;
    }

    processed += 1;
    lastSlug = slug;
    if (!company?.name) continue;

    const companyJobs = company.jobs ?? [];
    if (companyJobs.length === 0) continue;

    companies.push({
      board_external_id: slug,
      name: company.name.trim(),
      domain: normalizeDomain(company.url ?? null),
      logo_url: company.logoUrl ?? null,
      // YC batch ("S26") is the most honest stage signal WaaS gives us.
      stage: company.batch ? `YC ${company.batch}` : null,
      headcount: company.teamSize != null ? String(company.teamSize) : null,
      industry: company.industry ?? null,
    });

    const founderRows = (company.founders ?? [])
      .map((f) => (f.name ?? "").trim())
      .filter((name) => name.length > 0)
      .map((full_name) => ({ full_name, role_title: "Founder" }));
    if (founderRows.length > 0) {
      founders.push({ company_board_external_id: slug, founders: founderRows });
    }

    for (const job of companyJobs) {
      if (job.id == null || !job.title) continue;

      // Description needs its own page. Out of budget → still emit the job
      // (title/comp/location are useful now); a later pass fills the body
      // via the RPC's coalesce, so nothing is lost.
      let description: string | null = null;
      if (Date.now() - startedAt <= budgetMs) {
        try {
          description = await fetchJobDescription(origin, job.id);
        } catch {
          description = null;
        }
      }

      jobs.push({
        board_external_id: String(job.id),
        company_board_external_id: slug,
        // The public posting, NOT WaaS's applyUrl — that one redirects
        // through a YC login wall, so it's useless as a destination.
        apply_url: `${origin}/jobs/${job.id}`,
        title: job.title,
        location: job.location ?? company.location ?? null,
        posted_at: null, // WaaS exposes no posting date
        compensation_text: job.salaryRange ?? null,
        compensation: { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
        employment_type: job.jobType ?? null,
        description: description ? htmlToText(description) : null,
        description_raw: description,
      });
    }
  }

  const drained = index >= slugs.length;
  return {
    companies,
    jobs,
    founders,
    nextCursor: drained ? null : lastSlug,
    pages: processed,
  };
}

async function fetchHiringSlugs(listURL: string): Promise<string[]> {
  const res = await fetchWithTimeout(listURL, { Accept: "application/json" });
  const payload = await res.json() as YCListEntry[];
  if (!Array.isArray(payload)) return [];
  return payload
    .map((entry) => entry.slug?.trim())
    .filter((slug): slug is string => !!slug)
    // Stable ordering so the cursor means the same thing across runs even
    // as companies enter and leave the hiring list.
    .sort();
}

async function fetchCompany(origin: string, slug: string): Promise<WaaSCompany | null> {
  const html = await fetchPage(`${origin}/companies/${encodeURIComponent(slug)}`);
  const props = extractPageProps(html);
  return (props?.company as WaaSCompany | undefined) ?? null;
}

async function fetchJobDescription(origin: string, jobId: number): Promise<string | null> {
  const html = await fetchPage(`${origin}/jobs/${jobId}`);
  const props = extractPageProps(html);
  const job = props?.job as { descriptionHtml?: string } | undefined;
  return job?.descriptionHtml?.trim() || null;
}

async function fetchPage(url: string): Promise<string> {
  // WaaS 406s any request without an explicit HTML Accept header.
  const res = await fetchWithTimeout(url, { Accept: "text/html" });
  const body = await res.text();
  await sleep(REQUEST_DELAY_MS);
  return body;
}

async function fetchWithTimeout(url: string, headers: Record<string, string>): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT, ...headers },
      signal: controller.signal,
    });
    if (!res.ok) {
      await res.body?.cancel();
      throw new Error(`${url} → HTTP ${res.status}`);
    }
    return res;
  } finally {
    clearTimeout(timer);
  }
}

// Every WaaS page renders its server props into `data-page` on the mount
// node. Exported for tests.
export function extractPageProps(html: string): Record<string, unknown> | null {
  const match = html.match(/data-page="([^"]*)"/);
  if (!match) return null;
  try {
    const decoded = decodeHtmlEntities(match[1]);
    const parsed = JSON.parse(decoded) as { props?: Record<string, unknown> };
    return parsed.props ?? null;
  } catch {
    return null;
  }
}

export function decodeHtmlEntities(value: string): string {
  return value
    .replaceAll("&quot;", "\"")
    .replaceAll("&#39;", "'")
    .replaceAll("&apos;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&nbsp;", " ")
    // Ampersand last — decoding it first would corrupt the entities above.
    .replaceAll("&amp;", "&");
}

// jobs.description is the plain-text body the carousel LLM and embeddings
// read; description_raw keeps the original markup.
export function htmlToText(html: string): string {
  return decodeHtmlEntities(
    html
      .replace(/<\s*(br|\/p|\/li|\/div|\/h[1-6])\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, ""),
  )
    .replace(/\n{3,}/g, "\n\n")
    .split("\n")
    .map((line) => line.trim())
    .join("\n")
    .trim();
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

function stripTrailingSlash(url: string): string {
  return url.endsWith("/") ? url.slice(0, -1) : url;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
