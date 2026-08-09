-- Work at a Startup (YC's official job board) as a first-class board source.
--
-- Unlike Getro/Consider, WaaS hands us the full job description at ingest
-- time (its pages embed a JSON blob), so these jobs are carousel-ready
-- immediately and never enter the enrich-descriptions queue. It also gives
-- founder names per company, which feed the existing contact pipeline —
-- hence the new 'yc_directory' contact source.

-- 1) Board ingest can now carry descriptions.
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
      description              text,
      description_raw          text,
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
      description, description_raw,
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
      i.description, i.description_raw,
      true, true,
      i.now_ts, i.now_ts
    from input i
    on conflict (dedup_key) do update set
      last_seen_at = excluded.last_seen_at,
      is_active    = true,
      closed_at    = null,
      -- Write-once for content, same posture as the rest of this RPC: only
      -- fill a description we don't already have. Re-ingests never clobber
      -- an enriched body, and updated_at stays content-driven (DB-P1-5).
      description     = coalesce(j.description, excluded.description),
      description_raw = coalesce(j.description_raw, excluded.description_raw)
    returning j.id, j.dedup_key, (j.xmax = 0) as inserted
  )
  select u.id, u.dedup_key, u.inserted from upserted u;
end;
$$;

revoke all on function public.upsert_board_jobs(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_board_jobs(jsonb) to service_role;

-- 2) Founders scraped from the YC directory are their own contact tier.
alter table public.company_contacts
  drop constraint if exists company_contacts_source_check;
alter table public.company_contacts
  add constraint company_contacts_source_check
  check (source in ('llm_job_listing', 'llm_scrape', 'posting_email', 'manual', 'yc_directory'));

-- 3) New board platform.
alter table public.funds drop constraint if exists funds_platform_check;
alter table public.funds
  add constraint funds_platform_check
  check (platform in ('getro', 'consider', 'bespoke', 'workatastartup'));

-- 4) The fund row ingest-jobs drives. board_url is the WaaS origin;
--    external_collection_id points at the public YC company index the
--    adapter enumerates (yc-oss, refreshed daily, no key required).
insert into public.funds (name, slug, board_url, platform, external_collection_id)
values (
  'Y Combinator',
  'ycombinator',
  'https://www.workatastartup.com',
  'workatastartup',
  'https://yc-oss.github.io/api/companies/hiring.json'
)
on conflict (slug) do update set
  board_url               = excluded.board_url,
  platform                = excluded.platform,
  external_collection_id  = excluded.external_collection_id;
