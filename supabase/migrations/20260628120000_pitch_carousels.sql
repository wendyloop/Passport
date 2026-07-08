-- Pitch carousel generation.
--
-- For every active job we produce one carousel: an ordered set of 3–6
-- swipeable slides (cover, about_company, role, requirements, details).
-- Carousels pair structured text content with a `theme_id` that the iOS
-- app resolves to a palette/typography bundle at render time. We never
-- store images.
--
-- Cache + regeneration model: `source_hash` is a sha over the job + company
-- + fund fields the carousel consumed. The generator recomputes on each run
-- and skips when the hash matches the stored value.
--
-- Migrates the v0 placeholder schema (theme/slide_urls) into the v1 shape.
-- Any existing rows are placeholder data from before generation existed and
-- are cleared so the new NOT NULL columns can be enforced.

create table if not exists public.carousels (
  id           uuid primary key default extensions.gen_random_uuid(),
  job_id       uuid not null unique references public.jobs(id) on delete cascade,
  created_at   timestamptz not null default timezone('utc', now())
);

-- Clear v0 placeholder rows. Carousels are regenerated from jobs anyway,
-- so this is non-destructive in practice — the next ingest+generate run
-- repopulates from current job state.
truncate table public.carousels;

-- Drop unused v0 columns if present (they belonged to an image-based design).
alter table public.carousels drop column if exists theme;
alter table public.carousels drop column if exists slide_urls;

-- Add v1 columns. Safe to re-run.
alter table public.carousels
  add column if not exists theme_id     text,
  add column if not exists slide_count  int,
  add column if not exists content      jsonb,
  add column if not exists source_hash  text,
  add column if not exists status       text default 'generated',
  add column if not exists generated_at timestamptz default timezone('utc', now());

-- Enforce NOT NULL after the table is empty (truncate above).
alter table public.carousels
  alter column theme_id     set not null,
  alter column slide_count  set not null,
  alter column content      set not null,
  alter column source_hash  set not null,
  alter column status       set not null,
  alter column generated_at set not null;

-- Status enum (drop+re-add so this re-runs cleanly).
alter table public.carousels drop constraint if exists carousels_status_check;
alter table public.carousels
  add constraint carousels_status_check
  check (status in ('generated', 'fallback'));

alter table public.carousels drop constraint if exists carousels_slide_count_check;
alter table public.carousels
  add constraint carousels_slide_count_check
  check (slide_count between 3 and 6);

create index if not exists carousels_source_hash_idx on public.carousels (source_hash);
create index if not exists carousels_generated_at_idx on public.carousels (generated_at);

-- ---------------------------------------------------------------------------
-- RLS: feed reads are public (anon), writes only by service_role.
-- ---------------------------------------------------------------------------

alter table public.carousels enable row level security;

drop policy if exists "carousels_public_read" on public.carousels;
create policy "carousels_public_read" on public.carousels
  for select using (true);

drop policy if exists "carousels_service_write" on public.carousels;
create policy "carousels_service_write" on public.carousels
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
