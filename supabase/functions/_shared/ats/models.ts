// Shared types for the Pitch ATS sync pipeline.
//
// Every adapter (Greenhouse / Lever / Ashby / SmartRecruiters / Recruitee)
// returns a list of NormalizedJob. The sync orchestrator uses content_hash
// to skip writes for unchanged jobs.

export type ATSType =
  | "greenhouse"
  | "lever"
  | "ashby"
  | "smartrecruiters"
  | "recruitee";

export type ApplyFlow = "ats_form" | "external_link" | "message";

export type ParsedCompensation = {
  min_annual: number | null;
  max_annual: number | null;
  min_hourly: number | null;
  max_hourly: number | null;
};

export type NormalizedJob = {
  source_ats: ATSType;
  external_id: string;             // provider's own job id
  title: string | null;
  listing_url: string | null;      // job detail page
  apply_url: string | null;        // direct apply, falls back to listing_url
  apply_flow: ApplyFlow;           // derived from apply_url host
  compensation_text: string | null;
  compensation: ParsedCompensation;
  location: string | null;
  category: string | null;         // department / function
  employment_type: string | null;  // full-time, contract, etc.
  posted_at: string | null;        // ISO-8601 UTC
  description: string | null;      // full JD body (may include HTML)
  description_raw: string | null;  // pre-strip raw value if different
  contact_email_on_posting: string | null;
  content_hash: string;            // sha256 over meaningful fields
};

export type AdapterFetchInput = {
  ats_token: string;
  company_name?: string | null;
};

export type AdapterFetchResult = {
  jobs: NormalizedJob[];
  // Some adapters (Greenhouse) expose the company display name; surface it so
  // the orchestrator can keep `companies.name` in sync.
  company_name_from_source?: string | null;
};

export type ATSAdapter = (
  input: AdapterFetchInput,
) => Promise<AdapterFetchResult>;

export type CompanyRow = {
  id: string;
  name: string;
  domain: string | null;
  ats_type: ATSType | null;
  ats_token: string | null;
};

export type FundRow = {
  id: string;
  name: string;
  slug: string;
  board_url: string | null;
  platform: "getro" | "consider" | "bespoke" | "workatastartup" | null;
  external_collection_id: string | null; // Getro: collection id, Consider: board slug
};

// Per-company outcome surfaced in the sync summary.
export type SyncOutcome = {
  company_id: string;
  company_name: string;
  inserted: number;
  updated: number;
  expired: number;
  error: string | null;
};
