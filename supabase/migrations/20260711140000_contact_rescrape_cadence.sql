-- T9 (partial): re-scrape cadence. The contact scraper was scrape-once —
-- a company whose site yielded zero founders was never retried. Now
-- zero-contact companies become eligible again 14 days after their last
-- attempt (sites change, team pages get published). Companies that HAVE
-- contacts are still never re-scraped here; freshness for them comes from
-- the cheaper carousel-JD tier.

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
    and (
      c.contacts_scraped_at is null
      or c.contacts_scraped_at < now() - interval '14 days'
    )
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
