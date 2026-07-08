// Resend delivery-event webhook (Svix-signed). Deployed with JWT
// verification off — authenticity comes from the Svix signature, verified
// inline with WebCrypto (no dependency).
//
// Bounces and complaints flow back into the contact directory:
//   email.bounced    → outreach row 'bounced',    contact 'bounced'
//   email.complained → outreach row 'complained', contact 'suppressed'
//   email.delivered  → contact guessed → verified (a guessed address that
//                      hard-delivers is a deliverability signal; catch-all
//                      domains can false-positive, which is why 'verified'
//                      means deliverable, not identity-confirmed)
//
// Events for emails we didn't send through founder outreach (the same
// Resend account sends application emails) are acknowledged and ignored.

import { createAdminClient } from "../_shared/client.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";

const WEBHOOK_SECRET = Deno.env.get("RESEND_WEBHOOK_SECRET") ?? "";
const TIMESTAMP_TOLERANCE_S = 5 * 60;

type ResendEvent = {
  type?: string;
  data?: { email_id?: string };
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonError("Method not allowed", 405);
  // Fail closed, same rule as the cron secret.
  if (!WEBHOOK_SECRET) return jsonError("unauthorized", 401);

  const rawBody = await request.text();
  const verified = await verifySvixSignature(request.headers, rawBody, WEBHOOK_SECRET);
  if (!verified) return jsonError("invalid signature", 401);

  const event = safeParse(rawBody);
  const emailId = event?.data?.email_id;
  const type = event?.type ?? "";

  if (!emailId || !["email.bounced", "email.complained", "email.delivered"].includes(type)) {
    return jsonResponse({ handled: false });
  }

  const admin = createAdminClient();
  const { data: outreach } = await admin
    .from("founder_outreach_messages")
    .select("id, contact_id")
    .eq("resend_email_id", emailId)
    .maybeSingle();

  // Not one of ours (application/outreach emails share the Resend account).
  if (!outreach) return jsonResponse({ handled: false });

  if (type === "email.bounced" || type === "email.complained") {
    const outreachStatus = type === "email.bounced" ? "bounced" : "complained";
    const contactStatus = type === "email.bounced" ? "bounced" : "suppressed";

    await admin
      .from("founder_outreach_messages")
      .update({ delivery_status: outreachStatus })
      .eq("id", outreach.id);

    if (outreach.contact_id) {
      await admin
        .from("company_contacts")
        .update({ email_status: contactStatus })
        .eq("id", outreach.contact_id);
    }
  } else if (type === "email.delivered" && outreach.contact_id) {
    // Promote only from 'guessed' — never resurrect a bounced/suppressed row.
    await admin
      .from("company_contacts")
      .update({ email_status: "verified" })
      .eq("id", outreach.contact_id)
      .eq("email_status", "guessed");
  }

  console.log(JSON.stringify({ event: "resend_webhook", type, outreach_id: outreach.id }));
  return jsonResponse({ handled: true });
});

function safeParse(raw: string): ResendEvent | null {
  try {
    return JSON.parse(raw) as ResendEvent;
  } catch {
    return null;
  }
}

// Svix scheme: HMAC-SHA256 over "{id}.{timestamp}.{body}" with the
// base64-decoded portion of the whsec_ secret; signature header carries
// space-separated "v1,<base64>" candidates.
async function verifySvixSignature(
  headers: Headers,
  body: string,
  secret: string,
): Promise<boolean> {
  const id = headers.get("svix-id");
  const timestamp = headers.get("svix-timestamp");
  const signatureHeader = headers.get("svix-signature");
  if (!id || !timestamp || !signatureHeader) return false;

  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(Date.now() / 1000 - ts) > TIMESTAMP_TOLERANCE_S) {
    return false;
  }

  const secretB64 = secret.startsWith("whsec_") ? secret.slice(6) : secret;
  const keyBytes = decodeBase64(secretB64);
  if (!keyBytes) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signedContent = new TextEncoder().encode(`${id}.${timestamp}.${body}`);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, signedContent));
  const expected = btoa(String.fromCharCode(...mac));

  return signatureHeader
    .split(" ")
    .map((candidate) => candidate.split(",")[1] ?? "")
    .some((candidate) => timingSafeEqual(candidate, expected));
}

function decodeBase64(b64: string): Uint8Array<ArrayBuffer> | null {
  try {
    return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
