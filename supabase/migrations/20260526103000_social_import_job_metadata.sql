alter table public.jobs
  add column if not exists source_platform text,
  add column if not exists source_caption text,
  add column if not exists source_posted_at timestamptz;

alter table public.jobs
  drop constraint if exists jobs_source_platform_check;

alter table public.jobs
  add constraint jobs_source_platform_check
  check (
    source_platform is null
    or source_platform in ('tiktok', 'instagram', 'other')
  );
