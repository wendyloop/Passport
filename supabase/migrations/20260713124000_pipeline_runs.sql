-- DB-P1-9: pipeline run outcomes lived only in ephemeral function logs, and
-- pg_cron discards the HTTP results — three silent failures ran for weeks
-- (Apify inserts violating NOT NULL, the founder_email_sent enum miss, the
-- 2026-07-08 verify_jwt 401s) because nothing queryable recorded whether a
-- run happened or what it did. Every pipeline function now inserts one row
-- per run; "no successful ingest-jobs run in 36h" becomes one SQL query.

create table if not exists public.pipeline_runs (
  id            uuid primary key default extensions.gen_random_uuid(),
  function_name text not null,
  started_at    timestamptz not null default timezone('utc', now()),
  duration_ms   integer,
  summary       jsonb not null default '{}'::jsonb,
  error_count   integer not null default 0
);

create index if not exists pipeline_runs_fn_started_idx
  on public.pipeline_runs (function_name, started_at desc);

alter table public.pipeline_runs enable row level security;

-- Admins can read run history (future admin-screen widget); writes go
-- through the service role only (no client write policies).
drop policy if exists "pipeline_runs_admin_read" on public.pipeline_runs;
create policy "pipeline_runs_admin_read"
on public.pipeline_runs
for select
to authenticated
using (public.auth_role_in(array['admin']));
