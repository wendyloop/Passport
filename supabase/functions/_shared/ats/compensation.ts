// Best-effort parser: free-text compensation → structured min/max in USD.
//
// Per spec & user note: ALWAYS keep the raw string (compensation_text). Only
// populate the structured min/max fields when we can do so confidently —
// otherwise leave them null. Never fabricate.
//
// Handles common ATS shapes:
//   "$120,000 - $160,000"
//   "USD 120K - 160K"
//   "$60/hour"
//   "$60–$80 per hour"
//   "120000 to 160000 annually"
//
// Currency: USD-only in v1. Non-USD strings keep compensation_text but leave
// min/max null. (Multi-currency parsing belongs in Phase 2.)

import type { ParsedCompensation } from "./models.ts";

const EMPTY: ParsedCompensation = {
  min_annual: null,
  max_annual: null,
  min_hourly: null,
  max_hourly: null,
};

export function parseCompensation(raw: string | null | undefined): ParsedCompensation {
  if (!raw) return EMPTY;
  const trimmed = raw.trim();
  if (!trimmed) return EMPTY;

  const lower = trimmed.toLowerCase();

  // Bail on non-USD strings. (€/£/CHF/etc.) USD is "$" or "usd" or unmarked.
  if (/[€£¥₹]|eur|gbp|cad|aud|chf|sgd|inr/i.test(trimmed)) return EMPTY;

  const isHourly = /\b(hour|hr|hourly|per hour|\/hr|\/hour)\b/i.test(lower);

  const numbers = extractNumbers(trimmed);
  if (numbers.length === 0) return EMPTY;

  const [first, second] = numbers;
  const min = first ?? null;
  const max = second ?? first ?? null;

  if (isHourly) {
    return {
      min_annual: null,
      max_annual: null,
      min_hourly: min,
      max_hourly: max,
    };
  }

  // Annual amounts under 1,000 are suspect (probably typos or hourly).
  if (min !== null && min < 1000) return EMPTY;

  return {
    min_annual: min,
    max_annual: max,
    min_hourly: null,
    max_hourly: null,
  };
}

// Pulls up to two numeric values out of a compensation string, handling
// k-suffix (120K → 120000), commas (120,000), and ranges (- – —).
function extractNumbers(input: string): number[] {
  const pattern = /(\d[\d,]*\.?\d*)\s*([kKmM])?/g;
  const out: number[] = [];
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(input)) !== null) {
    const numericPart = match[1].replace(/,/g, "");
    const value = Number.parseFloat(numericPart);
    if (!Number.isFinite(value)) continue;

    const suffix = match[2]?.toLowerCase();
    let scaled = value;
    if (suffix === "k") scaled = value * 1_000;
    else if (suffix === "m") scaled = value * 1_000_000;
    else if (value < 1000 && !/[.]/.test(numericPart)) {
      // Bare numbers under 1000 with no decimal — interpret as K (e.g. "120 - 160")
      scaled = value * 1_000;
    }

    out.push(Math.round(scaled));
    if (out.length === 2) break;
  }
  return out;
}

const EMAIL_REGEX = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i;

export function extractFirstEmail(text: string | null | undefined): string | null {
  if (!text) return null;
  const match = text.match(EMAIL_REGEX);
  return match ? match[0].toLowerCase() : null;
}

// Strip HTML tags from a JD body. ATS APIs vary: Greenhouse returns HTML;
// Lever returns plain text. We always normalize to plain text for storage
// in `jobs.description` and keep the original in `jobs.description_raw`.
export function stripHTML(html: string | null | undefined): string | null {
  if (!html) return null;
  const text = html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|h\d)>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\r\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]+\n/g, "\n")
    .trim();
  return text || null;
}

// Stable SHA-256 hash over the meaningful fields, so we can detect "did the
// ATS payload actually change" without diffing every column.
export async function computeContentHash(parts: Array<string | number | null>): Promise<string> {
  const data = new TextEncoder().encode(parts.map((p) => p ?? "").join("|"));
  const buffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function sanitizeISODate(value: string | null | undefined): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString().replace(/\.\d+Z$/, "Z");
}
