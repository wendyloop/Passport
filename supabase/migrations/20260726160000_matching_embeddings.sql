-- M-E: matching foundations. Embeddings live in SEPARATE service-role-only
-- tables — never as columns on jobs / job_seeker_profiles, which the iOS
-- client fetches with select=* (a 1536-dim vector is ~34KB of JSON per row;
-- the feed would drag megabytes per load). Clients get scores only, via the
-- job_match_scores RPC (M-F).

create table if not exists public.job_embeddings (
  job_id      uuid primary key references public.jobs(id) on delete cascade,
  embedding   extensions.vector(1536) not null,
  quality     text not null default 'full' check (quality in ('full', 'title_only')),
  embedded_at timestamptz not null default timezone('utc', now())
);
alter table public.job_embeddings enable row level security;
-- No client policies by design: service role + security-definer RPCs only.

create table if not exists public.candidate_resume_embeddings (
  profile_id  uuid primary key references public.profiles(id) on delete cascade,
  embedding   extensions.vector(1536) not null,
  embedded_at timestamptz not null default timezone('utc', now())
);
alter table public.candidate_resume_embeddings enable row level security;
-- No client policies by design (also keeps resume vectors out of employer
-- reach under discovery RLS).

-- Queue probe for the embed-jobs cron: active/published jobs with no
-- embedding, or content updated since the last one (jobs.updated_at is
-- content-only since 20260715123000). Never-embedded rows first.
create or replace function public.get_jobs_needing_embedding(p_limit int default 300)
returns table (
  job_id uuid,
  title text,
  job_function text,
  company_name text,
  company_stage text,
  compensation_min_annual int,
  compensation_max_annual int,
  description text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    j.id,
    j.title,
    j.job_function::text,
    j.company_name,
    c.stage,
    j.compensation_min_annual,
    j.compensation_max_annual,
    j.description
  from jobs j
  left join companies c on c.id = j.company_id
  left join job_embeddings e on e.job_id = j.id
  where j.is_published
    and j.is_active
    and (e.job_id is null or j.updated_at > e.embedded_at)
  order by (e.job_id is null) desc, j.created_at desc
  limit p_limit;
$$;
revoke all on function public.get_jobs_needing_embedding(int) from public, anon, authenticated;
grant execute on function public.get_jobs_needing_embedding(int) to service_role;
