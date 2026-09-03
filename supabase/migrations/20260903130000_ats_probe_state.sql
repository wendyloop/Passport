-- C-2: remember which companies have been probed, so the prober does not
-- re-guess the same 1,800 companies every hour forever.
--
-- Most probes MISS — a company on a bespoke careers site has no board to
-- find, and no amount of retrying changes that. Recording the attempt is what
-- turns this from a treadmill into a queue that drains.
alter table public.companies
  add column if not exists ats_probed_at      timestamptz,
  add column if not exists ats_probe_attempts integer not null default 0;

-- The prober's queue: unresolved companies, never-probed first, then
-- least-recently-probed. Partial because resolved companies are never probed.
create index if not exists companies_ats_probe_queue_idx
  on public.companies (ats_probed_at nulls first, ats_probe_attempts)
  where ats_type is null;
