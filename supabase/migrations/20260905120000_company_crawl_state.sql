-- C-8: per-company crawl cadence.
--
-- companies.last_synced_at already exists and is enrich-descriptions' queue
-- cursor. The direct crawler needs its OWN cursor: the two run on different
-- cadences for different reasons, and sharing one would have each starve the
-- other's queue.
alter table public.companies
  add column if not exists last_crawled_at timestamptz;

-- The crawler's queue: crawlable companies, never-crawled first.
create index if not exists companies_crawl_queue_idx
  on public.companies (last_crawled_at nulls first)
  where ats_type is not null and ats_token is not null;

-- Its expiry sweep filters jobs by (company_id, source_board, is_active,
-- last_seen_at). Without this the sweep seq-scans a 38k-row table once per
-- company, 25 times a run.
create index if not exists jobs_direct_crawl_sweep_idx
  on public.jobs (company_id, last_seen_at)
  where source_board = 'ats-direct' and is_active;
