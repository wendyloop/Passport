// Pitch v2 description enrichment. Boards give us titles + apply URLs (which
// is enough to render the feed) but no JD body. This function fills the gap
// for jobs whose apply URL classified to a supported ATS:
//
//   1. Find companies that have at least one active board job with
//      description IS NULL and a resolved ats_type.
//   2. Per company: call the matching ATS adapter, build {external_id →
//      NormalizedJob} map.
//   3. UPDATE jobs SET description = ... WHERE id = ? AND description IS NULL.
//      The `description IS NULL` guard makes enrichment write-once at the
//      column level — once filled, the description text is frozen even if
//      the ATS edits the JD copy.
//   4. Soft-close the pending jobs the adapter did NOT return: the ATS is the
//      system of record, so a posting absent from a successfully-fetched,
//      non-empty board is closed. See _shared/ats/vanished.ts for why
//      ingest-jobs' board-driven sweep misses these.
//
// Why (4) belongs here: without it the queue is self-perpetuating. A closed
// posting can never be enriched, but it keeps its company in
// get_stale_enrichable_companies forever, so every hourly run spends its
// 30-company budget re-fetching boards for jobs that cannot be filled. As of
// 2026-08-09 that was ~2.1k un-fillable rows — a 45-company / 1,150-job sweep
// against the live boards found 91% simply no longer exist upstream — starving
// the genuinely new postings the feed needs.
//
// Per-run budget + oldest-first ordering: 2,400+ companies × per-company HTTP
// can't finish in 60s. companies.last_synced_at doubles as a queue cursor.
// Hourly cron drains the backlog every few hours.
//
// Per-company isolation: one bad ATS token does not abort the run, does not
// cause expiry for other companies, and the failing company still has its
// last_synced_at bumped so we don't grind on it indefinitely.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { getAdapter } from "../_shared/ats/adapters/index.ts";
import type { ATSType, NormalizedJob } from "../_shared/ats/models.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";
import { insertPostingEmailContact } from "../_shared/contacts.ts";
import { feedIsAuthoritative, selectVanishedJobIds } from "../_shared/ats/vanished.ts";

const RUN_BUDGET_MS = 50_000;
// Each company costs one ATS list-fetch (often hundreds of HTML JD bodies in
// memory at once for Greenhouse/Lever). 200 was too many — Supabase killed
// the worker for memory. 30 fits comfortably; the hourly cron drains the
// backlog over a day.
const MAX_COMPANIES_PER_RUN = 30;
// Grace before a job the ATS board doesn't list is soft-closed, matching
// ingest-jobs' EXPIRY_GRACE_MS. Absorbs the ingest→enrich race where a board
// surfaces a posting before it appears in a cached ATS response.
const VANISHED_GRACE_MS = 48 * 60 * 60 * 1000;
// PostgREST puts `.in()` values in the query string; chunk so a company with
// hundreds of closed postings can't blow the URL length limit.
const EXPIRE_CHUNK = 100;

type RequestBody = { company_id?: string };

type EnrichOutcome = {
  company_id: string;
  company_name: string;
  jobs_pending: number;
  jobs_enriched: number;
  jobs_expired: number;
  error: string | null;
};

type CompanyRow = {
  id: string;
  name: string;
  ats_type: ATSType;
  ats_token: string;
};

type PendingJob = {
  id: string;
  ats_external_id: string;
  created_at: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const body: RequestBody = await request.json().catch(() => ({}));
  const admin = createAdminClient();

  // Companies with at least one active ats-resolved job missing a description,
  // ordered by last_synced_at NULLS FIRST. The RPC inverts the natural query
  // direction (start from companies, EXISTS into jobs) so small funds aren't
  // starved by the UUID-order scan that returns only big-fund job rows.
  let companies: CompanyRow[];
  if (body.company_id) {
    const { data, error } = await admin
      .from("companies")
      .select("id, name, ats_type, ats_token")
      .eq("id", body.company_id)
      .not("ats_type", "is", null)
      .not("ats_token", "is", null);
    if (error) return jsonError(`Failed to load company: ${error.message}`);
    companies = (data ?? []) as CompanyRow[];
  } else {
    const { data, error } = await admin.rpc("get_stale_enrichable_companies", {
      p_limit: MAX_COMPANIES_PER_RUN,
    });
    if (error) return jsonError(`Failed to load companies: ${error.message}`);
    companies = (data ?? []) as CompanyRow[];
  }

  if (companies.length === 0) {
    return jsonResponse({ summary: { event: "enrich_descriptions_run", company_count: 0 }, outcomes: [] });
  }

  const outcomes: EnrichOutcome[] = [];
  const startedAt = Date.now();
  let budgetHit = false;

  for (const company of companies) {
    if (!body.company_id && Date.now() - startedAt > RUN_BUDGET_MS) {
      budgetHit = true;
      break;
    }

    const outcome = await enrichCompany(admin, company);
    outcomes.push(outcome);

    // Bump regardless of error so we don't pin the queue on a broken token.
    await admin
      .from("companies")
      .update({ last_synced_at: new Date().toISOString() })
      .eq("id", company.id);

    console.log(JSON.stringify({ event: "enrich_descriptions_company", ...outcome }));
  }

  const summary = {
    event: "enrich_descriptions_run",
    company_count: outcomes.length,
    companies_remaining: budgetHit ? companies.length - outcomes.length : 0,
    budget_hit: budgetHit,
    enriched: sum(outcomes, (o) => o.jobs_enriched),
    expired: sum(outcomes, (o) => o.jobs_expired),
    errored: outcomes.filter((o) => o.error).length,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));
  await recordPipelineRun(admin, "enrich-descriptions", startedAt, summary, summary.errored);

  return jsonResponse({ summary, outcomes });
});

async function enrichCompany(
  admin: ReturnType<typeof createAdminClient>,
  company: CompanyRow,
): Promise<EnrichOutcome> {
  const base: EnrichOutcome = {
    company_id: company.id,
    company_name: company.name,
    jobs_pending: 0,
    jobs_enriched: 0,
    jobs_expired: 0,
    error: null,
  };

  // Pending jobs for this company — we need ats_external_id to match adapter
  // output. Jobs ingested before classify could extract an id will be null
  // here and skipped (they'll still be enriched if a later re-classify fills
  // ats_external_id, or remain description-less which is acceptable).
  const { data: pendingJobs, error: pendingError } = await admin
    .from("jobs")
    .select("id, ats_external_id, created_at")
    .eq("company_id", company.id)
    .is("description", null)
    .eq("is_active", true)
    .eq("ats_type", company.ats_type)
    .not("ats_external_id", "is", null);

  if (pendingError) {
    return { ...base, error: `load pending failed: ${pendingError.message}` };
  }

  const pending = (pendingJobs ?? []) as PendingJob[];
  if (pending.length === 0) return base;

  let fetched: NormalizedJob[];
  try {
    const adapter = getAdapter(company.ats_type);
    const result = await adapter({ ats_token: company.ats_token, company_name: company.name });
    fetched = result.jobs;
  } catch (error) {
    return { ...base, jobs_pending: pending.length, error: (error as Error).message };
  }

  const fetchedById = new Map(fetched.map((j) => [j.external_id, j]));
  let enriched = 0;

  for (const job of pending) {
    const match = fetchedById.get(job.ats_external_id);
    if (!match || (!match.description && !match.description_raw)) continue;

    // description IS NULL guard makes this a write-once update — concurrent
    // re-runs cannot overwrite each other. posting_contact_email rides along:
    // it goes to its own column, NOT application_email, because that column
    // gates the iOS easy-apply path and extractFirstEmail can surface
    // unrelated addresses (accessibility@, privacy@) from JD boilerplate.
    const { error, count } = await admin
      .from("jobs")
      .update(
        {
          description: match.description,
          description_raw: match.description_raw,
          posting_contact_email: match.contact_email_on_posting,
        },
        { count: "exact" },
      )
      .eq("id", job.id)
      .is("description", null);
    if (error) {
      console.error(JSON.stringify({
        event: "enrich_descriptions_update_failed",
        company_id: company.id,
        job_id: job.id,
        error: error.message,
      }));
      continue;
    }
    if ((count ?? 0) > 0) enriched += 1;

    // Tier-2 contact: an email published on the posting itself is a
    // verified address. Failure-isolated from enrichment.
    if ((count ?? 0) > 0 && match.contact_email_on_posting) {
      try {
        await insertPostingEmailContact(admin, company.id, match.contact_email_on_posting);
      } catch (contactError) {
        console.error(JSON.stringify({
          event: "posting_email_contact_insert_failed",
          company_id: company.id,
          job_id: job.id,
          error: (contactError as Error).message,
        }));
      }
    }
  }

  // Close the pending jobs the board didn't return. Failure-isolated: a broken
  // expiry must not discard the enrichment we just did.
  let expired = 0;
  if (feedIsAuthoritative(fetched.length)) {
    const vanishedIds = selectVanishedJobIds(pending, new Set(fetchedById.keys()), {
      now: Date.now(),
      graceMs: VANISHED_GRACE_MS,
    });
    try {
      expired = await expireVanishedJobs(admin, company.id, vanishedIds);
    } catch (expireError) {
      console.error(JSON.stringify({
        event: "enrich_descriptions_expire_failed",
        company_id: company.id,
        error: (expireError as Error).message,
      }));
    }
  }

  return {
    ...base,
    jobs_pending: pending.length,
    jobs_enriched: enriched,
    jobs_expired: expired,
  };
}

/**
 * Soft-closes jobs confirmed gone from their ATS. The `is_active` guard keeps
 * the count honest when a concurrent ingest run closed the same row first.
 */
async function expireVanishedJobs(
  admin: ReturnType<typeof createAdminClient>,
  companyId: string,
  jobIds: string[],
): Promise<number> {
  let expired = 0;
  for (let i = 0; i < jobIds.length; i += EXPIRE_CHUNK) {
    const slice = jobIds.slice(i, i + EXPIRE_CHUNK);
    const { error, count } = await admin
      .from("jobs")
      .update(
        { is_active: false, closed_at: new Date().toISOString() },
        { count: "exact" },
      )
      .in("id", slice)
      .eq("is_active", true);
    if (error) {
      console.error(JSON.stringify({
        event: "enrich_descriptions_expire_chunk_failed",
        company_id: companyId,
        chunk_start: i,
        error: error.message,
      }));
      continue;
    }
    expired += count ?? 0;
  }
  return expired;
}

function sum<T>(items: T[], pick: (item: T) => number): number {
  return items.reduce((acc, item) => acc + pick(item), 0);
}

