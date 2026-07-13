-- The 20260713122000 policies probed job_applications with plain subqueries.
-- job_applications' own select policy subqueries profiles (admin check),
-- which loops back into the new profiles→job_seeker_profiles→job_applications
-- chain: 42P17 "infinite recursion detected in policy" on every profiles/jsp
-- read. Caught by the REST verification harness before any client saw it.
--
-- Fix: probe job_applications through a SECURITY DEFINER helper (same
-- recursion-breaking pattern as auth_role_in), so job_applications' policies
-- never evaluate inside these policies.

create or replace function public.candidate_applied_to_employer(p_candidate_profile_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.job_applications ja
    where ja.candidate_profile_id = p_candidate_profile_id
      and ja.employer_profile_id = auth.uid()
  );
$$;
revoke all on function public.candidate_applied_to_employer(uuid) from public, anon;
grant execute on function public.candidate_applied_to_employer(uuid) to authenticated;

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
            and public.candidate_applied_to_employer(profiles.id)
          )
        )
    )
  )
);

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
        and public.candidate_applied_to_employer(profile_id)
      )
    )
  )
);

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
            and public.candidate_applied_to_employer(job_seeker_employers.profile_id)
          )
        )
    )
  )
);

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
            and public.candidate_applied_to_employer(candidate_videos.profile_id)
          )
        )
    )
  )
);
