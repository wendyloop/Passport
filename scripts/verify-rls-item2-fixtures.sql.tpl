-- Audit item-2 verification fixtures (throwaway; removed by cleanup.sql).
-- candA: private candidate with PII + an application to empE's job.
-- candB: another job seeker (the prober). empE: employer.

delete from auth.users where email in
  ('canda@auditverify.local', 'candb@auditverify.local', 'empe@auditverify.local');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
select
  '00000000-0000-0000-0000-000000000000', extensions.gen_random_uuid(),
  'authenticated', 'authenticated', e.email,
  extensions.crypt('__PW__', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', e.full_name), now(), now(),
  '', '', '', '', '', '', '', ''
from (values
  ('canda@auditverify.local', 'Cand A'),
  ('candb@auditverify.local', 'Cand B'),
  ('empe@auditverify.local', 'Emp E')
) as e(email, full_name);

insert into auth.identities (
  id, user_id, provider_id, provider, identity_data,
  last_sign_in_at, created_at, updated_at
)
select
  extensions.gen_random_uuid(), u.id, u.id::text, 'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  now(), now(), now()
from auth.users u
where u.email like '%auditverify.local';

update public.profiles set role = 'employer', onboarding_complete = true
where email = 'empe@auditverify.local';
update public.profiles set onboarding_complete = true, full_name = 'Cand A'
where email = 'canda@auditverify.local';
update public.profiles set onboarding_complete = true, full_name = 'Cand B'
where email = 'candb@auditverify.local';

insert into public.employer_profiles (profile_id, company_name)
select id, 'AuditCo' from public.profiles where email = 'empe@auditverify.local'
on conflict (profile_id) do nothing;

-- candA: private, with the PII the audit says must be invisible.
insert into public.job_seeker_profiles
  (profile_id, school_name, phone, desired_compensation_range, discovery_visibility)
select id, 'Audit University', '+1 555 0100', '$150k-$175k', 'private'
from public.profiles where email = 'canda@auditverify.local'
on conflict (profile_id) do update
  set discovery_visibility = 'private', phone = '+1 555 0100',
      desired_compensation_range = '$150k-$175k';

insert into public.job_seeker_profiles (profile_id)
select id from public.profiles where email = 'candb@auditverify.local'
on conflict (profile_id) do nothing;

insert into public.job_seeker_employers (profile_id, employer_name)
select id, 'PrevCo' from public.profiles where email = 'canda@auditverify.local';

insert into public.candidate_videos (profile_id, video_url)
select id, 'https://example.com/pitch.mp4'
from public.profiles where email = 'canda@auditverify.local';

insert into public.candidate_essay_answers
  (candidate_profile_id, question_text, question_norm, answer)
select id, 'Why do you want to work here?', 'why do you want to work here?',
  'SECRET ESSAY: my visa status and salary floor'
from public.profiles where email = 'canda@auditverify.local'
on conflict (candidate_profile_id, question_norm) do nothing;

insert into public.jobs
  (employer_profile_id, posted_by_profile_id, title, company_name, description,
   application_email, video_url, is_published)
select p.id, p.id, 'Audit Verification Role', 'AuditCo', 'fixture',
  'jobs@auditverify.local', 'https://example.com/job.mp4', true
from public.profiles p where p.email = 'empe@auditverify.local';

insert into public.job_applications
  (job_id, employer_profile_id, candidate_profile_id, job_title, company_name,
   application_email, candidate_name, email_delivery_status)
select j.id, e.id, a.id, 'Audit Verification Role', 'AuditCo',
  'jobs@auditverify.local', 'Cand A', 'sent'
from public.jobs j
cross join public.profiles e
cross join public.profiles a
where j.title = 'Audit Verification Role'
  and e.email = 'empe@auditverify.local'
  and a.email = 'canda@auditverify.local'
on conflict (job_id, candidate_profile_id) do nothing;

select
  (select id from public.profiles where email = 'canda@auditverify.local') as cand_a,
  (select id from public.profiles where email = 'candb@auditverify.local') as cand_b,
  (select id from public.profiles where email = 'empe@auditverify.local') as emp_e,
  (select id from public.jobs where title = 'Audit Verification Role') as job_id,
  (select count(*) from public.job_applications ja
     join public.jobs j on j.id = ja.job_id
     where j.title = 'Audit Verification Role') as applications;
