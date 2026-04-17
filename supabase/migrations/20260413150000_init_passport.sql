create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum ('job_seeker', 'employer');
  end if;

  if not exists (select 1 from pg_type where typname = 'job_function') then
    create type public.job_function as enum (
      'engineering',
      'design',
      'product',
      'science',
      'sales',
      'marketing',
      'support',
      'operations',
      'hr',
      'finance',
      'legal'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'interview_request_status') then
    create type public.interview_request_status as enum (
      'pending_candidate_selection',
      'pending_employer_approval',
      'approved',
      'declined',
      'cancelled'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'slot_status') then
    create type public.slot_status as enum ('open', 'reserved', 'booked', 'blocked');
  end if;

  if not exists (select 1 from pg_type where typname = 'invite_status') then
    create type public.invite_status as enum ('issued', 'used', 'expired');
  end if;

  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type public.notification_type as enum (
      'interview_request_created',
      'slot_selected',
      'interview_approved',
      'interview_declined',
      'referral_invite_issued',
      'referral_invite_used',
      'calendar_sync_needed'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'resume_parse_status') then
    create type public.resume_parse_status as enum (
      'pending',
      'parsed',
      'failed',
      'pending_manual_review'
    );
  end if;
end $$;

create or replace function public.set_current_timestamp_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role,
  full_name text,
  email extensions.citext unique,
  avatar_url text,
  headline text,
  onboarding_complete boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.employer_profiles (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  company_name text,
  company_domain extensions.citext,
  position_title text,
  calendar_connected boolean not null default false,
  monthly_referral_limit integer not null default 5 check (monthly_referral_limit > 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.referral_invites (
  id uuid primary key default extensions.gen_random_uuid(),
  employer_profile_id uuid not null references public.employer_profiles(profile_id) on delete cascade,
  token text not null unique default encode(extensions.gen_random_bytes(18), 'hex'),
  email extensions.citext,
  status public.invite_status not null default 'issued',
  expires_at timestamptz not null default timezone('utc', now()) + interval '30 days',
  used_by_profile_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.job_seeker_profiles (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  school_name text,
  job_function public.job_function,
  referral_badge boolean not null default false,
  referral_invite_id uuid references public.referral_invites(id) on delete set null,
  intro_video_url text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.job_seeker_employers (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references public.job_seeker_profiles(profile_id) on delete cascade,
  employer_name text not null,
  sort_order integer not null default 1,
  created_at timestamptz not null default timezone('utc', now()),
  unique (profile_id, employer_name)
);

create table if not exists public.resume_uploads (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  file_path text not null,
  parse_status public.resume_parse_status not null default 'pending',
  parsed_school_name text,
  parsed_employers jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.candidate_videos (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  video_url text not null,
  poster_url text,
  duration_seconds integer,
  status text not null default 'ready',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (profile_id, video_url)
);

create table if not exists public.calendar_connections (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  provider text not null default 'google',
  access_token text,
  refresh_token text,
  token_expires_at timestamptz,
  scopes text[] not null default '{}'::text[],
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.candidate_likes (
  id uuid primary key default extensions.gen_random_uuid(),
  employer_profile_id uuid not null references public.employer_profiles(profile_id) on delete cascade,
  candidate_profile_id uuid not null references public.job_seeker_profiles(profile_id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  unique (employer_profile_id, candidate_profile_id)
);

create table if not exists public.availability_slots (
  id uuid primary key default extensions.gen_random_uuid(),
  employer_profile_id uuid not null references public.employer_profiles(profile_id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  slot_status public.slot_status not null default 'open',
  source text not null default 'manual',
  google_event_id text,
  reserved_by_profile_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (end_at > start_at)
);

create table if not exists public.interview_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  employer_profile_id uuid not null references public.employer_profiles(profile_id) on delete cascade,
  candidate_profile_id uuid not null references public.job_seeker_profiles(profile_id) on delete cascade,
  status public.interview_request_status not null default 'pending_candidate_selection',
  availability_slot_id uuid references public.availability_slots(id) on delete set null,
  requested_at timestamptz not null default timezone('utc', now()),
  candidate_selected_at timestamptz,
  approved_at timestamptz,
  declined_at timestamptz,
  calendar_event_id text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (employer_profile_id, candidate_profile_id)
);

create table if not exists public.notifications (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  type public.notification_type not null,
  title text not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists profiles_role_idx on public.profiles(role);
create index if not exists notifications_profile_id_created_at_idx on public.notifications(profile_id, created_at desc);
create index if not exists interview_requests_candidate_status_idx on public.interview_requests(candidate_profile_id, status);
create index if not exists interview_requests_employer_status_idx on public.interview_requests(employer_profile_id, status);
create index if not exists availability_slots_employer_start_at_idx on public.availability_slots(employer_profile_id, start_at);
create index if not exists referral_invites_employer_created_at_idx on public.referral_invites(employer_profile_id, created_at desc);

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_employer_profiles_updated_at on public.employer_profiles;
create trigger set_employer_profiles_updated_at
before update on public.employer_profiles
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_referral_invites_updated_at on public.referral_invites;
create trigger set_referral_invites_updated_at
before update on public.referral_invites
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_job_seeker_profiles_updated_at on public.job_seeker_profiles;
create trigger set_job_seeker_profiles_updated_at
before update on public.job_seeker_profiles
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_resume_uploads_updated_at on public.resume_uploads;
create trigger set_resume_uploads_updated_at
before update on public.resume_uploads
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_candidate_videos_updated_at on public.candidate_videos;
create trigger set_candidate_videos_updated_at
before update on public.candidate_videos
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_calendar_connections_updated_at on public.calendar_connections;
create trigger set_calendar_connections_updated_at
before update on public.calendar_connections
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_availability_slots_updated_at on public.availability_slots;
create trigger set_availability_slots_updated_at
before update on public.availability_slots
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_interview_requests_updated_at on public.interview_requests;
create trigger set_interview_requests_updated_at
before update on public.interview_requests
for each row execute function public.set_current_timestamp_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')
  )
  on conflict (id) do update
  set email = excluded.email;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.issue_referral_invite(p_email extensions.citext default null)
returns public.referral_invites
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid := auth.uid();
  v_limit integer;
  v_count integer;
  v_row public.referral_invites;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_user_id
      and p.role = 'employer'
  ) then
    raise exception 'Only employers can issue referral invites';
  end if;

  select monthly_referral_limit
  into v_limit
  from public.employer_profiles
  where profile_id = v_user_id;

  if v_limit is null then
    raise exception 'Employer profile is incomplete';
  end if;

  select count(*)
  into v_count
  from public.referral_invites
  where employer_profile_id = v_user_id
    and date_trunc('month', created_at) = date_trunc('month', timezone('utc', now()));

  if v_count >= v_limit then
    raise exception 'Monthly referral limit reached';
  end if;

  insert into public.referral_invites (employer_profile_id, email)
  values (v_user_id, p_email)
  returning * into v_row;

  insert into public.notifications (profile_id, type, title, body, metadata)
  values (
    v_user_id,
    'referral_invite_issued',
    'Referral invite created',
    'You created a new referral invite.',
    jsonb_build_object('invite_id', v_row.id, 'token', v_row.token)
  );

  return v_row;
end;
$$;

create or replace function public.consume_referral_invite(p_token text)
returns public.referral_invites
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.referral_invites;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_row
  from public.referral_invites
  where token = p_token
    and status = 'issued'
    and expires_at > timezone('utc', now())
  limit 1;

  if v_row.id is null then
    raise exception 'Referral invite is invalid or expired';
  end if;

  update public.referral_invites
  set status = 'used',
      used_by_profile_id = v_user_id
  where id = v_row.id;

  insert into public.job_seeker_profiles (profile_id, referral_badge, referral_invite_id)
  values (v_user_id, true, v_row.id)
  on conflict (profile_id) do update
  set referral_badge = true,
      referral_invite_id = excluded.referral_invite_id;

  insert into public.notifications (profile_id, type, title, body, metadata)
  values (
    v_row.employer_profile_id,
    'referral_invite_used',
    'Referral invite accepted',
    'A referred job seeker used one of your Passport invites.',
    jsonb_build_object('invite_id', v_row.id, 'candidate_profile_id', v_user_id)
  );

  select * into v_row from public.referral_invites where id = v_row.id;
  return v_row;
end;
$$;

create or replace function public.like_candidate(p_candidate_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_user_id and role = 'employer'
  ) then
    raise exception 'Only employers can like candidates';
  end if;

  insert into public.candidate_likes (employer_profile_id, candidate_profile_id)
  values (v_user_id, p_candidate_profile_id)
  on conflict (employer_profile_id, candidate_profile_id) do nothing;

  insert into public.interview_requests (employer_profile_id, candidate_profile_id)
  values (v_user_id, p_candidate_profile_id)
  on conflict (employer_profile_id, candidate_profile_id) do nothing;

  select id
  into v_request_id
  from public.interview_requests
  where employer_profile_id = v_user_id
    and candidate_profile_id = p_candidate_profile_id;

  insert into public.notifications (profile_id, type, title, body, metadata)
  values (
    p_candidate_profile_id,
    'interview_request_created',
    'New interview request',
    'An employer liked your profile and invited you to choose an interview time.',
    jsonb_build_object('request_id', v_request_id, 'employer_profile_id', v_user_id)
  )
  on conflict do nothing;

  return v_request_id;
end;
$$;

create or replace function public.select_interview_slot(p_request_id uuid, p_slot_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_request public.interview_requests;
  v_slot public.availability_slots;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_request
  from public.interview_requests
  where id = p_request_id
    and candidate_profile_id = v_user_id;

  if v_request.id is null then
    raise exception 'Interview request not found';
  end if;

  update public.availability_slots
  set slot_status = 'reserved',
      reserved_by_profile_id = v_user_id
  where id = p_slot_id
    and slot_status = 'open'
  returning * into v_slot;

  if v_slot.id is null then
    raise exception 'Availability slot is not open';
  end if;

  if v_slot.employer_profile_id <> v_request.employer_profile_id then
    raise exception 'Availability slot does not belong to the employer on this request';
  end if;

  update public.interview_requests
  set availability_slot_id = p_slot_id,
      status = 'pending_employer_approval',
      candidate_selected_at = timezone('utc', now())
  where id = p_request_id;

  insert into public.notifications (profile_id, type, title, body, metadata)
  values (
    v_request.employer_profile_id,
    'slot_selected',
    'Candidate selected a time',
    'A candidate chose one of your open interview slots and is waiting for approval.',
    jsonb_build_object('request_id', p_request_id, 'slot_id', p_slot_id)
  );

  return p_request_id;
end;
$$;

create or replace function public.respond_to_interview_request(p_request_id uuid, p_approved boolean)
returns public.interview_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_request public.interview_requests;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_request
  from public.interview_requests
  where id = p_request_id
    and employer_profile_id = v_user_id;

  if v_request.id is null then
    raise exception 'Interview request not found';
  end if;

  if p_approved then
    if v_request.availability_slot_id is null then
      raise exception 'Interview request has no selected slot';
    end if;

    update public.interview_requests
    set status = 'approved',
        approved_at = timezone('utc', now())
    where id = p_request_id
    returning * into v_request;

    update public.availability_slots
    set slot_status = 'booked'
    where id = v_request.availability_slot_id;

    insert into public.notifications (profile_id, type, title, body, metadata)
    values (
      v_request.candidate_profile_id,
      'interview_approved',
      'Interview approved',
      'Your selected interview time was approved by the employer.',
      jsonb_build_object('request_id', p_request_id, 'slot_id', v_request.availability_slot_id)
    );
  else
    update public.interview_requests
    set status = 'declined',
        declined_at = timezone('utc', now())
    where id = p_request_id
    returning * into v_request;

    if v_request.availability_slot_id is not null then
      update public.availability_slots
      set slot_status = 'open',
          reserved_by_profile_id = null
      where id = v_request.availability_slot_id;
    end if;

    insert into public.notifications (profile_id, type, title, body, metadata)
    values (
      v_request.candidate_profile_id,
      'interview_declined',
      'Interview declined',
      'The employer declined the selected interview slot. You can choose another time if they reopen availability.',
      jsonb_build_object('request_id', p_request_id)
    );
  end if;

  return v_request;
end;
$$;

create or replace function public.mark_notifications_read(p_notification_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  update public.notifications
  set read_at = timezone('utc', now())
  where profile_id = v_user_id
    and read_at is null
    and (p_notification_ids is null or id = any (p_notification_ids));

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace view public.candidate_feed
with (security_invoker = true)
as
select
  p.id as candidate_id,
  p.full_name,
  p.headline,
  jsp.school_name,
  jsp.job_function,
  jsp.referral_badge,
  coalesce(array_agg(distinct jse.employer_name) filter (where jse.employer_name is not null), '{}') as previous_employers,
  cv.video_url,
  cv.poster_url
from public.profiles p
join public.job_seeker_profiles jsp
  on jsp.profile_id = p.id
left join public.job_seeker_employers jse
  on jse.profile_id = p.id
left join lateral (
  select video_url, poster_url
  from public.candidate_videos
  where profile_id = p.id
  order by created_at desc
  limit 1
) cv on true
where p.role = 'job_seeker'
  and p.onboarding_complete = true
  and cv.video_url is not null
group by
  p.id,
  p.full_name,
  p.headline,
  jsp.school_name,
  jsp.job_function,
  jsp.referral_badge,
  cv.video_url,
  cv.poster_url;

alter table public.profiles enable row level security;
alter table public.employer_profiles enable row level security;
alter table public.referral_invites enable row level security;
alter table public.job_seeker_profiles enable row level security;
alter table public.job_seeker_employers enable row level security;
alter table public.resume_uploads enable row level security;
alter table public.candidate_videos enable row level security;
alter table public.calendar_connections enable row level security;
alter table public.candidate_likes enable row level security;
alter table public.availability_slots enable row level security;
alter table public.interview_requests enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "Profiles are readable by owner or public job seekers" on public.profiles;
create policy "Profiles are readable by owner or public job seekers"
on public.profiles
for select
to authenticated
using (
  auth.uid() = id
  or (role = 'job_seeker' and onboarding_complete = true)
);

drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "Employer profiles are readable by owner" on public.employer_profiles;
create policy "Employer profiles are readable by owner"
on public.employer_profiles
for select
to authenticated
using (auth.uid() = profile_id);

drop policy if exists "Employer profiles are mutable by owner" on public.employer_profiles;
create policy "Employer profiles are mutable by owner"
on public.employer_profiles
for all
to authenticated
using (auth.uid() = profile_id)
with check (auth.uid() = profile_id);

drop policy if exists "Referral invites visible to employer or recipient" on public.referral_invites;
create policy "Referral invites visible to employer or recipient"
on public.referral_invites
for select
to authenticated
using (auth.uid() = employer_profile_id or auth.uid() = used_by_profile_id);

drop policy if exists "Job seeker profiles readable by owner or public" on public.job_seeker_profiles;
create policy "Job seeker profiles readable by owner or public"
on public.job_seeker_profiles
for select
to authenticated
using (
  auth.uid() = profile_id
  or exists (
    select 1
    from public.profiles p
    where p.id = job_seeker_profiles.profile_id
      and p.role = 'job_seeker'
      and p.onboarding_complete = true
  )
);

drop policy if exists "Job seeker profiles mutable by owner" on public.job_seeker_profiles;
create policy "Job seeker profiles mutable by owner"
on public.job_seeker_profiles
for all
to authenticated
using (auth.uid() = profile_id)
with check (auth.uid() = profile_id);

drop policy if exists "Job seeker employers readable by owner or public" on public.job_seeker_employers;
create policy "Job seeker employers readable by owner or public"
on public.job_seeker_employers
for select
to authenticated
using (
  auth.uid() = profile_id
  or exists (
    select 1
    from public.profiles p
    where p.id = job_seeker_employers.profile_id
      and p.role = 'job_seeker'
      and p.onboarding_complete = true
  )
);

drop policy if exists "Job seeker employers mutable by owner" on public.job_seeker_employers;
create policy "Job seeker employers mutable by owner"
on public.job_seeker_employers
for all
to authenticated
using (auth.uid() = profile_id)
with check (auth.uid() = profile_id);

drop policy if exists "Resume uploads are visible to owner" on public.resume_uploads;
create policy "Resume uploads are visible to owner"
on public.resume_uploads
for select
to authenticated
using (auth.uid() = profile_id);

drop policy if exists "Resume uploads are mutable by owner" on public.resume_uploads;
create policy "Resume uploads are mutable by owner"
on public.resume_uploads
for all
to authenticated
using (auth.uid() = profile_id)
with check (auth.uid() = profile_id);

drop policy if exists "Candidate videos are readable by owner or public" on public.candidate_videos;
create policy "Candidate videos are readable by owner or public"
on public.candidate_videos
for select
to authenticated
using (
  auth.uid() = profile_id
  or exists (
    select 1
    from public.profiles p
    where p.id = candidate_videos.profile_id
      and p.role = 'job_seeker'
      and p.onboarding_complete = true
  )
);

drop policy if exists "Candidate videos are mutable by owner" on public.candidate_videos;
create policy "Candidate videos are mutable by owner"
on public.candidate_videos
for all
to authenticated
using (auth.uid() = profile_id)
with check (auth.uid() = profile_id);

drop policy if exists "Calendar connections are visible to owner" on public.calendar_connections;
create policy "Calendar connections are visible to owner"
on public.calendar_connections
for select
to authenticated
using (auth.uid() = profile_id);

drop policy if exists "Calendar connections are mutable by owner" on public.calendar_connections;
create policy "Calendar connections are mutable by owner"
on public.calendar_connections
for all
to authenticated
using (auth.uid() = profile_id)
with check (auth.uid() = profile_id);

drop policy if exists "Candidate likes belong to employer owner" on public.candidate_likes;
create policy "Candidate likes belong to employer owner"
on public.candidate_likes
for all
to authenticated
using (auth.uid() = employer_profile_id)
with check (auth.uid() = employer_profile_id);

drop policy if exists "Availability slots are visible to participants" on public.availability_slots;
create policy "Availability slots are visible to participants"
on public.availability_slots
for select
to authenticated
using (
  auth.uid() = employer_profile_id
  or exists (
    select 1
    from public.interview_requests ir
    where ir.employer_profile_id = availability_slots.employer_profile_id
      and ir.candidate_profile_id = auth.uid()
  )
);

drop policy if exists "Availability slots are mutable by employer owner" on public.availability_slots;
create policy "Availability slots are mutable by employer owner"
on public.availability_slots
for all
to authenticated
using (auth.uid() = employer_profile_id)
with check (auth.uid() = employer_profile_id);

drop policy if exists "Interview requests are visible to participants" on public.interview_requests;
create policy "Interview requests are visible to participants"
on public.interview_requests
for select
to authenticated
using (
  auth.uid() = employer_profile_id
  or auth.uid() = candidate_profile_id
);

drop policy if exists "Notifications are visible to owner" on public.notifications;
create policy "Notifications are visible to owner"
on public.notifications
for select
to authenticated
using (auth.uid() = profile_id);

drop policy if exists "Notifications are mutable by owner" on public.notifications;
create policy "Notifications are mutable by owner"
on public.notifications
for update
to authenticated
using (auth.uid() = profile_id)
with check (auth.uid() = profile_id);

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('videos', 'videos', true),
  ('resumes', 'resumes', false)
on conflict (id) do nothing;

drop policy if exists "Public read for avatars" on storage.objects;
create policy "Public read for avatars"
on storage.objects
for select
to authenticated
using (bucket_id = 'avatars');

drop policy if exists "Public read for videos" on storage.objects;
create policy "Public read for videos"
on storage.objects
for select
to authenticated
using (bucket_id = 'videos');

drop policy if exists "Private read for resumes by owner" on storage.objects;
create policy "Private read for resumes by owner"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'resumes'
  and owner = auth.uid()
);

drop policy if exists "Avatar uploads scoped to owner folder" on storage.objects;
create policy "Avatar uploads scoped to owner folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Video uploads scoped to owner folder" on storage.objects;
create policy "Video uploads scoped to owner folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'videos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Resume uploads scoped to owner folder" on storage.objects;
create policy "Resume uploads scoped to owner folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'resumes'
  and (storage.foldername(name))[1] = auth.uid()::text
);
