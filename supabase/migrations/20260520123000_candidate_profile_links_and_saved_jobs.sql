alter table public.job_seeker_profiles
  add column if not exists linkedin_url text,
  add column if not exists professional_social_url text;

create table if not exists public.saved_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references public.job_seeker_profiles(profile_id) on delete cascade,
  job_id uuid not null references public.jobs(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  unique (profile_id, job_id)
);

create index if not exists saved_jobs_profile_created_at_idx
  on public.saved_jobs(profile_id, created_at desc);

create index if not exists saved_jobs_job_idx
  on public.saved_jobs(job_id);

alter table public.saved_jobs enable row level security;

drop policy if exists "Saved jobs visible by owner" on public.saved_jobs;
create policy "Saved jobs visible by owner"
on public.saved_jobs
for select
to authenticated
using (auth.uid() = profile_id);

drop policy if exists "Saved jobs mutable by owner" on public.saved_jobs;
create policy "Saved jobs mutable by owner"
on public.saved_jobs
for all
to authenticated
using (auth.uid() = profile_id)
with check (auth.uid() = profile_id);
