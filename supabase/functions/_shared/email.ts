// Shared Resend email sending. Returns the Resend email id on success so
// callers can correlate bounce/complaint webhooks back to their own records.

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const DEFAULT_FROM = Deno.env.get("JOBTOK_FROM_EMAIL") ?? "JobTok <applications@jobtok.app>";

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}

export type SendEmailParams = {
  to: string;
  subject: string;
  text: string;
  html: string;
  from?: string;
  replyTo?: string;
};

export type SendEmailResult = {
  status: "sent" | "failed" | "skipped";
  error: string | null;
  resendId: string | null;
};

export async function sendEmail(params: SendEmailParams): Promise<SendEmailResult> {
  if (!RESEND_API_KEY) {
    return {
      status: "skipped",
      error: "Missing RESEND_API_KEY in Supabase Edge Function secrets.",
      resendId: null,
    };
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: params.from ?? DEFAULT_FROM,
      to: [params.to],
      subject: params.subject,
      text: params.text,
      html: params.html,
      ...(params.replyTo ? { reply_to: [params.replyTo] } : {}),
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    return {
      status: "failed",
      error: body || `Resend request failed with status ${response.status}.`,
      resendId: null,
    };
  }

  const payload = await response.json().catch(() => ({})) as { id?: string };
  return { status: "sent", error: null, resendId: payload.id ?? null };
}
