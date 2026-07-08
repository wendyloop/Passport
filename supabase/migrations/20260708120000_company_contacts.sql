-- Founder / contact directory per company, feeding the "email the founder"
-- apply path. Rows arrive from three sources, cheapest first:
--   llm_job_listing  — founders named in a JD, extracted during the carousel
--                      generation LLM call (zero extra API cost)
--   posting_email    — a real contact email found in the JD by the ATS
--                      adapters (verified: it was published on the posting)
--   llm_scrape       — website scrape fallback (enrich-company-contacts) for
--                      companies the cheaper tiers produced nothing for
--   manual           — admin-entered
--
-- Guessed emails follow firstname@domain (~90% hit rate against startup
-- domains per prior testing); the Resend bounce webhook flips misses to
-- 'bounced' so they are never retried.

create table if not exists public.company_contacts (
  id          uuid primary key default extensions.gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete cascade,
  full_name   text,
  first_name  text,
  role_title  text,
  source      text not null
    check (source in ('llm_job_listing', 'llm_scrape', 'posting_email', 'manual')),
  email       extensions.citext,
  email_status text not null default 'guessed'
    check (email_status in ('guessed', 'verified', 'bounced', 'suppressed')),
  confidence  numeric(3,2) check (confidence between 0 and 1),
  scraped_at  timestamptz,
  created_at  timestamptz not null default timezone('utc', now()),
  updated_at  timestamptz not null default timezone('utc', now())
);

create unique index if not exists company_contacts_company_email_idx
  on public.company_contacts (company_id, email)
  where email is not null;

create index if not exists company_contacts_company_idx
  on public.company_contacts (company_id);

create trigger set_company_contacts_updated_at
  before update on public.company_contacts
  for each row execute function public.set_current_timestamp_updated_at();

-- RLS on, and deliberately NO client policies: reads and writes go through
-- service-role edge functions only. companies/funds/carousels being
-- anon-readable is an existing inconsistency we must NOT extend here —
-- guessed founder emails would otherwise be harvestable via the anon key.
alter table public.company_contacts enable row level security;

-- Website-scrape queue cursor (tier 3). Set even on failed scrapes so a
-- broken site doesn't wedge the queue.
alter table public.companies
  add column if not exists contacts_scraped_at timestamptz;

-- Tier-3 queue: companies with a domain, at least one active job, no scrape
-- attempt yet, and nothing already contributed by the cheaper tiers.
create or replace function public.get_companies_needing_contact_scrape(p_limit int)
returns table (
  id     uuid,
  name   text,
  domain text
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.name, c.domain
  from public.companies c
  where c.domain is not null
    and c.contacts_scraped_at is null
    and exists (
      select 1 from public.jobs j
      where j.company_id = c.id
        and j.is_active = true
    )
    and not exists (
      select 1 from public.company_contacts cc
      where cc.company_id = c.id
    )
  order by c.first_seen_at asc
  limit p_limit;
$$;

revoke all on function public.get_companies_needing_contact_scrape(int) from public, anon, authenticated;
grant execute on function public.get_companies_needing_contact_scrape(int) to service_role;
