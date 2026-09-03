-- S-2: resume <-> job-description keyword gap.
--
-- Two additions:
--   1. resume_uploads.parsed_text — the resume's raw text, which was being
--      thrown away.
--   2. job_keywords — a lazily-filled cache of the requirement terms in a
--      job description.

-- ---------------------------------------------------------------------------
-- 1. resume_uploads.parsed_text
-- ---------------------------------------------------------------------------
--
-- parse-resume has always received rawText from the client (extracted on
-- device by ResumeTextExtractor) and persisted only the structured
-- parsed_json. That blob carries at most 30 skills plus employer titles and
-- education — no accomplishment bullets at all. Matching a job's requirements
-- against it therefore over-reports "missing": a resume that says "built ETL
-- pipelines in Airflow" in a bullet has no "Airflow" anywhere the matcher can
-- see unless the parser happened to lift it into skills.
--
-- Also a prerequisite for S-4: bullets cannot be tailored if they were never
-- stored.
--
-- No new exposure — the resume PDF itself already sits in the `resumes`
-- bucket, and this column inherits resume_uploads' existing owner-only RLS.
-- Existing rows stay null and the matcher falls back to parsed_json alone,
-- which is the pre-S-2 behaviour; they fill in on the next parse.
alter table public.resume_uploads
  add column if not exists parsed_text text;

-- ---------------------------------------------------------------------------
-- 2. job_keywords
-- ---------------------------------------------------------------------------
--
-- Requirement terms are a property of the JOB, identical for every candidate,
-- so they are extracted once and reused. Filled lazily by the first candidate
-- to open a job rather than by a cron: a backfill over every job would cost a
-- model call each across the whole corpus, and most jobs are never opened.
-- Popular jobs warm immediately; the long tail costs nothing.
--
-- description_hash guards staleness. Re-scraped postings change wording, and
-- keywords extracted from the old text would quietly mis-score every
-- candidate after that.
create table if not exists public.job_keywords (
  job_id           uuid primary key references public.jobs(id) on delete cascade,
  -- [{ term, kind: skill|tool|credential|domain, importance: required|preferred }]
  keywords         jsonb not null default '[]'::jsonb,
  description_hash text not null,
  model            text,
  created_at       timestamptz not null default timezone('utc', now()),
  updated_at       timestamptz not null default timezone('utc', now())
);

drop trigger if exists set_job_keywords_updated_at on public.job_keywords;
create trigger set_job_keywords_updated_at
before update on public.job_keywords
for each row execute function public.set_current_timestamp_updated_at();

-- Service-role only, same posture as job_embeddings. The keywords themselves
-- are derived from a public JD and are not sensitive, but the useful output is
-- the DIFF against a private resume, and that is computed in the edge function
-- — so the client never needs to read this table directly.
alter table public.job_keywords enable row level security;
