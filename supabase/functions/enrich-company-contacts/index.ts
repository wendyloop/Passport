// Tier-3 founder contact scrape (website fallback).
//
// The cheaper tiers come first: generate-carousel extracts founders named in
// JDs for free, and enrich-descriptions records verified posting emails.
// This function covers companies those tiers produced nothing for:
//
//   1. get_companies_needing_contact_scrape: companies with a domain, an
//      active job, no scrape attempt, and zero existing contacts. The queue
//      shrinks as tier 1/2 land contacts.
//   2. Fetch the homepage, discover up to MAX_TEAM_PAGES likely team/about
//      pages from its links, fetch those too.
//   3. One gpt-4o-mini structured call → founders (founder/co-founder/CEO
//      only; empty when unsure).
//   4. Guess emails (firstname@domain) and insert via the shared helper —
//      conflict-ignore keeps bounced/verified rows intact.
//
// contacts_scraped_at is bumped even on failure so a broken site can't wedge
// the queue. Per-company isolation mirrors enrich-descriptions.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { callStructured } from "../_shared/openai.ts";
import {
  type FounderCandidate,
  insertFounderContacts,
  normalizeDomain,
} from "../_shared/contacts.ts";

const RUN_BUDGET_MS = 50_000;
// Each company costs 1-3 page fetches (10s timeout each) + one LLM call.
const MAX_COMPANIES_PER_RUN = 15;
const PAGE_FETCH_TIMEOUT_MS = 10_000;
const MAX_TEAM_PAGES = 2;
const MAX_PROMPT_CHARS = 15_000;

const TEAM_PATH_HINT = /about|team|company|people|founders|leadership/i;

type RequestBody = { company_id?: string };

type ScrapeOutcome = {
  company_id: string;
  company_name: string;
  pages_fetched: number;
  founders_found: number;
  contacts_inserted: number;
  error: string | null;
};

type CompanyRow = {
  id: string;
  name: string;
  domain: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const body: RequestBody = await request.json().catch(() => ({}));
  const admin = createAdminClient();

  let companies: CompanyRow[];
  if (body.company_id) {
    const { data, error } = await admin
      .from("companies")
      .select("id, name, domain")
      .eq("id", body.company_id)
      .not("domain", "is", null);
    if (error) return jsonError(`Failed to load company: ${error.message}`);
    companies = (data ?? []) as CompanyRow[];
  } else {
    const { data, error } = await admin.rpc("get_companies_needing_contact_scrape", {
      p_limit: MAX_COMPANIES_PER_RUN,
    });
    if (error) return jsonError(`Failed to load companies: ${error.message}`);
    companies = (data ?? []) as CompanyRow[];
  }

  if (companies.length === 0) {
    return jsonResponse({
      summary: { event: "enrich_company_contacts_run", company_count: 0 },
      outcomes: [],
    });
  }

  const outcomes: ScrapeOutcome[] = [];
  const startedAt = Date.now();
  let budgetHit = false;

  for (const company of companies) {
    if (!body.company_id && Date.now() - startedAt > RUN_BUDGET_MS) {
      budgetHit = true;
      break;
    }

    const outcome = await scrapeCompany(admin, company);
    outcomes.push(outcome);

    // Bump even on error so a broken site doesn't wedge the queue.
    await admin
      .from("companies")
      .update({ contacts_scraped_at: new Date().toISOString() })
      .eq("id", company.id);

    console.log(JSON.stringify({ event: "enrich_company_contacts_company", ...outcome }));
  }

  const summary = {
    event: "enrich_company_contacts_run",
    company_count: outcomes.length,
    companies_remaining: budgetHit ? companies.length - outcomes.length : 0,
    budget_hit: budgetHit,
    contacts_inserted: outcomes.reduce((acc, o) => acc + o.contacts_inserted, 0),
    errored: outcomes.filter((o) => o.error).length,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));

  return jsonResponse({ summary, outcomes });
});

async function scrapeCompany(
  admin: ReturnType<typeof createAdminClient>,
  company: CompanyRow,
): Promise<ScrapeOutcome> {
  const base: ScrapeOutcome = {
    company_id: company.id,
    company_name: company.name,
    pages_fetched: 0,
    founders_found: 0,
    contacts_inserted: 0,
    error: null,
  };

  const domain = company.domain ? normalizeDomain(company.domain) : null;
  if (!domain) return { ...base, error: "no usable domain" };

  try {
    const homepageURL = `https://${domain}`;
    const homepage = await fetchPageText(homepageURL);
    let combined = homepage.text;
    base.pages_fetched = 1;

    for (const path of discoverTeamPaths(homepage.html, homepageURL)) {
      if (base.pages_fetched > MAX_TEAM_PAGES) break;
      try {
        const page = await fetchPageText(path);
        combined += `\n\n--- ${path} ---\n${page.text}`;
        base.pages_fetched += 1;
      } catch {
        // A missing team page is not an error; the homepage often suffices.
      }
    }

    const founders = await extractFounders(company.name, combined.slice(0, MAX_PROMPT_CHARS));
    base.founders_found = founders.length;

    if (founders.length > 0) {
      base.contacts_inserted = await insertFounderContacts(admin, {
        companyId: company.id,
        domain,
        founders,
        source: "llm_scrape",
      });
    }

    return base;
  } catch (error) {
    return { ...base, error: (error as Error).message };
  }
}

async function fetchPageText(url: string): Promise<{ html: string; text: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PAGE_FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      headers: {
        "user-agent": "PitchJobBot/1.0 (+https://jobtok.app/bots) supabase-edge-function",
        accept: "text/html",
      },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`HTTP ${response.status} for ${url}`);
    const html = await response.text();
    return { html, text: stripHTMLToText(html) };
  } finally {
    clearTimeout(timer);
  }
}

// Homepage links whose path smells like a team/about page, same-origin only.
function discoverTeamPaths(html: string, baseURL: string): string[] {
  const base = new URL(baseURL);
  const found = new Set<string>();
  for (const match of html.matchAll(/href=["']([^"'#?]+)["']/gi)) {
    if (found.size >= MAX_TEAM_PAGES) break;
    try {
      const url = new URL(match[1], base);
      if (url.hostname !== base.hostname) continue;
      if (!TEAM_PATH_HINT.test(url.pathname)) continue;
      found.add(url.href);
    } catch {
      // unparseable href — skip
    }
  }
  return [...found];
}

function stripHTMLToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
}

async function extractFounders(
  companyName: string,
  pageText: string,
): Promise<FounderCandidate[]> {
  const parsed = await callStructured<{ founders: FounderCandidate[] }>({
    systemPrompt:
      "You extract founder names from a company's website text. " +
      `Return people explicitly identified as founder, co-founder, or CEO of ${companyName} — ` +
      "never investors, advisors, board members, or employees with other titles. " +
      "Never guess from context. confidence is 0-1 reflecting how explicit the evidence is. " +
      "Return an empty array when unsure or when no founders are named.",
    userPrompt: pageText,
    schemaName: "founder_extraction",
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["founders"],
      properties: {
        founders: {
          type: "array",
          maxItems: 3,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["full_name", "role_title", "confidence"],
            properties: {
              full_name: { type: "string", maxLength: 80 },
              role_title: { type: ["string", "null"], maxLength: 60 },
              confidence: { type: "number" },
            },
          },
        },
      },
    },
    maxOutputTokens: 300,
  });
  return (parsed.founders ?? []).filter((f) => f.full_name?.trim());
}
