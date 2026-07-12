-- M3: security posture (T8) + employer application workflow (P2).

-- ── T8: RLS lockdown — no more anonymous reads ──────────────────────
-- companies/funds/company_funds/carousels were `for select using(true)`
-- with no role restriction (anon-readable) while jobs required auth. The
-- app is fully authenticated and the share landing page reads via the
-- service role, so nothing legitimate needs anon access. Decided
-- 2026-07-11 with the App Store security posture.

drop policy if exists "funds_public_read" on public.funds;
create policy "funds_authenticated_read" on public.funds
  for select to authenticated using (true);

drop policy if exists "companies_public_read" on public.companies;
create policy "companies_authenticated_read" on public.companies
  for select to authenticated using (true);

drop policy if exists "company_funds_public_read" on public.company_funds;
create policy "company_funds_authenticated_read" on public.company_funds
  for select to authenticated using (true);

drop policy if exists "carousels_public_read" on public.carousels;
create policy "carousels_authenticated_read" on public.carousels
  for select to authenticated using (true);

-- ── P2: application states + internal notes ────────────────────────
-- 'submitted' stays the initial state (existing rows use it; the UI labels
-- it "New"). Employers move applications through reviewing → contacted →
-- rejected/hired and can keep optional private notes — the feedback loop
-- for improving both sides of the marketplace.

alter table public.job_applications
  add column if not exists internal_notes text;

alter table public.job_applications
  drop constraint if exists job_applications_status_check;
alter table public.job_applications
  add constraint job_applications_status_check
  check (status in ('submitted', 'reviewing', 'contacted', 'rejected', 'hired'));

-- Employers may update their own applications (the app only ever patches
-- status + internal_notes; row scope keeps them off other employers' rows).
drop policy if exists "job_applications_employer_update" on public.job_applications;
create policy "job_applications_employer_update" on public.job_applications
  for update to authenticated
  using (employer_profile_id = (select auth.uid()))
  with check (employer_profile_id = (select auth.uid()));
