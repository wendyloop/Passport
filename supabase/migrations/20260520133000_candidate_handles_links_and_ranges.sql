alter table public.profiles
  add column if not exists handle_last_changed_at timestamptz,
  add column if not exists full_name_last_changed_at timestamptz;

create or replace function public.enforce_profile_handle_change_rules()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.full_name is distinct from old.full_name then
    if old.full_name is not null
       and old.full_name_last_changed_at is not null
       and old.full_name_last_changed_at > timezone('utc', now()) - interval '7 days' then
      raise exception 'Full name can only be changed once every 7 days.';
    end if;

    new.full_name_last_changed_at = timezone('utc', now());
  end if;

  if new.handle is distinct from old.handle then
    if old.handle is not null
       and old.handle_last_changed_at is not null
       and old.handle_last_changed_at > timezone('utc', now()) - interval '30 days' then
      raise exception 'Handle can only be changed once every 30 days.';
    end if;

    new.handle_last_changed_at = timezone('utc', now());
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_profile_handle_change_rules on public.profiles;
create trigger enforce_profile_handle_change_rules
before update on public.profiles
for each row execute function public.enforce_profile_handle_change_rules();

alter table public.job_seeker_profiles
  add column if not exists desired_compensation_range text,
  add column if not exists instagram_username text,
  add column if not exists tiktok_username text;

alter table public.job_seeker_profiles
  drop constraint if exists job_seeker_profiles_compensation_range_check;

update public.job_seeker_profiles
set desired_compensation_range = '$50k-$75k'
where desired_compensation_range = 'Under $75k';

alter table public.job_seeker_profiles
  add constraint job_seeker_profiles_compensation_range_check
  check (
    desired_compensation_range is null
    or desired_compensation_range in (
      'Under $50k',
      '$50k-$75k',
      '$75k-$100k',
      '$100k-$125k',
      '$125k-$150k',
      '$150k-$175k',
      '$175k-$200k',
      '$200k+'
    )
  );

alter table public.job_seeker_profiles
  drop constraint if exists job_seeker_profiles_instagram_username_format;

alter table public.job_seeker_profiles
  add constraint job_seeker_profiles_instagram_username_format
  check (
    instagram_username is null
    or instagram_username ~ '^[A-Za-z0-9._]{1,30}$'
  );

alter table public.job_seeker_profiles
  drop constraint if exists job_seeker_profiles_tiktok_username_format;

alter table public.job_seeker_profiles
  add constraint job_seeker_profiles_tiktok_username_format
  check (
    tiktok_username is null
    or tiktok_username ~ '^[A-Za-z0-9._]{1,24}$'
  );

alter table public.job_seeker_profiles
  drop constraint if exists job_seeker_profiles_linkedin_url_format;

alter table public.job_seeker_profiles
  add constraint job_seeker_profiles_linkedin_url_format
  check (
    linkedin_url is null
    or linkedin_url ~ '^https?://'
  );

alter table public.job_applications
  add column if not exists candidate_linkedin_url text,
  add column if not exists candidate_instagram_username text,
  add column if not exists candidate_tiktok_username text,
  add column if not exists candidate_compensation_range text;

drop view if exists public.employer_candidate_discovery;

create view public.employer_candidate_discovery
with (security_invoker = true)
as
select
  p.id as candidate_id,
  p.full_name,
  p.headline,
  p.handle,
  p.avatar_url,
  jsp.school_name,
  jsp.job_function,
  jsp.dream_role,
  jsp.discovery_visibility,
  jsp.linkedin_url,
  jsp.instagram_username,
  jsp.tiktok_username,
  jsp.desired_compensation_range,
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
  p.handle,
  p.avatar_url,
  jsp.school_name,
  jsp.job_function,
  jsp.dream_role,
  jsp.discovery_visibility,
  jsp.linkedin_url,
  jsp.instagram_username,
  jsp.tiktok_username,
  jsp.desired_compensation_range,
  cv.video_url;
