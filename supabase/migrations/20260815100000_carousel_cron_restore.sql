-- F9: restore pitch-generate-carousel to */30 after the 2026-07-31 backlog drain.
--
-- On 2026-07-31 the schedule was raised from '*/30 * * * *' to '*/2 * * * *'
-- to drain a 21,432-job carousel backlog, with a plan to restore it around
-- 08-02. It was applied with a live `cron.alter_job` rather than a migration,
-- so for two weeks the repo said */30 while production ran */2 and nothing in
-- git revealed the difference. `supabase db push` could not correct it —
-- 20260709120000_pipeline_rescue.sql had already been applied. This migration
-- exists so that divergence cannot silently persist again.
--
-- Verified before restoring (2026-08-15):
--   * 0 active jobs without a carousel — the backlog is fully drained.
--   * ~18 productive runs/day processing ~350 jobs, in two bursts that track
--     the ingest (06:00) and contact-enrichment (08:30) crons. The other ~700
--     daily invocations found an empty queue and returned immediately.
--   * At 30 jobs/run, */30 gives ~1,440 jobs/day of capacity against a peak
--     daily burst of ~300 — it keeps up with several times the headroom.
--
-- If a future backfill needs the faster cadence again, prefer a migration over
-- a live alter_job, or note the temporary change somewhere git can see it.

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
  '*/30 * * * *',
  $$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/generate-carousel',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-pitch-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'pitch_cron_secret')
      ),
      body    := '{}'::jsonb,
      timeout_milliseconds := 90000
    );
  $$
);
