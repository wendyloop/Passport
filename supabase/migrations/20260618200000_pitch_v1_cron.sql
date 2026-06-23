-- Schedule the two Pitch orchestrator edge functions:
--   * sync-jobs     — daily  07:00 UTC (ATS job ingestion)
--   * crawl-rosters — weekly Mon 06:00 UTC (fund roster discovery)
--
-- pg_cron runs the SQL; pg_net's net.http_post fires the function. The shared
-- secret (PITCH_CRON_SECRET on the function side) is stored in vault.secrets
-- so it doesn't appear in pg_cron.job_run_details.
--
-- Before this migration's first run, an operator must store the secrets:
--   select vault.create_secret('https://<project>.supabase.co', 'project_url');
--   select vault.create_secret('<random>', 'pitch_cron_secret');
-- and also set PITCH_CRON_SECRET on the edge functions (matching value).

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- Idempotent: unschedule before re-scheduling so re-running this migration on
-- a project that already has the jobs doesn't error out.
do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname in ('pitch-sync-jobs', 'pitch-crawl-rosters')
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

-- ---------- daily sync-jobs at 07:00 UTC ----------
select cron.schedule(
  'pitch-sync-jobs',
  '0 7 * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/sync-jobs',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);

-- ---------- weekly crawl-rosters Monday 06:00 UTC ----------
select cron.schedule(
  'pitch-crawl-rosters',
  '0 6 * * 1',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/crawl-rosters',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
