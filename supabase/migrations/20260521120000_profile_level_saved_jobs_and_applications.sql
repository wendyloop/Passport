alter table public.saved_jobs
  drop constraint if exists saved_jobs_profile_id_fkey;

alter table public.saved_jobs
  add constraint saved_jobs_profile_id_fkey
  foreign key (profile_id) references public.profiles(id) on delete cascade;

alter table public.job_applications
  drop constraint if exists job_applications_candidate_profile_id_fkey;

alter table public.job_applications
  add constraint job_applications_candidate_profile_id_fkey
  foreign key (candidate_profile_id) references public.profiles(id) on delete cascade;
