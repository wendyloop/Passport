-- Backfill ATS coordinates for Greenhouse/Lever EU-resident board URLs.
--
-- classify.ts now recognises both EU hosts, but that only helps rows ingested
-- from here on. Existing rows are stuck:
--
--   * jobs.eu.lever.co/{token}/{id}          → ats_type null (host unmatched)
--   * job-boards.eu.greenhouse.io/{t}/jobs/{id}
--       → ats_type greenhouse but ats_external_id null, because the old
--         `.greenhouse.io` subdomain branch read the token as "job-boards.eu"
--         and then looked for the id in the wrong path position.
--
-- Both shapes are skipped by enrich-descriptions, which requires a non-null
-- ats_external_id. dedup_key is rewritten in the same statement: classify now
-- derives "{ats}:{id}" for these URLs, so leaving the old URL-shaped key would
-- make the next ingest insert a second row for the same posting.
--
-- The NOT EXISTS guard skips any row whose new key is already taken (there are
-- none today) so the backfill can never merge two distinct postings.

update public.jobs j
set ats_type        = 'lever',
    ats_external_id = sub.ext_id,
    dedup_key       = 'lever:' || sub.ext_id
from (
  select id,
         substring(apply_url from '^https://jobs\.eu\.lever\.co/[^/?#]+/([^/?#]+)') as ext_id
  from public.jobs
  where ats_type is null
    and apply_url like 'https://jobs.eu.lever.co/%'
) sub
where j.id = sub.id
  and sub.ext_id is not null
  and not exists (
    select 1 from public.jobs other
    where other.dedup_key = 'lever:' || sub.ext_id and other.id <> j.id
  );

update public.jobs j
set ats_external_id = sub.ext_id,
    dedup_key       = 'greenhouse:' || sub.ext_id
from (
  select id,
         substring(
           apply_url from '^https://(?:job-)?boards\.eu\.greenhouse\.io/[^/?#]+/jobs/([^/?#]+)'
         ) as ext_id
  from public.jobs
  where ats_type = 'greenhouse'
    and ats_external_id is null
    and apply_url like '%.eu.greenhouse.io/%'
) sub
where j.id = sub.id
  and sub.ext_id is not null
  and not exists (
    select 1 from public.jobs other
    where other.dedup_key = 'greenhouse:' || sub.ext_id and other.id <> j.id
  );

-- Companies whose token was captured from the EU host ("job-boards.eu") point
-- the adapter at a board that does not exist; null it so enrichment falls back
-- to the token carried on each job's apply_url.
update public.companies
set ats_token = null
where ats_type = 'greenhouse'
  and ats_token in ('job-boards.eu', 'boards.eu');
