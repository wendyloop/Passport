// C-9: turning a public early-career job list into COMPANY SEEDS.
//
// The pivot needs a company set that actually hires interns and new grads.
// VC boards do not supply one — a live crawl of Anthropic's board returned
// 594 jobs and zero early-career roles. Public new-grad/internship lists are
// exactly that set.
//
// WHAT IS TAKEN, AND WHAT IS NOT. Only the company's identity: a name, and
// the (ats_type, ats_token) recovered from the posting URL. No titles, no
// locations, no descriptions, no ids — nothing that would amount to
// republishing somebody else's compilation. Postings are then fetched from
// each company's OWN public ATS API by crawl-companies, which is the same
// lawful path already used for VC-board companies. The lists answer "who
// hires early career"; they are never the source of a job row.
//
// Inactive records are kept deliberately. A closed internship from last
// season is stale as a POSTING and perfectly good as evidence that the
// company runs an internship programme — which is the only claim being made.

import { classifyApplyURL } from "./classify.ts";
import type { ATSType } from "./models.ts";

export type SeedRecord = {
  company_name?: string | null;
  url?: string | null;
};

export type SeedCompany = {
  name: string;
  ats_type: ATSType;
  ats_token: string;
};

export type SeedExtraction = {
  companies: SeedCompany[];
  /// Boards claimed by three or more distinct employers — aggregator boards,
  /// not companies. Surfaced rather than silently dropped so a growing list
  /// is visible.
  aggregatorsDropped: string[];
  stats: {
    records: number;
    distinctCompanyNames: number;
    resolved: number;
    // Companies whose postings sit on an ATS with no adapter yet. Counted
    // rather than dropped silently: this number IS the size of the prize for
    // C-3 (Workday) and C-4 (Oracle/iCIMS), measured on the exact market the
    // pivot targets.
    unsupportedByHost: Record<string, number>;
  };
};

/// Hosts worth naming in the unsupported tally. Anything else lands under
/// "other" — mostly bespoke careers sites, which no adapter will ever cover.
const UNSUPPORTED_HOSTS: Array<[RegExp, string]> = [
  [/myworkdayjobs\.com|myworkday(site)?\.com|workday\.com/i, "workday"],
  [/oraclecloud\.com|taleo\.net/i, "oracle/taleo"],
  [/icims\.com/i, "icims"],
  [/workable\.com/i, "workable"],
  [/jobvite\.com|breezy\.hr|bamboohr\.com|rippling\.com|teamtailor\.com/i, "other known ATS"],
];

export function extractSeedCompanies(records: SeedRecord[]): SeedExtraction {
  // One board legitimately answers to two spellings — "Match Group" and
  // "Tinder", "PlayStation" and "Sony Interactive Entertainment". Three or
  // more distinct employers on one board is not a spelling variant, it is an
  // aggregator board, and attributing its postings to whichever name happened
  // to arrive first would put other companies' jobs under that employer in
  // the feed.
  const AGGREGATOR_NAME_THRESHOLD = 3;
  const namesByToken = new Map<string, Set<string>>();

  // Keyed by ATS coordinates, not by name. Two records can spell a company
  // differently ("1stdibs" / "1stDibs.com") while pointing at one board, and
  // the board is the identity that matters — it is also what
  // companies_ats_unique dedupes on, so keying this way means the insert
  // cannot collide with itself.
  const byToken = new Map<string, SeedCompany>();
  const names = new Set<string>();
  const unsupportedByHost: Record<string, number> = {};

  for (const record of records) {
    const name = record.company_name?.trim();
    const url = record.url?.trim();
    if (!name || !url) continue;
    names.add(name.toLowerCase());

    const resolution = classifyApplyURL(url);
    if (!resolution) {
      let bucket = "other";
      for (const [pattern, label] of UNSUPPORTED_HOSTS) {
        if (pattern.test(url)) { bucket = label; break; }
      }
      unsupportedByHost[bucket] = (unsupportedByHost[bucket] ?? 0) + 1;
      continue;
    }

    const key = `${resolution.ats_type}:${resolution.ats_token}`;
    const nameSet = namesByToken.get(key) ?? new Set<string>();
    nameSet.add(name.toLowerCase());
    namesByToken.set(key, nameSet);

    // First name wins. Later records for the same board are the same company
    // under a variant spelling, and churning the name buys nothing.
    if (!byToken.has(key)) {
      byToken.set(key, {
        name,
        ats_type: resolution.ats_type,
        ats_token: resolution.ats_token,
      });
    }
  }

  const aggregators: string[] = [];
  for (const [key, nameSet] of namesByToken) {
    if (nameSet.size >= AGGREGATOR_NAME_THRESHOLD) {
      aggregators.push(key);
      byToken.delete(key);
    }
  }

  return {
    companies: [...byToken.values()],
    aggregatorsDropped: aggregators,
    stats: {
      records: records.length,
      distinctCompanyNames: names.size,
      resolved: byToken.size,
      unsupportedByHost,
    },
  };
}
