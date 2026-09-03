// C-2: find a company's ATS board by guessing its slug.
//
// Every supported ATS publishes an unauthenticated board API keyed by a short
// company slug, so a company whose slug we can guess becomes fully crawlable
// with no scraping at all. C-0 measured the pool: 1,803 companies with a
// domain and no ATS coordinates — larger than the entire resolved address book.
//
// THE DANGER IS THE FALSE POSITIVE. `greenhouse.io/acme` returns 200 for
// somebody's Acme, not necessarily ours, and writing that token points the
// per-company crawler at another employer's board — every posting it returns
// attributed to the wrong company, permanently and silently. A 200 is never
// sufficient on its own. Acceptance needs one of:
//
//   1. the board names itself and the name matches (Greenhouse only), or
//   2. the slug came from the company's own DOMAIN and the board has jobs.
//
// A name-derived guess against an ATS that does not name its owner is
// rejected outright. Deliberately conservative: a miss costs one retry later,
// a false positive corrupts the feed.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { jsonResponse } from "../_shared/http.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";
import {
  boardNameMatches,
  leverCaseVariants,
  type SlugCandidate,
  slugCandidates,
} from "../_shared/ats/slug_candidates.ts";
import type { ATSType } from "../_shared/ats/models.ts";

// Edge ceiling is 150s; stop short so bookkeeping always lands.
const RUN_BUDGET_MS = 100_000;
const REQUEST_TIMEOUT_MS = 6_000;
// ~18 requests and a couple of seconds per company, so the run budget binds
// long before this does; it only caps the size of the queue query.
const COMPANY_BATCH = 40;
// Companies move onto an ATS over time, so a miss is worth revisiting.
const REPROBE_AFTER_DAYS = 45;
const MAX_ATTEMPTS = 4;

type Hit = { ats_type: ATSType; ats_token: string; evidence: string };
type ProbeResult = { hit: Hit | null; requests: number };

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const startedAt = Date.now();
  const admin = createAdminClient();

  let scanned = 0;
  let resolved = 0;
  let taken = 0;
  let requests = 0;
  const hits: string[] = [];
  const errors: string[] = [];

  try {
    const cutoff = new Date(Date.now() - REPROBE_AFTER_DAYS * 86_400_000).toISOString();
    const { data: companies, error } = await admin
      .from("companies")
      .select("id, name, domain, ats_probe_attempts")
      .is("ats_type", null)
      .lt("ats_probe_attempts", MAX_ATTEMPTS)
      .or(`ats_probed_at.is.null,ats_probed_at.lt.${cutoff}`)
      .order("ats_probed_at", { ascending: true, nullsFirst: true })
      .limit(COMPANY_BATCH);
    if (error) throw error;

    for (const company of companies ?? []) {
      if (Date.now() - startedAt > RUN_BUDGET_MS) break;
      scanned++;

      let hit: Hit | null = null;
      for (const candidate of slugCandidates(company.name, company.domain)) {
        if (Date.now() - startedAt > RUN_BUDGET_MS) break;
        const found = await probeCandidate(candidate, company.name);
        requests += found.requests;
        if (found.hit) { hit = found.hit; break; }
      }

      // Stamped on every pass, hit or miss. Without it the same 1,800
      // companies would be re-probed every hour for ever.
      const stamp = {
        ats_probed_at: new Date().toISOString(),
        ats_probe_attempts: (company.ats_probe_attempts ?? 0) + 1,
      };

      if (!hit) {
        await admin.from("companies").update(stamp).eq("id", company.id);
        continue;
      }

      // companies_ats_unique: another row may hold this token already, usually
      // the same org ingested twice under different names. Claiming it would
      // 409, and the duplicate is a separate problem.
      const { data: holder } = await admin
        .from("companies")
        .select("id")
        .eq("ats_type", hit.ats_type)
        .eq("ats_token", hit.ats_token)
        .maybeSingle();
      if (holder?.id && holder.id !== company.id) {
        taken++;
        await admin.from("companies").update(stamp).eq("id", company.id);
        continue;
      }

      const { error: updateError } = await admin
        .from("companies")
        .update({ ...stamp, ats_type: hit.ats_type, ats_token: hit.ats_token })
        .eq("id", company.id)
        .is("ats_type", null);   // never clobber coords resolved meanwhile
      if (updateError) {
        errors.push(`${company.name}: ${updateError.message}`);
        continue;
      }
      resolved++;
      if (hits.length < 20) {
        hits.push(`${company.name} -> ${hit.ats_type}/${hit.ats_token} (${hit.evidence})`);
      }
    }

    const summary = {
      scanned, resolved, taken, requests, hits,
      errors: errors.slice(0, 10),
      duration_ms: Date.now() - startedAt,
    };
    await recordPipelineRun(admin, "probe-ats-tokens", startedAt, summary, errors.length);
    return jsonResponse(summary);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await recordPipelineRun(
      admin, "probe-ats-tokens", startedAt, { scanned, resolved, error: message }, 1,
    );
    return jsonResponse({ error: message }, 500);
  }
});

/// One slug across every supported ATS. Greenhouse first: it is the only one
/// that can confirm identity by name, so a hit there is trustworthy wherever
/// the slug came from.
async function probeCandidate(
  candidate: SlugCandidate,
  companyName: string | null,
): Promise<ProbeResult> {
  let requests = 0;

  const greenhouse = await probeGreenhouse(candidate, companyName);
  requests += greenhouse.requests;
  if (greenhouse.hit) return { hit: greenhouse.hit, requests };

  // None of the rest names its board owner, so they can only be accepted on
  // domain provenance. Skip them for name-derived guesses rather than spending
  // requests on results that would be rejected anyway.
  if (candidate.provenance !== "domain") return { hit: null, requests };

  const others = await Promise.all([
    probeAshby(candidate),
    probeLever(candidate, companyName),
    probeSmartRecruiters(candidate),
    probeRecruitee(candidate),
  ]);
  for (const result of others) {
    requests += result.requests;
    if (result.hit) return { hit: result.hit, requests };
  }
  return { hit: null, requests };
}

async function probeGreenhouse(
  candidate: SlugCandidate,
  companyName: string | null,
): Promise<ProbeResult> {
  const meta = await getJSON<{ name?: string }>(
    `https://boards-api.greenhouse.io/v1/boards/${encodeURIComponent(candidate.slug)}`,
  );
  if (!meta) return { hit: null, requests: 1 };

  if (boardNameMatches(meta.name, companyName)) {
    return {
      hit: { ats_type: "greenhouse", ats_token: candidate.slug, evidence: `name:${meta.name}` },
      requests: 1,
    };
  }
  // The board exists but calls itself something else. From a domain-derived
  // slug that is still almost certainly the right company under a fuller legal
  // name; from a name-derived slug it is very probably somebody else's.
  if (candidate.provenance === "domain") {
    return {
      hit: { ats_type: "greenhouse", ats_token: candidate.slug, evidence: "domain" },
      requests: 1,
    };
  }
  return { hit: null, requests: 1 };
}

async function probeAshby(candidate: SlugCandidate): Promise<ProbeResult> {
  const data = await getJSON<{ jobs?: unknown[] }>(
    `https://api.ashbyhq.com/posting-api/job-board/${encodeURIComponent(candidate.slug)}`,
  );
  const ok = Array.isArray(data?.jobs) && data.jobs.length > 0;
  return {
    hit: ok ? { ats_type: "ashby", ats_token: candidate.slug, evidence: "domain" } : null,
    requests: 1,
  };
}

/// Lever is CASE-SENSITIVE and shard-split. Verified live:
/// api.lever.co/v0/postings/Kyverna -> 200 while /kyverna -> 404, and boards
/// hosted at jobs.eu.lever.co answer on api.eu.lever.co. Probing one host in
/// one casing silently misses both populations.
async function probeLever(
  candidate: SlugCandidate,
  companyName: string | null,
): Promise<ProbeResult> {
  let requests = 0;
  for (const host of ["api.lever.co", "api.eu.lever.co"]) {
    for (const variant of leverCaseVariants(candidate, companyName)) {
      const data = await getJSON<unknown[]>(
        `https://${host}/v0/postings/${encodeURIComponent(variant)}?mode=json&limit=1`,
      );
      requests++;
      if (Array.isArray(data) && data.length > 0) {
        return {
          hit: { ats_type: "lever", ats_token: variant, evidence: `domain:${host}` },
          requests,
        };
      }
    }
  }
  return { hit: null, requests };
}

async function probeSmartRecruiters(candidate: SlugCandidate): Promise<ProbeResult> {
  const data = await getJSON<{ content?: unknown[] }>(
    `https://api.smartrecruiters.com/v1/companies/${encodeURIComponent(candidate.slug)}/postings?limit=1`,
  );
  const ok = Array.isArray(data?.content) && data.content.length > 0;
  return {
    hit: ok
      ? { ats_type: "smartrecruiters", ats_token: candidate.slug, evidence: "domain" }
      : null,
    requests: 1,
  };
}

async function probeRecruitee(candidate: SlugCandidate): Promise<ProbeResult> {
  const data = await getJSON<{ offers?: unknown[] }>(
    `https://${encodeURIComponent(candidate.slug)}.recruitee.com/api/offers/`,
  );
  const ok = Array.isArray(data?.offers) && data.offers.length > 0;
  return {
    hit: ok ? { ats_type: "recruitee", ats_token: candidate.slug, evidence: "domain" } : null,
    requests: 1,
  };
}

/// Null on anything that is not a clean 200 with JSON. Misses are the expected
/// case here — most probes are meant to 404 — so nothing is logged.
async function getJSON<T>(url: string): Promise<T | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: { "User-Agent": "scout22-ats-probe/1.0 (+https://tryscout22.com)" },
    });
    if (!response.ok) return null;
    return await response.json() as T;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
