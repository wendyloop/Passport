-- One-time reset of every candidate's weekly founder-pitch quota.
--
-- The quota is not a stored counter — reserve_founder_email_send counts
-- founder_outreach_messages inside a rolling 7-day window. To hand everyone
-- a fresh 5 without deleting send history (which would also destroy the
-- once-per-contact dedupe and the audit trail), the count window now starts
-- at whichever is LATER: 7 days ago, or a configurable epoch.
--
-- Setting the epoch to now() zeroes everyone's usage instantly. As the week
-- rolls forward the ordinary 7-day window takes over again on its own, so
-- this is a genuine one-off reset rather than a permanent limit change —
-- founder_email_weekly_limit stays at 5.
--
-- To reset again later (no deploy needed, app_config is read per request):
--   update public.app_config set value = to_jsonb(timezone('utc', now()))
--   where key = 'founder_email_quota_epoch';

insert into public.app_config (key, value)
values ('founder_email_quota_epoch', to_jsonb(timezone('utc', now())))
on conflict (key) do update set value = excluded.value, updated_at = timezone('utc', now());

-- Signature unchanged, so the existing revoke/grant ACL carries over
-- (create or replace preserves it — see DB-P0-1). The epoch is read inside
-- the function, which keeps the edge function and its call site untouched.
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
  v_epoch timestamptz;
  v_window_start timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('founder_email:' || p_candidate::text));

  select coalesce((value #>> '{}')::timestamptz, '-infinity'::timestamptz)
    into v_epoch
    from app_config
   where key = 'founder_email_quota_epoch';

  v_window_start := greatest(
    timezone('utc', now()) - interval '7 days',
    coalesce(v_epoch, '-infinity'::timestamptz)
  );

  select count(*) into v_count
  from founder_outreach_messages
  where candidate_profile_id = p_candidate
    and created_at > v_window_start
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

-- Re-assert the narrow grant (convention: every create function migration
-- ends with an explicit revoke + narrowest grant).
revoke all on function public.reserve_founder_email_send(uuid, uuid, uuid, uuid, extensions.citext, text, text, text, int) from public, anon, authenticated;
grant execute on function public.reserve_founder_email_send(uuid, uuid, uuid, uuid, extensions.citext, text, text, text, int) to service_role;
