-- Fix the dead founder-contact pipeline (found 2026-07-20).
--
-- company_contacts_company_email_idx was a PARTIAL unique index
-- (WHERE email IS NOT NULL). PostgREST upserts emit a plain
-- ON CONFLICT (company_id, email), which Postgres refuses to match to a
-- partial index — error 42P10 — so EVERY contact insert from all three
-- extraction tiers (generate-carousel JD founders, enrich-descriptions
-- posting emails, enrich-company-contacts website scrape) has failed since
-- the feature shipped. All three call sites are failure-isolated, so the
-- errors only ever reached ephemeral function logs: company_contacts has
-- zero rows despite 1,023 jobs carrying a posting_contact_email.
--
-- Fix: every writer already refuses to insert a null email (the guess
-- helper drops founders without one), so make the column NOT NULL — the
-- table is empty, nothing to migrate — and rebuild the index non-partial
-- so ON CONFLICT works.

alter table public.company_contacts alter column email set not null;

drop index if exists public.company_contacts_company_email_idx;
create unique index company_contacts_company_email_idx
  on public.company_contacts (company_id, email);

-- Backfill tier 2 from data we already hold: posting contact emails
-- extracted from JDs (the highest-trust tier — they were published by the
-- company itself). Cap 3 per company to match MAX_CONTACTS_PER_COMPANY,
-- newest jobs first; skip obvious no-reply addresses.
insert into public.company_contacts (company_id, source, email, email_status, scraped_at)
select company_id, 'posting_email', email, 'verified', timezone('utc', now())
from (
  select
    j.company_id,
    lower(j.posting_contact_email) as email,
    row_number() over (
      partition by j.company_id
      order by max(j.created_at) desc
    ) as rn
  from public.jobs j
  where j.posting_contact_email is not null
    and j.company_id is not null
    and lower(j.posting_contact_email) not like 'no%reply%'
    and lower(j.posting_contact_email) not like 'donotreply%'
  group by j.company_id, lower(j.posting_contact_email)
) ranked
where rn <= 3
on conflict (company_id, email) do nothing;

-- Every "scraped" company to date was scraped into the broken insert —
-- zero rows landed. Clear the cadence stamp so enrich-company-contacts
-- revisits them now that inserts work (15/day, same cron).
update public.companies
set contacts_scraped_at = null
where contacts_scraped_at is not null;
