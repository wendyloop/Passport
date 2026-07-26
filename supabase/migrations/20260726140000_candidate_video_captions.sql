-- M-C: multiple pitch videos with captions. candidate_videos already allows
-- many rows per candidate (unique is on profile_id+video_url); this adds a
-- caption, an explicit primary flag, and owner RPCs that keep
-- job_seeker_profiles.intro_video_url mirroring the primary video —
-- send-founder-email's default and employer snapshots read that column.

alter table public.candidate_videos
  add column if not exists caption text,
  add column if not exists is_primary boolean not null default false;

alter table public.candidate_videos
  drop constraint if exists candidate_videos_caption_len;
alter table public.candidate_videos
  add constraint candidate_videos_caption_len
  check (caption is null or char_length(caption) <= 150);

create unique index if not exists candidate_videos_one_primary
  on public.candidate_videos (profile_id) where is_primary;

-- Owners may edit their own rows (caption edits); the app never read this
-- table before M-C, so update was never granted.
drop policy if exists "Candidate videos updatable by owner" on public.candidate_videos;
create policy "Candidate videos updatable by owner"
on public.candidate_videos
for update
to authenticated
using (profile_id = (select auth.uid()))
with check (profile_id = (select auth.uid()));

-- Backfill: the row matching each profile's current intro video is primary.
update public.candidate_videos cv
set is_primary = true
from public.job_seeker_profiles p
where p.profile_id = cv.profile_id
  and p.intro_video_url = cv.video_url
  and not exists (
    select 1 from public.candidate_videos other
    where other.profile_id = cv.profile_id and other.is_primary
  );

create or replace function public.set_primary_candidate_video(p_video_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v candidate_videos;
begin
  select * into v from candidate_videos
  where id = p_video_id and profile_id = auth.uid();
  if not found then
    raise exception 'video_not_found';
  end if;
  update candidate_videos set is_primary = false
  where profile_id = auth.uid() and is_primary and id <> p_video_id;
  update candidate_videos set is_primary = true where id = p_video_id;
  update job_seeker_profiles set intro_video_url = v.video_url
  where profile_id = auth.uid();
end;
$$;
revoke all on function public.set_primary_candidate_video(uuid) from public, anon;
grant execute on function public.set_primary_candidate_video(uuid) to authenticated, service_role;

create or replace function public.delete_candidate_video(p_video_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v candidate_videos;
  replacement candidate_videos;
begin
  select * into v from candidate_videos
  where id = p_video_id and profile_id = auth.uid();
  if not found then
    raise exception 'video_not_found';
  end if;
  delete from candidate_videos where id = p_video_id;
  if v.is_primary then
    select * into replacement from candidate_videos
    where profile_id = auth.uid()
    order by created_at desc
    limit 1;
    if found then
      update candidate_videos set is_primary = true where id = replacement.id;
      update job_seeker_profiles set intro_video_url = replacement.video_url
      where profile_id = auth.uid();
    else
      update job_seeker_profiles set intro_video_url = null
      where profile_id = auth.uid();
    end if;
  end if;
end;
$$;
revoke all on function public.delete_candidate_video(uuid) from public, anon;
grant execute on function public.delete_candidate_video(uuid) to authenticated, service_role;
