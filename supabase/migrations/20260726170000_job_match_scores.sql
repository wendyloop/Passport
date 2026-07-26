-- M-F: resume↔job match scores. One formula everywhere — this SQL mirrors
-- _shared/matching.ts mapSimilarityToScore exactly: cosine similarity
-- normalized through app_config-tunable floor/ceiling to 0-100. The gate
-- flag ships OFF: calibrate floor/ceiling on real pairs post-backfill, then
-- flip founder_email_require_match without a redeploy.

insert into public.app_config (key, value) values
  ('match_score_floor', '0.20'::jsonb),
  ('match_score_ceiling', '0.75'::jsonb),
  ('founder_email_min_match', '50'::jsonb),
  ('founder_email_require_match', 'false'::jsonb)
on conflict (key) do nothing;

-- Client-callable: scores for an explicit id-list, always the caller's own
-- resume embedding (auth.uid()). Exact <=> over ≤500 ids — no ANN needed.
create or replace function public.job_match_scores(p_job_ids uuid[])
returns table (job_id uuid, score int, quality text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with config as (
    select
      coalesce((select (value #>> '{}')::float from app_config where key = 'match_score_floor'), 0.20) as floor_v,
      coalesce((select (value #>> '{}')::float from app_config where key = 'match_score_ceiling'), 0.75) as ceiling_v
  )
  select
    e.job_id,
    round(greatest(0, least(1,
      ((1 - (e.embedding <=> cre.embedding)) - config.floor_v)
        / nullif(config.ceiling_v - config.floor_v, 0)
    )) * 100)::int,
    e.quality
  from job_embeddings e
  cross join config
  join candidate_resume_embeddings cre on cre.profile_id = auth.uid()
  where coalesce(array_length(p_job_ids, 1), 0) <= 500
    and e.job_id = any (p_job_ids);
$$;
revoke all on function public.job_match_scores(uuid[]) from public, anon;
grant execute on function public.job_match_scores(uuid[]) to authenticated;

-- Service-side variant for send-founder-email (service role has no
-- auth.uid()). Same formula, explicit candidate.
create or replace function public.founder_match_score(p_candidate uuid, p_job uuid)
returns table (score int, quality text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with config as (
    select
      coalesce((select (value #>> '{}')::float from app_config where key = 'match_score_floor'), 0.20) as floor_v,
      coalesce((select (value #>> '{}')::float from app_config where key = 'match_score_ceiling'), 0.75) as ceiling_v
  )
  select
    round(greatest(0, least(1,
      ((1 - (e.embedding <=> cre.embedding)) - config.floor_v)
        / nullif(config.ceiling_v - config.floor_v, 0)
    )) * 100)::int,
    e.quality
  from job_embeddings e
  cross join config
  join candidate_resume_embeddings cre on cre.profile_id = p_candidate
  where e.job_id = p_job;
$$;
revoke all on function public.founder_match_score(uuid, uuid) from public, anon, authenticated;
grant execute on function public.founder_match_score(uuid, uuid) to service_role;
