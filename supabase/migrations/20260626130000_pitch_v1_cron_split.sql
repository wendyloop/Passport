-- Replace pitch-crawl-rosters with separate Getro + Consider crons, and
-- promote sync-jobs from daily to hourly.
--
-- Why the split:
--   * Getro completes in one pass (5 funds, ~5 min). Weekly is enough.
--   * Consider can't drain Sequoia/a16z in a single 60s edge call, so it
--     uses funds.crawl_cursor to resume. Runs daily; a big fund fully
--     drains in ~3–5 days, then the cursor clears and starts fresh.
--   * sync-jobs has 2,400+ companies × per-company HTTP work. Daily can't
--     keep up; hourly cron + soft budget drains the backlog in ~4 days.
--
-- Same Vault entries used by the previous cron migration:
--   project_url, pitch_cron_secret.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- Drop the legacy combined-roster job and the old daily sync.
do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job
    where jobname in (
      'pitch-sync-jobs',
      'pitch-crawl-rosters',
      'pitch-crawl-getro',
      'pitch-crawl-consider'
    )
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

-- ---------- hourly sync-jobs (top of every hour UTC) ----------
select cron.schedule(
  'pitch-sync-jobs',
  '0 * * * *',
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

-- ---------- weekly crawl-getro Monday 06:00 UTC ----------
-- Getro funds drain in one pass; no point hitting api.getro.com daily.
select cron.schedule(
  'pitch-crawl-getro',
  '0 6 * * 1',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/crawl-getro',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);

-- ---------- daily crawl-consider 06:30 UTC ----------
-- 30 min after the weekly Getro slot so they don't pile onto the edge
-- workers at once on Mondays.
select cron.schedule(
  'pitch-crawl-consider',
  '30 6 * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/crawl-consider',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
