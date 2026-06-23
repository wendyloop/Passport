// Shared types for board crawlers (weekly roster discovery).
//
// Each crawler takes a FundRow and returns DiscoveredCompany[]. The
// `crawl-rosters` orchestrator upserts these into companies + company_funds.

import type { ATSType, FundRow } from "../ats/models.ts";

export type DiscoveredCompany = {
  // Display fields used by the iOS feed.
  name: string;
  domain: string | null;
  logo_url: string | null;
  // Resolved ATS coordinates — null when the company's apply links don't
  // match any supported ATS. Stored as-is so we can re-resolve next crawl.
  ats_type: ATSType | null;
  ats_token: string | null;
  // Optional metadata surfaced by some boards.
  stage: string | null;
  headcount: string | null;
  industry: string | null;
  // Provenance — which board the company was seen on.
  source_board: string;
};

export type BoardCrawler = (fund: FundRow) => Promise<DiscoveredCompany[]>;
