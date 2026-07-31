-- Company-size filter: derive a trustworthy bucket from the two half-good
-- signals we already extract. stage's explicit size labels win; numeric
-- headcount is trusted at >=10 (Consider reports true staff counts) but at
-- 1-9 only for early-stage companies (Getro's head_count field emits
-- garbage small integers for big companies — "Facebook, headcount 1");
-- funding stage approximates the rest. NULL = unknown, excluded from
-- specific size filters.

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
         and p_stage in ('pre_seed', 'seed', 'series_unknown', 'undisclosed') then 'under_10'
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
  add column if not exists size_bucket text
  generated always as (public.derive_company_size_bucket(stage, headcount)) stored;
