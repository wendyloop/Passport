-- S-4: record a candidate's own rewrite of a bullet.
--
-- Keyed by a hash of the ORIGINAL bullet text, and stored on the BASE resume,
-- so the correction survives every future tailoring of every job. Editing a
-- clumsy line once has to be enough; making someone re-fix it per application
-- is how a tailoring feature becomes work.
create or replace function public.set_bullet_override(
  p_resume_id  uuid,
  p_bullet_key text,
  p_text       text
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

  if p_bullet_key is null or btrim(p_bullet_key) = '' then
    raise exception 'bullet key required';
  end if;

  if p_text is null or btrim(p_text) = '' then
    -- Clearing an override restores the model's phrasing rather than leaving
    -- an empty bullet on the resume.
    update public.resume_uploads
    set bullet_overrides = coalesce(bullet_overrides, '{}'::jsonb) - p_bullet_key
    where id = p_resume_id;
  else
    update public.resume_uploads
    set bullet_overrides = coalesce(bullet_overrides, '{}'::jsonb)
                           || jsonb_build_object(p_bullet_key, btrim(p_text))
    where id = p_resume_id;
  end if;
end;
$$;

revoke all on function public.set_bullet_override(uuid, text, text) from public, anon;
grant execute on function public.set_bullet_override(uuid, text, text) to authenticated;
