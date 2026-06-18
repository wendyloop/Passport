-- Pitch v1 — VC-portfolio ATS-job ingestion pipeline
--
-- Adds:
--   * funds, companies, company_funds — discovery layer (weekly roster crawl)
--   * jobs.source_kind — explicit 'employer_post' | 'reel' | 'ats' marker
--   * jobs.company_id + ATS metadata + lifecycle timestamps (first/last_seen, closed_at)
--   * Partial unique (source_ats, external_id) for idempotent ATS upserts
--   * compensation_text raw string alongside existing structured fields
--   * Seed of 12 confirmed funds
--
-- Fixes:
--   * job_applications.employer_profile_id → nullable (scraped reels have no employer)
--   * application_events.event_type → enum (was TEXT CHECK)
--
-- Cleanup:
--   * Drop unused job_seeker_profiles.professional_social_url
--   * Drop legacy enums interview_request_status, slot_status, invite_status
--
-- Indexes added for known hot paths.

-- ============================================================================
-- 1. Discovery layer: funds, companies, company_funds
-- ============================================================================

create table if not exists public.funds (
  id          uuid primary key default extensions.gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  board_url   text,
  platform    text check (platform in ('getro', 'consider', 'bespoke')),
  created_at  timestamptz not null default timezone('utc', now())
);

create table if not exists public.companies (
  id            uuid primary key default extensions.gen_random_uuid(),
  name          text not null,
  domain        text unique,
  ats_type      text check (ats_type in ('greenhouse', 'lever', 'ashby', 'smartrecruiters', 'recruitee')),
  ats_token     text,
  stage         text,
  headcount     text,
  industry      text,
  logo_url      text,
  source_board  text,
  first_seen_at timestamptz not null default timezone('utc', now()),
  last_seen_at  timestamptz not null default timezone('utc', now())
);

create unique index if not exists companies_ats_unique
  on public.companies (ats_type, ats_token)
  where ats_type is not null and ats_token is not null;

create table if not exists public.company_funds (
  company_id uuid not null references public.companies(id) on delete cascade,
  fund_id    uuid not null references public.funds(id) on delete cascade,
  primary key (company_id, fund_id)
);

-- ============================================================================
-- 2. Extend jobs for ATS ingestion + explicit source_kind marker
-- ============================================================================

alter table public.jobs
  add column if not exists company_id        uuid references public.companies(id) on delete set null,
  add column if not exists source_kind       text,
  add column if not exists source_ats        text check (source_ats in ('greenhouse', 'lever', 'ashby', 'smartrecruiters', 'recruitee')),
  add column if not exists external_id       text,
  add column if not exists apply_flow        text check (apply_flow in ('ats_form', 'external_link', 'message')),
  add column if not exists content_hash      text,
  add column if not exists compensation_text text,
  add column if not exists first_seen_at     timestamptz not null default timezone('utc', now()),
  add column if not exists last_seen_at      timestamptz not null default timezone('utc', now()),
  add column if not exists closed_at         timestamptz;

-- Backfill source_kind for existing rows:
--   * source_platform set → reel (TikTok/Instagram import)
--   * else → employer_post (admin- or employer-created)
update public.jobs
  set source_kind = case
    when source_platform is not null then 'reel'
    else 'employer_post'
  end
  where source_kind is null;

alter table public.jobs
  alter column source_kind set not null,
  add constraint jobs_source_kind_check
    check (source_kind in ('employer_post', 'reel', 'ats'));

-- ATS jobs are uniquely identified by (provider, provider-id). Partial index
-- lets reel + employer_post rows coexist without filling these columns.
create unique index if not exists jobs_ats_external_unique
  on public.jobs (source_ats, external_id)
  where source_ats is not null and external_id is not null;

create index if not exists jobs_company_id_idx
  on public.jobs (company_id);

create index if not exists jobs_is_active_last_seen_idx
  on public.jobs (is_active, last_seen_at desc);

-- ============================================================================
-- 3. Fix: scraped-reel applies fail because job_applications.employer_profile_id
--    is NOT NULL. Drop the constraint; RLS already returns false for the
--    employer-equality clause when the column is null, so no policy change
--    needed.
-- ============================================================================

alter table public.job_applications
  alter column employer_profile_id drop not null;

-- ============================================================================
-- 4. Promote application_events.event_type from TEXT CHECK to enum
-- ============================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'application_event_type') then
    create type public.application_event_type as enum ('opened', 'submitted');
  end if;
end$$;

alter table public.application_events
  drop constraint if exists application_events_event_type_check;

alter table public.application_events
  alter column event_type type public.application_event_type
    using event_type::public.application_event_type;

-- ============================================================================
-- 5. Missing indexes on FK hot paths
-- ============================================================================

create index if not exists resume_uploads_profile_id_idx
  on public.resume_uploads (profile_id);

create index if not exists application_events_job_id_idx
  on public.application_events (job_id);

create index if not exists candidate_outreach_messages_related_job_idx
  on public.candidate_outreach_messages (related_job_id)
  where related_job_id is not null;

-- ============================================================================
-- 6. Drop unused columns + legacy enums
-- ============================================================================

alter table public.job_seeker_profiles
  drop column if exists professional_social_url;

drop type if exists public.interview_request_status;
drop type if exists public.slot_status;
drop type if exists public.invite_status;

-- ============================================================================
-- 7. RLS on new tables
-- ============================================================================

alter table public.funds         enable row level security;
alter table public.companies     enable row level security;
alter table public.company_funds enable row level security;

-- Funds/companies are reference data the iOS feed needs to display alongside
-- jobs. Public read is fine; writes are restricted to admins (the Python
-- sync worker uses the service role key, which bypasses RLS).
drop policy if exists "funds_public_read" on public.funds;
create policy "funds_public_read" on public.funds
  for select using (true);

drop policy if exists "funds_admin_write" on public.funds;
create policy "funds_admin_write" on public.funds
  for all to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin'));

drop policy if exists "companies_public_read" on public.companies;
create policy "companies_public_read" on public.companies
  for select using (true);

drop policy if exists "companies_admin_write" on public.companies;
create policy "companies_admin_write" on public.companies
  for all to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin'));

drop policy if exists "company_funds_public_read" on public.company_funds;
create policy "company_funds_public_read" on public.company_funds
  for select using (true);

drop policy if exists "company_funds_admin_write" on public.company_funds;
create policy "company_funds_admin_write" on public.company_funds
  for all to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin'));

-- ============================================================================
-- 8. Seed the 12 confirmed funds (MVP set; remaining 8 TBD)
-- ============================================================================

insert into public.funds (name, slug, board_url, platform) values
  ('Andreessen Horowitz', 'a16z',             'https://portfoliojobs.a16z.com',     'consider'),
  ('Sequoia Capital',     'sequoia',          'https://jobs.sequoiacap.com',        'consider'),
  ('Greylock',            'greylock',         'https://jobs.greylock.com',          'consider'),
  ('Lightspeed',          'lightspeed',       'https://jobs.lsvp.com',              'consider'),
  ('Bessemer',            'bessemer',         'https://jobs.bvp.com',               'consider'),
  ('Kleiner Perkins',     'kleiner-perkins',  'https://jobs.kleinerperkins.com',    'consider'),
  ('NEA',                 'nea',              'https://careers.nea.com',            'consider'),
  ('Accel',               'accel',            'https://jobs.accel.com',             'getro'),
  ('Index Ventures',      'index-ventures',   'https://indexventures.getro.com',    'getro'),
  ('General Catalyst',    'general-catalyst', 'https://jobs.generalcatalyst.com',   'getro'),
  ('Insight Partners',    'insight-partners', 'https://jobs.insightpartners.com',   'getro'),
  ('Craft Ventures',      'craft-ventures',   'https://jobs.craftventures.com',     'getro')
on conflict (slug) do update set
  name      = excluded.name,
  board_url = excluded.board_url,
  platform  = excluded.platform;
