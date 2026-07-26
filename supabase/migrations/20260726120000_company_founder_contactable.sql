-- M-A (roadmap 2026-07-26): the iOS "Pitch the founder" button previously
-- showed for any non-big company and dead-ended at "no contact" for ~82% of
-- jobs. The client needs a per-company signal that a usable founder contact
-- exists — without exposing anything about the contact itself
-- (company_contacts stays service-role-only). Denormalized boolean on
-- companies (authenticated-readable), maintained by trigger so inserts from
-- all three extraction tiers and bounce/suppress flips from resend-webhook
-- keep it correct with no function changes.

alter table public.companies
  add column if not exists founder_contactable boolean not null default false;

create or replace function public.refresh_founder_contactable(target_company uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.companies c
  set founder_contactable = exists (
    select 1 from public.company_contacts cc
    where cc.company_id = target_company
      and cc.email is not null
      and coalesce(cc.email_status, '') not in ('bounced', 'suppressed')
  )
  where c.id = target_company;
$$;
revoke all on function public.refresh_founder_contactable(uuid) from public, anon, authenticated;
grant execute on function public.refresh_founder_contactable(uuid) to service_role;

create or replace function public.company_contacts_sync_contactable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company uuid;
begin
  if tg_op = 'DELETE' then
    company := old.company_id;
  else
    company := new.company_id;
  end if;
  perform public.refresh_founder_contactable(company);
  if tg_op = 'UPDATE' and new.company_id is distinct from old.company_id then
    perform public.refresh_founder_contactable(old.company_id);
  end if;
  return null;
end;
$$;
revoke all on function public.company_contacts_sync_contactable() from public, anon, authenticated;

drop trigger if exists company_contacts_sync_contactable on public.company_contacts;
create trigger company_contacts_sync_contactable
after insert or delete or update of email, email_status, company_id
on public.company_contacts
for each row execute function public.company_contacts_sync_contactable();

-- Backfill from current contact state.
update public.companies c
set founder_contactable = true
where exists (
  select 1 from public.company_contacts cc
  where cc.company_id = c.id
    and cc.email is not null
    and coalesce(cc.email_status, '') not in ('bounced', 'suppressed')
);
