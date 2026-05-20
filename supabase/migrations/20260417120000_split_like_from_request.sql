create or replace function public.like_candidate(p_candidate_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_user_id and role = 'employer'
  ) then
    raise exception 'Only employers can like candidates';
  end if;

  insert into public.candidate_likes (employer_profile_id, candidate_profile_id)
  values (v_user_id, p_candidate_profile_id)
  on conflict (employer_profile_id, candidate_profile_id) do nothing;

  return p_candidate_profile_id;
end;
$$;

create or replace function public.request_interview(p_candidate_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_user_id and role = 'employer'
  ) then
    raise exception 'Only employers can request interviews';
  end if;

  if not exists (
    select 1 from public.candidate_likes
    where employer_profile_id = v_user_id
      and candidate_profile_id = p_candidate_profile_id
  ) then
    raise exception 'Candidate must be liked before requesting an interview';
  end if;

  insert into public.interview_requests (employer_profile_id, candidate_profile_id)
  values (v_user_id, p_candidate_profile_id)
  on conflict (employer_profile_id, candidate_profile_id) do nothing;

  select id
  into v_request_id
  from public.interview_requests
  where employer_profile_id = v_user_id
    and candidate_profile_id = p_candidate_profile_id;

  insert into public.notifications (profile_id, type, title, body, metadata)
  values (
    p_candidate_profile_id,
    'interview_request_created',
    'New interview request',
    'An employer requested an interview and invited you to choose a time.',
    jsonb_build_object('request_id', v_request_id, 'employer_profile_id', v_user_id)
  )
  on conflict do nothing;

  return v_request_id;
end;
$$;
