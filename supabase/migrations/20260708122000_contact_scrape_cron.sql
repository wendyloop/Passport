-- Tier-3 founder contact scrape cron.
--
-- Runs after the rest of the pipeline so the day's new companies have had
-- their chance to get contacts from the cheaper tiers first:
--   06:00 UTC  pitch-ingest-jobs               new board rows land
--   06:30 UTC  pitch-enrich-descriptions       descriptions + posting emails (hourly)
--   07:00 UTC  pitch-generate-carousel         carousels + JD-named founders
--   08:30 UTC  pitch-enrich-company-contacts   website scrape for the rest

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'pitch-enrich-company-contacts'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

select cron.schedule(
  'pitch-enrich-company-contacts',
  '30 8 * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/enrich-company-contacts',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
