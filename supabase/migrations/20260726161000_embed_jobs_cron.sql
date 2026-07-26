-- M-E: embed-jobs cron. Every 10 minutes until the ~33k-job backfill
-- drains (~300/run ≈ 18h), then it naturally idles at delta-only work;
-- relax to hourly later if the empty runs bother pipeline_runs (F9-style
-- cost hygiene, not correctness).

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'embed-jobs'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

select cron.schedule(
  'embed-jobs',
  '*/10 * * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/embed-jobs',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
