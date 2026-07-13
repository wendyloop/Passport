-- DB-P1-3: discovery_visibility was only enforced by the
-- employer_candidate_discovery view (security_invoker), while the base-table
-- policies let ANY authenticated user — including every other job seeker —
-- read every onboarded candidate's profiles row (email!), job_seeker_profiles
-- row (phone, comp expectations, socials), employer history, and videos,
-- regardless of the candidate's visibility setting.
--
-- New shape: owner and admin always read; employers read only candidates who
-- are 'discoverable_to_hiring_employers', or non-private candidates who
-- applied to one of their jobs ('applied_roles_only' semantics). Other job
-- seekers read nothing but their own rows. The iOS clients never read another
-- candidate's base rows directly (feed = jobs/companies/carousels; employer
-- lists use application snapshot columns; discovery goes through the view,
-- which keeps working under these tighter policies).

-- Helper: role check that bypasses RLS (a profiles policy can't subquery
-- profiles directly — infinite recursion).
create or replace function public.auth_role_in(p_roles text[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role::text = any (p_roles)
  );
$$;
revoke all on function public.auth_role_in(text[]) from public, anon;
grant execute on function public.auth_role_in(text[]) to authenticated;

-- profiles: owner, admin, or employer gated by the candidate's visibility.
-- Job seekers can no longer read other job seekers' rows (email lives here).
drop policy if exists "Profiles are readable by owner or public job seekers" on public.profiles;
drop policy if exists "Profiles readable per discovery visibility" on public.profiles;
create policy "Profiles readable per discovery visibility"
on public.profiles
for select
to authenticated
using (
  auth.uid() = id
  or public.auth_role_in(array['admin'])
  or (
    public.auth_role_in(array['employer'])
    and exists (
      select 1 from public.job_seeker_profiles jsp
      where jsp.profile_id = profiles.id
        and (
          jsp.discovery_visibility = 'discoverable_to_hiring_employers'
          or (
            jsp.discovery_visibility <> 'private'
            and exists (
              select 1 from public.job_applications ja
              where ja.candidate_profile_id = profiles.id
                and ja.employer_profile_id = (select auth.uid())
            )
          )
        )
    )
  )
);

-- job_seeker_profiles: same gate, directly on the row's own visibility column.
drop policy if exists "Job seeker profiles readable by owner or public" on public.job_seeker_profiles;
drop policy if exists "Job seeker profiles readable per visibility" on public.job_seeker_profiles;
create policy "Job seeker profiles readable per visibility"
on public.job_seeker_profiles
for select
to authenticated
using (
  auth.uid() = profile_id
  or public.auth_role_in(array['admin'])
  or (
    public.auth_role_in(array['employer'])
    and (
      discovery_visibility = 'discoverable_to_hiring_employers'
      or (
        discovery_visibility <> 'private'
        and exists (
          select 1 from public.job_applications ja
          where ja.candidate_profile_id = job_seeker_profiles.profile_id
            and ja.employer_profile_id = (select auth.uid())
        )
      )
    )
  )
);

-- Same gate for the two satellite tables the discovery view joins.
drop policy if exists "Job seeker employers readable by owner or public" on public.job_seeker_employers;
drop policy if exists "Job seeker employers readable per visibility" on public.job_seeker_employers;
create policy "Job seeker employers readable per visibility"
on public.job_seeker_employers
for select
to authenticated
using (
  auth.uid() = profile_id
  or public.auth_role_in(array['admin'])
  or (
    public.auth_role_in(array['employer'])
    and exists (
      select 1 from public.job_seeker_profiles jsp
      where jsp.profile_id = job_seeker_employers.profile_id
        and (
          jsp.discovery_visibility = 'discoverable_to_hiring_employers'
          or (
            jsp.discovery_visibility <> 'private'
            and exists (
              select 1 from public.job_applications ja
              where ja.candidate_profile_id = job_seeker_employers.profile_id
                and ja.employer_profile_id = (select auth.uid())
            )
          )
        )
    )
  )
);

drop policy if exists "Candidate videos are readable by owner or public" on public.candidate_videos;
drop policy if exists "Candidate videos readable per visibility" on public.candidate_videos;
create policy "Candidate videos readable per visibility"
on public.candidate_videos
for select
to authenticated
using (
  auth.uid() = profile_id
  or public.auth_role_in(array['admin'])
  or (
    public.auth_role_in(array['employer'])
    and exists (
      select 1 from public.job_seeker_profiles jsp
      where jsp.profile_id = candidate_videos.profile_id
        and (
          jsp.discovery_visibility = 'discoverable_to_hiring_employers'
          or (
            jsp.discovery_visibility <> 'private'
            and exists (
              select 1 from public.job_applications ja
              where ja.candidate_profile_id = candidate_videos.profile_id
                and ja.employer_profile_id = (select auth.uid())
            )
          )
        )
    )
  )
);
