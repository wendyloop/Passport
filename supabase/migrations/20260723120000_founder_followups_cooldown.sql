-- Follow-ups to founders are allowed (product decision 2026-07-23): the
-- once-per-candidate-per-founder-EVER unique index becomes a 7-day
-- per-contact cooldown enforced in the reservation RPC. Anti-spam still
-- holds three ways: 5 sends/candidate/week, 3 emails/company/week, and no
-- more than one email to the same founder per week per candidate.
--
-- Side fix: the old unique index counted FAILED sends too, so a candidate
-- whose first attempt failed at the provider was locked out of that founder
-- forever. The cooldown only counts non-failed sends.

drop index if exists public.founder_outreach_once_per_contact_idx;

-- Lookup index for the cooldown probe (and contact-history queries).
create index if not exists founder_outreach_candidate_contact_idx
  on public.founder_outreach_messages (candidate_profile_id, contact_id, created_at desc)
  where contact_id is not null;

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

  -- Per-contact cooldown: one email to a given founder per week per
  -- candidate. Failed sends don't count — a provider error must not
  -- consume the founder.
  if p_contact is not null and exists (
    select 1 from founder_outreach_messages
    where candidate_profile_id = p_candidate
      and contact_id = p_contact
      and delivery_status <> 'failed'
      and created_at > timezone('utc', now()) - interval '7 days'
  ) then
    raise exception 'CONTACT_COOLDOWN';
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
