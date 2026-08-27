// Pitch v2 description enrichment. Boards give us titles + apply URLs (which
// is enough to render the feed) but no JD body. This function fills the gap
// for jobs whose apply URL classified to a supported ATS:
//
//   1. Find companies that have at least one active board job with
//      description IS NULL and a resolved ats_type.
//   2. Per company: group its pending jobs by the ATS coordinates carried in
//      their own apply_url (see _shared/ats/enrich_targets.ts — the company
//      row goes stale when a company migrates ATS), call the adapter for each
//      board, and build an {external_id → NormalizedJob} map.
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
import { buildMatchIndex, groupPendingJobs } from "../_shared/ats/enrich_targets.ts";
import type { PendingJob } from "../_shared/ats/enrich_targets.ts";
import type { ATSType, NormalizedJob } from "../_shared/ats/models.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";
import { insertPostingEmailContact } from "../_shared/contacts.ts";
import { classifyGetroDetail, fetchGetroJobDetail } from "../_shared/boards/getro_detail.ts";
import { pMap } from "../_shared/ats/http.ts";
import { feedIsAuthoritative, selectVanishedJobIds } from "../_shared/ats/vanished.ts";

const RUN_BUDGET_MS = 50_000;
// The two phases draw on one 50s budget, so the ATS phase is capped rather
// than allowed to consume everything: one slow company used to leave nothing
// for anything else. Getro gets the remainder — it is the higher-yield of the
// two (~15.7k of the ~16.2k blank jobs sit on Getro funds), so it must never
// be the phase that gets starved.
const ATS_BUDGET_MS = 25_000;
// One request per job, so this is the real throughput knob. 6 in flight is
// roughly 10 jobs/sec against api.getro.com — enough to drain the backlog in
// a few days of hourly runs without hammering a third party we don't own.
const GETRO_CONCURRENCY = 6;
// Upper bound on rows pulled per run; the deadline usually bites first.
const GETRO_JOBS_PER_RUN = 400;
// Jobs that already have a description still need their liveness re-checked —
// nothing else does it. ingest-jobs' sweep sees ~333 jobs/day against 30k
// active rows (a ~3-month cycle) and is gated on a full drain the big funds
// have never achieved, so `jobs_expired` is 0 on every run. Blank jobs keep
// priority (they gain a description AND a liveness check); whatever budget is
// left rotates over described ones, oldest-check first.
const GETRO_MIN_LIVENESS_SLOTS = 120;
// Each company costs one ATS list-fetch (often hundreds of HTML JD bodies in
// memory at once for Greenhouse/Lever). 200 was too many — Supabase killed
// the worker for memory. 30 fits comfortably; the hourly cron drains the
// backlog over a day.
const MAX_COMPANIES_PER_RUN = 30;
// A company's jobs can span several boards (an ATS migration leaves live jobs
// on both). Each board is its own list-fetch, so cap the fan-out — groups are
// ordered largest-first, and the tail gets picked up on the next pass.
const MAX_BOARDS_PER_COMPANY = 3;
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
  // Advisory only: a company that migrated ATS keeps the old provider here,
  // and rows that never classified leave both null. Used as a fallback token
  // source for jobs whose apply_url no longer classifies.
  ats_type: ATSType | null;
  ats_token: string | null;
};

// The targeting fields (see enrich_targets.ts) plus created_at, which the
// vanished check needs to know whether the grace window has elapsed.
type PendingJobRow = PendingJob & { created_at: string | null };

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
    // No ats_type filter: the jobs carry their own coordinates, so a company
    // row with a null or stale provider is still enrichable.
    const { data, error } = await admin
      .from("companies")
      .select("id, name, ats_type, ats_token")
      .eq("id", body.company_id);
    if (error) return jsonError(`Failed to load company: ${error.message}`);
    companies = (data ?? []) as CompanyRow[];
  } else {
    const { data, error } = await admin.rpc("get_stale_enrichable_companies", {
      p_limit: MAX_COMPANIES_PER_RUN,
    });
    if (error) return jsonError(`Failed to load companies: ${error.message}`);
    companies = (data ?? []) as CompanyRow[];
  }

  const outcomes: EnrichOutcome[] = [];
  const startedAt = Date.now();
  let budgetHit = false;

  // An empty company list is not an empty run: the Getro phase below works
  // from jobs, not companies, and used to be skipped by an early return here.
  for (const company of companies) {
    if (!body.company_id && Date.now() - startedAt > ATS_BUDGET_MS) {
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

  // Board phase. Failure-isolated from the ATS phase above: whatever that
  // already wrote stands even if Getro is unreachable.
  const getro = body.company_id
    ? null
    : await runGetroPass(admin, Math.max(0, RUN_BUDGET_MS - (Date.now() - startedAt)));

  const summary = {
    event: "enrich_descriptions_run",
    company_count: outcomes.length,
    companies_remaining: budgetHit ? companies.length - outcomes.length : 0,
    budget_hit: budgetHit,
    enriched: sum(outcomes, (o) => o.jobs_enriched),
    expired: sum(outcomes, (o) => o.jobs_expired),
    errored: outcomes.filter((o) => o.error).length,
    getro_examined: getro?.examined ?? 0,
    getro_enriched: getro?.enriched ?? 0,
    getro_expired: getro?.expired ?? 0,
    getro_errors: getro?.errors ?? 0,
    getro_liveness_checked: getro?.liveness_checked ?? 0,
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
  //
  // Filtered on the job's own ats_type, not the company's: see enrich_targets.
  const { data: pendingJobs, error: pendingError } = await admin
    .from("jobs")
    .select("id, ats_type, ats_external_id, apply_url, created_at")
    .eq("company_id", company.id)
    .is("description", null)
    .eq("is_active", true)
    .not("ats_type", "is", null)
    .not("ats_external_id", "is", null);

  if (pendingError) {
    return { ...base, error: `load pending failed: ${pendingError.message}` };
  }

  const pending = (pendingJobs ?? []) as PendingJobRow[];
  if (pending.length === 0) return base;

  const { groups } = groupPendingJobs(pending, company);
  const errors: string[] = [];
  let enriched = 0;
  let expired = 0;

  // Largest board first, so the cap sheds only the long tail.
  for (const group of groups.slice(0, MAX_BOARDS_PER_COMPANY)) {
    const groupJobs = group.jobs as PendingJobRow[];
    let index: Map<string, NormalizedJob>;
    try {
      const adapter = getAdapter(group.ats_type);
      const result = await adapter({ ats_token: group.ats_token, company_name: company.name });
      index = buildMatchIndex(result.jobs);
      enriched += await applyDescriptions(admin, company, groupJobs, index);
      if (!feedIsAuthoritative(result.jobs.length)) continue;
    } catch (error) {
      // One dead board must not cost this company its other boards — and a
      // board we failed to reach proves nothing about whether its postings
      // still exist, so nothing here is expired.
      errors.push(`${group.ats_type}/${group.ats_token}: ${(error as Error).message}`);
      continue;
    }

    // Absence is only evidence within the board we actually fetched, so this
    // is scoped to that group's jobs — never the company's whole pending set.
    // Failure-isolated: a broken expiry must not discard the enrichment above.
    try {
      expired += await expireVanishedJobs(
        admin,
        company.id,
        selectVanishedJobIds(groupJobs, new Set(index.keys()), {
          now: Date.now(),
          graceMs: VANISHED_GRACE_MS,
        }),
      );
    } catch (expireError) {
      console.error(JSON.stringify({
        event: "enrich_descriptions_expire_failed",
        company_id: company.id,
        ats_token: group.ats_token,
        error: (expireError as Error).message,
      }));
    }
  }

  return {
    ...base,
    jobs_pending: pending.length,
    jobs_enriched: enriched,
    jobs_expired: expired,
    error: errors.length > 0 ? errors.join("; ") : null,
  };
}

async function applyDescriptions(
  admin: ReturnType<typeof createAdminClient>,
  company: CompanyRow,
  jobs: PendingJob[],
  fetchedById: Map<string, NormalizedJob>,
): Promise<number> {
  let enriched = 0;

  for (const job of jobs) {
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

  return enriched;
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


type GetroPassResult = {
  examined: number;
  enriched: number;
  expired: number;
  errors: number;
  // Re-verified rows that already had a description: liveness only, no write.
  liveness_checked: number;
};

/**
 * Board phase: fill descriptions (and close dead postings) from Getro's
 * per-job endpoint. Job-driven rather than company-driven — the ATS phase
 * above can only reach the five providers we have adapters for, while Getro
 * answers for every posting on its boards regardless of where it's hosted.
 */
async function runGetroPass(
  admin: ReturnType<typeof createAdminClient>,
  budgetMs: number,
): Promise<GetroPassResult> {
  const result: GetroPassResult = {
    examined: 0, enriched: 0, expired: 0, errors: 0, liveness_checked: 0,
  };
  if (budgetMs <= 0) return result;
  const deadline = Date.now() + budgetMs;

  // source_board is the fund slug; the collection id it maps to lives on the
  // fund row, so nothing here hardcodes a fund.
  const { data: fundRows, error: fundError } = await admin
    .from("funds")
    .select("slug, external_collection_id")
    .eq("platform", "getro")
    .not("external_collection_id", "is", null);
  if (fundError || !fundRows || fundRows.length === 0) {
    if (fundError) console.error(JSON.stringify({ event: "getro_pass_funds_failed", error: fundError.message }));
    return result;
  }
  const collectionBySlug = new Map(
    (fundRows as Array<{ slug: string; external_collection_id: string }>)
      .map((f) => [f.slug, f.external_collection_id]),
  );

  const slugs = [...collectionBySlug.keys()];

  // Most-recently-seen first: those are the likeliest to still be open, so
  // the feed gains real postings early instead of after a long tail of
  // closures. The closures still happen — just later in the drain.
  const blankBudget = Math.max(0, GETRO_JOBS_PER_RUN - GETRO_MIN_LIVENESS_SLOTS);
  const { data: blankRows, error: jobError } = await admin
    .from("jobs")
    .select("id, external_id, source_board")
    .is("description", null)
    .eq("is_active", true)
    .in("source_board", slugs)
    .not("external_id", "is", null)
    .order("last_seen_at", { ascending: false })
    .limit(blankBudget);
  if (jobError) {
    console.error(JSON.stringify({ event: "getro_pass_jobs_failed", error: jobError.message }));
    return result;
  }

  const jobs = (blankRows ?? []) as Array<{ id: string; external_id: string; source_board: string }>;
  const blankIds = new Set(jobs.map((j) => j.id));

  // Fill the rest of the run with liveness re-checks. Least-recently-verified
  // first (NULL = never), so the whole population rotates instead of the same
  // rows being re-checked every hour.
  if (jobs.length < GETRO_JOBS_PER_RUN) {
    const { data: liveRows, error: liveError } = await admin
      .from("jobs")
      .select("id, external_id, source_board")
      .not("description", "is", null)
      .eq("is_active", true)
      .in("source_board", slugs)
      .not("external_id", "is", null)
      .order("liveness_checked_at", { ascending: true, nullsFirst: true })
      .limit(GETRO_JOBS_PER_RUN - jobs.length);
    if (liveError) {
      console.error(JSON.stringify({ event: "getro_pass_liveness_query_failed", error: liveError.message }));
    } else {
      jobs.push(...((liveRows ?? []) as typeof jobs));
    }
  }
  if (jobs.length === 0) return result;

  const toExpire: string[] = [];
  // Rows whose cursor to stamp. A failed fetch counts as an attempt: the
  // liveness queue is ordered by this column, so a row that errors every time
  // would otherwise sit at the head of the rotation forever and starve the
  // rest of the population.
  const checked: string[] = [];

  await pMap(jobs, GETRO_CONCURRENCY, async (job) => {
    if (Date.now() > deadline) return;
    const collectionId = collectionBySlug.get(job.source_board);
    if (!collectionId) return;

    let detail;
    try {
      detail = await fetchGetroJobDetail(job.external_id, collectionId);
    } catch (error) {
      // A job we couldn't reach proves nothing about whether it still exists,
      // so it is never expired on a fetch failure — it stays queued.
      result.errors += 1;
      checked.push(job.id);
      console.error(JSON.stringify({
        event: "getro_pass_fetch_failed",
        job_id: job.id,
        external_id: job.external_id,
        error: (error as Error).message.slice(0, 160),
      }));
      return;
    }
    result.examined += 1;

    const outcome = classifyGetroDetail(detail);
    if (outcome.kind === "expire") {
      toExpire.push(job.id);
      return;
    }
    // Getro says it's open: stamp the rotation cursor whether or not there is
    // a description to write, so a job with no JD text can't pin the queue.
    checked.push(job.id);
    if (!blankIds.has(job.id)) {
      result.liveness_checked += 1;
      return; // already described — this row was queued for liveness only
    }
    if (outcome.kind === "skip") return;

    // Same write-once guard as the ATS path: never overwrite a description
    // another pass already filled.
    const { error, count } = await admin
      .from("jobs")
      .update(
        { description: outcome.description, description_raw: outcome.description_raw },
        { count: "exact" },
      )
      .eq("id", job.id)
      .is("description", null);
    if (error) {
      result.errors += 1;
      console.error(JSON.stringify({
        event: "getro_pass_update_failed",
        job_id: job.id,
        error: error.message,
      }));
      return;
    }
    if ((count ?? 0) > 0) result.enriched += 1;
  });

  // Cursor stamping is best-effort: a failure here costs a re-check next run,
  // never a wrong expiry.
  for (let i = 0; i < checked.length; i += EXPIRE_CHUNK) {
    const { error } = await admin
      .from("jobs")
      .update({ liveness_checked_at: new Date().toISOString() })
      .in("id", checked.slice(i, i + EXPIRE_CHUNK));
    if (error) {
      console.error(JSON.stringify({ event: "getro_pass_cursor_failed", error: error.message }));
      break;
    }
  }

  try {
    result.expired = await expireVanishedJobs(admin, "getro-pass", toExpire);
  } catch (expireError) {
    console.error(JSON.stringify({
      event: "getro_pass_expire_failed",
      error: (expireError as Error).message,
    }));
  }

  console.log(JSON.stringify({ event: "enrich_descriptions_getro_pass", ...result }));
  return result;
}
