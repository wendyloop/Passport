// Founder/contact helpers shared by all three extraction tiers
// (generate-carousel JD extraction, enrich-descriptions posting emails,
// enrich-company-contacts website scrape).

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

export const MAX_CONTACTS_PER_COMPANY = 3;

export type FounderCandidate = {
  full_name: string;
  role_title: string | null;
  confidence: number | null;
};

export type ContactSource =
  | "llm_job_listing"
  | "llm_scrape"
  | "posting_email"
  | "manual"
  // Founders named on a YC company page (WaaS ingest, migration 20260801120000).
  | "yc_directory";

const HONORIFICS = new Set(["dr", "mr", "mrs", "ms", "prof"]);

// "Dr. José Álvarez-Smith" + "www.Acme.io" → "jose@acme.io".
// Returns null when no usable first name or domain survives normalization.
export function guessFounderEmail(fullName: string, domain: string): string | null {
  const cleanDomain = normalizeDomain(domain);
  if (!cleanDomain) return null;

  const first = fullName
    .trim()
    .split(/\s+/)
    .map((token) =>
      token
        .normalize("NFD")
        .replace(/[^\p{L}]/gu, "")
        .toLowerCase()
    )
    .find((token) => token && !HONORIFICS.has(token)) ?? "";
  if (!first) return null;

  return `${first}@${cleanDomain}`;
}

export function normalizeDomain(raw: string): string | null {
  const trimmed = raw.trim().toLowerCase();
  if (!trimmed) return null;
  let host = trimmed;
  try {
    host = new URL(trimmed.startsWith("http") ? trimmed : `https://${trimmed}`).hostname;
  } catch {
    // keep trimmed as-is
  }
  host = host.replace(/^www\./, "");
  return host.includes(".") ? host : null;
}

export function firstNameOf(fullName: string): string | null {
  const first = fullName.trim().split(/\s+/)[0] ?? "";
  return first || null;
}

// Insert contacts for a company, capped at MAX_CONTACTS_PER_COMPANY total.
// on-conflict-do-nothing on (company_id, email): a fresh guess never
// overwrites an existing row, so bounced/verified statuses are preserved.
// Founders whose email guess fails are dropped — the send path can't use
// them, and null emails would bypass the partial unique index and duplicate
// on regeneration.
export async function insertFounderContacts(
  admin: SupabaseClient,
  params: {
    companyId: string;
    domain: string | null;
    founders: FounderCandidate[];
    source: ContactSource;
  },
): Promise<number> {
  if (!params.domain || params.founders.length === 0) return 0;

  const { count: existingCount, error: countError } = await admin
    .from("company_contacts")
    .select("id", { count: "exact", head: true })
    .eq("company_id", params.companyId);
  if (countError) throw new Error(`contact count failed: ${countError.message}`);

  const room = MAX_CONTACTS_PER_COMPANY - (existingCount ?? 0);
  if (room <= 0) return 0;

  const rows = params.founders
    .map((f) => ({
      company_id: params.companyId,
      full_name: f.full_name.trim() || null,
      first_name: firstNameOf(f.full_name),
      role_title: f.role_title?.trim() || null,
      source: params.source,
      email: guessFounderEmail(f.full_name, params.domain as string),
      email_status: "guessed",
      confidence: f.confidence,
      scraped_at: new Date().toISOString(),
    }))
    .filter((row) => row.email !== null)
    .slice(0, room);
  if (rows.length === 0) return 0;

  const { error } = await admin
    .from("company_contacts")
    .upsert(rows, { onConflict: "company_id,email", ignoreDuplicates: true });
  if (error) throw new Error(`contact upsert failed: ${error.message}`);
  return rows.length;
}

// Record a verified contact email found on the posting itself (tier 2).
export async function insertPostingEmailContact(
  admin: SupabaseClient,
  companyId: string,
  email: string,
): Promise<void> {
  const { error } = await admin
    .from("company_contacts")
    .upsert(
      [{
        company_id: companyId,
        source: "posting_email",
        email: email.toLowerCase(),
        email_status: "verified",
        scraped_at: new Date().toISOString(),
      }],
      { onConflict: "company_id,email", ignoreDuplicates: true },
    );
  if (error) throw new Error(`posting-email contact upsert failed: ${error.message}`);
}
