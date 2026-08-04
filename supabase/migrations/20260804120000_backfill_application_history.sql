-- Backfill the Applications page from history that predates application
-- tracking.
--
-- 20260801130000 made founder pitches write job_applications rows — but only
-- from that point forward. Pitches sent before it live solely in
-- founder_outreach_messages, so the Applications tab said "No applications
-- yet" to candidates who had already sent five. Same story for ATS-portal
-- applies: log-application-event now records a job_applications row on the
-- submitted funnel event, and this backfills any submitted events that came
-- first.
--
-- Both inserts are idempotent: distinct-on collapses repeats per
-- (job, candidate), and the unique dup guard makes re-runs no-ops. Pitch
-- rows win over portal rows only in the sense that whichever lands first
-- holds the slot; the other path upgrades/no-ops at runtime.

-- 1. Founder pitches → founder_pitch application rows.
insert into public.job_applications (
  job_id, employer_profile_id, candidate_profile_id, application_kind,
  founder_pitched_at, job_title, company_name, job_location,
  candidate_name, candidate_headline, candidate_video_url,
  email_delivery_status, status, applied_at
)
select distinct on (m.job_id, m.candidate_profile_id)
  m.job_id,
  null,
  m.candidate_profile_id,
  'founder_pitch',
  m.created_at,
  coalesce(j.title, 'Open role'),
  coalesce(j.company_name, 'the company'),
  j.location,
  coalesce(p.full_name, 'A scout22 candidate'),
  p.headline,
  jsp.intro_video_url,
  m.delivery_status,
  'submitted',
  m.created_at
from public.founder_outreach_messages m
join public.jobs j on j.id = m.job_id
join public.profiles p on p.id = m.candidate_profile_id
left join public.job_seeker_profiles jsp on jsp.profile_id = m.candidate_profile_id
where m.job_id is not null
  and m.delivery_status <> 'failed'
order by m.job_id, m.candidate_profile_id, m.created_at desc
on conflict (job_id, candidate_profile_id) do nothing;

-- 2. Portal submits (application_events.submitted) → ats_apply rows.
--    applied_at = first submit for that (job, candidate).
insert into public.job_applications (
  job_id, employer_profile_id, candidate_profile_id, application_kind,
  job_title, company_name, job_location, application_email,
  candidate_name, candidate_headline,
  email_delivery_status, status, applied_at
)
select distinct on (e.job_id, e.candidate_profile_id)
  e.job_id,
  j.employer_profile_id,
  e.candidate_profile_id,
  'ats_apply',
  coalesce(j.title, 'Open role'),
  coalesce(j.company_name, 'the company'),
  j.location,
  j.application_email,
  coalesce(p.full_name, 'A scout22 candidate'),
  p.headline,
  'not_applicable',
  'submitted',
  e.created_at
from public.application_events e
join public.jobs j on j.id = e.job_id
join public.profiles p on p.id = e.candidate_profile_id
where e.event_type = 'submitted'
order by e.job_id, e.candidate_profile_id, e.created_at asc
on conflict (job_id, candidate_profile_id) do nothing;
