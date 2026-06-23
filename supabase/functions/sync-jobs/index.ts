// Daily Pitch sync. For every company with resolved ATS coordinates:
//   1. Call the matching adapter.
//   2. Upsert jobs by (source_ats, external_id), keyed on content_hash so
//      unchanged rows only bump last_seen_at.
//   3. Soft-expire jobs not seen this run (is_active = false, closed_at = now).
//
// Per-company isolation: a single 5xx from one ATS does NOT abort the run and
// must NOT trigger false expiry for other companies. The orchestrator catches
// per-company errors, records them in the summary, and moves on.
//
// Triggered by pg_cron daily at 07:00 UTC. Also callable manually for testing.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { getAdapter } from "../_shared/ats/adapters/index.ts";
import { deriveApplyFlow } from "../_shared/ats/classify.ts";
import type {
  CompanyRow,
  NormalizedJob,
  SyncOutcome,
} from "../_shared/ats/models.ts";

const PITCH_CRON_SECRET = Deno.env.get("PITCH_CRON_SECRET") ?? "";

type RequestBody = {
  // Optional. When set, sync only this company (manual replay / debugging).
  company_id?: string;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Cron-style invocation uses a shared secret header. Manual invocation can
  // skip it when the function is called via the Supabase dashboard.
  const providedSecret = request.headers.get("x-pitch-cron-secret");
  if (PITCH_CRON_SECRET && providedSecret !== PITCH_CRON_SECRET) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const body: RequestBody = await request.json().catch(() => ({}));
  const admin = createAdminClient();

  const query = admin
    .from("companies")
    .select("id, name, domain, ats_type, ats_token")
    .not("ats_type", "is", null)
    .not("ats_token", "is", null);

  if (body.company_id) query.eq("id", body.company_id);

  const { data: companies, error: companyError } = await query;
  if (companyError) {
    return jsonError(`Failed to load companies: ${companyError.message}`);
  }

  const outcomes: SyncOutcome[] = [];
  const startedAt = Date.now();

  for (const company of (companies ?? []) as CompanyRow[]) {
    const outcome = await syncCompany(admin, company);
    outcomes.push(outcome);
    // Surface every per-company outcome so the function logs are searchable.
    console.log(JSON.stringify({ event: "pitch_sync_company", ...outcome }));
  }

  const summary = {
    event: "pitch_sync_run",
    company_count: outcomes.length,
    inserted: sum(outcomes, (o) => o.inserted),
    updated: sum(outcomes, (o) => o.updated),
    expired: sum(outcomes, (o) => o.expired),
    errored: outcomes.filter((o) => o.error).length,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));

  return new Response(JSON.stringify({ summary, outcomes }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

async function syncCompany(
  admin: ReturnType<typeof createAdminClient>,
  company: CompanyRow,
): Promise<SyncOutcome> {
  const baseOutcome: SyncOutcome = {
    company_id: company.id,
    company_name: company.name,
    inserted: 0,
    updated: 0,
    expired: 0,
    error: null,
  };

  if (!company.ats_type || !company.ats_token) {
    return { ...baseOutcome, error: "company missing ats_type or ats_token" };
  }

  let fetched: NormalizedJob[];
  try {
    const adapter = getAdapter(company.ats_type);
    const result = await adapter({
      ats_token: company.ats_token,
      company_name: company.name,
    });
    fetched = result.jobs;
  } catch (error) {
    // Fetch failure: record + bail without touching is_active. We will retry
    // on the next run; do not mark this company's jobs as expired.
    return { ...baseOutcome, error: (error as Error).message };
  }

  // Load the existing rows for this company so we can diff on content_hash.
  const { data: existingRows, error: existingError } = await admin
    .from("jobs")
    .select("id, source_ats, external_id, content_hash, is_active")
    .eq("company_id", company.id)
    .eq("source_kind", "ats");

  if (existingError) {
    return { ...baseOutcome, error: `load existing failed: ${existingError.message}` };
  }

  type ExistingRow = {
    id: string;
    source_ats: string;
    external_id: string;
    content_hash: string | null;
    is_active: boolean;
  };

  const existingByExternalId = new Map<string, ExistingRow>();
  for (const row of (existingRows ?? []) as ExistingRow[]) {
    if (row.external_id) existingByExternalId.set(row.external_id, row);
  }

  const seenExternalIds = new Set<string>();
  const nowISO = new Date().toISOString();
  let inserted = 0;
  let updated = 0;

  for (const job of fetched) {
    seenExternalIds.add(job.external_id);
    const existing = existingByExternalId.get(job.external_id);
    const row = toJobRow(company, job, nowISO);

    if (!existing) {
      const { error } = await admin.from("jobs").insert({
        ...row,
        first_seen_at: nowISO,
      });
      if (error) {
        // Continue on per-row failure; one malformed row should not kill the
        // company's whole sync. Record + log.
        console.error(JSON.stringify({
          event: "pitch_sync_insert_failed",
          company_id: company.id,
          external_id: job.external_id,
          error: error.message,
        }));
        continue;
      }
      inserted += 1;
      continue;
    }

    if (existing.content_hash === job.content_hash && existing.is_active) {
      // Unchanged + already active → just bump last_seen_at so the expiry
      // sweep below doesn't mark this row.
      await admin
        .from("jobs")
        .update({ last_seen_at: nowISO })
        .eq("id", existing.id);
      continue;
    }

    const { error } = await admin
      .from("jobs")
      .update({
        ...row,
        // Reactivate rows that come back after going dark.
        is_active: true,
        closed_at: null,
      })
      .eq("id", existing.id);
    if (error) {
      console.error(JSON.stringify({
        event: "pitch_sync_update_failed",
        company_id: company.id,
        external_id: job.external_id,
        error: error.message,
      }));
      continue;
    }
    updated += 1;
  }

  // Expiry sweep: any previously-active row not seen this run gets soft-closed.
  const toExpire = (existingRows ?? [])
    .filter((row) => row.is_active && !seenExternalIds.has(row.external_id))
    .map((row) => row.id);

  let expired = 0;
  if (toExpire.length > 0) {
    const { error, count } = await admin
      .from("jobs")
      .update({ is_active: false, closed_at: nowISO }, { count: "exact" })
      .in("id", toExpire);
    if (error) {
      return { ...baseOutcome, inserted, updated, expired: 0, error: `expiry failed: ${error.message}` };
    }
    expired = count ?? toExpire.length;
  }

  return { ...baseOutcome, inserted, updated, expired };
}

function toJobRow(
  company: CompanyRow,
  job: NormalizedJob,
  nowISO: string,
): Record<string, unknown> {
  const title = job.title ?? "Untitled role";
  return {
    company_id: company.id,
    source_kind: "ats",
    source_ats: job.source_ats,
    external_id: job.external_id,
    title,
    company_name: company.name,
    location: job.location,
    description: job.description,
    description_raw: job.description_raw,
    application_email: job.contact_email_on_posting,
    apply_url: job.apply_url,
    apply_flow: job.apply_flow ?? deriveApplyFlow(job.apply_url),
    ats_type: job.source_ats,
    source_url: job.listing_url,
    employment_type: normalizeEmploymentType(job.employment_type),
    compensation_text: job.compensation_text,
    compensation_min_annual: toInt(job.compensation.min_annual),
    compensation_max_annual: toInt(job.compensation.max_annual),
    compensation_min_hourly: toInt(job.compensation.min_hourly),
    compensation_max_hourly: toInt(job.compensation.max_hourly),
    content_hash: job.content_hash,
    is_published: true,
    is_active: true,
    last_seen_at: nowISO,
  };
}

function sum<T>(items: T[], pick: (item: T) => number): number {
  return items.reduce((acc, item) => acc + pick(item), 0);
}

// Jobs table enforces employment_type in ('full_time', 'part_time', 'contract').
// ATS providers return free-form strings ("Full-time", "Internship", "Contractor"…);
// map known values and drop the rest to null so the CHECK passes.
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

function jsonError(message: string, status = 500) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
