// Attachment builders for the unified pitch email: founders get the actual
// resume PDF and video file, not links. Size-guarded — Gmail hard-bounces
// messages over ~25MB and base64 inflates by a third, so oversized files
// fall back to links (callers keep the URL lines when an attachment comes
// back null). All fetchers fail-open: a broken attachment must never block
// the send.

import type { EmailAttachment } from "./email.ts";

export const VIDEO_ATTACHMENT_MAX_BYTES = 14 * 1024 * 1024;
export const RESUME_ATTACHMENT_MAX_BYTES = 5 * 1024 * 1024;

// "Wendy Shi" + "resume.pdf" → "Wendy_Shi_Resume.pdf". Pure, tested.
export function attachmentFilename(
  candidateName: string,
  kind: "Resume" | "Pitch",
  sourcePath: string,
  fallbackExt: string,
): string {
  const safe = candidateName
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 40) || "Candidate";
  const rawExt = sourcePath.split("?")[0].split("#")[0].split(".").pop() ?? "";
  const ext = /^[A-Za-z0-9]{2,5}$/.test(rawExt) ? rawExt.toLowerCase() : fallbackExt;
  return `${safe}_${kind}.${ext}`;
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

// Public storage URLs (pitch videos).
export async function fetchUrlAttachment(
  url: string,
  filename: string,
  maxBytes: number,
): Promise<EmailAttachment | null> {
  try {
    const response = await fetch(url);
    if (!response.ok) return null;
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > maxBytes) return null;
    return { filename, content: toBase64(bytes) };
  } catch {
    return null;
  }
}

type StorageClient = {
  storage: {
    from(bucket: string): {
      download(path: string): Promise<{ data: Blob | null; error: unknown }>;
    };
  };
};

// Private buckets (resumes) via the service-role client.
export async function storageAttachment(
  admin: StorageClient,
  bucket: string,
  path: string,
  filename: string,
  maxBytes: number,
): Promise<EmailAttachment | null> {
  try {
    const { data, error } = await admin.storage.from(bucket).download(path);
    if (error || !data) return null;
    const bytes = new Uint8Array(await data.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > maxBytes) return null;
    return { filename, content: toBase64(bytes) };
  } catch {
    return null;
  }
}
