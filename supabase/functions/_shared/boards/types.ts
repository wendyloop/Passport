// Unified board adapter interface. Every supported portfolio platform
// (Getro, Consider, and any future addition) implements `BoardAdapter`
// so that ingest-jobs can drive them through a single orchestration loop.
//
// Adapter contract: given a fund + resume cursor + soft time budget, walk
// the board's job search endpoint and return everything seen this call as
// (companies, jobs, nextCursor). nextCursor=null means the fund fully
// drained for this cycle and the orchestrator will clear it.

import type { FundRow, ParsedCompensation } from "../ats/models.ts";

export type BoardCompany = {
  // The board's own stable organization id (Getro org id, Consider
  // companyId). Used as part of dedupe when domain is unknown.
  board_external_id: string;
  name: string;
  // Consider boards include this; Getro's search/jobs doesn't. Null is
  // acceptable — the upsert path falls back to (source_board,
  // board_external_id) for dedupe.
  domain: string | null;
  logo_url: string | null;
  stage: string | null;
  headcount: string | null;
  industry: string | null;
};

export type BoardJob = {
  // The board's own stable job id (Getro: numeric job id; Consider:
  // jobId). Stored in `jobs.external_id` so re-ingests are idempotent.
  board_external_id: string;
  // Foreign key into BoardCompany.board_external_id within the same
  // AdapterResult batch. The orchestrator resolves it to a real
  // companies.id after upserting the companies first.
  company_board_external_id: string;
  apply_url: string;
  title: string | null;
  location: string | null;
  posted_at: string | null;
  compensation_text: string | null;
  compensation: ParsedCompensation;
  employment_type: string | null;
  // Most boards ship listing stubs only and leave the body to
  // enrich-descriptions. WaaS is the exception — it hands over the full JD
  // at ingest time, so these are optional and default to null.
  description?: string | null;
  description_raw?: string | null;
};

export type AdapterInput = {
  fund: FundRow;
  startCursor: string | null;
  budgetMs: number;
};

export type AdapterResult = {
  companies: BoardCompany[];
  jobs: BoardJob[];
  // null = fund fully drained; non-null = persist as funds.crawl_cursor
  // and pass back in next run's `startCursor`.
  nextCursor: string | null;
  pages: number;
};

export type BoardAdapter = (input: AdapterInput) => Promise<AdapterResult>;
