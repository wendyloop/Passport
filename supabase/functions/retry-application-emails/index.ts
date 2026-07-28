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
import { sendPitchEmail } from "../_shared/pitch_email.ts";
import {
  attachmentFilename,
  fetchUrlAttachment,
  RESUME_ATTACHMENT_MAX_BYTES,
  storageAttachment,
  VIDEO_ATTACHMENT_MAX_BYTES,
} from "../_shared/email_attachments.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";

const MAX_ATTEMPTS = 5;
const BATCH_LIMIT = 25;

type RetryRow = {
  id: string;
  candidate_profile_id: string | null;
  candidate_compensation_range: string | null;
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
      "id, candidate_profile_id, candidate_compensation_range, candidate_name, candidate_headline, candidate_school_name, candidate_dream_role, candidate_previous_employers, candidate_video_url, candidate_linkedin_url, candidate_instagram_username, candidate_tiktok_username, resume_file_path, email_delivery_attempts, application_email, job_title, company_name",
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
    // Rebuild the same attachments as the original send from snapshot data.
    const resumeAttachment = row.resume_file_path
      ? await storageAttachment(
        admin,
        "resumes",
        row.resume_file_path,
        attachmentFilename(row.candidate_name, "Resume", row.resume_file_path, "pdf"),
        RESUME_ATTACHMENT_MAX_BYTES,
      )
      : null;
    const videoAttachment = row.candidate_video_url
      ? await fetchUrlAttachment(
        row.candidate_video_url,
        attachmentFilename(row.candidate_name, "Pitch", row.candidate_video_url, "mp4"),
        VIDEO_ATTACHMENT_MAX_BYTES,
      )
      : null;

    let resumeSignedURL: string | null = null;
    if (row.resume_file_path && !resumeAttachment) {
      const signed = await admin.storage
        .from("resumes")
        .createSignedUrl(row.resume_file_path, 60 * 60 * 24 * 7);
      resumeSignedURL = signed.data?.signedUrl ?? null;
    }

    let candidateEmail: string | null = null;
    if (row.candidate_profile_id) {
      const { data: candidateProfile } = await admin
        .from("profiles")
        .select("email")
        .eq("id", row.candidate_profile_id)
        .maybeSingle();
      candidateEmail = candidateProfile?.email ?? null;
    }

    const result = await sendPitchEmail({
      to: row.application_email,
      candidateName: row.candidate_name,
      candidateEmail,
      headline: row.candidate_headline,
      jobTitle: row.job_title,
      companyName: row.company_name,
      schoolName: row.candidate_school_name,
      previousEmployers: row.candidate_previous_employers ?? [],
      compensationRange: row.candidate_compensation_range,
      linkedInURL: row.candidate_linkedin_url,
      instagramUsername: row.candidate_instagram_username,
      tiktokUsername: row.candidate_tiktok_username,
      videoAttached: !!videoAttachment,
      resumeAttached: !!resumeAttachment,
      pitchVideoURL: row.candidate_video_url,
      resumeSignedURL,
    }, {
      attachments: [resumeAttachment, videoAttachment].filter(
        (a): a is NonNullable<typeof a> => !!a,
      ),
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
