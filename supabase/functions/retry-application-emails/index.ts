// AUDIT P1-8: applications whose employer email failed used to dead-end —
// the candidate saw "submitted", nothing retried, no one was told. This cron
// pass re-sends the identical employer email (shared builder with
// apply-to-job) for failed rows, capped at MAX_ATTEMPTS so a permanently
// bad address can't retry forever. All data comes from the application row's
// snapshot columns, so it works even if the job has changed since.
//
// Invoked by pg_cron (x-pitch-cron-secret header, fail-closed) — see
// migration 20260715121000_retry_failed_application_emails.sql.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { sendEmployerApplicationEmail } from "../_shared/application_email.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";

const MAX_ATTEMPTS = 5;
const BATCH_LIMIT = 25;

type RetryRow = {
  id: string;
  candidate_name: string;
  candidate_headline: string | null;
  candidate_school_name: string | null;
  candidate_dream_role: string | null;
  candidate_previous_employers: string[];
  candidate_video_url: string | null;
  candidate_linkedin_url: string | null;
  candidate_instagram_username: string | null;
  candidate_tiktok_username: string | null;
  resume_file_path: string | null;
  email_delivery_attempts: number;
  application_email: string;
  job_title: string;
  company_name: string;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const startedAt = Date.now();
  const admin = createAdminClient();

  const { data: rows, error } = await admin
    .from("job_applications")
    .select(
      "id, candidate_name, candidate_headline, candidate_school_name, candidate_dream_role, candidate_previous_employers, candidate_video_url, candidate_linkedin_url, candidate_instagram_username, candidate_tiktok_username, resume_file_path, email_delivery_attempts, application_email, job_title, company_name",
    )
    .eq("email_delivery_status", "failed")
    .lt("email_delivery_attempts", MAX_ATTEMPTS)
    .order("applied_at", { ascending: true })
    .limit(BATCH_LIMIT);

  if (error) {
    return jsonError(`Failed to load failed applications: ${error.message}`);
  }

  const outcomes: Array<{ application_id: string; status: string; error: string | null }> = [];

  for (const row of (rows ?? []) as RetryRow[]) {
    let resumeSignedURL: string | null = null;
    if (row.resume_file_path) {
      const signed = await admin.storage
        .from("resumes")
        .createSignedUrl(row.resume_file_path, 60 * 60 * 24 * 7);
      resumeSignedURL = signed.data?.signedUrl ?? null;
    }

    const result = await sendEmployerApplicationEmail({
      to: row.application_email,
      employerCompany: row.company_name,
      jobTitle: row.job_title,
      candidateName: row.candidate_name,
      headline: row.candidate_headline,
      schoolName: row.candidate_school_name,
      dreamRole: row.candidate_dream_role,
      previousEmployers: row.candidate_previous_employers ?? [],
      pitchVideoURL: row.candidate_video_url,
      resumeSignedURL,
      linkedInURL: row.candidate_linkedin_url,
      instagramUsername: row.candidate_instagram_username,
      tiktokUsername: row.candidate_tiktok_username,
    });

    const { error: updateError } = await admin
      .from("job_applications")
      .update({
        email_delivery_status: result.status,
        email_delivery_error: result.error,
        email_delivery_attempts: row.email_delivery_attempts + 1,
      })
      .eq("id", row.id);
    if (updateError) {
      console.error(`retry update failed for ${row.id}: ${updateError.message}`);
    }

    outcomes.push({ application_id: row.id, status: result.status, error: result.error });
    console.log(JSON.stringify({ event: "retry_application_email", application_id: row.id, status: result.status }));
  }

  const summary = {
    event: "retry_application_emails_run",
    picked_up: outcomes.length,
    sent: outcomes.filter((o) => o.status === "sent").length,
    still_failed: outcomes.filter((o) => o.status !== "sent").length,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));
  await recordPipelineRun(admin, "retry-application-emails", startedAt, summary, summary.still_failed);

  return jsonResponse({ summary, outcomes });
});
