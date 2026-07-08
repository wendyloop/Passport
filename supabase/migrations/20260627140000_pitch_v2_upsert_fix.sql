-- Fix: upsert_board_jobs returned "column reference 'dedup_key' is ambiguous"
-- because the RETURNS TABLE column names (id, dedup_key, inserted) become
-- PL/pgSQL variables that shadow column references inside the inner SQL —
-- specifically the `on conflict (dedup_key)` target.
--
-- The fix is a one-line directive: `#variable_conflict use_column` tells
-- PL/pgSQL to resolve ambiguous names as columns inside embedded SQL, which
-- is exactly what we want here.

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
      title, location, employment_type,
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

grant execute on function public.upsert_board_jobs(jsonb) to service_role;
