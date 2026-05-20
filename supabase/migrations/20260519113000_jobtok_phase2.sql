do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'notification_type'
      and e.enumlabel = 'candidate_outreach_received'
  ) then
    alter type public.notification_type add value 'candidate_outreach_received';
  end if;
end $$;

create table if not exists public.candidate_outreach_messages (
  id uuid primary key default extensions.gen_random_uuid(),
  employer_profile_id uuid not null references public.employer_profiles(profile_id) on delete cascade,
  candidate_profile_id uuid not null references public.job_seeker_profiles(profile_id) on delete cascade,
  related_job_id uuid references public.jobs(id) on delete set null,
  subject text not null,
  body text not null,
  delivery_status text not null default 'pending',
  delivery_error text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists candidate_outreach_employer_created_at_idx
  on public.candidate_outreach_messages(employer_profile_id, created_at desc);

create index if not exists candidate_outreach_candidate_created_at_idx
  on public.candidate_outreach_messages(candidate_profile_id, created_at desc);

drop trigger if exists set_candidate_outreach_messages_updated_at on public.candidate_outreach_messages;
create trigger set_candidate_outreach_messages_updated_at
before update on public.candidate_outreach_messages
for each row execute function public.set_current_timestamp_updated_at();

create or replace view public.employer_candidate_discovery
with (security_invoker = true)
as
select
  p.id as candidate_id,
  p.full_name,
  p.headline,
  jsp.school_name,
  jsp.job_function,
  jsp.dream_role,
  jsp.discovery_visibility,
  coalesce(array_agg(distinct jse.employer_name) filter (where jse.employer_name is not null), '{}') as previous_employers,
  cv.video_url
from public.profiles p
join public.job_seeker_profiles jsp
  on jsp.profile_id = p.id
left join public.job_seeker_employers jse
  on jse.profile_id = p.id
left join lateral (
  select video_url
  from public.candidate_videos
  where profile_id = p.id
  order by created_at desc
  limit 1
) cv on true
where p.role = 'job_seeker'
  and p.onboarding_complete = true
  and jsp.discovery_visibility = 'discoverable_to_hiring_employers'
  and cv.video_url is not null
  and exists (
    select 1
    from public.profiles viewer
    where viewer.id = auth.uid()
      and viewer.role::text in ('employer', 'admin')
  )
group by
  p.id,
  p.full_name,
  p.headline,
  jsp.school_name,
  jsp.job_function,
  jsp.dream_role,
  jsp.discovery_visibility,
  cv.video_url;

alter table public.candidate_outreach_messages enable row level security;

drop policy if exists "Candidate outreach is visible to participants and admins" on public.candidate_outreach_messages;
create policy "Candidate outreach is visible to participants and admins"
on public.candidate_outreach_messages
for select
to authenticated
using (
  auth.uid() = employer_profile_id
  or auth.uid() = candidate_profile_id
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  )
);
