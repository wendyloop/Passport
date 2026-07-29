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
  // The candidate's own line (founder compose sheet).
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
  // Founder path: pitches are quota-capped (5/week), which is the honest
  // scarcity line; Easy Apply isn't capped, so it gets the intent line.
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

export function skillsLine(facts: PitchFacts | null | undefined): string | null {
  const skills = (facts?.skills ?? []).map((s) => s.trim()).filter(Boolean).slice(0, 10);
  return skills.length ? skills.join(", ") : null;
}

// Subject hook: the candidate's strongest one-liner credential.
export function pitchHook(params: Pick<PitchEmailParams, "headline" | "facts" | "previousEmployers" | "schoolName">): string | null {
  const headline = clean(params.headline);
  if (headline) return headline.slice(0, 46);
  const currentTitle = clean(params.facts?.current_title);
  const currentCompany = clean(params.facts?.current_company);
  if (currentTitle && currentCompany) return `${currentTitle} @ ${currentCompany}`.slice(0, 46);
  const firstEmployer = clean(params.facts?.employers?.[0]?.company) ?? clean(params.previousEmployers?.[0]);
  if (firstEmployer) return `ex-${firstEmployer}`.slice(0, 46);
  const school = clean(params.schoolName) ?? clean(params.facts?.education?.[0]?.school);
  return school ? school.slice(0, 46) : null;
}

export function pitchSubject(params: Pick<PitchEmailParams, "candidateName" | "jobTitle" | "headline" | "facts" | "previousEmployers" | "schoolName">): string {
  const hook = pitchHook(params);
  return `Applicant for your ${params.jobTitle}: ${params.candidateName}${hook ? ` (${hook})` : ""}`;
}

export function buildPitchEmailContent(params: PitchEmailParams): {
  subject: string;
  text: string;
  html: string;
} {
  // Recruiter-submission shape (copy v4): present the candidate first,
  // product positioning last. Hey, I have an applicant → highlights →
  // their own words → video as the pre-screen → sign-off explains scout22.
  const greeting = clean(params.recipientFirstName) ? `Hi ${clean(params.recipientFirstName)},` : "Hi,";
  const intro = params.limitedPitches
    ? `I have an applicant who picked out your ${params.jobTitle} role at ${params.companyName} — ${params.candidateName}.`
    : `I have an applicant for your ${params.jobTitle} role at ${params.companyName} — ${params.candidateName}.`;
  const note = clean(params.note);
  const headline = clean(params.headline);

  const experience = experienceLines(params.facts, params.previousEmployers).slice(0, 1);
  const education = educationLine(params.facts, params.schoolName);
  const skills = (params.facts?.skills ?? []).map((skill) => skill.trim()).filter(Boolean).slice(0, 5).join(", ");
  const factBullets = [
    experience[0] ?? headline,
    education ? `Education: ${education}` : null,
    skills ? `Skills: ${skills}` : null,
  ].filter((line): line is string => !!line).slice(0, 3);

  // One link only — the strongest available.
  const link = clean(params.linkedInURL)
    ?? clean(params.githubURL)
    ?? clean(params.portfolioURL)
    ?? (clean(params.instagramUsername) ? `https://instagram.com/${clean(params.instagramUsername)}` : null)
    ?? (clean(params.tiktokUsername) ? `https://www.tiktok.com/@${clean(params.tiktokUsername)}` : null);

  const attachmentLine = params.videoAttached
    ? `We have a video intro from ${params.candidateName.split(" ")[0]} — it's attached${params.resumeAttached ? " along with their resume" : ""}. A quick watch gives you a read on them before you ever book a call.`
    : params.resumeAttached
      ? "Their resume is attached."
      : null;
  const videoFallback = !params.videoAttached && clean(params.pitchVideoURL)
    ? `Watch their video intro: ${clean(params.pitchVideoURL)}`
    : null;
  const resumeFallback = !params.resumeAttached && clean(params.resumeSignedURL)
    ? `Resume: ${clean(params.resumeSignedURL)}`
    : null;

  const replyLine = `Reply to this email to reach ${params.candidateName}.`;
  const footerLine =
    "scout22 — where startups get to know applicants as people, not PDFs. Every application comes with a video intro.";

  const text = [
    greeting,
    "",
    intro,
    "",
    "A few highlights:",
    ...factBullets.map((line) => `  - ${line}`),
    link ? `  - ${link}` : null,
    note ? `\nIn their words: "${note}"` : null,
    "",
    attachmentLine,
    videoFallback,
    resumeFallback,
    "",
    replyLine,
    "",
    "— Wendy",
    footerLine,
  ].filter((line): line is string => line !== null).join("\n");

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.55; color: #111827; max-width: 540px;">
      <p>${escapeHtml(greeting)}</p>
      <p>I have an applicant ${params.limitedPitches ? "who picked out" : "for"} your <strong>${escapeHtml(params.jobTitle)}</strong> role at ${escapeHtml(params.companyName)} — <strong>${escapeHtml(params.candidateName)}</strong>.</p>
      <p style="margin-bottom: 2px;"><strong>A few highlights:</strong></p>
      <ul style="margin-top: 2px;">
        ${factBullets.map((line) => `<li>${escapeHtml(line)}</li>`).join("")}
        ${link ? `<li><a href="${escapeHtml(link)}">${escapeHtml(link)}</a></li>` : ""}
      </ul>
      ${note ? `<p style="margin-bottom: 2px;">In their words:</p><blockquote style="margin: 4px 0 12px; padding-left: 12px; border-left: 3px solid #d1d5db; color: #374151;">&ldquo;${escapeHtml(note)}&rdquo;</blockquote>` : ""}
      ${attachmentLine ? `<p>${escapeHtml(attachmentLine)}</p>` : ""}
      ${videoFallback ? `<p><a href="${escapeHtml(clean(params.pitchVideoURL)!)}">▶ Watch their video intro</a></p>` : ""}
      ${resumeFallback ? `<p><a href="${escapeHtml(clean(params.resumeSignedURL)!)}">Open their resume</a></p>` : ""}
      <p>${escapeHtml(replyLine)}</p>
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
