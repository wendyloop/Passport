-- S-1: AI-generated application answers.
--
-- Three-mode answer resolution (see suggest-application-answer):
--   reuse    — cosine >= 0.85 against a prior answer. No LLM call.
--   adapt    — 0.60 <= cosine < 0.85. LLM rewrites the closest prior answer.
--   generate — cosine < 0.60. Cold generation grounded in resume + voice.
--
-- The retrieval half already exists (candidate_essay_answers +
-- match_candidate_essay). This migration adds only what generation needs:
-- provenance on answers, and a record of what was suggested.

-- ---------------------------------------------------------------------------
-- 1. Provenance on candidate_essay_answers
-- ---------------------------------------------------------------------------
--
-- ANTI-SLOP INVARIANT: only 'human' and 'edited' rows are ever used as voice
-- samples when prompting. Feeding model-generated text back in as a style
-- exemplar collapses every future answer toward one synthetic voice within a
-- few months. `source` is what makes that rule enforceable in SQL rather than
-- a convention someone forgets.
--
-- Existing rows default to 'human', which is correct: every answer captured
-- before this migration was typed by the candidate on an ATS form.
alter table public.candidate_essay_answers
  add column if not exists source text not null default 'human';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'candidate_essay_answers_source_check'
  ) then
    alter table public.candidate_essay_answers
      add constraint candidate_essay_answers_source_check
      check (source in ('human', 'generated', 'edited'));
  end if;
end $$;

-- Voice-sample lookup is "newest N rows this candidate actually wrote".
create index if not exists candidate_essay_answers_voice_idx
  on public.candidate_essay_answers (candidate_profile_id, updated_at desc)
  where source in ('human', 'edited');

-- ---------------------------------------------------------------------------
-- 2. candidate_answer_suggestions
-- ---------------------------------------------------------------------------
--
-- What the assistant offered, so capture can tell accepted-verbatim from
-- edited. store-application-fields compares the submitted answer against the
-- newest suggestion for the same question_norm:
--   identical  -> source = 'generated'
--   different  -> source = 'edited'
--   no row     -> source = 'human'
--
-- Doubles as the tuning corpus: accept rate and edit distance per mode are
-- the only honest signal on whether a prompt change helped.
create table if not exists public.candidate_answer_suggestions (
  id                    uuid primary key default extensions.gen_random_uuid(),
  candidate_profile_id  uuid not null references public.profiles(id) on delete cascade,
  question_text         text not null,
  -- Same normalization as candidate_essay_answers.question_norm so the two
  -- join on equal terms (normalizeQuestion in _shared/openai_embeddings.ts).
  question_norm         text not null,
  suggested_answer      text not null,
  -- 'reuse' | 'adapt' | 'generate'
  mode                  text not null,
  -- The prior answer an 'adapt' was built from, for before/after inspection.
  source_answer_id      uuid references public.candidate_essay_answers(id) on delete set null,
  job_id                uuid references public.jobs(id) on delete set null,
  created_at            timestamptz not null default timezone('utc', now()),
  constraint candidate_answer_suggestions_mode_check
    check (mode in ('reuse', 'adapt', 'generate'))
);

create index if not exists candidate_answer_suggestions_lookup_idx
  on public.candidate_answer_suggestions
    (candidate_profile_id, question_norm, created_at desc);

-- Service-role only, same posture as job_embeddings / candidate_resume_embeddings:
-- RLS on with no policies means only the service role reaches it. Both writers
-- (suggest-application-answer, store-application-fields) are edge functions
-- holding the admin client; the client never reads this table.
alter table public.candidate_answer_suggestions enable row level security;

-- ---------------------------------------------------------------------------
-- 3. Config
-- ---------------------------------------------------------------------------
--
-- Everything ships FREE — these are cost guards, not a paywall.
--   ai_answers_enabled   kill-switch; false makes the function fall back to
--                        pure retrieval, exactly today's behaviour.
--   ai_answers_daily_cap per-candidate generate+adapt calls per UTC day. At
--                        gpt-4o-mini rates a generation is ~$0.0006, so this
--                        exists to bound a runaway loop, not to ration.
insert into public.app_config (key, value) values
  ('ai_answers_enabled', 'true'::jsonb),
  ('ai_answers_daily_cap', '60'::jsonb)
on conflict (key) do nothing;
