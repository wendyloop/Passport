-- Product decision 2026-07-30: project/program management is its own
-- section, and clinical roles at healthcare startups get classified
-- instead of sitting unfiltered. Enum values land in their own migration
-- because Postgres forbids using a value in the transaction that adds it —
-- the v3 backfill follows in 20260730131000.
alter type public.job_function add value if not exists 'program_management';
alter type public.job_function add value if not exists 'clinical';
