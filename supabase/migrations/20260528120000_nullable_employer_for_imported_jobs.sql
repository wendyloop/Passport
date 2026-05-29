-- Imported social posts don't belong to a registered employer profile.
-- Allow employer_profile_id to be null for admin-imported JobToks.
alter table public.jobs
  alter column employer_profile_id drop not null;
