alter table public.profiles
  alter column role set default 'job_seeker';

update public.profiles
set role = 'job_seeker'
where role is null;

alter table public.profiles
  alter column role set not null;

create table if not exists public.profile_role_assignments (
  email extensions.citext primary key,
  role public.app_role not null,
  notes text,
  assigned_by_profile_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists profile_role_assignments_role_idx
  on public.profile_role_assignments(role);

drop trigger if exists set_profile_role_assignments_updated_at on public.profile_role_assignments;
create trigger set_profile_role_assignments_updated_at
before update on public.profile_role_assignments
for each row execute function public.set_current_timestamp_updated_at();

create or replace function public.resolve_profile_role(p_email extensions.citext)
returns public.app_role
language sql
stable
set search_path = public, extensions
as $$
  select coalesce(
    (
      select pra.role
      from public.profile_role_assignments pra
      where pra.email = p_email
    ),
    'job_seeker'::public.app_role
  );
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
    public.resolve_profile_role(new.email)
  )
  on conflict (id) do update
  set email = excluded.email,
      role = public.resolve_profile_role(excluded.email);

  return new;
end;
$$;

create or replace function public.sync_profile_role_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.profiles
  set role = new.role,
      onboarding_complete = case
        when role is distinct from new.role then false
        else onboarding_complete
      end
  where email = new.email;

  return new;
end;
$$;

drop trigger if exists sync_profile_role_assignment_after_write on public.profile_role_assignments;
create trigger sync_profile_role_assignment_after_write
after insert or update on public.profile_role_assignments
for each row execute function public.sync_profile_role_assignment();

create or replace function public.prevent_client_profile_role_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and new.role is distinct from old.role
     and not exists (
       select 1
       from public.profiles p
       where p.id = auth.uid()
         and p.role::text = 'admin'
     ) then
    raise exception 'Profile roles are managed in the backend';
  end if;

  return new;
end;
$$;

drop trigger if exists prevent_client_profile_role_changes_before_update on public.profiles;
create trigger prevent_client_profile_role_changes_before_update
before update on public.profiles
for each row execute function public.prevent_client_profile_role_changes();

alter table public.profile_role_assignments enable row level security;

drop policy if exists "Role assignments are visible to admins" on public.profile_role_assignments;
create policy "Role assignments are visible to admins"
on public.profile_role_assignments
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  )
);

drop policy if exists "Role assignments are mutable by admins" on public.profile_role_assignments;
create policy "Role assignments are mutable by admins"
on public.profile_role_assignments
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
