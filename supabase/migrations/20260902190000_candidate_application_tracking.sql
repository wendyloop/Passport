-- S-6: the candidate's own view of their applications.
--
-- job_applications.status is the EMPLOYER's pipeline (New/Reviewing/
-- Contacted/Rejected/Hired, P2). It is written by the employer, and most rows
-- in this app have no employer at all — board and reel jobs, and founder
-- pitches, which reach a personal inbox rather than an applicant pipeline. So
-- it cannot double as "where am I with this".
--
-- This is the exact mirror of application_notes (AUDIT P1-9), and for the
-- mirror-image reason: RLS distinguishes rows, not columns, so a candidate's
-- private note ("recruiter seemed checked out") must live on a row the
-- employer cannot select. Putting these fields on job_applications would ship
-- them straight to the employer, whose client fetches that row with select=*.

create table if not exists public.candidate_application_tracking (
  application_id        uuid primary key references public.job_applications(id) on delete cascade,
  candidate_profile_id  uuid not null references public.profiles(id) on delete cascade,
  -- The candidate's own stage, not the employer's. 'no_response' exists
  -- because it is the single most common real outcome and leaving it
  -- indistinguishable from 'applied' is what makes a tracker useless after
  -- fifty applications.
  stage                 text not null default 'applied'
    check (stage in ('applied', 'screening', 'interview', 'offer', 'rejected', 'no_response')),
  interview_at          timestamptz,
  -- A date, not a timestamp: "follow up on the 14th" has no meaningful time.
  follow_up_on          date,
  notes                 text,
  created_at            timestamptz not null default timezone('utc', now()),
  updated_at            timestamptz not null default timezone('utc', now())
);

-- Drives the Inbox's "needs a follow-up" section. Partial, because most rows
-- never get a follow-up date set.
create index if not exists candidate_tracking_follow_up_idx
  on public.candidate_application_tracking (candidate_profile_id, follow_up_on)
  where follow_up_on is not null;

create index if not exists candidate_tracking_stage_idx
  on public.candidate_application_tracking (candidate_profile_id, stage);

drop trigger if exists set_candidate_application_tracking_updated_at
  on public.candidate_application_tracking;
create trigger set_candidate_application_tracking_updated_at
before update on public.candidate_application_tracking
for each row execute function public.set_current_timestamp_updated_at();

alter table public.candidate_application_tracking enable row level security;

-- Candidate-only, both directions. The `with check` also verifies the
-- application really belongs to them, so a row cannot be attached to someone
-- else's application id.
drop policy if exists "candidate_tracking_owner_only" on public.candidate_application_tracking;
create policy "candidate_tracking_owner_only"
on public.candidate_application_tracking
for all
to authenticated
using (candidate_profile_id = (select auth.uid()))
with check (
  candidate_profile_id = (select auth.uid())
  and exists (
    select 1 from public.job_applications ja
    where ja.id = candidate_application_tracking.application_id
      and ja.candidate_profile_id = (select auth.uid())
  )
);
