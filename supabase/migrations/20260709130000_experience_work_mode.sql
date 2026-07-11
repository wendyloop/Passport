-- Carousel v3 groundwork: experience_level + work_mode on jobs.
--
-- Research (LinkedIn/SHRM/Handshake, July 2026): salary, experience
-- requirements, and remote/hybrid status are the top decide-to-apply
-- signals — and Gen Z filters on them hard. Both columns are populated
-- three ways, mirroring job_function:
--   1. title/location keyword pass at ingest (shared title_classify.ts)
--   2. this migration's backfill for the existing catalog
--   3. generate-carousel's LLM, which reads the full JD and fills the
--      ~59% of jobs whose titles carry no level signal (fills nulls only)

alter table public.jobs
  add column if not exists experience_level text
    check (experience_level in ('intern','entry','mid','senior','staff','exec')),
  add column if not exists work_mode text
    check (work_mode in ('remote','hybrid','onsite'));

-- ── Backfill from titles/locations (keyword mirror of title_classify.ts) ──

update public.jobs set experience_level = case
  when lower(title) ~ '\mintern(ship)?s?\M|\mco-?op\M' then 'intern'
  when lower(title) ~ '\mjunior\M|\mjr\.?\M|entry.level|new grad|university grad|graduate program|graduate scheme|early.career|\mapprentice\M|\mtrainee\M' then 'entry'
  when lower(title) ~ '\mdirector\M|\mvp\M|vice president|head of|\mchief\M|\mc[tefo]o\M|\mpresident\M|founding' then 'exec'
  when lower(title) ~ '\mprincipal\M|\mstaff\M|distinguished|\marchitect\M|\mfellow\M' then 'staff'
  when lower(title) ~ '\msenior\M|\msr\.?\M|\mlead\M' then 'senior'
  else null
end
where source_kind in ('board','ats') and experience_level is null;

update public.jobs set work_mode = case
  when lower(coalesce(location,'')) ~ '\mhybrid\M' then 'hybrid'
  when lower(coalesce(location,'')) ~ '\mremote\M|work from home|\mwfh\M|\mdistributed\M' then 'remote'
  when lower(coalesce(location,'')) ~ '\mon-?site\M|in.office' then 'onsite'
  else null
end
where source_kind in ('board','ats') and work_mode is null;

-- ── upsert_board_jobs learns both columns (write-once like the rest) ──

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
      experience_level         text,
      work_mode                text,
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
      experience_level, work_mode,
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
      i.experience_level, i.work_mode,
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
