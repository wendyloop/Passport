import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { sendPitchEmail } from "../_shared/pitch_email.ts";
import { selectResume } from "../_shared/resume_select.ts";
import {
  attachmentFilename,
  fetchUrlAttachment,
  RESUME_ATTACHMENT_MAX_BYTES,
  storageAttachment,
  VIDEO_ATTACHMENT_MAX_BYTES,
} from "../_shared/email_attachments.ts";

type ApplyRequest = {
  jobId?: string;
  resumeFilePath?: string;
  selectedVideoURL?: string;
  socialLink?: string;
};

// INSTAGRAM MESSAGING API (DM on apply) — disabled until Meta app review is complete.
// To enable: set INSTAGRAM_ACCESS_TOKEN and INSTAGRAM_BUSINESS_ACCOUNT_ID in Supabase edge function secrets,
// then uncomment sendInstagramDM, the isInstagramReel routing block, and the canApply change in iOS.
// const instagramAccessToken = Deno.env.get("INSTAGRAM_ACCESS_TOKEN") ?? "";
// const instagramAccountId = Deno.env.get("INSTAGRAM_BUSINESS_ACCOUNT_ID") ?? "";

function normalizedSocialPayload(rawValue?: string | null) {
  const trimmed = rawValue?.trim();
  if (!trimmed) {
    return {
      linkedInURL: null,
      instagramUsername: null,
      tiktokUsername: null,
    };
  }

  const lower = trimmed.toLowerCase();
  if (lower.includes("linkedin.com")) {
    return {
      linkedInURL: trimmed,
      instagramUsername: null,
      tiktokUsername: null,
    };
  }

  if (lower.includes("instagram.com")) {
    const match = trimmed.match(/instagram\.com\/([^/?#]+)/i);
    return {
      linkedInURL: null,
      instagramUsername: match?.[1]?.replace(/^@/, "") ?? null,
      tiktokUsername: null,
    };
  }

  if (lower.includes("tiktok.com")) {
    const match = trimmed.match(/tiktok\.com\/@?([^/?#]+)/i);
    return {
      linkedInURL: null,
      instagramUsername: null,
      tiktokUsername: match?.[1]?.replace(/^@/, "") ?? null,
    };
  }

  return {
    linkedInURL: lower.startsWith("http://") || lower.startsWith("https://") ? trimmed : null,
    instagramUsername: null,
    tiktokUsername: null,
  };
}

// The employer email itself lives in _shared/pitch_email.ts so the
// retry-application-emails cron pass (AUDIT P1-8) sends the identical email.

// async function sendInstagramDM(params: {
//   creatorHandle: string;
//   candidateName: string;
//   jobTitle: string;
//   headline: string | null;
//   resumeURL: string | null;
// }): Promise<{ status: string; error: string | null }> {
//   const lines = [
//     `Hi @${params.creatorHandle}! 👋`,
//     ``,
//     `${params.candidateName} just applied to your hiring post on scout22.`,
//     params.headline ? `"${params.headline}"` : null,
//     params.resumeURL ? `\nResume: ${params.resumeURL}` : null,
//     `\nReply to this message to connect with them directly.`,
//   ].filter(Boolean).join("\n");
//   const resp = await fetch(
//     `https://graph.facebook.com/v18.0/${instagramAccountId}/messages`,
//     {
//       method: "POST",
//       headers: { "Content-Type": "application/json" },
//       body: JSON.stringify({
//         recipient: { username: params.creatorHandle },
//         message: { text: lines },
//         access_token: instagramAccessToken,
//       }),
//     },
//   );
//   if (!resp.ok) {
//     const err = await resp.text().catch(() => `HTTP ${resp.status}`);
//     return { status: "failed", error: err };
//   }
//   return { status: "sent", error: null };
// }

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const adminClient = createAdminClient();
    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = (await request.json().catch(() => ({}))) as ApplyRequest;
    const jobId = body.jobId?.trim();
    const requestedResumePath = body.resumeFilePath?.trim() || null;
    const selectedVideoURL = body.selectedVideoURL?.trim() || null;
    const socialPayload = normalizedSocialPayload(body.socialLink);

    if (!jobId) {
      return new Response(JSON.stringify({ error: "Missing jobId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const [
      { data: profile, error: profileError },
      { data: candidateProfile, error: candidateProfileError },
      { data: candidateEmployers, error: candidateEmployersError },
      { data: job, error: jobError },
    ] = await Promise.all([
      adminClient
        .from("profiles")
        .select("id, role, full_name, headline, email")
        .eq("id", user.id)
        .single(),
      adminClient
        .from("job_seeker_profiles")
        .select("profile_id, school_name, job_function, dream_role, intro_video_url, linkedin_url, instagram_username, tiktok_username, desired_compensation_range")
        .eq("profile_id", user.id)
        .maybeSingle(),
      adminClient
        .from("job_seeker_employers")
        .select("employer_name, sort_order")
        .eq("profile_id", user.id)
        .order("sort_order", { ascending: true }),
      adminClient
        .from("jobs")
        .select("id, employer_profile_id, title, company_name, location, application_email, is_published, source_platform, source_creator_name")
        .eq("id", jobId)
        .single(),
    ]);

    // S-5: an explicit pick wins, then the candidate's default, then the
    // newest. The explicit path is unchanged in behaviour — apply-to-job has
    // always honoured requestedResumePath — it just shares one resolver now.
    const resumeRecord = await selectResume<{ file_path: string; parsed_json: unknown }>(
      adminClient,
      user.id,
      { columns: "file_path, parsed_json", requestedPath: requestedResumePath },
    );
    const resumeError = null;

    if (profileError || !profile) throw profileError ?? new Error("Profile not found.");
    if (candidateProfileError) throw candidateProfileError;
    if (candidateEmployersError) throw candidateEmployersError;
    if (resumeError) throw resumeError;
    if (jobError || !job) throw jobError ?? new Error("Job not found.");

    if (profile.role !== "job_seeker") {
      throw new Error("Only job seekers can apply.");
    }

    if (!job.is_published) {
      throw new Error("This job is not open for applications.");
    }

    if (!job.application_email?.trim()) {
      throw new Error("Applications are not available for this job yet.");
    }
    // const isInstagramReel = job.source_platform === "instagram" && !!job.source_creator_name;

    if (!resumeRecord?.file_path) {
      throw new Error("Select a resume before applying.");
    }

    const previousEmployers = (candidateEmployers ?? []).map((row) => row.employer_name);
    const resumeFileName = resumeRecord.file_path.split("/").pop() ?? "resume";
    const resolvedLinkedInURL = candidateProfile?.linkedin_url ?? socialPayload.linkedInURL;
    const resolvedInstagramUsername = candidateProfile?.instagram_username ?? socialPayload.instagramUsername;
    const resolvedTiktokUsername = candidateProfile?.tiktok_username ?? socialPayload.tiktokUsername;
    // M-C: candidates can pick which of their videos rides along — but only
    // one they actually own (the client sends a bare URL).
    if (selectedVideoURL && selectedVideoURL !== candidateProfile?.intro_video_url) {
      const { count: ownedCount, error: ownedError } = await adminClient
        .from("candidate_videos")
        .select("id", { count: "exact", head: true })
        .eq("profile_id", user.id)
        .eq("video_url", selectedVideoURL);
      if (ownedError) throw ownedError;
      if ((ownedCount ?? 0) === 0) {
        return new Response(JSON.stringify({ error: "Selected video does not belong to this account" }), {
          status: 422,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const resolvedVideoURL = selectedVideoURL ?? candidateProfile?.intro_video_url ?? null;

    // The pitch video is optional as of 2026-08-22: it was a hard gate on
    // applying, and the video step is where candidates drop out. A resume
    // is still required. The video attaches when there is one, and the
    // client nudges for it at the apply drawer instead of blocking.
    //
    // NOTE: send-founder-email still requires a video — pitching a founder
    // cold is the one place the video IS the product.

    if (socialPayload.linkedInURL || socialPayload.instagramUsername || socialPayload.tiktokUsername) {
      const { error: upsertCandidateProfileError } = await adminClient
        .from("job_seeker_profiles")
        .upsert({
          profile_id: user.id,
          intro_video_url: candidateProfile?.intro_video_url ?? resolvedVideoURL,
          linkedin_url: resolvedLinkedInURL,
          instagram_username: resolvedInstagramUsername,
          tiktok_username: resolvedTiktokUsername,
        }, {
          onConflict: "profile_id",
        });

      if (upsertCandidateProfileError) throw upsertCandidateProfileError;
    }

    const applicationRow = {
      job_id: job.id,
      employer_profile_id: job.employer_profile_id,
      candidate_profile_id: user.id,
      application_kind: "ats_apply",
      cover_note: null,
      job_title: job.title,
      company_name: job.company_name,
      job_location: job.location,
      application_email: job.application_email,
      candidate_name: profile.full_name ?? user.email ?? "Candidate",
      candidate_headline: profile.headline,
      candidate_school_name: candidateProfile?.school_name ?? null,
      candidate_job_function: candidateProfile?.job_function ?? null,
      candidate_dream_role: candidateProfile?.dream_role ?? null,
      candidate_previous_employers: previousEmployers,
      candidate_video_url: resolvedVideoURL,
      candidate_linkedin_url: resolvedLinkedInURL,
      candidate_instagram_username: resolvedInstagramUsername,
      candidate_tiktok_username: resolvedTiktokUsername,
      candidate_compensation_range: candidateProfile?.desired_compensation_range ?? null,
      resume_file_path: resumeRecord.file_path,
      resume_file_name: resumeFileName,
      email_delivery_status: "pending",
    };

    let { data: insertedApplication, error: insertError } = await adminClient
      .from("job_applications")
      .insert(applicationRow)
      .select("*")
      .single();

    // 23505: a row already exists for this (job, candidate). If it came from
    // a founder pitch, upgrade it in place to a full application instead of
    // failing — the candidate pitched first and is now applying properly.
    // founder_pitched_at is not in the payload, so the pitch history survives.
    // A row that is already an ats_apply is a genuine duplicate and must keep
    // hitting the dup guard.
    if (insertError?.code === "23505") {
      const { data: upgraded, error: upgradeError } = await adminClient
        .from("job_applications")
        .update(applicationRow)
        .eq("job_id", job.id)
        .eq("candidate_profile_id", user.id)
        .eq("application_kind", "founder_pitch")
        .select("*")
        .maybeSingle();
      if (upgradeError) throw upgradeError;
      if (upgraded) {
        insertedApplication = upgraded;
        insertError = null;
      }
    }

    if (insertError) {
      throw insertError;
    }

    // FIRST-100-USERS: a video application lands in a founder's inbox like a
    // founder email does, so stamp the job for feed deprioritization — spread
    // applications across companies while the user base is tiny. See
    // 20260708140000_founder_fatigue.sql.
    if (resolvedVideoURL) {
      await adminClient
        .from("jobs")
        .update({ last_founder_touch_at: new Date().toISOString() })
        .eq("id", job.id);
    }

    // Attach the actual files; anything oversized/broken falls back to a
    // link (resume link is a 7-day signed URL, video is a public URL).
    const candidateName = insertedApplication.candidate_name as string;
    const resumeAttachment = await storageAttachment(
      adminClient,
      "resumes",
      resumeRecord.file_path,
      attachmentFilename(candidateName, "Resume", resumeRecord.file_path, "pdf"),
      RESUME_ATTACHMENT_MAX_BYTES,
    );
    const videoAttachment = resolvedVideoURL
      ? await fetchUrlAttachment(
        resolvedVideoURL,
        attachmentFilename(candidateName, "Pitch", resolvedVideoURL, "mp4"),
        VIDEO_ATTACHMENT_MAX_BYTES,
      )
      : null;

    let resumeURL: string | null = null;
    if (!resumeAttachment) {
      const signedResume = await adminClient.storage
        .from("resumes")
        .createSignedUrl(resumeRecord.file_path, 60 * 60 * 24 * 7);
      resumeURL = signedResume.data?.signedUrl ?? null;
    }

    const deliveryResult = await sendPitchEmail({
      to: job.application_email!,
      candidateName,
      candidateEmail: profile.email ?? user.email ?? null,
      headline: insertedApplication.candidate_headline,
      jobTitle: job.title,
      companyName: job.company_name,
      facts: resumeRecord.parsed_json ?? null,
      schoolName: insertedApplication.candidate_school_name,
      previousEmployers,
      compensationRange: insertedApplication.candidate_compensation_range,
      linkedInURL: insertedApplication.candidate_linkedin_url,
      instagramUsername: insertedApplication.candidate_instagram_username,
      tiktokUsername: insertedApplication.candidate_tiktok_username,
      videoAttached: !!videoAttachment,
      resumeAttached: !!resumeAttachment,
      pitchVideoURL: insertedApplication.candidate_video_url,
      resumeSignedURL: resumeURL,
    }, {
      attachments: [resumeAttachment, videoAttachment].filter(
        (a): a is NonNullable<typeof a> => !!a,
      ),
    });

    await adminClient
      .from("job_applications")
      .update({
        email_delivery_status: deliveryResult.status,
        email_delivery_error: deliveryResult.error,
      })
      .eq("id", insertedApplication.id);

    // Scraped reels have no employer_profile_id, so skip the employer
    // notification when there's no one to notify. The candidate always gets one.
    const notifications: Array<Record<string, unknown>> = [
      {
        profile_id: user.id,
        type: "job_application_submitted",
        title: "Application submitted",
        body: `Your application for ${job.title} at ${job.company_name} was submitted.`,
        metadata: {
          application_id: insertedApplication.id,
          job_id: job.id,
        },
      },
    ];

    if (job.employer_profile_id) {
      notifications.push({
        profile_id: job.employer_profile_id,
        type: "job_application_received",
        title: "New applicant received",
        body: `${insertedApplication.candidate_name} applied to ${job.title}.`,
        metadata: {
          application_id: insertedApplication.id,
          job_id: job.id,
          candidate_profile_id: user.id,
        },
      });
    }

    await adminClient.from("notifications").insert(notifications);

    return new Response(JSON.stringify({
      application: {
        ...insertedApplication,
        email_delivery_status: deliveryResult.status,
        email_delivery_error: deliveryResult.error,
      },
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
