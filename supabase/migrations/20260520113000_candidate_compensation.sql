alter table public.job_seeker_profiles
  add column if not exists desired_compensation_annual integer;

alter table public.job_seeker_profiles
  drop constraint if exists job_seeker_profiles_desired_compensation_nonnegative;

alter table public.job_seeker_profiles
  add constraint job_seeker_profiles_desired_compensation_nonnegative
  check (
    desired_compensation_annual is null
    or desired_compensation_annual >= 0
  );
