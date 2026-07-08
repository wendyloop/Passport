-- Pitch v1 cursor columns for incremental crawling/syncing.
--
-- crawl-consider can't drain Sequoia (9k jobs) or a16z (1k+) in a single
-- 60-second edge function run, so it persists a paging cursor between runs.
-- A daily cron means a fund fully drains in ~3–5 days; on completion the
-- cursor clears and the next run starts fresh from the top.
--
-- sync-jobs has the same problem at the company axis (2,400+ companies,
-- each ~1–3s of HTTP work). We order by last_synced_at asc nulls first,
-- work through a soft per-run budget, and update the timestamp as we go.
-- No explicit cursor needed — the timestamp doubles as one.

alter table public.funds
  add column if not exists crawl_cursor text;

alter table public.companies
  add column if not exists last_synced_at timestamptz;

-- Speeds up the "oldest synced first" scan in sync-jobs.
create index if not exists companies_last_synced_idx
  on public.companies (last_synced_at nulls first)
  where ats_type is not null and ats_token is not null;
