-- Candidate-only v0: the privacy toggle is hidden in the iOS UI and the
-- client no longer writes discovery_visibility, so every candidate stays on
-- the column default. Flip that default to public/discoverable — the future
-- employer view needs a full candidate pool (available videos are the
-- bottleneck to launching the employer side) — and normalize existing rows,
-- some of which carry more-private values from the earlier default.
--
-- The discovery_visibility RLS policies (20260713122000/123000) stay fully
-- intact: public-by-default means visible-to-the-future-EMPLOYER-view only.
-- Candidates still cannot read each other's rows, and the toggle gets
-- re-surfaced client-side when the employer view ships.

alter table public.job_seeker_profiles
  alter column discovery_visibility set default 'discoverable_to_hiring_employers';

update public.job_seeker_profiles
  set discovery_visibility = 'discoverable_to_hiring_employers'
  where discovery_visibility <> 'discoverable_to_hiring_employers';
