do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'app_role'
      and e.enumlabel = 'admin'
  ) then
    alter type public.app_role add value 'admin';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'candidate_visibility') then
    create type public.candidate_visibility as enum (
      'private',
      'applied_roles_only',
      'discoverable_to_hiring_employers'
    );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'notification_type'
      and e.enumlabel = 'job_application_submitted'
  ) then
    alter type public.notification_type add value 'job_application_submitted';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'notification_type'
      and e.enumlabel = 'job_application_received'
  ) then
    alter type public.notification_type add value 'job_application_received';
  end if;
end $$;

alter table public.job_seeker_profiles
  add column if not exists dream_role text,
  add column if not exists discovery_visibility public.candidate_visibility not null default 'applied_roles_only';

create table if not exists public.jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  employer_profile_id uuid not null references public.employer_profiles(profile_id) on delete cascade,
  posted_by_profile_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  company_name text not null,
  location text,
  job_function public.job_function,
  description text not null,
  application_email extensions.citext not null,
  video_url text not null,
  source_url text,
  is_published boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.job_applications (
  id uuid primary key default extensions.gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  employer_profile_id uuid not null references public.employer_profiles(profile_id) on delete cascade,
  candidate_profile_id uuid not null references public.job_seeker_profiles(profile_id) on delete cascade,
  status text not null default 'submitted',
  cover_note text,
  job_title text not null,
  company_name text not null,
  job_location text,
  application_email extensions.citext not null,
  candidate_name text not null,
  candidate_headline text,
  candidate_school_name text,
  candidate_job_function public.job_function,
  candidate_dream_role text,
  candidate_previous_employers text[] not null default '{}'::text[],
  candidate_video_url text,
  resume_file_path text,
  resume_file_name text,
  email_delivery_status text not null default 'pending',
  email_delivery_error text,
  applied_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (job_id, candidate_profile_id)
);

create index if not exists jobs_employer_created_at_idx
  on public.jobs(employer_profile_id, created_at desc);

create index if not exists jobs_published_created_at_idx
  on public.jobs(is_published, created_at desc);

create index if not exists job_applications_candidate_applied_at_idx
  on public.job_applications(candidate_profile_id, applied_at desc);

create index if not exists job_applications_employer_applied_at_idx
  on public.job_applications(employer_profile_id, applied_at desc);

drop trigger if exists set_jobs_updated_at on public.jobs;
create trigger set_jobs_updated_at
before update on public.jobs
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_job_applications_updated_at on public.job_applications;
create trigger set_job_applications_updated_at
before update on public.job_applications
for each row execute function public.set_current_timestamp_updated_at();

alter table public.jobs enable row level security;
alter table public.job_applications enable row level security;

drop policy if exists "Jobs are visible by publication state or ownership" on public.jobs;
create policy "Jobs are visible by publication state or ownership"
on public.jobs
for select
to authenticated
using (
  is_published = true
  or auth.uid() = employer_profile_id
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  )
);

drop policy if exists "Jobs are mutable by admins" on public.jobs;
create policy "Jobs are mutable by admins"
on public.jobs
for all
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  )
);

drop policy if exists "Job applications are visible to participants and admins" on public.job_applications;
create policy "Job applications are visible to participants and admins"
on public.job_applications
for select
to authenticated
using (
  auth.uid() = candidate_profile_id
  or auth.uid() = employer_profile_id
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  )
);

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'storage'
      and table_name = 'buckets'
  ) and exists (
    select 1
    from information_schema.tables
    where table_schema = 'storage'
      and table_name = 'objects'
  ) then
    insert into storage.buckets (id, name, public)
    values ('job-videos', 'job-videos', true)
    on conflict (id) do nothing;

    execute 'drop policy if exists "Public read for job videos" on storage.objects';
    execute 'create policy "Public read for job videos" on storage.objects for select to authenticated using (bucket_id = ''job-videos'')';

    execute 'drop policy if exists "Job video uploads scoped to admin folder" on storage.objects';
    execute 'create policy "Job video uploads scoped to admin folder" on storage.objects for insert to authenticated with check (bucket_id = ''job-videos'' and (storage.foldername(name))[1] = auth.uid()::text and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = ''admin''))';
  else
    raise notice 'storage schema not present; skipping job video bucket and policy setup';
  end if;
end $$;
