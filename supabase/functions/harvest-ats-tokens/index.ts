// C-1: fill in ATS coordinates that the company's own jobs already reveal.
//
// upsertCompanyAndLink resolves (ats_type, ats_token) from the COMPANY's board
// entry. When a board lists a company with no ATS hint — common on Getro — the
// company is stored with ats_type null, even though every one of its jobs
// carries a perfectly good boards.greenhouse.io/{token} apply URL. Those
// companies are then invisible to the per-company ATS crawler: their postings
// only refresh when the VC board happens to mention them again.
//
// This closes that gap from data already in the database. No network calls, no
// model calls, and the same classifyApplyURL the ingest path uses — so the two
// can never disagree about what a URL means.
//
// Re-runnable and idempotent. It is a cron rather than a one-off because the
// gap is structural: as long as boards list companies without ATS hints, new
// stragglers appear.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { jsonResponse } from "../_shared/http.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";
import { harvestFromApplyURLs } from "../_shared/ats/harvest.ts";

// Companies scanned per run. Small because each one costs a jobs query; the
// backlog is finite and drains in a few runs.
const COMPANY_BATCH = 200;
// Apply URLs inspected per company. A company posting on two ATS at once is
// rare, but reading more than a handful only helps consensus.
const URL_SAMPLE = 25;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const startedAt = Date.now();
  const admin = createAdminClient();

  let scanned = 0;
  let resolved = 0;
  let ambiguous = 0;
  let taken = 0;
  const errors: string[] = [];

  try {
    // Oldest first, so a large backlog drains deterministically rather than
    // re-scanning the same head every run.
    const { data: companies, error: companiesError } = await admin
      .from("companies")
      .select("id, name")
      .is("ats_type", null)
      .order("first_seen_at", { ascending: true })
      .limit(COMPANY_BATCH);
    if (companiesError) throw companiesError;

    for (const company of companies ?? []) {
      scanned++;

      const { data: jobs, error: jobsError } = await admin
        .from("jobs")
        .select("apply_url")
        .eq("company_id", company.id)
        .not("apply_url", "is", null)
        .limit(URL_SAMPLE);
      if (jobsError) {
        errors.push(`${company.name}: ${jobsError.message}`);
        continue;
      }

      const verdict = harvestFromApplyURLs((jobs ?? []).map((j) => j.apply_url));
      if (verdict.kind !== "resolved") {
        // Left alone in both cases. Guessing a token would point the crawler
        // at another company's board.
        if (verdict.kind === "ambiguous") ambiguous++;
        continue;
      }
      const resolution = verdict.resolution;

      // companies_ats_unique means another company may already hold this
      // token — most often because the same org appears twice under different
      // names from two boards. Claiming it here would 409; the duplicate is a
      // separate problem and is not solved by failing this run.
      const { data: holder } = await admin
        .from("companies")
        .select("id")
        .eq("ats_type", resolution.ats_type)
        .eq("ats_token", resolution.ats_token)
        .maybeSingle();
      if (holder?.id && holder.id !== company.id) {
        taken++;
        continue;
      }

      const { error: updateError } = await admin
        .from("companies")
        .update({
          ats_type: resolution.ats_type,
          ats_token: resolution.ats_token,
        })
        .eq("id", company.id)
        // Never overwrite coordinates resolved since this row was read.
        .is("ats_type", null);
      if (updateError) {
        errors.push(`${company.name}: ${updateError.message}`);
        continue;
      }
      resolved++;
    }

    const summary = {
      scanned,
      resolved,
      ambiguous,
      taken,
      errors: errors.slice(0, 10),
      duration_ms: Date.now() - startedAt,
    };

    await recordPipelineRun(admin, "harvest-ats-tokens", startedAt, summary, errors.length);

    return jsonResponse(summary);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await recordPipelineRun(
      admin,
      "harvest-ats-tokens",
      startedAt,
      { scanned, resolved, error: message },
      1,
    );
    return jsonResponse({ error: message }, 500);
  }
});
