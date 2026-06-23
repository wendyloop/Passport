// Weekly Pitch discovery. For every fund with a known platform crawler:
//   1. Hit the fund's portfolio job board.
//   2. Dedupe companies by (domain) → (ats_type, ats_token) → name.
//   3. Upsert into companies; link via company_funds; bump last_seen_at.
//
// Companies that fail to resolve to a supported ATS are still stored with
// ats_type = null so we can re-resolve on the next crawl as their roster
// evolves. They are skipped by sync-jobs until they get coordinates.
//
// Triggered by pg_cron weekly on Monday 06:00 UTC. Also callable manually.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { getCrawler } from "../_shared/boards/index.ts";
import type { DiscoveredCompany } from "../_shared/boards/models.ts";
import type { FundRow } from "../_shared/ats/models.ts";

const PITCH_CRON_SECRET = Deno.env.get("PITCH_CRON_SECRET") ?? "";

type RequestBody = {
  // Optional. Restrict to a single fund slug (manual replay / debugging).
  fund_slug?: string;
};

type FundOutcome = {
  fund_slug: string;
  fund_name: string;
  discovered: number;
  inserted: number;
  updated: number;
  linked: number;
  unresolved_ats: number;
  error: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const providedSecret = request.headers.get("x-pitch-cron-secret");
  if (PITCH_CRON_SECRET && providedSecret !== PITCH_CRON_SECRET) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const body: RequestBody = await request.json().catch(() => ({}));
  const admin = createAdminClient();

  const query = admin
    .from("funds")
    .select("id, name, slug, board_url, platform")
    .not("platform", "is", null);
  if (body.fund_slug) query.eq("slug", body.fund_slug);

  const { data: funds, error: fundsError } = await query;
  if (fundsError) {
    return jsonError(`Failed to load funds: ${fundsError.message}`);
  }

  const outcomes: FundOutcome[] = [];
  const startedAt = Date.now();

  for (const fund of (funds ?? []) as FundRow[]) {
    const outcome = await crawlFund(admin, fund);
    outcomes.push(outcome);
    console.log(JSON.stringify({ event: "pitch_crawl_fund", ...outcome }));
  }

  const summary = {
    event: "pitch_crawl_run",
    fund_count: outcomes.length,
    discovered: sum(outcomes, (o) => o.discovered),
    inserted: sum(outcomes, (o) => o.inserted),
    updated: sum(outcomes, (o) => o.updated),
    linked: sum(outcomes, (o) => o.linked),
    unresolved_ats: sum(outcomes, (o) => o.unresolved_ats),
    errored: outcomes.filter((o) => o.error).length,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));

  return new Response(JSON.stringify({ summary, outcomes }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

async function crawlFund(
  admin: ReturnType<typeof createAdminClient>,
  fund: FundRow,
): Promise<FundOutcome> {
  const base: FundOutcome = {
    fund_slug: fund.slug,
    fund_name: fund.name,
    discovered: 0,
    inserted: 0,
    updated: 0,
    linked: 0,
    unresolved_ats: 0,
    error: null,
  };

  const crawler = getCrawler(fund.platform);
  if (!crawler) {
    return { ...base, error: `no crawler registered for platform "${fund.platform}"` };
  }

  let companies: DiscoveredCompany[];
  try {
    companies = await crawler(fund);
  } catch (error) {
    return { ...base, error: (error as Error).message };
  }

  let inserted = 0;
  let updated = 0;
  let linked = 0;
  let unresolvedATS = 0;

  for (const company of companies) {
    if (!company.ats_type) unresolvedATS += 1;
    try {
      const result = await upsertCompanyAndLink(admin, fund, company);
      if (result === "inserted") inserted += 1;
      if (result === "updated") updated += 1;
      if (result !== "skipped") linked += 1;
    } catch (error) {
      console.error(JSON.stringify({
        event: "pitch_crawl_upsert_failed",
        fund_slug: fund.slug,
        company_name: company.name,
        error: (error as Error).message,
      }));
    }
  }

  return {
    ...base,
    discovered: companies.length,
    inserted,
    updated,
    linked,
    unresolved_ats: unresolvedATS,
  };
}

type UpsertResult = "inserted" | "updated" | "skipped";

async function upsertCompanyAndLink(
  admin: ReturnType<typeof createAdminClient>,
  fund: FundRow,
  discovered: DiscoveredCompany,
): Promise<UpsertResult> {
  const nowISO = new Date().toISOString();

  // Try to find an existing row, in priority order:
  //   1. matching domain
  //   2. matching (ats_type, ats_token)
  // We deliberately don't dedupe by name alone — too many collisions.
  let existingId: string | null = null;

  if (discovered.domain) {
    const { data } = await admin
      .from("companies")
      .select("id")
      .eq("domain", discovered.domain)
      .maybeSingle();
    if (data?.id) existingId = data.id;
  }

  if (!existingId && discovered.ats_type && discovered.ats_token) {
    const { data } = await admin
      .from("companies")
      .select("id")
      .eq("ats_type", discovered.ats_type)
      .eq("ats_token", discovered.ats_token)
      .maybeSingle();
    if (data?.id) existingId = data.id;
  }

  let result: UpsertResult;

  if (existingId) {
    const { error } = await admin
      .from("companies")
      .update({
        name: discovered.name,
        domain: discovered.domain,
        logo_url: discovered.logo_url,
        // Don't clobber an existing resolved ats_type with null — keep it.
        ats_type: discovered.ats_type ?? undefined,
        ats_token: discovered.ats_token ?? undefined,
        stage: discovered.stage,
        headcount: discovered.headcount,
        industry: discovered.industry,
        source_board: discovered.source_board,
        last_seen_at: nowISO,
      })
      .eq("id", existingId);
    if (error) throw new Error(`update companies failed: ${error.message}`);
    result = "updated";
  } else {
    const { data, error } = await admin
      .from("companies")
      .insert({
        name: discovered.name,
        domain: discovered.domain,
        logo_url: discovered.logo_url,
        ats_type: discovered.ats_type,
        ats_token: discovered.ats_token,
        stage: discovered.stage,
        headcount: discovered.headcount,
        industry: discovered.industry,
        source_board: discovered.source_board,
        first_seen_at: nowISO,
        last_seen_at: nowISO,
      })
      .select("id")
      .single();
    if (error || !data?.id) throw new Error(`insert companies failed: ${error?.message ?? "no id"}`);
    existingId = data.id;
    result = "inserted";
  }

  // company_funds is (company_id, fund_id) — composite PK so a re-insert is a
  // no-op via on_conflict=do_nothing semantics through upsert with ignoreDuplicates.
  const { error: linkError } = await admin
    .from("company_funds")
    .upsert({ company_id: existingId, fund_id: fund.id }, { ignoreDuplicates: true });
  if (linkError) throw new Error(`link company_funds failed: ${linkError.message}`);

  return result;
}

function sum<T>(items: T[], pick: (item: T) => number): number {
  return items.reduce((acc, item) => acc + pick(item), 0);
}

function jsonError(message: string, status = 500) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
