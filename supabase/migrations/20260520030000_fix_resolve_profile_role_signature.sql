create or replace function public.resolve_profile_role(p_email text)
returns public.app_role
language sql
stable
set search_path = public, extensions
as $$
  select coalesce(
    (
      select pra.role
      from public.profile_role_assignments pra
      where pra.email = p_email::extensions.citext
    ),
    'job_seeker'::public.app_role
  );
$$;

create or replace function public.resolve_profile_role(p_email extensions.citext)
returns public.app_role
language sql
stable
set search_path = public, extensions
as $$
  select public.resolve_profile_role(p_email::text);
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    public.resolve_profile_role(new.email::text)
  )
  on conflict (id) do update
  set email = excluded.email,
      role = public.resolve_profile_role(excluded.email::text);

  return new;
end;
$$;
