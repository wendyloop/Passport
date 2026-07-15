// The employer-facing application email, shared by apply-to-job (first
// attempt) and retry-application-emails (AUDIT P1-8 retry pass). Content
// building is pure so it can be unit-tested.

import { escapeHtml, sendEmail, type SendEmailResult } from "./email.ts";

export type ApplicationEmailParams = {
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
};

export function buildApplicationEmailContent(params: ApplicationEmailParams): {
  subject: string;
  text: string;
  html: string;
} {
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

  return {
    subject: `New applicant: ${params.candidateName} for ${params.jobTitle}`,
    text,
    html,
  };
}

export async function sendEmployerApplicationEmail(
  params: ApplicationEmailParams,
): Promise<SendEmailResult> {
  const content = buildApplicationEmailContent(params);
  return await sendEmail({
    to: params.to,
    subject: content.subject,
    text: content.text,
    html: content.html,
  });
}
