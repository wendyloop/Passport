// The unified candidate pitch email (product decision 2026-07-28): Easy
// Apply and Pitch-the-founder send the SAME thing — the candidate's video
// and resume attached, one founder-useful format. Only the recipient
// differs: a job's listed application email wins; otherwise the founder
// contact pipeline finds one. Content building is pure so shared_test.ts
// covers it; retry-application-emails reuses it from snapshot columns.

import { escapeHtml, sendEmail, type EmailAttachment, type SendEmailResult } from "./email.ts";

export type PitchFacts = {
  years_experience?: string;
  current_title?: string;
  current_company?: string;
  employers?: Array<{
    company?: string;
    title?: string;
    start_date?: string;
    end_date?: string;
    is_current?: boolean;
  }>;
  education?: Array<{
    school?: string;
    degree?: string;
    field_of_study?: string;
    graduation_year?: string;
  }>;
  skills?: string[];
};

export type PitchEmailParams = {
  to: string;
  // Founder path knows a first name; application inboxes don't.
  recipientFirstName?: string | null;
  candidateName: string;
  candidateEmail?: string | null;
  headline?: string | null;
  jobTitle: string;
  companyName: string;
  // The candidate's own line (founder compose sheet). Accepted for caller
  // compatibility but NOT rendered since copy v5 (2026-07-30).
  note?: string | null;
  // Parsed resume; fall back to profile fields when absent.
  facts?: PitchFacts | null;
  schoolName?: string | null;
  previousEmployers?: string[];
  compensationRange?: string | null;
  linkedInURL?: string | null;
  githubURL?: string | null;
  portfolioURL?: string | null;
  instagramUsername?: string | null;
  tiktokUsername?: string | null;
  // Formerly switched the intro line for the founder path; both paths read
  // the same since copy v6. Accepted for caller compatibility, unused.
  limitedPitches?: boolean;
  videoAttached: boolean;
  resumeAttached: boolean;
  // Link fallbacks for whatever couldn't be attached.
  pitchVideoURL?: string | null;
  resumeSignedURL?: string | null;
};

function clean(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

// Top-3 experience lines: "SWE Intern · Stripe (2025-06 – now)".
export function experienceLines(facts: PitchFacts | null | undefined, fallbackEmployers?: string[]): string[] {
  const parsed = (facts?.employers ?? [])
    .map((job) => {
      const role = [clean(job.title), clean(job.company)].filter(Boolean).join(" · ");
      if (!role) return null;
      const start = clean(job.start_date);
      const end = job.is_current ? "now" : clean(job.end_date);
      const dates = start || end ? ` (${start ?? "?"} – ${end ?? "?"})` : "";
      return `${role}${dates}`;
    })
    .filter((line): line is string => !!line)
    .slice(0, 3);
  if (parsed.length) return parsed;
  return (fallbackEmployers ?? []).filter(Boolean).slice(0, 3);
}

export function educationLine(facts: PitchFacts | null | undefined, fallbackSchool?: string | null): string | null {
  const entry = (facts?.education ?? []).find((e) => clean(e.school));
  if (entry) {
    const degree = [clean(entry.degree), clean(entry.field_of_study)].filter(Boolean).join(" ");
    const year = clean(entry.graduation_year);
    return [degree || null, clean(entry.school), year ? `(${year})` : null].filter(Boolean).join(" ");
  }
  return clean(fallbackSchool);
}

// Copy v6 (2026-07-30): name only — no credential hook/bio in the subject.
export function pitchSubject(params: Pick<PitchEmailParams, "candidateName" | "jobTitle">): string {
  return `Applicant for your ${params.jobTitle}: ${params.candidateName}`;
}

export function buildPitchEmailContent(params: PitchEmailParams): {
  subject: string;
  text: string;
  html: string;
} {
  // Recruiter-submission shape (copy v6, 2026-07-30): present the candidate,
  // highlights, video as the pre-screen, sign-off explains scout22. No
  // skills list, no quoted note/bio, no reply-to-reach line (Wendy is the
  // middleman pre-launch), and one intro line for both paths — the
  // "who picked out" founder variant read weird.
  const greeting = clean(params.recipientFirstName) ? `Hi ${clean(params.recipientFirstName)},` : "Hi,";
  const intro = `I have an applicant for your ${params.jobTitle} role at ${params.companyName} — ${params.candidateName}.`;
  const headline = clean(params.headline);

  const experience = experienceLines(params.facts, params.previousEmployers).slice(0, 1);
  const education = educationLine(params.facts, params.schoolName);
  const factBullets = [
    experience[0] ?? headline,
    education ? `Education: ${education}` : null,
  ].filter((line): line is string => !!line);

  // One link only — the strongest available.
  const link = clean(params.linkedInURL)
    ?? clean(params.githubURL)
    ?? clean(params.portfolioURL)
    ?? (clean(params.instagramUsername) ? `https://instagram.com/${clean(params.instagramUsername)}` : null)
    ?? (clean(params.tiktokUsername) ? `https://www.tiktok.com/@${clean(params.tiktokUsername)}` : null);

  const attachmentLine = params.videoAttached
    ? `We have a video intro from ${params.candidateName.split(" ")[0]} — it's attached${params.resumeAttached ? " along with their resume" : ""}. Two minutes and you'll know if you want to meet them.`
    : params.resumeAttached
      ? "Their resume is attached."
      : null;
  const videoFallback = !params.videoAttached && clean(params.pitchVideoURL)
    ? `Watch their video intro: ${clean(params.pitchVideoURL)}`
    : null;
  const resumeFallback = !params.resumeAttached && clean(params.resumeSignedURL)
    ? `Resume: ${clean(params.resumeSignedURL)}`
    : null;

  // The video became optional on 2026-08-22, so the footer can no longer
  // claim every application has one. Applications that DO carry a video
  // keep the stronger line — that is the differentiator worth stating.
  const footerLine = params.videoAttached || clean(params.pitchVideoURL)
    ? "scout22 — applications come with a video intro, so you meet the person, not just the resume."
    : "scout22 — meet the person, not just the resume.";

  const text = [
    greeting,
    "",
    intro,
    "",
    "A few highlights:",
    ...factBullets.map((line) => `  - ${line}`),
    link ? `  - ${link}` : null,
    "",
    attachmentLine,
    videoFallback,
    resumeFallback,
    "",
    "— Wendy",
    footerLine,
  ].filter((line): line is string => line !== null).join("\n");

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.55; color: #111827; max-width: 540px;">
      <p>${escapeHtml(greeting)}</p>
      <p>I have an applicant for your <strong>${escapeHtml(params.jobTitle)}</strong> role at ${escapeHtml(params.companyName)} — <strong>${escapeHtml(params.candidateName)}</strong>.</p>
      <p style="margin-bottom: 2px;"><strong>A few highlights:</strong></p>
      <ul style="margin-top: 2px;">
        ${factBullets.map((line) => `<li>${escapeHtml(line)}</li>`).join("")}
        ${link ? `<li><a href="${escapeHtml(link)}">${escapeHtml(link)}</a></li>` : ""}
      </ul>
      ${attachmentLine ? `<p>${escapeHtml(attachmentLine)}</p>` : ""}
      ${videoFallback ? `<p><a href="${escapeHtml(clean(params.pitchVideoURL)!)}">▶ Watch their video intro</a></p>` : ""}
      ${resumeFallback ? `<p><a href="${escapeHtml(clean(params.resumeSignedURL)!)}">Open their resume</a></p>` : ""}
      <p style="margin-bottom: 0;">— Wendy</p>
      <p style="color: #6b7280; font-size: 12px; margin-top: 4px;">${escapeHtml(footerLine)}</p>
    </div>
  `;

  return { subject: pitchSubject(params), text, html };
}

// FIRST-100-USERS: pre-launch, replies on EVERY pitch path route to one
// monitored human mailbox (same secret the founder path uses) so Wendy
// sees each response. Unset FOUNDER_REPLY_TO_EMAIL to restore direct
// reply-to-candidate at scale.
const REPLY_TO_OVERRIDE = Deno.env.get("FOUNDER_REPLY_TO_EMAIL") ?? "";

export async function sendPitchEmail(
  params: PitchEmailParams,
  options?: { from?: string; replyTo?: string; attachments?: EmailAttachment[] },
): Promise<SendEmailResult> {
  const content = buildPitchEmailContent(params);
  return await sendEmail({
    to: params.to,
    subject: content.subject,
    text: content.text,
    html: content.html,
    from: options?.from,
    replyTo: options?.replyTo ?? (REPLY_TO_OVERRIDE || (clean(params.candidateEmail) ?? undefined)),
    attachments: options?.attachments,
  });
}
