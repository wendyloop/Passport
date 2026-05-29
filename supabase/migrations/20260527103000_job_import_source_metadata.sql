alter table public.jobs
  add column if not exists source_creator_name text,
  add column if not exists source_creator_url text,
  add column if not exists source_thumbnail_url text,
  add column if not exists source_caption_raw text,
  add column if not exists source_apply_email_extracted extensions.citext;
