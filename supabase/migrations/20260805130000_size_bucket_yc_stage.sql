-- size_bucket blind spot: the 1-9 headcount rule only trusted an explicit
-- early funding stage, because Getro's head_count emits garbage small
-- integers for big companies ("Facebook, headcount 1"). WaaS writes a real
-- teamSize and a 'YC <batch>' stage, so YC rows with headcount 1-9 were
-- landing in NULL — losing exactly the under-10 startups the filter is for.
-- Only our WaaS adapter writes 'YC %', so it's a safe reliability proxy.
--
-- The function backs a stored generated column, so it has to be dropped and
-- re-added for existing rows to recompute.

alter table public.companies drop column if exists size_bucket;

create or replace function public.derive_company_size_bucket(p_stage text, p_headcount text)
returns text
language sql
immutable
as $$
  select case
    when p_stage = '1-10 employees' then 'under_10'
    when p_stage = '10-100 employees' then '10_100'
    when p_stage = '100-1000 employees' then '100_1000'
    when p_stage = '1000+ employees' then '1000_plus'
    when p_headcount ~ '^[0-9]+$' and p_headcount::int >= 1000 then '1000_plus'
    when p_headcount ~ '^[0-9]+$' and p_headcount::int >= 100 then '100_1000'
    when p_headcount ~ '^[0-9]+$' and p_headcount::int >= 10 then '10_100'
    when p_headcount ~ '^[0-9]+$' and p_headcount::int between 1 and 9
         and (p_stage like 'YC %'
              or p_stage in ('pre_seed', 'seed', 'series_unknown', 'undisclosed')) then 'under_10'
    when p_stage like 'YC %' then 'under_10'
    when p_stage in ('pre_seed', 'seed') then 'under_10'
    when p_stage in ('series_a', 'series_b') then '10_100'
    when p_stage in ('series_c', 'series_d') then '100_1000'
    when p_stage in ('series_e', 'series_f', 'series_g', 'series_h', 'series_j', 'ipo', 'private_equity') then '1000_plus'
    else null
  end
$$;
revoke all on function public.derive_company_size_bucket(text, text) from public, anon;
grant execute on function public.derive_company_size_bucket(text, text) to authenticated, service_role;

alter table public.companies
  add column size_bucket text
  generated always as (public.derive_company_size_bucket(stage, headcount)) stored;
