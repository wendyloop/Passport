-- Pitch v2 cron schedule.
--
-- The old three-cron split (crawl-getro weekly, crawl-consider daily,
-- sync-jobs hourly) is collapsed into two crons that follow the v2 split:
--   * ingest-jobs daily — boards are the source of truth for which jobs
--     exist. One fund per run is fine; cursors carry partial drains across
--     days. Sequoia (~9k jobs) drains in 3–5 days then stays drained.
--   * enrich-descriptions hourly — fills description text for ats-resolved
--     jobs, keyed write-once by `description IS NULL`. Catches up on the
--     2,400+ company backlog over a few hours.
--
-- Uses the same Vault entries as v1: project_url, pitch_cron_secret.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- Drop v1 crons (and any earlier v0 names that may still be lingering).
do $$
declare
  jid bigint;
begin
  for jid in select jobid from cron.job
    where jobname in (
      'pitch-sync-jobs',
      'pitch-crawl-rosters',
      'pitch-crawl-getro',
      'pitch-crawl-consider',
      'pitch-ingest-jobs',
      'pitch-enrich-descriptions'
    )
  loop
    perform cron.unschedule(jid);
  end loop;
end$$;

-- ---------- daily ingest-jobs 06:00 UTC ----------
-- Walks every board (Getro + Consider) with resume cursors and a per-fund
-- time budget. Daily cadence drains even Sequoia within a week and keeps
-- it fresh thereafter.
select cron.schedule(
  'pitch-ingest-jobs',
  '0 6 * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/ingest-jobs',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);

-- ---------- hourly enrich-descriptions (top of every hour UTC) ----------
-- Fills description text for ats-resolved jobs. Write-once via the
-- `description IS NULL` guard in the UPDATE, so reruns are harmless.
select cron.schedule(
  'pitch-enrich-descriptions',
  '0 * * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/enrich-descriptions',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb
    );
  $$
);
