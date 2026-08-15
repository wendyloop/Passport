-- Instagram publishing cron.
--
-- Drains social_posts rows with status 'rendered', one post per run. Three
-- times a day gives a steady trickle well under Instagram's 50-per-24h cap,
-- spread across morning / midday / evening so the account doesn't look
-- botted by posting at a fixed hour.
--
-- Rendering is NOT on a cron — the carousel art is SwiftUI, so it happens
-- on-device from the admin Social tab in bursts of ~20. One batch keeps this
-- cron fed for roughly two weeks.
--
-- Requires two edge-function secrets, set in the dashboard:
--   IG_ACCESS_TOKEN  long-lived Instagram token (60 days, refreshable)
--   IG_USER_ID       the Instagram professional account's numeric id
-- The token expires silently; if posting stops, check it first.
--
-- verify_jwt=false lives in supabase/config.toml — a bare deploy without that
-- entry re-enables gateway JWT checks and every cron call 401s.

do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job where jobname = 'pitch-publish-social-post'
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

select cron.schedule(
  'pitch-publish-social-post',
  '15 13,17,22 * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/publish-social-post',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb,
      timeout_milliseconds := 90000
    );
  $$
);
