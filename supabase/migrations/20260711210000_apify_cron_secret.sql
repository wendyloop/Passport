-- AUDIT P0-2: trigger-apify-scrape previously had no caller check — any
-- holder of the public anon key could start paid Apify runs. The function
-- now requires the x-pitch-cron-secret header (fail-closed, same guard as
-- the other cron functions), so its schedule moves off the dashboard
-- "Edge Functions → Schedule" entry (which sends no such header) and onto
-- pg_cron + Vault, identical to 20260618200000_pitch_v1_cron.sql.
--
-- Uses the SAME Vault entries that migration set up ('project_url',
-- 'pitch_cron_secret') — no new one-time setup.
--
-- MANUAL FOLLOW-UP: delete the old dashboard schedule for
-- trigger-apify-scrape (it will only 401 from now on, but it's noise).

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'apify-daily-scrape'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

-- Daily 09:00 UTC, same time as the old dashboard schedule.
select cron.schedule(
  'apify-daily-scrape',
  '0 9 * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/trigger-apify-scrape',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
