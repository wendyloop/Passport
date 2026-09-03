-- S-4: tailored resume versions.
--
-- The base resume is never mutated. Each tailored copy is its own row, so a
-- candidate can hold one per job and the original stays exactly as uploaded —
-- the same guarantee Simplify makes ("tailored resume is saved as a separate
-- version"), and the reason a bad tailoring pass can never cost anyone their
-- real resume.

create table if not exists public.resume_versions (
  id               uuid primary key default extensions.gen_random_uuid(),
  profile_id       uuid not null references public.profiles(id) on delete cascade,
  base_resume_id   uuid not null references public.resume_uploads(id) on delete cascade,
  -- Null for a version the candidate made by hand rather than for a posting.
  job_id           uuid references public.jobs(id) on delete set null,
  label            text,
  -- Same shape as resume_uploads.parsed_json, so ParsedResumeDetails decodes
  -- both and the PDF renderer takes either without branching.
  content          jsonb not null,
  -- Storage path of the rendered PDF, once one exists. Rendering happens on
  -- device, so a version can exist before its file does.
  file_path        text,
  -- Coverage at render time, for showing "72% -> 91%" after a tailoring pass.
  coverage_before  int,
  coverage_after   int,
  created_at       timestamptz not null default timezone('utc', now()),
  updated_at       timestamptz not null default timezone('utc', now())
);

create index if not exists resume_versions_profile_idx
  on public.resume_versions (profile_id, created_at desc);

-- One tailored version per (base resume, job). Re-tailoring the same posting
-- should update that row rather than accumulating near-identical copies;
-- partial so hand-made versions with a null job_id are unconstrained.
create unique index if not exists resume_versions_one_per_job
  on public.resume_versions (base_resume_id, job_id)
  where job_id is not null;

drop trigger if exists set_resume_versions_updated_at on public.resume_versions;
create trigger set_resume_versions_updated_at
before update on public.resume_versions
for each row execute function public.set_current_timestamp_updated_at();

alter table public.resume_versions enable row level security;

drop policy if exists "own resume versions readable" on public.resume_versions;
create policy "own resume versions readable"
  on public.resume_versions for select
  using (profile_id = auth.uid());

drop policy if exists "own resume versions writable" on public.resume_versions;
create policy "own resume versions writable"
  on public.resume_versions for insert
  with check (profile_id = auth.uid());

drop policy if exists "own resume versions updatable" on public.resume_versions;
create policy "own resume versions updatable"
  on public.resume_versions for update
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

drop policy if exists "own resume versions deletable" on public.resume_versions;
create policy "own resume versions deletable"
  on public.resume_versions for delete
  using (profile_id = auth.uid());

-- ---------------------------------------------------------------------------
-- bullet_overrides
-- ---------------------------------------------------------------------------
--
-- { "<bullet key>": "<the candidate's own rewrite>" }, keyed by a hash of the
-- ORIGINAL bullet text.
--
-- Deliberately on the BASE resume, not on the version. If an edit lived on the
-- version, every future tailoring would start from the model's phrasing again
-- and the candidate would re-fix the same clumsy line for every job they apply
-- to. On the base, one correction improves every subsequent tailoring.
alter table public.resume_uploads
  add column if not exists bullet_overrides jsonb not null default '{}'::jsonb;

insert into public.app_config (key, value) values
  ('resume_tailoring_enabled', 'true'::jsonb)
on conflict (key) do nothing;
