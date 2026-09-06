#!/usr/bin/env -S deno run --allow-net --allow-run --allow-env
//
// C-9: seed the company table from public early-career job lists.
//
// WHY THIS IS A SCRIPT AND NOT A CRON. Two reasons. The lists are ~25MB of
// JSON and parsing them would sit close to an edge function's memory ceiling.
// And the thing being extracted — which companies run internship and new-grad
// programmes — changes over a season, not over an hour, so a manual run a few
// times a year is the honest cadence.
//
// WHAT IT TAKES. Company identity only: a name and the (ats_type, ats_token)
// recovered from the posting URL. No titles, locations, descriptions or ids.
// Postings are then fetched from each company's OWN public ATS API by
// crawl-companies — the same lawful path already used for VC-board companies.
// The lists answer "who hires early career" and are never the source of a job
// row. See _shared/ats/seed_listings.ts.
//
// Usage:
//   deno run --allow-net --allow-run --allow-env scripts/seed-early-career-companies.ts
//   ... --write        actually insert (default is a dry run)
//
// A dry run is the default on purpose: every company inserted here will be
// crawled, and every early-career job that crawl finds costs an LLM carousel
// and an embedding. That is a spend decision, so it is opt-in.

import { extractSeedCompanies, type SeedRecord } from "../supabase/functions/_shared/ats/seed_listings.ts";

const PROJECT_REF = "zqfurscyhmxlvrfendnc";

const SOURCES = [
  {
    label: "internships",
    url: "https://raw.githubusercontent.com/SimplifyJobs/Summer2027-Internships/dev/.github/scripts/listings.json",
  },
  {
    label: "new grad",
    url: "https://raw.githubusercontent.com/SimplifyJobs/New-Grad-Positions/dev/.github/scripts/listings.json",
  },
];

const write = Deno.args.includes("--write");

// Same keychain path the verify-*.sh harnesses use; the token is never printed.
async function managementToken(): Promise<string> {
  const proc = new Deno.Command("security", {
    args: ["find-generic-password", "-s", "Supabase CLI", "-w"],
    stdout: "piped",
  });
  const { stdout } = await proc.output();
  const raw = new TextDecoder().decode(stdout).trim();
  const encoded = raw.replace(/^go-keyring-base64:/, "");
  return new TextDecoder().decode(
    Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0)),
  ).trim();
}

async function query<T = Record<string, unknown>>(sql: string, token: string): Promise<T[]> {
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        // Cloudflare rejects the default Deno/urllib agent with error 1010.
        "User-Agent": "curl/8.6.0",
      },
      body: JSON.stringify({ query: sql }),
    },
  );
  if (!response.ok) {
    throw new Error(`query failed ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }
  return await response.json() as T[];
}

function sqlString(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

// ---------------------------------------------------------------------------

const seen = new Map<string, {
  name: string;
  ats_type: string;
  ats_token: string;
  ats_host?: string;
  ats_site?: string;
}>();
const unsupported: Record<string, number> = {};
const aggregators = new Set<string>();
let totalRecords = 0;

for (const source of SOURCES) {
  console.log(`fetching ${source.label}…`);
  const response = await fetch(source.url);
  if (!response.ok) {
    console.error(`  FAILED ${response.status}`);
    continue;
  }
  const records = await response.json() as SeedRecord[];
  const extracted = extractSeedCompanies(records);
  const { companies, stats } = extracted;
  totalRecords += stats.records;
  for (const [host, count] of Object.entries(stats.unsupportedByHost)) {
    unsupported[host] = (unsupported[host] ?? 0) + count;
  }
  for (const company of companies) {
    seen.set(`${company.ats_type}:${company.ats_token}`, company);
  }
  for (const key of extracted.aggregatorsDropped) aggregators.add(key);
  console.log(
    `  ${stats.records} records · ${stats.distinctCompanyNames} distinct names · ${stats.resolved} boards resolved`,
  );
}

// Aggregators can only be spotted across the whole corpus, so a board that
// looked like one company in the first file may be revealed by the second.
for (const key of aggregators) seen.delete(key);

const candidates = [...seen.values()];
if (aggregators.size) {
  console.log(`\ndropped ${aggregators.size} aggregator board(s): ${[...aggregators].join(", ")}`);
}
console.log(`\n${candidates.length} distinct boards across both lists`);
console.log("not reachable by any adapter yet:");
for (const [host, count] of Object.entries(unsupported).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(count).padStart(6)}  ${host}`);
}

const token = await managementToken();

// Diff against what is already held, so the report is "what this ADDS".
const existing = await query<{ ats_type: string; ats_token: string }>(
  "select ats_type, ats_token from companies where ats_type is not null and ats_token is not null;",
  token,
);
const held = new Set(existing.map((r) => `${r.ats_type}:${r.ats_token}`));
const additions = candidates.filter((c) => !held.has(`${c.ats_type}:${c.ats_token}`));

console.log(`\n${held.size} boards already held · ${candidates.length - additions.length} overlap · ${additions.length} NEW`);
console.log("sample of what would be added:");
for (const company of additions.slice(0, 15)) {
  const site = company.ats_site ? ` [${company.ats_host} / ${company.ats_site}]` : "";
  console.log(`  ${company.name} -> ${company.ats_type}/${company.ats_token}${site}`);
}
const workday = additions.filter((c) => c.ats_type === "workday").length;
if (workday) console.log(`  …of which ${workday} are Workday tenants`);

if (!write) {
  console.log(`\nDRY RUN. Re-run with --write to insert ${additions.length} companies.`);
  console.log("Each inserted company gets crawled, and every early-career job found");
  console.log("costs an LLM carousel plus an embedding — so this is a spend decision.");
  Deno.exit(0);
}

// source_board marks provenance so these are distinguishable from VC-board
// companies for ever after. ON CONFLICT DO NOTHING leans on
// companies_ats_unique rather than re-checking in the client.
const CHUNK = 200;
let inserted = 0;
for (let i = 0; i < additions.length; i += CHUNK) {
  const values = additions.slice(i, i + CHUNK)
    .map((c) =>
      `(${sqlString(c.name)}, ${sqlString(c.ats_type)}, ${sqlString(c.ats_token)}, ` +
      `${c.ats_host ? sqlString(c.ats_host) : "null"}, ${c.ats_site ? sqlString(c.ats_site) : "null"}, ` +
      `'early-career-seed')`
    )
    .join(",\n    ");
  const rows = await query<{ id: string }>(
    `insert into companies (name, ats_type, ats_token, ats_host, ats_site, source_board)
     values ${values}
     on conflict (ats_type, ats_token) where ats_type is not null and ats_token is not null
     do nothing
     returning id;`,
    token,
  );
  inserted += rows.length;
  console.log(`  inserted ${inserted}/${additions.length}`);
}
console.log(`\ndone — ${inserted} companies added. crawl-companies picks them up on its next pass.`);
