-- Fair company picker for enrich-descriptions.
--
-- Previously the function pulled candidate company ids from `jobs` with a
-- limited overfetch and no ordering. Postgres returned the first matching
-- rows (effectively by UUID order), which always belonged to the big funds
-- (accel/general-catalyst/index) and starved the smaller Consider funds
-- (a16z, sequoia, nea, etc.) — they never made the pool.
--
-- This RPC inverts the query: start from `companies` ordered by
-- last_synced_at NULLS FIRST, filter to those with at least one pending
-- enrichable job. Result is a fair queue across all funds.

create or replace function public.get_stale_enrichable_companies(p_limit int)
returns table (
  id        uuid,
  name      text,
  ats_type  text,
  ats_token text
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.name, c.ats_type, c.ats_token
  from public.companies c
  where c.ats_type is not null
    and c.ats_token is not null
    and exists (
      select 1
      from public.jobs j
      where j.company_id  = c.id
        and j.ats_type    = c.ats_type
        and j.description is null
        and j.is_active   = true
    )
  order by c.last_synced_at asc nulls first
  limit p_limit;
$$;

revoke all on function public.get_stale_enrichable_companies(int) from public, anon, authenticated;
grant execute on function public.get_stale_enrichable_companies(int) to service_role;
