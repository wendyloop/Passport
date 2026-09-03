-- S-4: keep parsed_json whole when the profile editor saves.
--
-- Pre-existing bug, surfaced by adding bullets. `updateResumeParsedDetails`
-- PATCHes parsed_json with the encoding of ParsedResumeDetails, which carries
-- four keys: current_title, employers, education, skills. jsonb assignment
-- REPLACES, so every save silently dropped everything else the parser had
-- extracted — first_name, email, phone, city, state, school, field_of_study,
-- work_authorization, graduation_year.
--
-- It went unnoticed because autofill reads canonical values from
-- candidate_field_history, not from this blob. But S-2's keyword haystack
-- reads parsed_json, and S-4's tailoring reads employers[].bullets — an edit
-- would have erased the bullets a candidate was about to tailor.
--
-- Merging rather than replacing also means the client never has to send back
-- fields it does not model.
create or replace function public.update_resume_parsed_details(
  p_resume_id uuid,
  p_patch     jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
begin
  select profile_id into v_profile_id
  from public.resume_uploads
  where id = p_resume_id;

  -- Ownership check, not a filter: security definer bypasses RLS.
  if v_profile_id is null or v_profile_id <> auth.uid() then
    raise exception 'resume not found';
  end if;

  -- `||` is a SHALLOW merge, which is what is wanted here: the client sends
  -- whole arrays (employers, education, skills), and a deep merge would try
  -- to combine array elements positionally.
  update public.resume_uploads
  set parsed_json = coalesce(parsed_json, '{}'::jsonb) || p_patch,
      updated_at  = timezone('utc', now())
  where id = p_resume_id;
end;
$$;

revoke all on function public.update_resume_parsed_details(uuid, jsonb) from public, anon;
grant execute on function public.update_resume_parsed_details(uuid, jsonb) to authenticated;
