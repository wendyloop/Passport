// C-8: crawl one company's own ATS board and ingest what it finds.
//
// This is the primitive that makes an ATS token worth anything. Before it,
// `ingest-jobs` was the ONLY path that inserted board jobs and it walks FUNDS
// — VC portfolio boards — so the job corpus was bounded by whoever a VC had
// backed. The per-ATS adapters existed but were imported by exactly one
// function, `enrich-descriptions`, which fills descriptions and closes
// vanished rows and never discovers a posting. A resolved (ats_type,
// ats_token) therefore bought description coverage and liveness, not jobs.
//
// Now a token means what it always should have: that company's whole board,
// refreshed on a cadence, independent of whether a VC ever wrote about them.
//
// EARLY-CAREER WRITE FILTER (the 2026-09-05 pivot). Jobs are filtered BEFORE
// insert, not at read time. Crawling one enterprise board for 40 internships
// would otherwise ingest ~3,000 postings and generate ~3,000 carousels —
// 99.8% of active jobs carry one, so job volume is LLM spend. classifyExperience
// is title-only and free, so it runs here. Companies reached through a VC fund
// keep their unfiltered path through ingest-jobs; this only governs what the
// direct crawl adds.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { jsonResponse } from "../_shared/http.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";
import { getAdapter } from "../_shared/ats/adapters/index.ts";
import { classifyApplyURL, computeDedupKey, deriveApplyFlow } from "../_shared/ats/classify.ts";
import { sanitizeCompensation } from "../_shared/ats/compensation.ts";
import { classifyExperience, classifyTitle, classifyWorkMode } from "../_shared/title_classify.ts";
import type { ATSType, NormalizedJob } from "../_shared/ats/models.ts";
import { crawlPriority, keepForEarlyCareerFeed } from "../_shared/ats/crawl_filter.ts";

// Edge ceiling is 150s; leave room for the write phase and the sweep.
const RUN_BUDGET_MS = 95_000;
const COMPANY_BATCH = 25;
// Re-crawl cadence. Boards do not churn hourly, and every crawl costs the
// vendor a request.
const RECRAWL_AFTER_HOURS = 24;
const CHUNK = 500;
// Marks jobs this path inserted, so ingest-jobs' per-fund expiry sweep leaves
// them alone and this function's own sweep can find them.
const SOURCE_BOARD = "ats-direct";
// A posting absent from a successful, non-empty crawl is closed after this.
// Same reasoning as ingest-jobs' EXPIRY_GRACE_MS: covers cron skips and
// transient board misses.
const EXPIRY_GRACE_MS = 48 * 60 * 60 * 1000;
// Deliberately short and generic. Each term is a separate paged sweep, so the
// list is a direct multiplier on request count, and keepForEarlyCareerFeed
// still filters whatever comes back — a term only has to be broad enough to
// surface the postings, not precise enough to be the filter.
const WORKDAY_SEARCH_TERMS = ["intern", "graduate", "entry level"];

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const startedAt = Date.now();
  const admin = createAdminClient();

  let companiesCrawled = 0;
  let jobsSeen = 0;
  let jobsKept = 0;
  let jobsInserted = 0;
  let jobsUpdated = 0;
  let jobsExpired = 0;
  const errors: string[] = [];

  try {
    const cutoff = new Date(Date.now() - RECRAWL_AFTER_HOURS * 3_600_000).toISOString();

    // Least-recently-crawled first, never-crawled ahead of everything. The
    // 679 companies already known to post early-career roles are crawled
    // first on the very first pass because their last_crawled_at is null
    // alongside everyone else's — after that, cadence takes over and priority
    // only breaks ties.
    const { data: companies, error } = await admin
      .from("companies")
      .select("id, name, ats_type, ats_token, ats_host, ats_site, last_crawled_at")
      .not("ats_type", "is", null)
      .not("ats_token", "is", null)
      .or(`last_crawled_at.is.null,last_crawled_at.lt.${cutoff}`)
      .order("last_crawled_at", { ascending: true, nullsFirst: true })
      .limit(COMPANY_BATCH * 3);
    if (error) throw error;

    const queue = await crawlPriority(admin, companies ?? []);

    for (const company of queue.slice(0, COMPANY_BATCH)) {
      if (Date.now() - startedAt > RUN_BUDGET_MS) break;

      const stamp = { last_crawled_at: new Date().toISOString() };
      // The query filters both out, but a runtime guard keeps a schema change
      // from silently sending an empty token to a board API — which on some
      // providers is a valid request for somebody else's board.
      const atsType = company.ats_type;
      const atsToken = company.ats_token;
      if (!atsType || !atsToken) continue;

      let result;
      try {
        const adapter = getAdapter(atsType as ATSType);
        result = await adapter({
          ats_token: atsToken,
          company_name: company.name,
          ats_host: company.ats_host,
          ats_site: company.ats_site,
          // Workday is the only supported ATS that searches server-side, and
          // it is the one that needs to: an enterprise board runs to thousands
          // of postings and its list endpoint caps at 20 per page. Pushing the
          // early-career filter into the request is the difference between
          // ~10 calls and ~150. Everything else ignores these.
          search: atsType === "workday" ? WORKDAY_SEARCH_TERMS : undefined,
          // The Workday list response carries no description and one detail
          // call PER JOB would spend the whole crawl budget on one company.
          // enrich-descriptions fills them in afterwards — the job it already
          // does for every board-ingested row.
          includeDetails: atsType !== "workday",
        });
      } catch (fetchError) {
        // A board that 404s or times out is stamped anyway: retrying a dead
        // token every run is how a queue becomes a treadmill.
        errors.push(`${company.name}: ${(fetchError as Error).message}`);
        await admin.from("companies").update(stamp).eq("id", company.id);
        continue;
      }

      companiesCrawled++;
      jobsSeen += result.jobs.length;

      const kept = result.jobs.filter(keepForEarlyCareerFeed);
      jobsKept += kept.length;

      const rows = buildRows(kept, company.id, company.name);
      for (let i = 0; i < rows.length; i += CHUNK) {
        const { data, error: upsertError } = await admin.rpc("upsert_board_jobs", {
          p_jobs: rows.slice(i, i + CHUNK),
        });
        if (upsertError) {
          errors.push(`${company.name}: upsert ${upsertError.message}`);
          break;
        }
        for (const row of (data ?? []) as Array<{ inserted: boolean }>) {
          if (row.inserted) jobsInserted++;
          else jobsUpdated++;
        }
      }

      // Sweep: postings this crawler owns for this company that the board no
      // longer returns. Guarded on a NON-EMPTY successful fetch — an empty
      // result is far more often a broken token or a rate limit than a
      // company that closed every role at once, and acting on it would wipe
      // their whole presence from the feed.
      if (result.jobs.length > 0) {
        const graceCutoff = new Date(Date.now() - EXPIRY_GRACE_MS).toISOString();
        const { data: expired } = await admin
          .from("jobs")
          .update({ is_active: false, closed_at: new Date().toISOString() })
          .eq("company_id", company.id)
          .eq("source_board", SOURCE_BOARD)
          .eq("is_active", true)
          .lt("last_seen_at", graceCutoff)
          .select("id");
        jobsExpired += (expired ?? []).length;
      }

      await admin.from("companies").update(stamp).eq("id", company.id);
    }

    const summary = {
      companies_crawled: companiesCrawled,
      jobs_seen: jobsSeen,
      jobs_kept_early_career: jobsKept,
      jobs_inserted: jobsInserted,
      jobs_updated: jobsUpdated,
      jobs_expired: jobsExpired,
      errors: errors.slice(0, 10),
      duration_ms: Date.now() - startedAt,
    };
    await recordPipelineRun(admin, "crawl-companies", startedAt, summary, errors.length);
    return jsonResponse(summary);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await recordPipelineRun(
      admin, "crawl-companies", startedAt,
      { companies_crawled: companiesCrawled, error: message }, 1,
    );
    return jsonResponse({ error: message }, 500);
  }
});

/// Same row shape ingest-jobs builds, so both paths land in one funnel and
/// `upsert_board_jobs`' write-once semantics apply identically.
function buildRows(
  jobs: NormalizedJob[],
  companyId: string,
  companyName: string | null,
): Record<string, unknown>[] {
  const nowISO = new Date().toISOString();
  // ON CONFLICT DO UPDATE cannot touch the same target row twice in one
  // statement, and one board can expose the same posting under two URL
  // variants. Last write wins; dupes carry identical content.
  const byDedupKey = new Map<string, Record<string, unknown>>();

  for (const job of jobs) {
    const applyURL = job.apply_url ?? job.listing_url;
    if (!applyURL || !job.title) continue;

    const resolution = classifyApplyURL(applyURL);
    const comp = sanitizeCompensation(job.compensation);

    byDedupKey.set(computeDedupKey(applyURL, resolution), {
      dedup_key: computeDedupKey(applyURL, resolution),
      company_id: companyId,
      company_name: companyName,
      source_board: SOURCE_BOARD,
      board_external_id: job.external_id,
      apply_url: applyURL,
      apply_flow: deriveApplyFlow(applyURL),
      title: job.title,
      location: job.location,
      employment_type: job.employment_type,
      job_function: classifyTitle(job.title),
      experience_level: classifyExperience(job.title),
      work_mode: classifyWorkMode(job.location),
      compensation_text: job.compensation_text,
      compensation_min_annual: comp.min_annual,
      compensation_max_annual: comp.max_annual,
      compensation_min_hourly: comp.min_hourly,
      compensation_max_hourly: comp.max_hourly,
      ats_type: resolution?.ats_type ?? job.source_ats,
      ats_token: resolution?.ats_token ?? null,
      ats_external_id: resolution?.ats_external_id ?? job.external_id,
      source_url: job.listing_url ?? applyURL,
      // The adapter already has the JD, so unlike a fund crawl these arrive
      // enriched. The RPC coalesces, so a null never clears a filled one.
      description: job.description,
      description_raw: job.description_raw,
      now_ts: nowISO,
    });
  }
  return [...byDedupKey.values()];
}
