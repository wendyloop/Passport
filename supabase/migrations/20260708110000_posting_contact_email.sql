-- Persist the contact email that ATS adapters already extract from job
-- descriptions (contact_email_on_posting on NormalizedJob). Written by
-- enrich-descriptions alongside the description.
--
-- Deliberately a separate column from application_email: that column gates
-- the iOS easy-apply path, and extracted addresses can be unrelated JD
-- boilerplate (accessibility@, privacy@). Promotion into application_email
-- stays a separate, reviewable decision.

alter table public.jobs
  add column if not exists posting_contact_email extensions.citext;
