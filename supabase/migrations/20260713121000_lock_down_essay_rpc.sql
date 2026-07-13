-- DB-P1-2: match_candidate_essay is SECURITY DEFINER, takes the target
-- profile id as a parameter, and never checks auth.uid() — the authenticated
-- grant let any signed-in user probe any candidate's saved essay answers
-- (personal statements, salary answers, visa status…) with arbitrary
-- embeddings. Only the match-essay-answer edge function calls it, and it
-- does so with the service role, so the client grant was pure attack surface.

revoke all on function public.match_candidate_essay(uuid, extensions.vector, float, int)
  from public, anon, authenticated;
grant execute on function public.match_candidate_essay(uuid, extensions.vector, float, int)
  to service_role;
