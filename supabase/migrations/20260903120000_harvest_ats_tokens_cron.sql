-- C-1: harvest-ats-tokens cron.
--
-- Backlog at time of writing: 1,857 companies with no ATS coordinates, of
-- which only ~15 currently resolve from their jobs' apply URLs — the rest are
-- on bespoke careers sites or an ATS with no adapter yet. So this is not a
-- drain job; it is a small, standing correction.
--
-- Hourly rather than every few minutes for exactly that reason: the work is
-- tiny and mostly finds nothing. The value is that a company whose board
-- entry lacked an ATS hint stops being invisible to the per-company crawler
-- within an hour of being ingested, instead of never.
--
-- Scheduled through a migration, not cron.alter_job, so the repo and
-- production cannot drift — the F9 carousel schedule ran */2 in production
-- while the repo said */30 for two weeks after exactly that mistake.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'harvest-ats-tokens'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

select cron.schedule(
  'harvest-ats-tokens',
  '17 * * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/harvest-ats-tokens',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
