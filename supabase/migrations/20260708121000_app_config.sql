-- Server-side app configuration readable only via service role. A table
-- rather than an env var so limits can change without redeploying functions.

create table if not exists public.app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.app_config enable row level security;
-- No client policies: service-role only.

insert into public.app_config (key, value)
values ('founder_email_weekly_limit', '5'::jsonb)
on conflict (key) do nothing;
