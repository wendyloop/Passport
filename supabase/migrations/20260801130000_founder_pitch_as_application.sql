-- Founder pitches count as applications, and one pitch cools a whole company.
--
-- Two changes, both FIRST-100-USERS-flavored (see docs/DEFERRED_WORK.md X1):
--
-- 1. A founder pitch now writes a job_applications row, so it shows on the
--    candidate's Applications page and feeds the same downstream logic as an
--    ordinary apply (For-You affinity, Saved-tab ordering, applied-state on
--    the feed card). The existing unique (job_id, candidate_profile_id) makes
--    pitch-then-apply collapse onto one row instead of double-counting.
--
-- 2. companies.last_founder_touch_at lets the feed demote EVERY role at a
--    company once anyone has pitched its founder. A company usually has one
--    founder but several open roles; demoting only the pitched job left the
--    other roles at full priority and the same inbox kept getting hit.
--    Stamped ONLY by send-founder-email — applying through a company's own
--    ATS portal costs the founder nothing and must not demote anything.

-- ---------------------------------------------------------------- 1. rows

alter table public.job_applications
  add column if not exists application_kind text not null default 'ats_apply',
  add column if not exists founder_pitched_at timestamptz;

do $$
begin
  alter table public.job_applications
    add constraint job_applications_application_kind_check
    check (application_kind in ('ats_apply', 'founder_pitch'));
exception
  when duplicate_object then null;
end $$;

-- A founder pitch has no ATS address, and the candidate can SELECT their own
-- application rows — putting the founder's real address here would leak a
-- contact the founder-email path deliberately masks. Left null for pitches.
alter table public.job_applications
  alter column application_email drop not null;

create index if not exists job_applications_kind_idx
  on public.job_applications (candidate_profile_id, application_kind);

-- --------------------------------------------------------- 2. company cool

alter table public.companies
  add column if not exists last_founder_touch_at timestamptz;

create index if not exists companies_last_founder_touch_idx
  on public.companies (last_founder_touch_at)
  where last_founder_touch_at is not null;
