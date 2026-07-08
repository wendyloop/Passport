-- Pitch v2: Unified board-driven job ingestion.
--
-- The board (Getro / Consider) becomes the source of truth for *which jobs
-- exist*. ATS adapters become a separate enrichment layer that only fills
-- description text on rows already inserted by the board ingestor.
--
-- Three things this migration does:
--   1. Drops NOT NULL on jobs columns that were authored for employer-posted
--      reels and silently rejected every ATS/board insert (employer_profile_id,
--      posted_by_profile_id, application_email, description). The old
--      sync-jobs path appeared to "run" but wrote nothing because of these.
--   2. Adds ats_external_id and dedup_key to jobs, plus a unique constraint
--      on dedup_key. dedup_key collapses the same posting seen across
--      multiple boards (Stripe in Accel + Sequoia) into one row, keeping
--      job_applications.job_id FKs stable forever.
--   3. Adds 'board' to source_kind and a bulk-upsert RPC that enforces
--      write-once content semantics: on conflict, only lifecycle fields
--      (last_seen_at, is_active, closed_at) update — title/apply_url/comp
--      stay frozen so a candidate's application keeps pointing at the
--      version of the posting they actually applied to.
--
-- Additive only. Old rows survive intact; legacy ats/employer_post/reel
-- rows continue to read and write through their existing paths.

-- ---------------------------------------------------------------------------
-- 1. Make legacy NOT NULLs nullable so non-reel jobs can be inserted.
-- ---------------------------------------------------------------------------

alter table public.jobs
  alter column employer_profile_id  drop not null,
  alter column posted_by_profile_id drop not null,
  alter column application_email    drop not null,
  alter column description          drop not null;

-- ---------------------------------------------------------------------------
-- 2. Add v2 columns.
-- ---------------------------------------------------------------------------

alter table public.jobs
  add column if not exists ats_external_id text,
  add column if not exists dedup_key       text;

-- ---------------------------------------------------------------------------
-- 3. Add 'board' to source_kind. Drop + re-add the check to widen it.
-- ---------------------------------------------------------------------------

alter table public.jobs
  drop constraint if exists jobs_source_kind_check;

alter table public.jobs
  add constraint jobs_source_kind_check
  check (source_kind in ('employer_post', 'reel', 'ats', 'board'));

-- ---------------------------------------------------------------------------
-- 4. Backfill dedup_key on every existing row so the unique constraint can
--    be added without failure. Rule order matches computeDedupKey() in TS:
--      a. (ats_type:external_id) when both present
--      b. apply_url when present
--      c. (source_kind:external_id) fallback so legacy rows still get a key
--      d. ('legacy:'||id) last-ditch so the column is never null
-- ---------------------------------------------------------------------------

update public.jobs
set dedup_key = case
  when ats_type    is not null and external_id is not null
    then ats_type || ':' || external_id
  when apply_url   is not null and length(apply_url) > 0
    then apply_url
  when source_kind is not null and external_id is not null
    then source_kind || ':' || external_id
  else
    'legacy:' || id::text
end
where dedup_key is null;

-- ---------------------------------------------------------------------------
-- 5. Enforce uniqueness. The constraint is essential: it is what guarantees
--    one job ↔ one row across boards, runs, and re-ingests, which in turn
--    keeps job_applications.job_id references stable.
-- ---------------------------------------------------------------------------

alter table public.jobs
  alter column dedup_key set not null;

create unique index if not exists jobs_dedup_key_unique
  on public.jobs (dedup_key);

-- ---------------------------------------------------------------------------
-- 6. Indexes that support the two hot read paths.
-- ---------------------------------------------------------------------------

-- enrich-descriptions reads: "for this company, jobs with no description"
create index if not exists jobs_needs_enrichment_idx
  on public.jobs (company_id, last_seen_at)
  where description is null and ats_type is not null and is_active = true;

-- ingest-jobs expiry sweep: "this board's active jobs we haven't seen recently"
create index if not exists jobs_board_seen_idx
  on public.jobs (source_board, last_seen_at)
  where source_board is not null and is_active = true;

-- ---------------------------------------------------------------------------
-- 7. Bulk upsert RPC for board jobs. One DB round-trip per page of
--    adapter output (typically 25–50 jobs at a time).
--
--    Write-once semantics are enforced HERE — at the database, not in TS —
--    so any caller (current or future) gets the same guarantees:
--      * INSERT  : writes all content + lifecycle fields
--      * CONFLICT: bumps last_seen_at, reactivates if previously expired,
--                  and NEVER updates title/apply_url/comp/etc.
-- ---------------------------------------------------------------------------

create or replace function public.upsert_board_jobs(p_jobs jsonb)
returns table (id uuid, dedup_key text, inserted boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  with input as (
    select * from jsonb_to_recordset(p_jobs) as t(
      dedup_key                text,
      company_id               uuid,
      company_name             text,
      source_board             text,
      board_external_id        text,
      apply_url                text,
      apply_flow               text,
      title                    text,
      location                 text,
      employment_type          text,
      compensation_text        text,
      compensation_min_annual  int,
      compensation_max_annual  int,
      compensation_min_hourly  int,
      compensation_max_hourly  int,
      ats_type                 text,
      ats_token                text,
      ats_external_id          text,
      source_url               text,
      now_ts                   timestamptz
    )
  ),
  upserted as (
    insert into public.jobs as j (
      dedup_key, company_id, company_name,
      source_kind, source_board, external_id,
      apply_url, apply_flow,
      title, location, employment_type,
      compensation_text,
      compensation_min_annual, compensation_max_annual,
      compensation_min_hourly, compensation_max_hourly,
      ats_type, ats_external_id,
      source_ats, source_url,
      is_published, is_active,
      first_seen_at, last_seen_at
    )
    select
      i.dedup_key, i.company_id, i.company_name,
      'board'::text, i.source_board, i.board_external_id,
      i.apply_url,
      coalesce(i.apply_flow, case when i.ats_type is not null then 'ats_form' else 'external_link' end),
      coalesce(i.title, 'Untitled role'), i.location, i.employment_type,
      i.compensation_text,
      i.compensation_min_annual, i.compensation_max_annual,
      i.compensation_min_hourly, i.compensation_max_hourly,
      i.ats_type, i.ats_external_id,
      i.ats_type, i.source_url,
      true, true,
      i.now_ts, i.now_ts
    from input i
    on conflict (dedup_key) do update set
      -- WRITE-ONCE: do NOT update content fields here.
      last_seen_at = excluded.last_seen_at,
      is_active    = true,
      closed_at    = null
    returning j.id, j.dedup_key, (j.xmax = 0) as inserted
  )
  select u.id, u.dedup_key, u.inserted from upserted u;
end;
$$;

-- Allow the service-role key (which is what edge functions use) to invoke.
grant execute on function public.upsert_board_jobs(jsonb) to service_role;
