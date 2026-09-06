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

// Plausibility bounds. Employers mistype comp into ATS and board forms —
// PermitFlow entered "130"/"160" (meaning $130K/$160K) into Getro, which
// stored it as 13000 cents = $130/yr, and the carousel rendered "$0k–$0k".
// Anything outside these bounds is a data-entry error, not a real offer.
const MIN_PLAUSIBLE_ANNUAL = 1_000;
const MAX_PLAUSIBLE_ANNUAL = 10_000_000;
const MIN_PLAUSIBLE_HOURLY = 5;
const MAX_PLAUSIBLE_HOURLY = 2_000;

/// Drops implausible structured compensation. Every ingestion path runs
/// through this — the free-text parser below, the board adapters that read
/// structured amounts (Getro cents, Lever salaryRange), and the ingest-jobs
/// write path as a backstop.
///
/// A null endpoint is legitimate ("up to $160,000"), so nulls pass through.
/// But a *present* endpoint that fails the bounds — or an inverted range —
/// poisons its whole pair: when one end of a range is a typo the other
/// almost always is too (130/160 above), so publishing the survivor would
/// be fabricating a number. Annual and hourly pairs are judged separately.
export function sanitizeCompensation(comp: ParsedCompensation): ParsedCompensation {
  const plausible = (value: number | null, lo: number, hi: number): boolean =>
    value === null || (Number.isFinite(value) && value >= lo && value <= hi);

  const keepPair = (min: number | null, max: number | null, lo: number, hi: number): boolean => {
    if (!plausible(min, lo, hi) || !plausible(max, lo, hi)) return false;
    return !(min !== null && max !== null && min > max);
  };

  const annualOK = keepPair(comp.min_annual, comp.max_annual, MIN_PLAUSIBLE_ANNUAL, MAX_PLAUSIBLE_ANNUAL);
  const hourlyOK = keepPair(comp.min_hourly, comp.max_hourly, MIN_PLAUSIBLE_HOURLY, MAX_PLAUSIBLE_HOURLY);

  return {
    min_annual: annualOK ? comp.min_annual : null,
    max_annual: annualOK ? comp.max_annual : null,
    min_hourly: hourlyOK ? comp.min_hourly : null,
    max_hourly: hourlyOK ? comp.max_hourly : null,
  };
}

export function parseCompensation(raw: string | null | undefined): ParsedCompensation {
  if (!raw) return EMPTY;
  const trimmed = raw.trim();
  if (!trimmed) return EMPTY;

  const lower = trimmed.toLowerCase();

  // Bail on non-USD strings. (€/£/CHF/etc.) USD is "$" or "usd" or unmarked.
  if (/[€£¥₹]|eur|gbp|cad|aud|chf|sgd|inr/i.test(trimmed)) return EMPTY;

  const isHourly = /\b(hour|hr|hourly|per hour|\/hr|\/hour)\b/i.test(lower);

  const numbers = extractNumbers(trimmed, isHourly);
  if (numbers.length === 0) return EMPTY;

  const [first, second] = numbers;
  const min = first ?? null;
  const max = second ?? first ?? null;

  if (isHourly) {
    return sanitizeCompensation({
      min_annual: null,
      max_annual: null,
      min_hourly: min,
      max_hourly: max,
    });
  }

  // Annual amounts under 1,000 are suspect (probably typos or hourly);
  // sanitizeCompensation owns that rule for every ingestion path.
  return sanitizeCompensation({
    min_annual: min,
    max_annual: max,
    min_hourly: null,
    max_hourly: null,
  });
}

// Pulls up to two numeric values out of a compensation string, handling
// k-suffix (120K → 120000), commas (120,000), and ranges (- – —).
//
// `isHourly` gates the bare-number heuristic below: "$120 - $160" annual
// means thousands, but "$60 - $80 per hour" means exactly sixty dollars.
// Applying the annual rule to hourly strings produced $60,000/hr.
function extractNumbers(input: string, isHourly = false): number[] {
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
    else if (!isHourly && value < 1000 && !/[.]/.test(numericPart)) {
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

/// ATS employment-type strings -> the three values jobs_employment_type_check
/// accepts. Anything unrecognised becomes null rather than being passed
/// through: the column is CHECK-constrained, and a raw "Full time" or
/// "FullTime" fails the whole INSERT, not just its own row.
///
/// Shared because it has to be. It lived privately inside ingest-jobs, and
/// crawl-companies reproduced that function's row shape without it — every
/// Workday and Ashby posting carrying "Full time" then broke its batch.
export function normalizeEmploymentType(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const normalized = raw.toLowerCase().replace(/[\s\-_]+/g, "");
  if (normalized.startsWith("full")) return "full_time";
  if (normalized.startsWith("part")) return "part_time";
  if (normalized.startsWith("contract") || normalized === "contractor" || normalized === "temp") {
    return "contract";
  }
  return null;
}
