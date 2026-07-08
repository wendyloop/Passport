-- Pitch v1 follow-up: external ID columns for fund + company discovery.
--
-- Getro: each fund has a numeric collection_id surfaced in their JS app
-- (e.g. Accel = 8672). Required to hit api.getro.com/api/v1/collections/<id>.
--
-- Consider: each fund has a board slug (e.g. Sequoia = sequoia-capital)
-- required by the {board_url}/api-boards/search-jobs payload.
--
-- We store both in funds.external_collection_id (text — Getro values are
-- numeric-looking strings, Consider values are kebab-case slugs).
--
-- Companies get external_id (provider org id) so we can dedupe in re-crawls
-- without relying on domain or name alone.

alter table public.funds
  add column if not exists external_collection_id text;

alter table public.companies
  add column if not exists external_id text;

-- Lookup by (source_board, external_id) used by crawl-rosters dedupe.
create index if not exists companies_source_external_idx
  on public.companies (source_board, external_id)
  where external_id is not null;
