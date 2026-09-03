-- S-3: cover letters.
--
-- Unlike essay answers, a letter is not reused verbatim — it names the
-- company in its first sentence. What survives across applications is the
-- VOICE, so an edited letter's value is as a style exemplar for the next one,
-- not as text to re-send.
create table if not exists public.candidate_cover_letters (
  id                    uuid primary key default extensions.gen_random_uuid(),
  candidate_profile_id  uuid not null references public.profiles(id) on delete cascade,
  job_id                uuid references public.jobs(id) on delete set null,
  body                  text not null,
  -- Same vocabulary and the same invariant as candidate_essay_answers.source:
  -- only 'human' and 'edited' letters are ever fed back as voice samples.
  -- Admitting 'generated' text would have every future letter shaped by the
  -- last generated one.
  source                text not null default 'generated'
    check (source in ('human', 'generated', 'edited')),
  created_at            timestamptz not null default timezone('utc', now()),
  updated_at            timestamptz not null default timezone('utc', now())
);

-- Newest-first per candidate, filtered to the two sources that can act as
-- voice samples. Mirrors candidate_essay_answers_voice_idx.
create index if not exists candidate_cover_letters_voice_idx
  on public.candidate_cover_letters (candidate_profile_id, updated_at desc)
  where source in ('human', 'edited');

drop trigger if exists set_candidate_cover_letters_updated_at on public.candidate_cover_letters;
create trigger set_candidate_cover_letters_updated_at
before update on public.candidate_cover_letters
for each row execute function public.set_current_timestamp_updated_at();

-- Owner-only, same shape as candidate_essay_answers: a cover letter is the
-- candidate's own writing about their own history.
alter table public.candidate_cover_letters enable row level security;

drop policy if exists "own cover letters readable" on public.candidate_cover_letters;
create policy "own cover letters readable"
  on public.candidate_cover_letters for select
  using (candidate_profile_id = auth.uid());

drop policy if exists "own cover letters writable" on public.candidate_cover_letters;
create policy "own cover letters writable"
  on public.candidate_cover_letters for insert
  with check (candidate_profile_id = auth.uid());

drop policy if exists "own cover letters updatable" on public.candidate_cover_letters;
create policy "own cover letters updatable"
  on public.candidate_cover_letters for update
  using (candidate_profile_id = auth.uid())
  with check (candidate_profile_id = auth.uid());

-- Cost guard, not a paywall — S-3 ships free like everything else.
insert into public.app_config (key, value) values
  ('cover_letters_enabled', 'true'::jsonb)
on conflict (key) do nothing;
