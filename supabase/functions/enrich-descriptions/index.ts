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

const PITCH_CRON_SECRET = Deno.env.get("PITCH_CRON_SECRET") ?? "";

const RUN_BUDGET_MS = 50_000;
// Each company costs one ATS list-fetch (often hundreds of HTML JD bodies in
// memory at once for Greenhouse/Lever). 200 was too many — Supabase killed
// the worker for memory. 30 fits comfortably; the hourly cron drains the
// backlog over a day.
const MAX_COMPANIES_PER_RUN = 30;

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
  ats_type: ATSType;
  ats_token: string;
};

type PendingJob = {
  id: string;
  ats_external_id: string;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Fail closed: an unset secret must never leave the endpoint open.
  const providedSecret = request.headers.get("x-pitch-cron-secret");
  if (!PITCH_CRON_SECRET || providedSecret !== PITCH_CRON_SECRET) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

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
    errored: outcomes.filter((o) => o.error).length,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));

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
  const { data: pendingJobs, error: pendingError } = await admin
    .from("jobs")
    .select("id, ats_external_id")
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
  }

  return { ...base, jobs_pending: pending.length, jobs_enriched: enriched };
}

function sum<T>(items: T[], pick: (item: T) => number): number {
  return items.reduce((acc, item) => acc + pick(item), 0);
}

function jsonResponse(body: unknown) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status = 500) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
