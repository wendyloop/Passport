alter table public.jobs
  add column if not exists compensation_min_hourly integer,
  add column if not exists compensation_max_hourly integer,
  add column if not exists employment_type text;

alter table public.jobs
  drop constraint if exists jobs_compensation_hourly_nonnegative;

alter table public.jobs
  add constraint jobs_compensation_hourly_nonnegative
  check (
    (compensation_min_hourly is null or compensation_min_hourly >= 0)
    and (compensation_max_hourly is null or compensation_max_hourly >= 0)
    and (
      compensation_min_hourly is null
      or compensation_max_hourly is null
      or compensation_min_hourly <= compensation_max_hourly
    )
  );

alter table public.jobs
  drop constraint if exists jobs_employment_type_check;

alter table public.jobs
  add constraint jobs_employment_type_check
  check (
    employment_type is null
    or employment_type in ('full_time', 'part_time', 'contract')
  );
