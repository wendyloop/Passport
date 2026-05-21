alter table public.jobs
  add column if not exists compensation_min_annual integer,
  add column if not exists compensation_max_annual integer;

alter table public.jobs
  drop constraint if exists jobs_compensation_nonnegative;

alter table public.jobs
  add constraint jobs_compensation_nonnegative
  check (
    (compensation_min_annual is null or compensation_min_annual >= 0)
    and (compensation_max_annual is null or compensation_max_annual >= 0)
    and (
      compensation_min_annual is null
      or compensation_max_annual is null
      or compensation_min_annual <= compensation_max_annual
    )
  );
