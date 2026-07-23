// Candidate → founder direct email, the secondary apply path.
//
// One function, two modes:
//   preview — resolves eligibility (video gate, contact availability, weekly
//             quota) and returns a masked recipient for the compose sheet.
//   send    — re-validates everything, reserves quota atomically via the
//             reserve_founder_email_send RPC (advisory lock — never
//             check-then-insert here), sends via Resend with reply-to set to
//             the candidate, and records the outreach row.
//
// Raw contact emails NEVER reach the client — only masked forms. Guessed
// addresses are a service-side asset and must not be harvestable.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";
import { escapeHtml, sendEmail } from "../_shared/email.ts";

const FOUNDER_FROM_EMAIL = Deno.env.get("FOUNDER_FROM_EMAIL") ??
  "scout22 <intro@tryscout22.com>";
// FIRST-100-USERS: pre-launch, all founder replies route to one monitored
// human mailbox (wendyshi@berkeley.edu) instead of each candidate's own
// address — tryscout22.com is send-only (no MX), and this keeps every reply
// somewhere Wendy actually reads. Unset the secret to restore per-candidate
// reply-to at scale.
const FOUNDER_REPLY_TO_OVERRIDE = Deno.env.get("FOUNDER_REPLY_TO_EMAIL") ?? "";
const DEFAULT_WEEKLY_LIMIT = 5;
const MAX_NOTE_CHARS = 400;
// Follow-ups to the same founder are allowed after this window (was a hard
// once-ever rule; relaxed by product decision 2026-07-23). The reserve RPC
// enforces the same window race-safely.
const CONTACT_COOLDOWN_DAYS = 7;

// TODO(deferred): T9 remainder — email verification: validate guessed
// addresses with a vendor (Hunter/NeverBounce) BEFORE sending, instead of
// relying only on the Resend bounce webhook after the fact. Needs a vendor
// account + API key. (Per-company cap + re-scrape cadence shipped
// 2026-07-11.) See docs/DEFERRED_WORK.md.

// T9: no company should hear from more than this many candidates per week,
// regardless of which candidates — protects founder goodwill beyond the
// per-candidate limit.
const COMPANY_WEEKLY_CAP = 3;

type RequestBody = {
  jobId?: string;
  mode?: "preview" | "send";
  note?: string;
  contactId?: string;
};

type ContactRow = {
  id: string;
  full_name: string | null;
  first_name: string | null;
  role_title: string | null;
  source: string;
  email: string;
  email_status: string;
  confidence: number | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const admin = createAdminClient();
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonError("Unauthorized", 401);

    const body = (await request.json().catch(() => ({}))) as RequestBody;
    const jobId = body.jobId?.trim();
    const mode = body.mode === "send" ? "send" : "preview";
    if (!jobId) return jsonError("Missing jobId", 400);

    const [
      { data: profile, error: profileError },
      { data: seekerProfile, error: seekerError },
      { data: job, error: jobError },
    ] = await Promise.all([
      admin.from("profiles").select("id, role, full_name, email").eq("id", user.id).single(),
      admin.from("job_seeker_profiles").select("profile_id, intro_video_url").eq("profile_id", user.id).maybeSingle(),
      admin.from("jobs").select("id, company_id, title, company_name, is_active").eq("id", jobId).single(),
    ]);

    if (profileError || !profile) return jsonError("Profile not found", 404);
    if (seekerError) return jsonError(seekerError.message);
    if (jobError || !job) return jsonError("Job not found", 404);
    if (profile.role !== "job_seeker") return jsonError("Only job seekers can email founders", 403);
    if (!job.company_id) return jsonError("This job has no linked company", 422);

    // Video gate — the whole point is candidates on video.
    const pitchVideoURL = seekerProfile?.intro_video_url?.trim() || null;
    if (!pitchVideoURL) {
      if (mode === "preview") {
        return jsonResponse(ineligible("pitch_video_required"));
      }
      return jsonError("A pitch video is required before emailing founders", 422);
    }

    // T9: per-company weekly cap — checked before per-candidate quota so the
    // preview can surface the right reason.
    const { count: companySends, error: companyCapError } = await admin
      .from("founder_outreach_messages")
      .select("id", { count: "exact", head: true })
      .eq("company_id", job.company_id)
      .gt("created_at", new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
      .neq("delivery_status", "failed");
    if (companyCapError) return jsonError(companyCapError.message);
    if ((companySends ?? 0) >= COMPANY_WEEKLY_CAP) {
      if (mode === "preview") return jsonResponse(ineligible("company_capped"));
      return jsonError("This founder has reached their weekly pitch limit", 429);
    }

    // Quota.
    const limit = await weeklyLimit(admin);
    const { count: usedCount, error: usedError } = await admin
      .from("founder_outreach_messages")
      .select("id", { count: "exact", head: true })
      .eq("candidate_profile_id", user.id)
      .gt("created_at", new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
      .neq("delivery_status", "failed");
    if (usedError) return jsonError(usedError.message);
    const remaining = Math.max(0, limit - (usedCount ?? 0));

    // Contact resolution: verified posting emails first, then best guess by
    // confidence; never bounced/suppressed; never one this candidate emailed
    // within the follow-up cooldown.
    const contact = await resolveContact(admin, {
      companyId: job.company_id,
      candidateId: user.id,
      contactId: body.contactId?.trim() || null,
    });

    if (!contact) {
      if (mode === "preview") return jsonResponse({ ...ineligible("no_contact"), remaining, limit });
      return jsonError("No founder contact available for this company", 422);
    }

    const subject = `Intro from ${profile.full_name ?? "a scout22 candidate"} — ${job.title ?? "your open role"}`;

    if (mode === "preview") {
      return jsonResponse({
        eligible: remaining > 0,
        reason: remaining > 0 ? null : "weekly_limit_reached",
        contact: {
          id: contact.id,
          fullName: contact.full_name,
          roleTitle: contact.role_title,
          emailMasked: maskEmail(contact.email),
          source: contact.source,
          confidence: contact.confidence,
        },
        remaining,
        limit,
        subjectPreview: subject,
      });
    }

    // ── send ──
    const note = sanitizeNote(body.note);

    // Signed resume URL is optional — founder emails lead with the video.
    const resumeURL = await latestResumeSignedURL(admin, user.id);

    const { text, html } = composeEmail({
      candidateName: profile.full_name ?? "A scout22 candidate",
      candidateEmail: profile.email ?? user.email ?? "",
      founderFirstName: contact.first_name,
      jobTitle: job.title ?? "your open role",
      companyName: job.company_name ?? "your company",
      pitchVideoURL,
      resumeURL,
      note,
    });

    const { data: reserved, error: reserveError } = await admin.rpc("reserve_founder_email_send", {
      p_candidate: user.id,
      p_company: job.company_id,
      p_contact: contact.id,
      p_job: job.id,
      p_to_email: contact.email,
      p_subject: subject,
      p_body: text,
      p_note: note,
      p_limit: limit,
    });

    if (reserveError) {
      if (reserveError.message.includes("WEEKLY_LIMIT_REACHED")) {
        return jsonError("Weekly founder email limit reached", 429);
      }
      if (reserveError.message.includes("CONTACT_COOLDOWN")) {
        return jsonError("You emailed this founder in the last week — give them a moment to reply", 429);
      }
      return jsonError(reserveError.message);
    }

    const outreachId = (reserved as Array<{ outreach_id: string; sends_used: number }>)[0]?.outreach_id;
    if (!outreachId) return jsonError("Reservation failed");

    const delivery = await sendEmail({
      from: FOUNDER_FROM_EMAIL,
      to: contact.email,
      replyTo: FOUNDER_REPLY_TO_OVERRIDE || (profile.email ?? user.email ?? undefined),
      subject,
      text,
      html,
    });

    const deliveryStatus = delivery.status === "sent" ? "sent" : "failed";
    await admin
      .from("founder_outreach_messages")
      .update({
        delivery_status: deliveryStatus,
        delivery_error: delivery.error,
        resend_email_id: delivery.resendId,
      })
      .eq("id", outreachId);

    if (deliveryStatus === "failed") {
      return jsonError(delivery.error ?? "Email delivery failed", 502);
    }

    // DB-P1-6: this insert failed silently for weeks because the enum label
    // didn't exist — never leave a notification insert unchecked again.
    const { error: notifyError } = await admin.from("notifications").insert({
      profile_id: user.id,
      type: "founder_email_sent",
      title: "Founder intro sent",
      body: `Your intro for ${job.title ?? "the role"} at ${job.company_name ?? "the company"} is on its way.`,
      metadata: { outreach_id: outreachId, job_id: job.id },
    });
    if (notifyError) {
      console.error(`founder_email_sent notification insert failed: ${notifyError.message}`);
    }

    // FIRST-100-USERS: stamp the job so the feed deprioritizes it — spread
    // intros across founders instead of piling onto one job. See
    // 20260708140000_founder_fatigue.sql.
    await admin
      .from("jobs")
      .update({ last_founder_touch_at: new Date().toISOString() })
      .eq("id", job.id);

    return jsonResponse({
      outreach: {
        id: outreachId,
        jobId: job.id,
        subject,
        deliveryStatus,
        createdAt: new Date().toISOString(),
      },
      remaining: Math.max(0, remaining - 1),
      limit,
    });
  } catch (error) {
    console.error(JSON.stringify({ event: "send_founder_email_error", error: (error as Error).message }));
    return jsonError((error as Error).message);
  }
});

function ineligible(reason: string) {
  return { eligible: false, reason, contact: null, remaining: 0, limit: 0, subjectPreview: null };
}

async function weeklyLimit(admin: ReturnType<typeof createAdminClient>): Promise<number> {
  const { data } = await admin
    .from("app_config")
    .select("value")
    .eq("key", "founder_email_weekly_limit")
    .maybeSingle();
  const parsed = Number(data?.value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_WEEKLY_LIMIT;
}

async function resolveContact(
  admin: ReturnType<typeof createAdminClient>,
  params: { companyId: string; candidateId: string; contactId: string | null },
): Promise<ContactRow | null> {
  // Exclude only contacts inside the follow-up cooldown (non-failed sends
  // in the last CONTACT_COOLDOWN_DAYS). Older sends don't exclude — the
  // candidate may follow up; the reserve RPC enforces the same window
  // atomically.
  const cutoff = new Date(Date.now() - CONTACT_COOLDOWN_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const { data: recentlyEmailed } = await admin
    .from("founder_outreach_messages")
    .select("contact_id")
    .eq("candidate_profile_id", params.candidateId)
    .neq("delivery_status", "failed")
    .gt("created_at", cutoff)
    .not("contact_id", "is", null);
  const excluded = new Set((recentlyEmailed ?? []).map((r) => r.contact_id as string));

  let query = admin
    .from("company_contacts")
    .select("id, full_name, first_name, role_title, source, email, email_status, confidence")
    .eq("company_id", params.companyId)
    .not("email", "is", null)
    .not("email_status", "in", "(bounced,suppressed)");
  if (params.contactId) query = query.eq("id", params.contactId);

  const { data, error } = await query;
  if (error) throw new Error(`contact lookup failed: ${error.message}`);

  const eligible = ((data ?? []) as ContactRow[]).filter((c) => !excluded.has(c.id));
  if (eligible.length === 0) return null;

  eligible.sort((a, b) => {
    // Verified posting emails beat guesses; then explicit verification;
    // then confidence.
    const sourceRank = (c: ContactRow) => (c.source === "posting_email" ? 0 : 1);
    const statusRank = (c: ContactRow) => (c.email_status === "verified" ? 0 : 1);
    return sourceRank(a) - sourceRank(b) ||
      statusRank(a) - statusRank(b) ||
      (b.confidence ?? 0) - (a.confidence ?? 0);
  });
  return eligible[0];
}

// "jane@acme.io" → "j•••@acme.io"
function maskEmail(email: string): string {
  const [local, domain] = email.split("@");
  if (!domain) return "•••";
  const head = local.slice(0, 1);
  return `${head}•••@${domain}`;
}

// Cap length and strip URLs — links in a stranger's first email tank
// deliverability and invite abuse.
function sanitizeNote(raw: string | undefined): string | null {
  const trimmed = raw?.trim();
  if (!trimmed) return null;
  return trimmed
    .replace(/(?:https?:\/\/|www\.)\S+/gi, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_NOTE_CHARS) || null;
}

function composeEmail(params: {
  candidateName: string;
  candidateEmail: string;
  founderFirstName: string | null;
  jobTitle: string;
  companyName: string;
  pitchVideoURL: string;
  resumeURL: string | null;
  note: string | null;
}): { text: string; html: string } {
  const greeting = params.founderFirstName ? `Hi ${params.founderFirstName},` : "Hi,";
  const intro =
    `${params.candidateName} saw your ${params.jobTitle} role at ${params.companyName} on scout22 and wanted to reach out directly.`;

  const text = [
    greeting,
    "",
    intro,
    "",
    `Pitch video: ${params.pitchVideoURL}`,
    params.resumeURL ? `Resume: ${params.resumeURL}` : null,
    params.note ? `\nIn their words: "${params.note}"` : null,
    "",
    `Reply to this email to reach ${params.candidateName} directly (${params.candidateEmail}).`,
    "— sent via scout22 at the candidate's request",
  ].filter((line) => line !== null).join("\n");

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.5; color: #111827;">
      <p>${escapeHtml(greeting)}</p>
      <p>${escapeHtml(intro)}</p>
      <p><a href="${escapeHtml(params.pitchVideoURL)}">▶ Watch their pitch video</a></p>
      ${params.resumeURL ? `<p><a href="${escapeHtml(params.resumeURL)}">Open their resume</a></p>` : ""}
      ${params.note ? `<blockquote style="margin: 8px 0; padding-left: 12px; border-left: 3px solid #d1d5db;">${escapeHtml(params.note)}</blockquote>` : ""}
      <p>Reply to this email to reach ${escapeHtml(params.candidateName)} directly.</p>
      <p style="color: #6b7280; font-size: 12px;">Sent via scout22 at the candidate's request.</p>
    </div>
  `;

  return { text, html };
}

async function latestResumeSignedURL(
  admin: ReturnType<typeof createAdminClient>,
  profileId: string,
): Promise<string | null> {
  const { data: resume } = await admin
    .from("resume_uploads")
    .select("file_path")
    .eq("profile_id", profileId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!resume?.file_path) return null;

  const { data: signed } = await admin.storage
    .from("resumes")
    .createSignedUrl(resume.file_path, 60 * 60 * 24 * 7);
  return signed?.signedUrl ?? null;
}
