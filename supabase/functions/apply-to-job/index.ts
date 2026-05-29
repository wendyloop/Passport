import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

type ApplyRequest = {
  jobId?: string;
  resumeFilePath?: string;
  selectedVideoURL?: string;
  socialLink?: string;
};

const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const fromEmail = Deno.env.get("JOBTOK_FROM_EMAIL") ?? "JobTok <applications@jobtok.app>";

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}

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

async function sendEmployerEmail(params: {
  to: string;
  employerCompany: string;
  jobTitle: string;
  candidateName: string;
  headline?: string | null;
  schoolName?: string | null;
  dreamRole?: string | null;
  previousEmployers: string[];
  pitchVideoURL?: string | null;
  resumeSignedURL?: string | null;
  linkedInURL?: string | null;
  instagramUsername?: string | null;
  tiktokUsername?: string | null;
}) {
  if (!resendApiKey) {
    return {
      status: "skipped",
      error: "Missing RESEND_API_KEY in Supabase Edge Function secrets.",
    };
  }

  const previousEmployers = params.previousEmployers.length
    ? params.previousEmployers.join(", ")
    : "Not provided";
  const pitchLine = params.pitchVideoURL
    ? `Pitch video: ${params.pitchVideoURL}`
    : "Pitch video: Not provided";
  const resumeLine = params.resumeSignedURL
    ? `Resume: ${params.resumeSignedURL}`
    : "Resume: No resume uploaded";
  const socialLine = params.linkedInURL
    ? `LinkedIn: ${params.linkedInURL}`
    : params.instagramUsername
      ? `Instagram: https://instagram.com/${params.instagramUsername}`
      : params.tiktokUsername
        ? `TikTok: https://www.tiktok.com/@${params.tiktokUsername}`
        : "Social link: Not provided";

  const text = [
    `New JobTok application for ${params.jobTitle} at ${params.employerCompany}.`,
    "",
    `Candidate: ${params.candidateName}`,
    params.headline ? `Headline: ${params.headline}` : null,
    params.schoolName ? `School: ${params.schoolName}` : null,
    params.dreamRole ? `Dream role: ${params.dreamRole}` : null,
    `Previous employers: ${previousEmployers}`,
    socialLine,
    pitchLine,
    resumeLine,
  ].filter(Boolean).join("\n");

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.5; color: #111827;">
      <h2 style="margin-bottom: 8px;">New JobTok application</h2>
      <p style="margin-top: 0;">${escapeHtml(params.candidateName)} applied to <strong>${escapeHtml(params.jobTitle)}</strong> at ${escapeHtml(params.employerCompany)}.</p>
      <ul>
        ${params.headline ? `<li><strong>Headline:</strong> ${escapeHtml(params.headline)}</li>` : ""}
        ${params.schoolName ? `<li><strong>School:</strong> ${escapeHtml(params.schoolName)}</li>` : ""}
        ${params.dreamRole ? `<li><strong>Dream role:</strong> ${escapeHtml(params.dreamRole)}</li>` : ""}
        <li><strong>Previous employers:</strong> ${escapeHtml(previousEmployers)}</li>
        ${params.linkedInURL ? `<li><strong>LinkedIn:</strong> <a href="${escapeHtml(params.linkedInURL)}">${escapeHtml(params.linkedInURL)}</a></li>` : ""}
        ${params.instagramUsername ? `<li><strong>Instagram:</strong> @${escapeHtml(params.instagramUsername)}</li>` : ""}
        ${params.tiktokUsername ? `<li><strong>TikTok:</strong> @${escapeHtml(params.tiktokUsername)}</li>` : ""}
      </ul>
      <p>${params.pitchVideoURL ? `<a href="${escapeHtml(params.pitchVideoURL)}">Watch candidate pitch video</a>` : "No pitch video uploaded."}</p>
      <p>${params.resumeSignedURL ? `<a href="${escapeHtml(params.resumeSignedURL)}">Open candidate resume</a>` : "No resume uploaded."}</p>
    </div>
  `;

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [params.to],
      subject: `New applicant: ${params.candidateName} for ${params.jobTitle}`,
      text,
      html,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    return {
      status: "failed",
      error: body || `Resend request failed with status ${response.status}.`,
    };
  }

  return { status: "sent", error: null };
}

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
        .select("id, role, full_name, headline")
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
        .select("id, employer_profile_id, title, company_name, location, application_email, is_published")
        .eq("id", jobId)
        .single(),
    ]);

    const resumeQuery = adminClient
      .from("resume_uploads")
      .select("file_path")
      .eq("profile_id", user.id)
      .order("created_at", { ascending: false })
      .limit(1);

    const { data: resumeRecord, error: resumeError } = requestedResumePath
      ? await adminClient
        .from("resume_uploads")
        .select("file_path")
        .eq("profile_id", user.id)
        .eq("file_path", requestedResumePath)
        .maybeSingle()
      : await resumeQuery.maybeSingle();

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

    if (!resumeRecord?.file_path) {
      throw new Error("Select a resume before applying.");
    }

    const previousEmployers = (candidateEmployers ?? []).map((row) => row.employer_name);
    const resumeFileName = resumeRecord.file_path.split("/").pop() ?? "resume";
    const resolvedLinkedInURL = candidateProfile?.linkedin_url ?? socialPayload.linkedInURL;
    const resolvedInstagramUsername = candidateProfile?.instagram_username ?? socialPayload.instagramUsername;
    const resolvedTiktokUsername = candidateProfile?.tiktok_username ?? socialPayload.tiktokUsername;
    const resolvedVideoURL = selectedVideoURL ?? candidateProfile?.intro_video_url ?? null;

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

    const { data: insertedApplication, error: insertError } = await adminClient
      .from("job_applications")
      .insert({
        job_id: job.id,
        employer_profile_id: job.employer_profile_id,
        candidate_profile_id: user.id,
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
      })
      .select("*")
      .single();

    if (insertError) {
      throw insertError;
    }

    const signedResume = await adminClient.storage
      .from("resumes")
      .createSignedUrl(resumeRecord.file_path, 60 * 60 * 24 * 7);

    const emailResult = await sendEmployerEmail({
      to: job.application_email,
      employerCompany: job.company_name,
      jobTitle: job.title,
      candidateName: insertedApplication.candidate_name,
      headline: insertedApplication.candidate_headline,
      schoolName: insertedApplication.candidate_school_name,
      dreamRole: insertedApplication.candidate_dream_role,
      previousEmployers,
      pitchVideoURL: insertedApplication.candidate_video_url,
      resumeSignedURL: signedResume.data?.signedUrl ?? null,
      linkedInURL: insertedApplication.candidate_linkedin_url,
      instagramUsername: insertedApplication.candidate_instagram_username,
      tiktokUsername: insertedApplication.candidate_tiktok_username,
    });

    await adminClient
      .from("job_applications")
      .update({
        email_delivery_status: emailResult.status,
        email_delivery_error: emailResult.error,
      })
      .eq("id", insertedApplication.id);

    await adminClient.from("notifications").insert([
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
      {
        profile_id: job.employer_profile_id,
        type: "job_application_received",
        title: "New applicant received",
        body: `${insertedApplication.candidate_name} applied to ${job.title}.`,
        metadata: {
          application_id: insertedApplication.id,
          job_id: job.id,
          candidate_profile_id: user.id,
        },
      },
    ]);

    return new Response(JSON.stringify({
      application: {
        ...insertedApplication,
        email_delivery_status: emailResult.status,
        email_delivery_error: emailResult.error,
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
