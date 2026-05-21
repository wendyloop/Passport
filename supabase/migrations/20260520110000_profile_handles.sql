alter table public.profiles
  add column if not exists handle text;

update public.profiles
set handle = lower(regexp_replace(coalesce(split_part(email::text, '@', 1), full_name, 'jobtokuser'), '[^a-zA-Z0-9_]+', '', 'g'))
where handle is null
  and email is not null;

create unique index if not exists profiles_handle_unique_idx
  on public.profiles(lower(handle))
  where handle is not null;

alter table public.profiles
  drop constraint if exists profiles_handle_format;

alter table public.profiles
  add constraint profiles_handle_format
  check (
    handle is null
    or (
      handle ~ '^[A-Za-z0-9_]{3,30}$'
      and handle = lower(handle)
    )
  );
