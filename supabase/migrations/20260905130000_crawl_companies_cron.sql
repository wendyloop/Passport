-- C-8: crawl-companies cron.
--
-- ~1,548 companies now carry ATS coordinates. At ~25 per run a full sweep
-- takes about an hour of runs, and the 24-hour re-crawl cadence means the
-- steady state is roughly one pass a day per company — boards do not churn
-- faster than that, and every crawl costs the vendor a request.
--
-- Every 10 minutes rather than continuously: the run budget caps each pass,
-- and spacing them keeps request rate polite across five ATS vendors this
-- product depends on.
--
-- Scheduled in a migration, not cron.alter_job, so production and the repo
-- cannot drift — the F9 carousel schedule ran */2 in production while the
-- repo said */30 for two weeks after exactly that mistake.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'crawl-companies'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

select cron.schedule(
  'crawl-companies',
  '*/10 * * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/crawl-companies',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
