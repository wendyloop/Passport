// Pitch v2 job ingest. Boards (Getro + Consider) are the source of truth
// for *which jobs exist*. This function:
//
//   1. Loads enabled funds (or one, if fund_slug is given).
//   2. For each fund: calls the platform adapter with a resume cursor and a
//      soft time budget; the adapter walks the board's search endpoint and
//      returns (companies, jobs, nextCursor).
//   3. Upserts each company (domain → ats coords → (board, ext_id) dedupe),
//      then bulk-upserts jobs via the upsert_board_jobs RPC. The RPC enforces
//      WRITE-ONCE semantics at the DB level: title/apply_url/comp never get
//      overwritten on conflict, so a candidate's job_applications.job_id keeps
//      pointing at the version of the posting they actually applied to.
//   4. Persists funds.crawl_cursor for next run, or clears it on full drain.
//   5. Runs a per-fund expiry sweep: any board job not seen in EXPIRY_GRACE_MS
//      gets soft-closed (is_active=false, closed_at=now). Grace handles cron
//      skips, cursor mid-drain, and transient board misses.
//
// Budget: edge function ceiling is 60s. We reserve ~10s for the post-loop
// DB work (cursor save + expiry sweep) and divide the rest across funds.
// One fund per run is acceptable — the daily cron means a multi-day fund
// (Sequoia, ~9k jobs) drains in 3–5 days and stays drained thereafter.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { getBoardAdapter } from "../_shared/boards/index.ts";
import { upsertCompanyAndLink } from "../_shared/boards/upsert.ts";
import {
  classifyApplyURL,
  computeDedupKey,
  deriveApplyFlow,
} from "../_shared/ats/classify.ts";
import type { FundRow } from "../_shared/ats/models.ts";
import type { BoardCompany, BoardJob } from "../_shared/boards/types.ts";
import { jsonError } from "../_shared/http.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";

// Total per-run wall-clock. Supabase edge ceiling is 150s; we stay well
// below to leave headroom for slow pages + the post-loop write phase.
const RUN_BUDGET_MS = 45_000;
// Time reserved AFTER the adapter loop for chunked RPC upserts, cursor save,
// and expiry sweep. On a big fund the RPC pass dominates this — observed
// ~95s to upsert 9k rows in 500-row chunks. Capping the adapter at ~20s
// keeps the per-run job count under ~4k, which fits in memory and finishes
// the RPC pass inside the run budget without hitting WORKER_RESOURCE_LIMIT.
const POST_LOOP_RESERVE_MS = 25_000;
// 48h grace before a job not seen on the board is soft-closed. Covers cron
// skips, partial drains, and transient API hiccups.
const EXPIRY_GRACE_MS = 48 * 60 * 60 * 1000;
// Min adapter budget per fund — below this it's not worth calling.
const MIN_FUND_BUDGET_MS = 5_000;

type RequestBody = { fund_slug?: string };

type FundOutcome = {
  fund_slug: string;
  fund_name: string;
  pages: number;
  companies_seen: number;
  companies_inserted: number;
  jobs_seen: number;
  jobs_inserted: number;
  jobs_updated: number;
  jobs_expired: number;
  cursor_before: string | null;
  cursor_after: string | null;
  error: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const body: RequestBody = await request.json().catch(() => ({}));
  const admin = createAdminClient();

  // Oldest-cursor-first ordering means funds mid-drain finish before fresh
  // funds get re-walked. Null cursors (fully drained last run) go to the
  // back so we don't starve mid-drain funds.
  const fundQuery = admin
    .from("funds")
    .select("id, name, slug, board_url, platform, external_collection_id, crawl_cursor")
    .in("platform", ["getro", "consider"])
    .order("crawl_cursor", { ascending: false, nullsFirst: false });
  if (body.fund_slug) fundQuery.eq("slug", body.fund_slug);

  const { data: funds, error: fundsError } = await fundQuery;
  if (fundsError) {
    return jsonError(`Failed to load funds: ${fundsError.message}`);
  }

  type FundWithCursor = FundRow & { crawl_cursor: string | null };
  const fundList = (funds ?? []) as FundWithCursor[];

  const outcomes: FundOutcome[] = [];
  const startedAt = Date.now();

  for (let i = 0; i < fundList.length; i++) {
    const fund = fundList[i];
    const elapsed = Date.now() - startedAt;
    const remaining = RUN_BUDGET_MS - elapsed - POST_LOOP_RESERVE_MS;
    if (remaining < MIN_FUND_BUDGET_MS) {
      console.log(JSON.stringify({
        event: "ingest_jobs_budget_skipped",
        fund_slug: fund.slug,
        elapsed_ms: elapsed,
      }));
      break;
    }
    // Divide remaining budget across remaining funds; first fund gets a
    // proportional share so one huge fund doesn't starve the rest.
    const fundsLeft = fundList.length - i;
    const fundBudget = Math.max(MIN_FUND_BUDGET_MS, Math.floor(remaining / fundsLeft));

    const outcome = await ingestFund(admin, fund, fundBudget);
    outcomes.push(outcome);
    console.log(JSON.stringify({ event: "ingest_jobs_fund", ...outcome }));
  }

  const summary = {
    event: "ingest_jobs_run",
    fund_count: outcomes.length,
    companies_seen: sum(outcomes, (o) => o.companies_seen),
    companies_inserted: sum(outcomes, (o) => o.companies_inserted),
    jobs_seen: sum(outcomes, (o) => o.jobs_seen),
    jobs_inserted: sum(outcomes, (o) => o.jobs_inserted),
    jobs_updated: sum(outcomes, (o) => o.jobs_updated),
    jobs_expired: sum(outcomes, (o) => o.jobs_expired),
    errored: outcomes.filter((o) => o.error).length,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));

  return new Response(JSON.stringify({ summary, outcomes }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

async function ingestFund(
  admin: ReturnType<typeof createAdminClient>,
  fund: FundRow & { crawl_cursor: string | null },
  budgetMs: number,
): Promise<FundOutcome> {
  const base: FundOutcome = {
    fund_slug: fund.slug,
    fund_name: fund.name,
    pages: 0,
    companies_seen: 0,
    companies_inserted: 0,
    jobs_seen: 0,
    jobs_inserted: 0,
    jobs_updated: 0,
    jobs_expired: 0,
    cursor_before: fund.crawl_cursor,
    cursor_after: fund.crawl_cursor,
    error: null,
  };

  const adapter = getBoardAdapter(fund.platform);
  if (!adapter) {
    return { ...base, error: `no adapter for platform ${fund.platform}` };
  }

  let result;
  try {
    result = await adapter({
      fund,
      startCursor: fund.crawl_cursor,
      budgetMs,
    });
  } catch (error) {
    return { ...base, error: (error as Error).message };
  }

  // Resolve every company first; jobs reference companies via board_external_id
  // within the batch, and the RPC needs the real company_id FK.
  const companyIdByBoardExtId = new Map<string, string>();
  let companiesInserted = 0;

  for (const company of result.companies) {
    // Find an apply URL from a job belonging to this company to classify ATS.
    const sampleJob = result.jobs.find(
      (j) => j.company_board_external_id === company.board_external_id,
    );
    const sampleResolution = sampleJob ? classifyApplyURL(sampleJob.apply_url) : null;
    const atsForCompany = sampleResolution
      ? { ats_type: sampleResolution.ats_type, ats_token: sampleResolution.ats_token }
      : null;

    try {
      const res = await upsertCompanyAndLink(admin, fund, company, atsForCompany);
      companyIdByBoardExtId.set(company.board_external_id, res.company_id);
      if (res.inserted) companiesInserted += 1;
    } catch (error) {
      console.error(JSON.stringify({
        event: "ingest_jobs_company_upsert_failed",
        fund_slug: fund.slug,
        company_name: company.name,
        error: (error as Error).message,
      }));
    }
  }

  const jobRows = buildJobRows(fund, result.jobs, result.companies, companyIdByBoardExtId);

  let jobsInserted = 0;
  let jobsUpdated = 0;

  // Chunk the upsert. ON CONFLICT in a single statement can't touch the same
  // row twice — buildJobRows already dedupes by dedup_key within the batch,
  // and chunking caps RPC parse/validate time so a parse failure doesn't burn
  // the whole edge-function budget.
  const CHUNK = 500;
  for (let i = 0; i < jobRows.length; i += CHUNK) {
    const slice = jobRows.slice(i, i + CHUNK);
    const { data, error } = await admin.rpc("upsert_board_jobs", { p_jobs: slice });
    if (error) {
      return {
        ...base,
        pages: result.pages,
        companies_seen: result.companies.length,
        companies_inserted: companiesInserted,
        jobs_seen: result.jobs.length,
        jobs_inserted: jobsInserted,
        jobs_updated: jobsUpdated,
        error: `upsert_board_jobs failed at chunk ${i}: ${error.message}`,
      };
    }
    for (const row of (data ?? []) as Array<{ inserted: boolean }>) {
      if (row.inserted) jobsInserted += 1;
      else jobsUpdated += 1;
    }
  }

  // Persist cursor (or clear on full drain).
  const { error: cursorError } = await admin
    .from("funds")
    .update({ crawl_cursor: result.nextCursor })
    .eq("id", fund.id);
  if (cursorError) {
    console.error(JSON.stringify({
      event: "ingest_jobs_cursor_save_failed",
      fund_slug: fund.slug,
      error: cursorError.message,
    }));
  }

  // Expiry sweep only when the fund fully drained this cycle (nextCursor is
  // null). Otherwise we'd soft-close jobs that simply weren't reached in this
  // partial pass.
  let jobsExpired = 0;
  if (result.nextCursor === null) {
    const expiredCount = await sweepExpired(admin, fund.slug);
    jobsExpired = expiredCount;
  }

  return {
    ...base,
    pages: result.pages,
    companies_seen: result.companies.length,
    companies_inserted: companiesInserted,
    jobs_seen: result.jobs.length,
    jobs_inserted: jobsInserted,
    jobs_updated: jobsUpdated,
    jobs_expired: jobsExpired,
    cursor_after: result.nextCursor,
  };
}

function buildJobRows(
  fund: FundRow,
  jobs: BoardJob[],
  companies: BoardCompany[],
  companyIdByBoardExtId: Map<string, string>,
): Record<string, unknown>[] {
  const companyByExtId = new Map(companies.map((c) => [c.board_external_id, c]));
  const nowISO = new Date().toISOString();
  // Dedupe by dedup_key within the batch — Postgres' ON CONFLICT DO UPDATE
  // can't touch the same target row twice in one statement. Two boards
  // (or two URL variants) can produce the same key in one ingest pass.
  // Last write wins; in practice all dupes carry identical content.
  const byDedupKey = new Map<string, Record<string, unknown>>();

  for (const job of jobs) {
    const companyId = companyIdByBoardExtId.get(job.company_board_external_id);
    if (!companyId) continue; // company upsert failed; skip its jobs

    const company = companyByExtId.get(job.company_board_external_id);
    const resolution = classifyApplyURL(job.apply_url);
    const dedupKey = computeDedupKey(job.apply_url, resolution);

    byDedupKey.set(dedupKey, {
      dedup_key: dedupKey,
      company_id: companyId,
      company_name: company?.name ?? null,
      source_board: fund.slug,
      board_external_id: job.board_external_id,
      apply_url: job.apply_url,
      apply_flow: deriveApplyFlow(job.apply_url),
      title: job.title,
      location: job.location,
      employment_type: normalizeEmploymentType(job.employment_type),
      compensation_text: job.compensation_text,
      compensation_min_annual: toInt(job.compensation.min_annual),
      compensation_max_annual: toInt(job.compensation.max_annual),
      compensation_min_hourly: toInt(job.compensation.min_hourly),
      compensation_max_hourly: toInt(job.compensation.max_hourly),
      ats_type: resolution?.ats_type ?? null,
      ats_token: resolution?.ats_token ?? null,
      ats_external_id: resolution?.ats_external_id ?? null,
      source_url: job.apply_url,
      now_ts: nowISO,
    });
  }

  return Array.from(byDedupKey.values());
}

async function sweepExpired(
  admin: ReturnType<typeof createAdminClient>,
  sourceBoard: string,
): Promise<number> {
  const cutoff = new Date(Date.now() - EXPIRY_GRACE_MS).toISOString();
  const { error, count } = await admin
    .from("jobs")
    .update(
      { is_active: false, closed_at: new Date().toISOString() },
      { count: "exact" },
    )
    .eq("source_board", sourceBoard)
    .eq("is_active", true)
    .lt("last_seen_at", cutoff);
  if (error) {
    console.error(JSON.stringify({
      event: "ingest_jobs_expiry_failed",
      source_board: sourceBoard,
      error: error.message,
    }));
    return 0;
  }
  return count ?? 0;
}

function normalizeEmploymentType(raw: string | null): string | null {
  if (!raw) return null;
  const normalized = raw.toLowerCase().replace(/[\s\-_]+/g, "");
  if (normalized.startsWith("full")) return "full_time";
  if (normalized.startsWith("part")) return "part_time";
  if (normalized.startsWith("contract") || normalized === "contractor" || normalized === "temp") {
    return "contract";
  }
  return null;
}

function toInt(value: number | null): number | null {
  if (value == null || !Number.isFinite(value)) return null;
  return Math.round(value);
}

function sum<T>(items: T[], pick: (item: T) => number): number {
  return items.reduce((acc, item) => acc + pick(item), 0);
}
