drop view if exists public.candidate_feed;

drop function if exists public.issue_referral_invite(extensions.citext);
drop function if exists public.consume_referral_invite(text);
drop function if exists public.like_candidate(uuid);
drop function if exists public.select_interview_slot(uuid, uuid);
drop function if exists public.respond_to_interview_request(uuid, boolean);

drop policy if exists "Referral invites visible to employer or recipient" on public.referral_invites;
drop policy if exists "Calendar connections are visible to owner" on public.calendar_connections;
drop policy if exists "Calendar connections are mutable by owner" on public.calendar_connections;
drop policy if exists "Candidate likes belong to employer owner" on public.candidate_likes;
drop policy if exists "Availability slots are visible to participants" on public.availability_slots;
drop policy if exists "Availability slots are mutable by employer owner" on public.availability_slots;
drop policy if exists "Interview requests are visible to participants" on public.interview_requests;

alter table if exists public.job_seeker_profiles
  drop column if exists referral_invite_id,
  drop column if exists referral_badge;

alter table if exists public.employer_profiles
  drop column if exists calendar_connected,
  drop column if exists monthly_referral_limit;

drop table if exists public.interview_requests;
drop table if exists public.availability_slots;
drop table if exists public.candidate_likes;
drop table if exists public.calendar_connections;
drop table if exists public.referral_invites;
