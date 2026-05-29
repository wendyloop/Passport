comment on table public.profiles is
  'Runtime user profile table. profiles.role is the effective role used by the app after signup.';

comment on column public.profiles.role is
  'Effective app role for this signed-in profile. This is what the app reads at runtime.';

comment on table public.profile_role_assignments is
  'Pre-signup role mapping by email. Used to pre-assign employer/admin access before a user account exists, then copied into profiles.role at signup and kept in sync afterward.';

comment on column public.profile_role_assignments.email is
  'Email-based lookup used before auth.users / profiles rows exist.';

comment on column public.profile_role_assignments.role is
  'Desired role for the matching email address. Copied into profiles.role by handle_new_user() and sync trigger.';

create or replace function public.admin_assign_profile_role(
  p_email extensions.citext,
  p_role public.app_role,
  p_notes text default null
)
returns public.profile_role_assignments
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_assignment public.profile_role_assignments;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  ) then
    raise exception 'Only admins can assign roles';
  end if;

  insert into public.profile_role_assignments (
    email,
    role,
    notes,
    assigned_by_profile_id
  )
  values (
    p_email,
    p_role,
    p_notes,
    auth.uid()
  )
  on conflict (email) do update
  set role = excluded.role,
      notes = excluded.notes,
      assigned_by_profile_id = auth.uid(),
      updated_at = timezone('utc', now())
  returning * into v_assignment;

  return v_assignment;
end;
$$;

create or replace function public.admin_clear_profile_role_assignment(
  p_email extensions.citext
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  ) then
    raise exception 'Only admins can clear role assignments';
  end if;

  delete from public.profile_role_assignments
  where email = p_email;

  update public.profiles
  set role = 'job_seeker'::public.app_role,
      onboarding_complete = false
  where email = p_email
    and role is distinct from 'job_seeker'::public.app_role;
end;
$$;

revoke all on function public.admin_assign_profile_role(extensions.citext, public.app_role, text) from public;
grant execute on function public.admin_assign_profile_role(extensions.citext, public.app_role, text) to authenticated;

revoke all on function public.admin_clear_profile_role_assignment(extensions.citext) from public;
grant execute on function public.admin_clear_profile_role_assignment(extensions.citext) to authenticated;
