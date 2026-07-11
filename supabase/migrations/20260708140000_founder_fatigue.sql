-- Founder-fatigue deprioritization (FIRST-100-USERS measure).
--
-- While the app is acquiring its first ~100 users we want applications
-- spread across companies, not one founder getting several videos in a day.
-- Any event that lands a candidate in a founder's inbox (a founder email or
-- a video application) stamps the job; the candidate feed then sorts jobs
-- touched today below everything untouched, and jobs touched this week
-- slightly less demoted. Revisit or remove once application volume justifies
-- a real ranking system.

alter table public.jobs
  add column if not exists last_founder_touch_at timestamptz;

create index if not exists jobs_last_founder_touch_idx
  on public.jobs (last_founder_touch_at)
  where last_founder_touch_at is not null;
