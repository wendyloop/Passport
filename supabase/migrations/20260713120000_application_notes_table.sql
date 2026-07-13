-- AUDIT P1-9 / DB-P1-4: job_applications.internal_notes sat on a row the
-- candidate can SELECT (participants policy) and the iOS client fetches with
-- select=* — an employer's "private" note was delivered verbatim to the
-- candidate it is about. RLS distinguishes rows, not columns, so the fix is
-- an employer-only table. Ships together with the iOS change that reads
-- and writes application_notes instead of the column.

create table if not exists public.application_notes (
  application_id       uuid primary key references public.job_applications(id) on delete cascade,
  employer_profile_id  uuid not null references public.profiles(id) on delete cascade,
  notes                text,
  created_at           timestamptz not null default timezone('utc', now()),
  updated_at           timestamptz not null default timezone('utc', now())
);

drop trigger if exists set_application_notes_updated_at on public.application_notes;
create trigger set_application_notes_updated_at
before update on public.application_notes
for each row execute function public.set_current_timestamp_updated_at();

alter table public.application_notes enable row level security;

drop policy if exists "application_notes_employer_only" on public.application_notes;
create policy "application_notes_employer_only"
on public.application_notes
for all
to authenticated
using (employer_profile_id = (select auth.uid()))
with check (
  employer_profile_id = (select auth.uid())
  and exists (
    select 1 from public.job_applications ja
    where ja.id = application_notes.application_id
      and ja.employer_profile_id = (select auth.uid())
  )
);

-- Migrate existing notes, then remove the leaking column.
insert into public.application_notes (application_id, employer_profile_id, notes)
select id, employer_profile_id, internal_notes
from public.job_applications
where internal_notes is not null
  and employer_profile_id is not null
on conflict (application_id) do nothing;

alter table public.job_applications drop column if exists internal_notes;
