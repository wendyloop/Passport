-- AUDIT P1-8: failed application emails dead-ended — the candidate saw
-- "submitted" while the employer never learned they existed. The new
-- retry-application-emails function re-sends failed employer emails hourly;
-- this migration adds the attempt counter that caps retries and schedules
-- the cron (pg_cron + Vault, same pattern as the other cron functions).
--
-- ORDERING: deploy the function (`supabase functions deploy
-- retry-application-emails` — config.toml already carries its
-- verify_jwt = false entry) before the first hourly tick; until then the
-- cron call 404s harmlessly (and visibly, via pipeline_runs absence).

alter table public.job_applications
  add column if not exists email_delivery_attempts integer not null default 1;

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'retry-application-emails'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

-- Hourly at :20 — retries land quickly without hammering Resend; each run
-- no-ops when there are no failed rows under the attempt cap.
select cron.schedule(
  'retry-application-emails',
  '20 * * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/retry-application-emails',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
