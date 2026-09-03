-- C-2: probe-ats-tokens cron.
--
-- Backlog is 1,803 companies with a domain and no ATS coordinates. A dry run
-- against production measured ~12% resolving at ~18 requests each, so the
-- whole sweep is roughly 32k outbound requests for roughly 200 newly
-- crawlable companies — each of which then yields its entire job board
-- forever on the existing per-company crawler.
--
-- Every 30 minutes: the run budget caps each pass at ~30-40 companies, so the
-- backlog drains in about two days and the job then idles against the
-- 45-day re-probe window. Spreading it out is also the polite way to send
-- 32k requests to five ATS vendors we depend on.
--
-- Scheduled in a migration, not via cron.alter_job, so production and the
-- repo cannot drift — the F9 carousel schedule ran */2 in production while
-- the repo said */30 for two weeks after exactly that mistake.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'probe-ats-tokens'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

select cron.schedule(
  'probe-ats-tokens',
  '3,33 * * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/probe-ats-tokens',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
