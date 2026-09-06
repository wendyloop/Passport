-- C-3: Workday, plus the coordinates it needs that the other five do not.
--
-- Measured on the early-career market this product is now pointed at:
-- Workday carries 1,566 companies and 16,527 postings — more than the
-- Greenhouse and Ashby address books combined. iCIMS (291) and Oracle (186)
-- are the next two, so the CHECK constraints admit them now rather than
-- forcing another migration when their adapters land.

alter table public.companies drop constraint if exists companies_ats_type_check;
alter table public.companies add constraint companies_ats_type_check
  check (ats_type in (
    'greenhouse', 'lever', 'ashby', 'smartrecruiters', 'recruitee',
    'workday', 'icims', 'oracle'
  ));

alter table public.jobs drop constraint if exists jobs_source_ats_check;
alter table public.jobs add constraint jobs_source_ats_check
  check (source_ats in (
    'greenhouse', 'lever', 'ashby', 'smartrecruiters', 'recruitee',
    'workday', 'icims', 'oracle'
  ));

-- ---------------------------------------------------------------------------
-- The Workday address is a triple, not a token
-- ---------------------------------------------------------------------------
--
-- Every other supported ATS is reachable from one string: greenhouse/stripe.
-- Workday needs (tenant, datacenter host, career site):
--
--   POST https://boeing.wd1.myworkdayjobs.com/wday/cxs/boeing/EXTERNAL_CAREERS/jobs
--                 ^tenant ^dc                      ^tenant ^site
--
-- ats_token holds the tenant, so companies_ats_unique still means one row per
-- Workday tenant. ats_host holds the full datacenter host — the shard (wd1,
-- wd3, wd5) is not derivable from the tenant. ats_site holds the career-site
-- path, which is not derivable from anything: guessing "RBCCareers" for RBC
-- returns 404. It has to be read off a real posting URL.
--
-- A tenant can publish several career sites — RTX runs both
-- rec_rtx_ext_gateway and Private_Posting_No_TMP — and this schema stores one.
-- The seed picks the site with the most postings, which is the public external
-- site in every sample checked. Secondary sites are a known, deliberate gap.
alter table public.companies
  add column if not exists ats_host text,
  add column if not exists ats_site text;

comment on column public.companies.ats_host is
  'Workday only: full datacenter host, e.g. boeing.wd1.myworkdayjobs.com. Null for single-token ATS.';
comment on column public.companies.ats_site is
  'Workday only: career-site path segment, e.g. EXTERNAL_CAREERS. Not derivable — read from a posting URL.';
