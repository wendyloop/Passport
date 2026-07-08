import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { escapeHtml, sendEmail } from "../_shared/email.ts";

type OutreachRequest = {
  candidateId?: string;
  relatedJobId?: string | null;
  subject?: string;
  message?: string;
};

async function sendCandidateEmail(params: {
  to: string;
  candidateName: string;
  employerName: string;
  companyName: string;
  subject: string;
  message: string;
  relatedJobTitle?: string | null;
}) {
  const intro = params.relatedJobTitle
    ? `${params.employerName} from ${params.companyName} reached out about ${params.relatedJobTitle}.`
    : `${params.employerName} from ${params.companyName} reached out through JobTok.`;

  const text = [
    `Hi ${params.candidateName},`,
    "",
    intro,
    "",
    params.message,
    "",
    "Reply directly to this email if you want to continue the conversation.",
  ].join("\n");

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.5; color: #111827;">
      <p>Hi ${escapeHtml(params.candidateName)},</p>
      <p>${escapeHtml(intro)}</p>
      <p>${escapeHtml(params.message).replaceAll("\n", "<br />")}</p>
      <p>Reply directly to this email if you want to continue the conversation.</p>
    </div>
  `;

  return await sendEmail({
    to: params.to,
    subject: params.subject,
    text,
    html,
  });
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

    const body = (await request.json().catch(() => ({}))) as OutreachRequest;
    const candidateId = body.candidateId?.trim();
    const relatedJobId = body.relatedJobId?.trim() || null;
    const subject = body.subject?.trim();
    const message = body.message?.trim();

    if (!candidateId || !subject || !message) {
      return new Response(JSON.stringify({ error: "candidateId, subject, and message are required." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const [{ data: employerProfile, error: employerProfileError }, { data: employerDetails, error: employerDetailsError }] = await Promise.all([
      adminClient
        .from("employer_profiles")
        .select("profile_id, company_name, position_title")
        .eq("profile_id", user.id)
        .single(),
      adminClient
        .from("profiles")
        .select("id, role, full_name, email")
        .eq("id", user.id)
        .single(),
    ]);

    if (employerProfileError || !employerProfile) throw employerProfileError ?? new Error("Employer profile not found.");
    if (employerDetailsError || !employerDetails) throw employerDetailsError ?? new Error("Employer account not found.");
    if (employerDetails.role !== "employer") {
      throw new Error("Only employers can reach out to candidates.");
    }

    const [{ data: discoverableCandidate, error: discoverableCandidateError }, { data: existingApplication, error: existingApplicationError }, { data: candidateDetails, error: candidateDetailsError }, { data: relatedJob, error: relatedJobError }] = await Promise.all([
      adminClient
        .from("employer_candidate_discovery")
        .select("candidate_id, full_name")
        .eq("candidate_id", candidateId)
        .maybeSingle(),
      adminClient
        .from("job_applications")
        .select("id, job_id, job_title")
        .eq("candidate_profile_id", candidateId)
        .eq("employer_profile_id", user.id)
        .limit(1)
        .maybeSingle(),
      adminClient
        .from("profiles")
        .select("id, full_name, email, onboarding_complete")
        .eq("id", candidateId)
        .single(),
      relatedJobId
        ? adminClient
            .from("jobs")
            .select("id, title, employer_profile_id")
            .eq("id", relatedJobId)
            .maybeSingle()
        : Promise.resolve({ data: null, error: null }),
    ]);

    if (discoverableCandidateError) throw discoverableCandidateError;
    if (existingApplicationError) throw existingApplicationError;
    if (candidateDetailsError || !candidateDetails) throw candidateDetailsError ?? new Error("Candidate profile not found.");
    if (relatedJobError) throw relatedJobError;

    const hasVisibilityAccess = Boolean(discoverableCandidate) || Boolean(existingApplication);
    if (!hasVisibilityAccess) {
      throw new Error("You can only contact discoverable candidates or candidates who already applied to your jobs.");
    }

    if (relatedJob && relatedJob.employer_profile_id !== user.id) {
      throw new Error("The selected job does not belong to your employer account.");
    }

    if (!candidateDetails.email) {
      throw new Error("Candidate email is not available.");
    }

    const emailResult = await sendCandidateEmail({
      to: candidateDetails.email,
      candidateName: candidateDetails.full_name ?? "there",
      employerName: employerDetails.full_name ?? "A hiring team",
      companyName: employerProfile.company_name ?? "a company",
      subject,
      message,
      relatedJobTitle: relatedJob?.title ?? existingApplication?.job_title ?? null,
    });

    const { data: outreach, error: outreachError } = await adminClient
      .from("candidate_outreach_messages")
      .insert({
        employer_profile_id: user.id,
        candidate_profile_id: candidateId,
        related_job_id: relatedJob?.id ?? relatedJobId ?? existingApplication?.job_id ?? null,
        subject,
        body: message,
        delivery_status: emailResult.status,
        delivery_error: emailResult.error,
      })
      .select("*")
      .single();

    if (outreachError) {
      throw outreachError;
    }

    await adminClient.from("notifications").insert({
      profile_id: candidateId,
      type: "candidate_outreach_received",
      title: "New employer outreach",
      body: `${employerProfile.company_name ?? "An employer"} reached out to you through JobTok.`,
      metadata: {
        outreach_id: outreach.id,
        employer_profile_id: user.id,
        related_job_id: relatedJob?.id ?? relatedJobId ?? existingApplication?.job_id ?? null,
      },
    });

    return new Response(JSON.stringify({ outreach }), {
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
