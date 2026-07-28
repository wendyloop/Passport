// Shared Resend email sending. Returns the Resend email id on success so
// callers can correlate bounce/complaint webhooks back to their own records.
//
// A Gmail-SMTP transport was built 2026-07-23 and shelved unused the same
// day (hypothetical explored, not wanted) — kept commented out below; see
// the sendViaGmail block for how to revive it.

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const DEFAULT_FROM = Deno.env.get("JOBTOK_FROM_EMAIL") ?? "Wendy <wendy@tryscout22.com>";
// const GMAIL_SMTP_USER = Deno.env.get("GMAIL_SMTP_USER") ?? "";
// const GMAIL_SMTP_APP_PASSWORD = Deno.env.get("GMAIL_SMTP_APP_PASSWORD") ?? "";

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}

export type EmailAttachment = {
  filename: string;
  // Base64-encoded file body, per Resend's attachments API.
  content: string;
};

export type SendEmailParams = {
  to: string;
  subject: string;
  text: string;
  html: string;
  from?: string;
  replyTo?: string;
  attachments?: EmailAttachment[];
};

export type SendEmailResult = {
  status: "sent" | "failed" | "skipped";
  error: string | null;
  resendId: string | null;
};

// Shelved Gmail transport (see header). To revive: uncomment this block,
// the two GMAIL consts above, the branch at the top of sendEmail, and the
// forceGmailFrom tests in shared_test.ts; set GMAIL_SMTP_USER +
// GMAIL_SMTP_APP_PASSWORD; redeploy the four email-sending functions.
/*
// Gmail forces From to be the authenticated account; keep the caller's
// display name so "Wendy from scout22 <intro@tryscout22.com>" becomes
// "Wendy from scout22 <account@gmail.com>". Exported for tests.
export function forceGmailFrom(from: string, gmailUser: string): string {
  const match = from.match(/^\s*(.*?)\s*<[^>]+>\s*$/);
  const displayName = match?.[1]?.trim() ?? "";
  return displayName ? `${displayName} <${gmailUser}>` : gmailUser;
}

async function sendViaGmail(params: SendEmailParams): Promise<SendEmailResult> {
  try {
    const { SMTPClient } = await import("https://deno.land/x/denomailer@1.6.0/mod.ts");
    const client = new SMTPClient({
      connection: {
        hostname: "smtp.gmail.com",
        port: 465,
        tls: true,
        auth: { username: GMAIL_SMTP_USER, password: GMAIL_SMTP_APP_PASSWORD },
      },
    });
    try {
      await client.send({
        from: forceGmailFrom(params.from ?? DEFAULT_FROM, GMAIL_SMTP_USER),
        to: params.to,
        ...(params.replyTo ? { replyTo: params.replyTo } : {}),
        subject: params.subject,
        content: params.text,
        html: params.html,
      });
    } finally {
      try {
        await client.close();
      } catch {
        // Close failures after a successful send are not delivery failures.
      }
    }
    return { status: "sent", error: null, resendId: null };
  } catch (error) {
    return { status: "failed", error: `Gmail SMTP: ${String(error)}`, resendId: null };
  }
}
*/

export async function sendEmail(params: SendEmailParams): Promise<SendEmailResult> {
  // if (GMAIL_SMTP_USER && GMAIL_SMTP_APP_PASSWORD) {
  // return await sendViaGmail(params);
  // }

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
      ...(params.attachments?.length ? { attachments: params.attachments } : {}),
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
