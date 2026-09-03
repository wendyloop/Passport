-- S-5: more than one resume per candidate.
--
-- resume_uploads has always stored one row per upload — the singular resume
-- was purely a query convention (`order created_at desc limit 1`) repeated in
-- five edge functions and the iOS client. This makes the choice explicit and,
-- more importantly, makes every path honour it: a default that the cover
-- letter and keyword gap ignored would be a lie.

alter table public.resume_uploads
  add column if not exists is_default boolean not null default false,
  -- User-facing name ("SWE resume", "PM resume"). Null renders as the file
  -- name, which is what every existing row will show.
  add column if not exists label text;

-- At most one default per candidate, enforced in the database rather than by
-- convention. A partial unique index is the right shape: rows with
-- is_default = false are unconstrained, so a candidate can hold any number of
-- non-default resumes.
create unique index if not exists resume_uploads_one_default_per_profile
  on public.resume_uploads (profile_id)
  where is_default;

-- Backfill: the newest successfully-parsed resume per candidate becomes the
-- default, which is exactly what `order created_at desc limit 1` already
-- resolved to. Nobody's behaviour changes on deploy.
with ranked as (
  select id,
         row_number() over (
           partition by profile_id
           order by created_at desc
         ) as rn
  from public.resume_uploads
  where parse_status <> 'failed'
)
update public.resume_uploads r
set is_default = true
from ranked
where ranked.id = r.id
  and ranked.rn = 1
  and not exists (
    select 1 from public.resume_uploads d
    where d.profile_id = r.profile_id and d.is_default
  );

-- Switching the default has to clear the old one first or the unique index
-- rejects the write. Doing that as two client round trips leaves a window
-- where the candidate has no default at all, so it is one statement here.
create or replace function public.set_default_resume(p_resume_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
begin
  -- Ownership check, not a filter: security definer bypasses RLS, so without
  -- this any signed-in user could re-point another candidate's default.
  select profile_id into v_profile_id
  from public.resume_uploads
  where id = p_resume_id;

  if v_profile_id is null or v_profile_id <> auth.uid() then
    raise exception 'resume not found';
  end if;

  update public.resume_uploads
  set is_default = (id = p_resume_id)
  where profile_id = v_profile_id
    and (is_default or id = p_resume_id);
end;
$$;

revoke all on function public.set_default_resume(uuid) from public, anon;
grant execute on function public.set_default_resume(uuid) to authenticated;
