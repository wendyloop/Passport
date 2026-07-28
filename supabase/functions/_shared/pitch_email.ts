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
  return `${params.candidateName} — 60-sec pitch for ${params.jobTitle}${hook ? ` (${hook})` : ""}`;
}

export function buildPitchEmailContent(params: PitchEmailParams): {
  subject: string;
  text: string;
  html: string;
} {
  const greeting = clean(params.recipientFirstName) ? `Hi ${clean(params.recipientFirstName)},` : "Hi,";
  const intro = `${params.candidateName} wants your ${params.jobTitle} role at ${params.companyName} — here's their 60-second video pitch.`;
  // Three jobs in one paragraph: what this email is, why this candidate
  // means it, and why video-first beats the ATS pile.
  const whyWatch = params.limitedPitches
    ? `I'm Wendy from scout22 — candidates here pitch startups on video instead of cover letters, and they only get five pitches a week. ${params.candidateName} chose to spend one on ${params.companyName}: that's genuine intent, not an ATS blast. Sixty seconds of them talking tells you more than any resume screen.`
    : `I'm Wendy from scout22 — candidates here apply with a 60-second video instead of a cover letter. ${params.candidateName} picked ${params.companyName} out and recorded this for you: that's genuine interest, not an ATS blast. Sixty seconds of them talking tells you more than any resume screen.`;
  const note = clean(params.note);
  const headline = clean(params.headline);

  // Three lines max — the video carries the pitch, this is just the floor.
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

  const attachmentLine = params.videoAttached && params.resumeAttached
    ? "Their video and resume are attached."
    : params.resumeAttached
      ? "Their resume is attached."
      : params.videoAttached
        ? "Their video is attached."
        : null;
  const videoFallback = !params.videoAttached && clean(params.pitchVideoURL)
    ? `Watch their pitch: ${clean(params.pitchVideoURL)}`
    : null;
  const resumeFallback = !params.resumeAttached && clean(params.resumeSignedURL)
    ? `Resume: ${clean(params.resumeSignedURL)}`
    : null;

  const replyLine = `Reply to this email and it goes straight to ${params.candidateName}${clean(params.candidateEmail) ? ` (${clean(params.candidateEmail)})` : ""}.`;

  const text = [
    greeting,
    "",
    intro,
    note ? `\nIn their words: "${note}"` : null,
    "",
    whyWatch,
    "",
    `${params.candidateName} in ${factBullets.length === 1 ? "one line" : `${factBullets.length} lines`}:`,
    ...factBullets.map((line) => `  - ${line}`),
    link ? `  - ${link}` : null,
    "",
    attachmentLine,
    videoFallback,
    resumeFallback,
    "",
    replyLine,
    `— Sent via scout22 on ${params.candidateName}'s behalf`,
  ].filter((line): line is string => line !== null).join("\n");

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.55; color: #111827; max-width: 540px;">
      <p>${escapeHtml(greeting)}</p>
      <p><strong>${escapeHtml(params.candidateName)}</strong> wants your <strong>${escapeHtml(params.jobTitle)}</strong> role at ${escapeHtml(params.companyName)} — here's their 60-second video pitch.</p>
      ${note ? `<blockquote style="margin: 10px 0; padding-left: 12px; border-left: 3px solid #d1d5db; color: #374151;">&ldquo;${escapeHtml(note)}&rdquo;</blockquote>` : ""}
      <p style="color: #374151;">${escapeHtml(whyWatch)}</p>
      <p style="margin-bottom: 2px;"><strong>${escapeHtml(params.candidateName)} in ${factBullets.length === 1 ? "one line" : `${factBullets.length} lines`}:</strong></p>
      <ul style="margin-top: 2px;">
        ${factBullets.map((line) => `<li>${escapeHtml(line)}</li>`).join("")}
        ${link ? `<li><a href="${escapeHtml(link)}">${escapeHtml(link)}</a></li>` : ""}
      </ul>
      ${attachmentLine ? `<p><strong>${escapeHtml(attachmentLine)}</strong></p>` : ""}
      ${videoFallback ? `<p><a href="${escapeHtml(clean(params.pitchVideoURL)!)}">▶ Watch their 60-second pitch</a></p>` : ""}
      ${resumeFallback ? `<p><a href="${escapeHtml(clean(params.resumeSignedURL)!)}">Open their resume</a></p>` : ""}
      <p>${escapeHtml(replyLine)}</p>
      <p style="color: #6b7280; font-size: 12px;">Sent via scout22 on ${escapeHtml(params.candidateName)}'s behalf.</p>
    </div>
  `;

  return { subject: pitchSubject(params), text, html };
}

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
    replyTo: options?.replyTo ?? clean(params.candidateEmail) ?? undefined,
    attachments: options?.attachments,
  });
}
