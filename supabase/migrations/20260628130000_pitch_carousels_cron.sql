-- Pitch carousel generation cron.
--
-- Steady-state: one daily run is enough. Boards see ~100–500 truly new jobs
-- per day across all 12 funds; one batch (≈30 jobs/run, ≤50s) handles the
-- trickle. During the initial backfill of existing rows, invoke the function
-- manually a few times in a row — or temporarily bump to hourly — to drain.
--
-- Order in the pipeline:
--   06:00 UTC  pitch-ingest-jobs            new board rows land
--   06:30 UTC  pitch-enrich-descriptions    ATS descriptions fill (hourly thereafter)
--   07:00 UTC  pitch-generate-carousel      carousels for today's new rows

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'pitch-generate-carousel'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

select cron.schedule(
  'pitch-generate-carousel',
  '0 7 * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/generate-carousel',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
