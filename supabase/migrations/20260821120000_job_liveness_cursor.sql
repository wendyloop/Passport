-- Rotation cursor for board-sourced liveness checks.
--
-- `is_active` is supposed to be maintained by ingest-jobs' expiry sweep, which
-- closes anything not seen on the VC board within 48h. That sweep cannot work
-- at the crawl's throughput: a daily run sees ~333 jobs total (measured
-- 2026-08-21) against 30,174 active rows, so one full pass over the board
-- would take roughly three months. The sweep is also gated on a fund draining
-- completely in a single run, which accel (parked at page 895),
-- general-catalyst, index-ventures and insight-partners have never once done.
-- Net effect: `jobs_expired: 0` on every run, and 16,846 jobs still marked
-- active that no board has listed in over a month.
--
-- Getro's per-job endpoint answers the same question ~20x faster (~6,600
-- jobs/day vs 333) and authoritatively — it returns closed_at/deactivated_at
-- rather than making us infer death from absence. enrich-descriptions already
-- calls it for jobs missing a description; this column lets the same pass
-- rotate over jobs that already HAVE one, which otherwise leave the queue
-- forever and are never re-checked by anything.
--
-- NULL means never checked, and sorts first: the backlog drains before any
-- row is re-verified.

alter table public.jobs
  add column if not exists liveness_checked_at timestamptz;

comment on column public.jobs.liveness_checked_at is
  'Last time the source board confirmed this posting is still open. Set by '
  'enrich-descriptions'' board pass; NULL = never verified. Distinct from '
  'last_seen_at, which only means "appeared in a board crawl page".';

-- Partial index: the pass only ever queries active rows, oldest-check first.
create index if not exists jobs_liveness_rotation_idx
  on public.jobs (liveness_checked_at nulls first)
  where is_active;
