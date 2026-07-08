-- Founder outreach: candidate → founder direct emails.
--
-- Separate table from candidate_outreach_messages (which models the reverse
-- direction, employer → candidate, and FKs employer_profiles).

create table if not exists public.founder_outreach_messages (
  id                    uuid primary key default extensions.gen_random_uuid(),
  candidate_profile_id  uuid not null references public.profiles(id) on delete cascade,
  company_id            uuid not null references public.companies(id) on delete cascade,
  contact_id            uuid references public.company_contacts(id) on delete set null,
  job_id                uuid references public.jobs(id) on delete set null,
  to_email              extensions.citext not null,
  subject               text not null,
  body                  text not null,
  candidate_note        text,
  delivery_status       text not null default 'pending'
    check (delivery_status in ('pending', 'sent', 'failed', 'bounced', 'complained')),
  delivery_error        text,
  resend_email_id       text,
  created_at            timestamptz not null default timezone('utc', now()),
  updated_at            timestamptz not null default timezone('utc', now())
);

create index if not exists founder_outreach_candidate_created_idx
  on public.founder_outreach_messages (candidate_profile_id, created_at desc);

-- One intro per candidate per founder, ever. Deliberate anti-spam default:
-- a founder should never hear from the same candidate twice through us.
create unique index if not exists founder_outreach_once_per_contact_idx
  on public.founder_outreach_messages (candidate_profile_id, contact_id)
  where contact_id is not null;

-- Bounce/complaint webhooks correlate by Resend email id.
create index if not exists founder_outreach_resend_id_idx
  on public.founder_outreach_messages (resend_email_id)
  where resend_email_id is not null;

create trigger set_founder_outreach_messages_updated_at
  before update on public.founder_outreach_messages
  for each row execute function public.set_current_timestamp_updated_at();

alter table public.founder_outreach_messages enable row level security;

create policy "Candidates read own founder outreach"
  on public.founder_outreach_messages
  for select
  to authenticated
  using (candidate_profile_id = (select auth.uid()));

-- Writes: service role only (no insert/update/delete policies).

-- Race-safe weekly quota + insert in one transaction. The advisory lock
-- serializes concurrent sends per candidate so two in-flight requests can't
-- both pass the count check. Failed sends do not consume quota.
create or replace function public.reserve_founder_email_send(
  p_candidate uuid,
  p_company   uuid,
  p_contact   uuid,
  p_job       uuid,
  p_to_email  extensions.citext,
  p_subject   text,
  p_body      text,
  p_note      text,
  p_limit     int
)
returns table (outreach_id uuid, sends_used int)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('founder_email:' || p_candidate::text));

  select count(*) into v_count
  from founder_outreach_messages
  where candidate_profile_id = p_candidate
    and created_at > timezone('utc', now()) - interval '7 days'
    and delivery_status <> 'failed';

  if v_count >= p_limit then
    raise exception 'WEEKLY_LIMIT_REACHED';
  end if;

  insert into founder_outreach_messages (
    candidate_profile_id, company_id, contact_id, job_id,
    to_email, subject, body, candidate_note
  ) values (
    p_candidate, p_company, p_contact, p_job,
    p_to_email, p_subject, p_body, p_note
  )
  returning id into v_id;

  return query select v_id, v_count + 1;
end;
$$;

revoke all on function public.reserve_founder_email_send(uuid, uuid, uuid, uuid, extensions.citext, text, text, text, int) from public, anon, authenticated;
grant execute on function public.reserve_founder_email_send(uuid, uuid, uuid, uuid, extensions.citext, text, text, text, int) to service_role;
