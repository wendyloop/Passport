-- M-D: the iOS onboarding flow ships now and gates on
-- profiles.onboarding_complete (default false since init). Every
-- pre-existing account must never be dumped into first-run onboarding —
-- flip them all complete before the app update rolls out. Also aligns with
-- employer_candidate_discovery, which only lists onboarded candidates.
update public.profiles
set onboarding_complete = true
where onboarding_complete is distinct from true;
