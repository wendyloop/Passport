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

const RUN_BUDGET_MS = 50_000;
// Each company costs one ATS list-fetch (often hundreds of HTML JD bodies in
// memory at once for Greenhouse/Lever). 200 was too many — Supabase killed
// the worker for memory. 30 fits comfortably; the hourly cron drains the
// backlog over a day.
const MAX_COMPANIES_PER_RUN = 30;
// A company's jobs can span several boards (an ATS migration leaves live jobs
// on both). Each board is its own list-fetch, so cap the fan-out — groups are
// ordered largest-first, and the tail gets picked up on the next pass.
const MAX_BOARDS_PER_COMPANY = 3;

type RequestBody = { company_id?: string };

type EnrichOutcome = {
  company_id: string;
  company_name: string;
  jobs_pending: number;
  jobs_enriched: number;
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
    .select("id, ats_type, ats_external_id, apply_url")
    .eq("company_id", company.id)
    .is("description", null)
    .eq("is_active", true)
    .not("ats_type", "is", null)
    .not("ats_external_id", "is", null);

  if (pendingError) {
    return { ...base, error: `load pending failed: ${pendingError.message}` };
  }

  const pending = (pendingJobs ?? []) as PendingJob[];
  if (pending.length === 0) return base;

  const { groups } = groupPendingJobs(pending, company);
  const errors: string[] = [];
  let enriched = 0;

  // Largest board first, so the cap sheds only the long tail.
  for (const group of groups.slice(0, MAX_BOARDS_PER_COMPANY)) {
    try {
      const adapter = getAdapter(group.ats_type);
      const result = await adapter({ ats_token: group.ats_token, company_name: company.name });
      enriched += await applyDescriptions(admin, company, group.jobs, buildMatchIndex(result.jobs));
    } catch (error) {
      // One dead board must not cost this company its other boards.
      errors.push(`${group.ats_type}/${group.ats_token}: ${(error as Error).message}`);
    }
  }

  return {
    ...base,
    jobs_pending: pending.length,
    jobs_enriched: enriched,
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

function sum<T>(items: T[], pick: (item: T) => number): number {
  return items.reduce((acc, item) => acc + pick(item), 0);
}

