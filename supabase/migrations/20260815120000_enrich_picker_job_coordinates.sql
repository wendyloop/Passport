-- Widen the enrich-descriptions queue to companies whose job rows carry ATS
-- coordinates the company row does not.
--
-- The previous picker required `c.ats_type is not null` and matched jobs with
-- `j.ats_type = c.ats_type`. Both assumptions fail in practice:
--
--   * A company that migrates ATS keeps the old provider on the company row.
--     Applied Intuition is company=greenhouse with 239 live ashby jobs; every
--     one was filtered out, and the company still reported "0 pending".
--   * ~93 description-less jobs belong to companies whose row never
--     classified at all (ats_type is null), so they never entered the queue.
--
-- Enrichment now reads each job's own ats_type + apply_url (see
-- _shared/ats/enrich_targets.ts), so the picker only has to answer "does this
-- company have enrichable work?". ats_type/ats_token are still returned as an
-- advisory fallback for rows whose apply_url no longer classifies.
--
-- ats_external_id is required here because a job without one can never be
-- matched to adapter output — including it would pin the queue on companies
-- that can never drain.

create or replace function public.get_stale_enrichable_companies(p_limit int)
returns table (
  id        uuid,
  name      text,
  ats_type  text,
  ats_token text
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.name, c.ats_type, c.ats_token
  from public.companies c
  where exists (
      select 1
      from public.jobs j
      where j.company_id       = c.id
        and j.ats_type        is not null
        and j.ats_external_id is not null
        and j.description     is null
        and j.is_active        = true
    )
  order by c.last_synced_at asc nulls first
  limit p_limit;
$$;

revoke all on function public.get_stale_enrichable_companies(int) from public, anon, authenticated;
grant execute on function public.get_stale_enrichable_companies(int) to service_role;
