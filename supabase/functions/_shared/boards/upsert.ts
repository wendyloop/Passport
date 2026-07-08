// Company upsert + fund linking for board ingestion.
//
// Dedupe priority:
//   1. domain — when present, the strongest signal that two boards are
//      pointing at the same company (Stripe in Accel and in Sequoia).
//   2. (ats_type, ats_token) — guaranteed unique per company; resolves the
//      no-domain Getro case when the apply URL is on a supported ATS.
//   3. (source_board, external_id) — same board re-crawl, same org id.
//
// Returns the resolved companies.id so the caller can build the job-upsert
// batch with a real FK.

import type { FundRow, ATSType } from "../ats/models.ts";
import type { BoardCompany } from "./types.ts";

export type CompanyResolution = {
  company_id: string;
  inserted: boolean;
};

type AdminClient = {
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
};

export async function upsertCompanyAndLink(
  admin: AdminClient,
  fund: FundRow,
  company: BoardCompany,
  ats: { ats_type: ATSType; ats_token: string } | null,
): Promise<CompanyResolution> {
  const nowISO = new Date().toISOString();

  let existingId: string | null = null;

  if (company.domain) {
    const { data } = await admin
      .from("companies")
      .select("id")
      .eq("domain", company.domain)
      .maybeSingle();
    if (data?.id) existingId = data.id;
  }

  if (!existingId && ats) {
    const { data } = await admin
      .from("companies")
      .select("id")
      .eq("ats_type", ats.ats_type)
      .eq("ats_token", ats.ats_token)
      .maybeSingle();
    if (data?.id) existingId = data.id;
  }

  if (!existingId) {
    const { data } = await admin
      .from("companies")
      .select("id")
      .eq("source_board", fund.slug)
      .eq("external_id", company.board_external_id)
      .maybeSingle();
    if (data?.id) existingId = data.id;
  }

  let inserted = false;

  if (existingId) {
    const { error } = await admin
      .from("companies")
      .update({
        name: company.name,
        domain: company.domain ?? undefined,
        logo_url: company.logo_url,
        // Don't clobber a resolved ats_type with null — keep it.
        ats_type: ats?.ats_type ?? undefined,
        ats_token: ats?.ats_token ?? undefined,
        stage: company.stage,
        headcount: company.headcount,
        industry: company.industry,
        source_board: fund.slug,
        external_id: company.board_external_id,
        last_seen_at: nowISO,
      })
      .eq("id", existingId);
    if (error) throw new Error(`update companies failed: ${error.message}`);
  } else {
    const { data, error } = await admin
      .from("companies")
      .insert({
        name: company.name,
        domain: company.domain,
        logo_url: company.logo_url,
        ats_type: ats?.ats_type ?? null,
        ats_token: ats?.ats_token ?? null,
        stage: company.stage,
        headcount: company.headcount,
        industry: company.industry,
        source_board: fund.slug,
        external_id: company.board_external_id,
        first_seen_at: nowISO,
        last_seen_at: nowISO,
      })
      .select("id")
      .single();
    if (error || !data?.id) {
      throw new Error(`insert companies failed: ${error?.message ?? "no id returned"}`);
    }
    existingId = data.id;
    inserted = true;
  }

  const { error: linkError } = await admin
    .from("company_funds")
    .upsert({ company_id: existingId, fund_id: fund.id }, { ignoreDuplicates: true });
  if (linkError) throw new Error(`link company_funds failed: ${linkError.message}`);

  return { company_id: existingId!, inserted };
}
