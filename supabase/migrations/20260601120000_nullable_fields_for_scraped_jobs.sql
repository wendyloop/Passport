-- Scraped jobs don't have a posting user, application email, or guaranteed description.
alter table public.jobs
  alter column posted_by_profile_id drop not null,
  alter column application_email    drop not null,
  alter column description          drop not null;
