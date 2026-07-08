-- Autofill v2 — Simplify-style profile autofill.
--
-- We already had `candidate_field_history` (upsert by field_label, newest-wins)
-- and `application_fields` (raw per-event capture). This migration adds the
-- two pieces missing for full autofill:
--
--   1. resume_uploads.parsed_json — full structured output from the LLM parser.
--      Lets us re-derive canonical fields later without re-running OpenAI.
--   2. candidate_essay_answers — free-text Q+A from prior applications, keyed
--      by question fingerprint + embedding for fuzzy retrieval.
--
-- We are intentionally NOT creating a new canonical-fields table — the existing
-- candidate_field_history already serves that purpose. Canonical keys go into
-- field_label using a stable prefix (see _shared/profile_fields.ts in the
-- function code), e.g. `canon:first_name`, `canon:salary_expectation`. Raw ATS
-- labels keep their natural form ("First name", "Desired salary"). One table,
-- one upsert path, no migration of existing data.

create extension if not exists vector with schema extensions;

-- ---------------------------------------------------------------------------
-- 1. resume_uploads.parsed_json
-- ---------------------------------------------------------------------------
--
-- We keep parsed_school_name + parsed_employers for back-compat with the v0
-- legacy flow (apply-to-job still reads parsed_employers). The new parser
-- writes the rich blob here AND back-fills the legacy columns so nothing
-- breaks.
alter table public.resume_uploads
  add column if not exists parsed_json jsonb;

-- ---------------------------------------------------------------------------
-- 2. candidate_essay_answers
-- ---------------------------------------------------------------------------
--
-- Free-text essay answers from job applications. Keyed by a normalized
-- fingerprint of the question so a re-asked-verbatim question updates the
-- existing row; semantically-similar questions are matched at query time via
-- the embedding column.
create table if not exists public.candidate_essay_answers (
  id                    uuid primary key default extensions.gen_random_uuid(),
  candidate_profile_id  uuid not null references public.profiles(id) on delete cascade,
  question_text         text not null,
  -- lowercased, trimmed, whitespace-collapsed; used as the upsert key so
  -- identical questions reused across applications mutate one row.
  question_norm         text not null,
  question_embedding    extensions.vector(1536),
  answer                text not null,
  source_job_id         uuid references public.jobs(id) on delete set null,
  source_event_id       uuid references public.application_events(id) on delete set null,
  created_at            timestamptz not null default timezone('utc', now()),
  updated_at            timestamptz not null default timezone('utc', now()),
  unique (candidate_profile_id, question_norm)
);

create index if not exists candidate_essay_answers_profile_idx
  on public.candidate_essay_answers (candidate_profile_id);

-- ivfflat needs at least a few hundred rows to be useful; for tiny tables
-- the planner will seq-scan anyway. Lists=100 is fine until ~100k rows.
create index if not exists candidate_essay_answers_embedding_idx
  on public.candidate_essay_answers
  using ivfflat (question_embedding extensions.vector_cosine_ops)
  with (lists = 100);

drop trigger if exists set_candidate_essay_answers_updated_at on public.candidate_essay_answers;
create trigger set_candidate_essay_answers_updated_at
before update on public.candidate_essay_answers
for each row execute function public.set_current_timestamp_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — same shape as candidate_field_history: owner-only reads + writes.
-- ---------------------------------------------------------------------------

alter table public.candidate_essay_answers enable row level security;

drop policy if exists "candidate_essay_answers_own" on public.candidate_essay_answers;
create policy "candidate_essay_answers_own" on public.candidate_essay_answers
  for all
  using (candidate_profile_id = auth.uid())
  with check (candidate_profile_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Similarity-search RPC.
--
-- Called by get-prefill-profile (or a new get-essay-suggestion endpoint) on
-- behalf of a candidate to fetch the closest prior answer for a question.
-- Caller embeds the new question client-side (in the edge function) and passes
-- the vector in.
-- ---------------------------------------------------------------------------
create or replace function public.match_candidate_essay(
  p_profile_id  uuid,
  p_embedding   extensions.vector(1536),
  p_min_score   float default 0.85,
  p_limit       int   default 1
)
returns table (
  id            uuid,
  question_text text,
  answer        text,
  similarity    float,
  source_job_id uuid,
  updated_at    timestamptz
)
language sql stable security definer set search_path = public, extensions
as $$
  select
    e.id,
    e.question_text,
    e.answer,
    1 - (e.question_embedding <=> p_embedding) as similarity,
    e.source_job_id,
    e.updated_at
  from public.candidate_essay_answers e
  where e.candidate_profile_id = p_profile_id
    and e.question_embedding is not null
    and 1 - (e.question_embedding <=> p_embedding) >= p_min_score
  order by e.question_embedding <=> p_embedding
  limit p_limit;
$$;

grant execute on function public.match_candidate_essay(uuid, extensions.vector, float, int)
  to authenticated, service_role;
