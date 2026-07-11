-- Pipeline rescue: three compounding failures left the feed with only 23
-- eligible jobs out of 32,740 ingested (diagnosed 2026-07-09):
--
--   1. generate-carousel selected from the 90 most-recently-seen jobs only;
--      once those had carousels every run processed zero. Fixed with a
--      proper queue RPC (below) + the function change that uses it.
--   2. pg_net's default ~5s timeout dropped the connection long before the
--      functions' 50s run budgets, killing them mid-run. All pitch crons are
--      rescheduled with timeout_milliseconds := 90000.
--   3. The 2026-07-08 redeploy re-enabled gateway JWT verification on the
--      cron functions (they carry their own fail-closed secret instead).
--      Fixed in config.toml (verify_jwt = false) + redeploy, not here.

-- ── Carousel queue RPC ──────────────────────────────────────────────
-- Jobs needing a carousel: none yet, or content changed after the carousel
-- was generated. Description-bearing jobs first — only LLM ('generated')
-- carousels reach the feed, so they're the valuable ones; description-less
-- jobs get fallback carousels and are regenerated later when
-- enrich-descriptions fills them in (updated_at > generated_at).
create or replace function public.get_jobs_needing_carousel(p_limit int)
returns table (id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select j.id
  from public.jobs j
  left join public.carousels c on c.job_id = j.id
  where j.is_active
    and j.company_id is not null
    and (c.job_id is null or j.updated_at > c.generated_at)
  order by (j.description is not null) desc, j.last_seen_at desc
  limit p_limit;
$$;

revoke all on function public.get_jobs_needing_carousel(int) from public, anon, authenticated;
grant execute on function public.get_jobs_needing_carousel(int) to service_role;

-- ── Regenerate the 45 pre-v2 carousels ──────────────────────────────
-- The carousel format is now v2 (fact-first cover + perks slide). The 45
-- existing rows were built as v1; deleting them routes every job through the
-- fixed queue so the whole catalog is uniform. They regenerate within the
-- first few cron ticks after deploy.
delete from public.carousels;

-- ── Reschedule pitch crons with a real timeout ──────────────────────
-- generate-carousel also moves to every 30 minutes while the ~11k backlog
-- of description-bearing jobs drains (~25-30 carousels/run); drop it back to
-- hourly or daily once the backlog is gone.
do $$
declare
  jid bigint;
  name text;
begin
  foreach name in array array[
    'pitch-ingest-jobs', 'pitch-enrich-descriptions',
    'pitch-generate-carousel', 'pitch-enrich-company-contacts'
  ] loop
    for jid in select jobid from cron.job where jobname = name loop
      perform cron.unschedule(jid);
    end loop;
  end loop;
end$$;

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
      body    := '{}'::jsonb,
      timeout_milliseconds := 90000
    );
  $$
);

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
      body    := '{}'::jsonb,
      timeout_milliseconds := 90000
    );
  $$
);

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
      body    := '{}'::jsonb,
      timeout_milliseconds := 90000
    );
  $$
);

-- ── upsert_board_jobs learns job_function ───────────────────────────
-- ingest-jobs now classifies titles at ingest time (shared
-- title_classify.ts); the RPC gains the column. Write-once like the rest
-- of the content columns.
create or replace function public.upsert_board_jobs(p_jobs jsonb)
returns table (id uuid, dedup_key text, inserted boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  return query
  with input as (
    select * from jsonb_to_recordset(p_jobs) as t(
      dedup_key                text,
      company_id               uuid,
      company_name             text,
      source_board             text,
      board_external_id        text,
      apply_url                text,
      apply_flow               text,
      title                    text,
      location                 text,
      employment_type          text,
      job_function             text,
      compensation_text        text,
      compensation_min_annual  int,
      compensation_max_annual  int,
      compensation_min_hourly  int,
      compensation_max_hourly  int,
      ats_type                 text,
      ats_token                text,
      ats_external_id          text,
      source_url               text,
      now_ts                   timestamptz
    )
  ),
  upserted as (
    insert into public.jobs as j (
      dedup_key, company_id, company_name,
      source_kind, source_board, external_id,
      apply_url, apply_flow,
      title, location, employment_type, job_function,
      compensation_text,
      compensation_min_annual, compensation_max_annual,
      compensation_min_hourly, compensation_max_hourly,
      ats_type, ats_external_id,
      source_ats, source_url,
      is_published, is_active,
      first_seen_at, last_seen_at
    )
    select
      i.dedup_key, i.company_id, i.company_name,
      'board'::text, i.source_board, i.board_external_id,
      i.apply_url,
      coalesce(i.apply_flow, case when i.ats_type is not null then 'ats_form' else 'external_link' end),
      coalesce(i.title, 'Untitled role'), i.location, i.employment_type,
      i.job_function::public.job_function,
      i.compensation_text,
      i.compensation_min_annual, i.compensation_max_annual,
      i.compensation_min_hourly, i.compensation_max_hourly,
      i.ats_type, i.ats_external_id,
      i.ats_type, i.source_url,
      true, true,
      i.now_ts, i.now_ts
    from input i
    on conflict (dedup_key) do update set
      last_seen_at = excluded.last_seen_at,
      is_active    = true,
      closed_at    = null
    returning j.id, j.dedup_key, (j.xmax = 0) as inserted
  )
  select u.id, u.dedup_key, u.inserted from upserted u;
end;
$$;

-- ── Backfill job_function from titles ───────────────────────────────
-- job_function was NULL on 100% of board/ats jobs, so the app's feed
-- filters matched nothing. Title-keyword classification is imperfect but
-- turns the filters on; ingest-jobs now classifies new rows the same way.
update public.jobs set job_function = case
  when lower(title) ~ '(software|backend|frontend|full.?stack|platform engineer|infrastructure|devops|sre|site reliab|mobile engineer|ios |android|embedded|firmware|security engineer|data engineer|ml engineer|machine learning|ai engineer|research engineer|hardware|electrical engineer|mechanical engineer|qa engineer|test engineer)' then 'engineering'
  when lower(title) ~ '(data scien|data analy|analytics|research scien|applied scien|quantitative)' then 'science'
  when lower(title) ~ '(product manager|product owner|technical program|program manager|head of product|product lead)' then 'product'
  when lower(title) ~ '(designer|design lead|\mux\M|\mui designer|user experience|user interface|brand design)' then 'design'
  when lower(title) ~ '(sales|account exec|account manager|business develop|\mbdr\M|\msdr\M|revenue|partnership)' then 'sales'
  when lower(title) ~ '(marketing|growth|content|brand manager|\mseo\M|social media|community manager)' then 'marketing'
  when lower(title) ~ '(customer success|customer support|support engineer|solutions engineer|implementation|technical account)' then 'support'
  when lower(title) ~ '(recruit|talent|people ops|people partner|\mhr\M|human resources)' then 'hr'
  when lower(title) ~ '(finance|accounting|controller|fp&a|treasury|payroll)' then 'finance'
  when lower(title) ~ '(legal|counsel|compliance|regulatory|paralegal)' then 'legal'
  when lower(title) ~ '(operations|\mops\M|chief of staff|office manager|executive assistant|logistics|supply chain)' then 'operations'
  else null
end::public.job_function
where source_kind in ('board','ats') and job_function is null;
