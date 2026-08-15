-- Social distribution: post generated carousels to Instagram / TikTok.
--
-- Carousels exist only as JSON slides plus SwiftUI templates — no image file
-- is produced anywhere in the system (the v1 carousel migration says so
-- outright: "We never store images"). Instagram and TikTok need a JPEG at a
-- publicly fetchable URL, so the iOS app renders each slide through the same
-- CardTemplateSlideView the feed uses, uploads to the `social-cards` bucket,
-- and records a row here. A cron then publishes from those rows.
--
-- Split of responsibilities:
--   * rendering is on-device and bursty (a batch every week or two)
--   * publishing is a cron draining the queue at 1-3/day
--
-- There is deliberately no human approval state. Quality is enforced by
-- get_jobs_needing_social_post below, which applies identically whether a
-- human or a cron does the posting. `skipped` is a manual kill switch.

create table if not exists public.social_posts (
  id               uuid primary key default extensions.gen_random_uuid(),
  job_id           uuid not null references public.jobs(id) on delete cascade,
  platform         text not null,
  status           text not null default 'rendered',
  -- Storage paths within the `social-cards` bucket, in slide order.
  image_paths      jsonb not null default '[]',
  caption          text not null default '',
  hashtags         text[] not null default '{}',
  -- Platform's own id + permalink once published.
  external_post_id text,
  permalink        text,
  posted_at        timestamptz,
  error            text,
  attempt_count    int not null default 0,
  created_at       timestamptz not null default timezone('utc', now()),
  updated_at       timestamptz not null default timezone('utc', now()),
  -- One post per job per platform. Reposting means deleting the row, which
  -- keeps accidental double-posting impossible by construction.
  unique (job_id, platform)
);

alter table public.social_posts drop constraint if exists social_posts_platform_check;
alter table public.social_posts
  add constraint social_posts_platform_check
  check (platform in ('instagram', 'tiktok'));

alter table public.social_posts drop constraint if exists social_posts_status_check;
alter table public.social_posts
  add constraint social_posts_status_check
  check (status in ('rendered', 'posted', 'failed', 'skipped'));

create index if not exists social_posts_queue_idx
  on public.social_posts (platform, status, created_at);
create index if not exists social_posts_job_idx
  on public.social_posts (job_id);

-- ---------------------------------------------------------------------------
-- RLS: admins read/write from the app; service_role (the publisher) bypasses.
-- ---------------------------------------------------------------------------

alter table public.social_posts enable row level security;

drop policy if exists "social_posts_admin_all" on public.social_posts;
create policy "social_posts_admin_all" on public.social_posts
for all
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin')
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin')
);

-- ---------------------------------------------------------------------------
-- Storage bucket. MUST be genuinely public: Meta's and TikTok's media
-- fetchers pull the image URL unauthenticated, so a signed-URL or
-- authenticated-read bucket would fail at publish time. Contents are
-- marketing renders of public job data only — the exporter excludes the
-- founder slide, which is the sole place a named private individual appears.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'storage' and table_name = 'objects'
  ) then
    insert into storage.buckets (id, name, public)
    values ('social-cards', 'social-cards', true)
    on conflict (id) do update set public = true;

    execute 'drop policy if exists "Social cards are publicly readable" on storage.objects';
    execute 'create policy "Social cards are publicly readable" on storage.objects for select to public using (bucket_id = ''social-cards'')';

    execute 'drop policy if exists "Social card uploads are admin only" on storage.objects';
    execute 'create policy "Social card uploads are admin only" on storage.objects for insert to authenticated with check (bucket_id = ''social-cards'' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = ''admin''))';

    execute 'drop policy if exists "Social card updates are admin only" on storage.objects';
    execute 'create policy "Social card updates are admin only" on storage.objects for update to authenticated using (bucket_id = ''social-cards'' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = ''admin''))';
  else
    raise notice 'storage schema not present; skipping social-cards bucket setup';
  end if;
end$$;

-- ---------------------------------------------------------------------------
-- Selection queue. THIS IS THE QUALITY GATE — it replaces per-post human
-- review, so tightening the bar means editing this function.
--
-- Rules, and why:
--   * carousels.status = 'generated' — fallback carousels (no JD) have no
--     interior content. Acceptable in an infinite feed, not as brand content.
--   * startup stages only — 56% of the catalog's thin rows sit at
--     acquisition/ipo/1000+/private_equity companies, which F8 already demotes
--     and which the founder-pitch path excludes. Posting them off-brands the
--     account.
--   * compensation present — the single most decision-useful field for job
--     seekers, and it makes a far stronger cover card.
--   * newest first, nothing already posted to that platform.
-- ---------------------------------------------------------------------------

create or replace function public.get_jobs_needing_social_post(p_limit int, p_platform text)
returns table (id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select j.id
  from public.jobs j
  join public.carousels c on c.job_id = j.id
  join public.companies co on co.id = j.company_id
  -- security definer + an `authenticated` grant means the guard has to live
  -- inside the body, not in the grant. service_role (cron) has no auth.uid().
  where (
      auth.role() = 'service_role'
      or exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role::text = 'admin')
    )
    and j.is_active
    and j.is_published
    and j.company_id is not null
    and c.status = 'generated'
    and coalesce(co.stage, '') not in
      ('1000+ employees', 'acquisition', 'ipo', 'private_equity')
    and (
      j.compensation_text is not null
      or j.compensation_min_annual is not null
      or j.compensation_min_hourly is not null
    )
    and not exists (
      select 1 from public.social_posts sp
      where sp.job_id = j.id and sp.platform = p_platform
    )
  order by j.created_at desc
  limit p_limit;
$$;

revoke all on function public.get_jobs_needing_social_post(int, text) from public, anon;
grant execute on function public.get_jobs_needing_social_post(int, text) to service_role, authenticated;

-- updated_at maintenance
create or replace function public.set_social_posts_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists set_social_posts_updated_at on public.social_posts;
create trigger set_social_posts_updated_at
before update on public.social_posts
for each row execute function public.set_social_posts_updated_at();
