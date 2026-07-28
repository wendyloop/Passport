// Candidate → founder direct email, the secondary apply path.
//
// One function, two modes:
//   preview — resolves eligibility (video gate, resume gate, contact
//             availability, weekly quota) and returns a masked recipient for
//             the compose sheet.
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
import { sendEmail } from "../_shared/email.ts";
import { founderProfileGateReason } from "../_shared/founder_eligibility.ts";
import { buildPitchEmailContent, pitchSubject } from "../_shared/pitch_email.ts";
import {
  attachmentFilename,
  fetchUrlAttachment,
  RESUME_ATTACHMENT_MAX_BYTES,
  storageAttachment,
  VIDEO_ATTACHMENT_MAX_BYTES,
} from "../_shared/email_attachments.ts";

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
  // M-C: optional specific video to feature; must belong to the candidate.
  // Defaults to the primary video (intro_video_url mirror).
  videoUrl?: string;
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
      { data: latestResume, error: resumeError },
      requireResume,
    ] = await Promise.all([
      admin.from("profiles").select("id, role, full_name, email, headline").eq("id", user.id).single(),
      admin.from("job_seeker_profiles")
        .select("profile_id, intro_video_url, school_name, desired_compensation_range, linkedin_url, github_url, portfolio_url, instagram_username, tiktok_username")
        .eq("profile_id", user.id).maybeSingle(),
      admin.from("jobs").select("id, company_id, title, company_name, is_active").eq("id", jobId).single(),
      admin.from("resume_uploads").select("id, file_path, parsed_json")
        .eq("profile_id", user.id).neq("parse_status", "failed")
        .order("created_at", { ascending: false }).limit(1).maybeSingle(),
      configFlag(admin, "founder_email_require_resume", true),
    ]);

    if (profileError || !profile) return jsonError("Profile not found", 404);
    if (seekerError) return jsonError(seekerError.message);
    if (jobError || !job) return jsonError("Job not found", 404);
    if (resumeError) return jsonError(resumeError.message);
    if (profile.role !== "job_seeker") return jsonError("Only job seekers can email founders", 403);
    if (!job.company_id) return jsonError("This job has no linked company", 422);

    // Profile gates — video first (the whole point is candidates on video),
    // then resume (M-B; config kill-switch founder_email_require_resume).
    let pitchVideoURL = seekerProfile?.intro_video_url?.trim() || null;

    // M-C: a specific chosen video overrides the primary — after ownership
    // validation, since the client sends a bare URL.
    const requestedVideoURL = body.videoUrl?.trim() || null;
    if (requestedVideoURL && requestedVideoURL !== pitchVideoURL) {
      const { count: ownedCount, error: ownedError } = await admin
        .from("candidate_videos")
        .select("id", { count: "exact", head: true })
        .eq("profile_id", user.id)
        .eq("video_url", requestedVideoURL);
      if (ownedError) return jsonError(ownedError.message);
      if ((ownedCount ?? 0) === 0) {
        return jsonError("Selected video does not belong to this account", 422);
      }
      pitchVideoURL = requestedVideoURL;
    }
    const gateReason = founderProfileGateReason({
      hasPitchVideo: Boolean(pitchVideoURL),
      hasResume: Boolean(latestResume),
      requireResume,
    });
    if (gateReason) {
      if (mode === "preview") {
        return jsonResponse(ineligible(gateReason));
      }
      return jsonError(
        gateReason === "pitch_video_required"
          ? "A pitch video is required before emailing founders"
          : "An uploaded resume is required before emailing founders",
        422,
      );
    }

    // M-F: resume↔job match gate, behind founder_email_require_match
    // (default off until floor/ceiling are calibrated). Fail open on missing
    // embeddings (backfill gap) and on title-only job embeddings — a coarse
    // vector must never block a pitch.
    let matchScore: number | null = null;
    const requireMatch = await configFlag(admin, "founder_email_require_match", false);
    if (requireMatch) {
      const { data: matchRows, error: matchError } = await admin.rpc("founder_match_score", {
        p_candidate: user.id,
        p_job: job.id,
      });
      if (matchError) return jsonError(matchError.message);
      const match = (matchRows as Array<{ score: number; quality: string }> | null)?.[0] ?? null;
      if (match && match.quality === "full") {
        matchScore = match.score;
        const minMatch = await configNumber(admin, "founder_email_min_match", 50);
        if (match.score < minMatch) {
          if (mode === "preview") {
            return jsonResponse({ ...ineligible("low_match"), matchScore: match.score });
          }
          return jsonError("This role isn't a strong match for your resume yet", 422);
        }
      }
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

    const candidateName = profile.full_name ?? "A scout22 candidate";
    const subject = pitchSubject({
      candidateName,
      jobTitle: job.title ?? "your open role",
      headline: profile.headline,
      facts: latestResume?.parsed_json ?? null,
      schoolName: seekerProfile?.school_name ?? null,
    });

    if (mode === "preview") {
      return jsonResponse({
        eligible: remaining > 0,
        reason: remaining > 0 ? null : "weekly_limit_reached",
        matchScore,
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

    // Attach the actual files (unified pitch, 2026-07-28); oversized or
    // broken files fall back to links.
    const resumeAttachment = latestResume?.file_path
      ? await storageAttachment(
        admin,
        "resumes",
        latestResume.file_path,
        attachmentFilename(candidateName, "Resume", latestResume.file_path, "pdf"),
        RESUME_ATTACHMENT_MAX_BYTES,
      )
      : null;
    const videoAttachment = await fetchUrlAttachment(
      pitchVideoURL,
      attachmentFilename(candidateName, "Pitch", pitchVideoURL, "mp4"),
      VIDEO_ATTACHMENT_MAX_BYTES,
    );

    let resumeURL: string | null = null;
    if (latestResume?.file_path && !resumeAttachment) {
      const { data: signed } = await admin.storage
        .from("resumes")
        .createSignedUrl(latestResume.file_path, 60 * 60 * 24 * 7);
      resumeURL = signed?.signedUrl ?? null;
    }

    const { text, html } = buildPitchEmailContent({
      to: contact.email,
      recipientFirstName: contact.first_name,
      candidateName,
      candidateEmail: profile.email ?? user.email ?? null,
      headline: profile.headline,
      jobTitle: job.title ?? "your open role",
      companyName: job.company_name ?? "your company",
      note,
      limitedPitches: true,
      facts: latestResume?.parsed_json ?? null,
      schoolName: seekerProfile?.school_name ?? null,
      compensationRange: seekerProfile?.desired_compensation_range ?? null,
      linkedInURL: seekerProfile?.linkedin_url ?? null,
      githubURL: seekerProfile?.github_url ?? null,
      portfolioURL: seekerProfile?.portfolio_url ?? null,
      instagramUsername: seekerProfile?.instagram_username ?? null,
      tiktokUsername: seekerProfile?.tiktok_username ?? null,
      videoAttached: !!videoAttachment,
      resumeAttached: !!resumeAttachment,
      pitchVideoURL,
      resumeSignedURL: resumeURL,
    });
    const pitchAttachments = [resumeAttachment, videoAttachment].filter(
      (a): a is NonNullable<typeof a> => !!a,
    );

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
      attachments: pitchAttachments,
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

async function configNumber(
  admin: ReturnType<typeof createAdminClient>,
  key: string,
  fallback: number,
): Promise<number> {
  const { data } = await admin
    .from("app_config")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  const parsed = Number(data?.value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

async function configFlag(
  admin: ReturnType<typeof createAdminClient>,
  key: string,
  fallback: boolean,
): Promise<boolean> {
  const { data } = await admin
    .from("app_config")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  if (data?.value == null) return fallback;
  return String(data.value).toLowerCase() !== "false";
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
