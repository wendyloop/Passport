-- Schedule the two Pitch orchestrator edge functions:
--   * sync-jobs     — daily  07:00 UTC (ATS job ingestion)
--   * crawl-rosters — weekly Mon 06:00 UTC (fund roster discovery)
--
-- pg_cron runs the SQL; pg_net.http_post fires the function. Two pieces of
-- config plumb out of Postgres into the HTTP call, both stored in Vault
-- because the dashboard role on managed Supabase lacks the superuser bit
-- needed to set custom database parameters:
--   * project URL        → vault entry 'project_url' (not actually secret;
--                          Vault is just the only writable per-project
--                          key/value store available to non-superusers)
--   * shared cron secret → vault entry 'pitch_cron_secret'
-- The secret is what stops randos who guess the function URL from triggering
-- a sync; the edge function rejects any request missing the matching header.
--
-- ONE-TIME SETUP (run in the SQL editor before the first cron fire):
--   select vault.create_secret('https://<your-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<paste openssl rand -hex 32 output>', 'pitch_cron_secret');
-- Also set PITCH_CRON_SECRET on BOTH edge functions (sync-jobs + crawl-rosters)
-- to the same value you stored in Vault.

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
