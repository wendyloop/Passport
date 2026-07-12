-- F7: founder slide in carousels ("meet Jane 👋" + pitch CTA).
--
-- 1. Slide-count cap rises 6 → 8: the full set is now cover + about + role
--    + requirements + perks + founder + details (7), with headroom.
-- 2. The carousel queue learns to regenerate when a company gains a contact
--    AFTER its carousel was generated — contacts arrive continuously from
--    the three extraction tiers, and jobs.updated_at doesn't move when they
--    do, so the existing arms would never pick those jobs up.

alter table public.carousels drop constraint if exists carousels_slide_count_check;
alter table public.carousels
  add constraint carousels_slide_count_check
  check (slide_count between 3 and 8);

create or replace function public.get_jobs_needing_carousel(p_limit int)
returns table (id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select j.id
  from public.jobs j
  left join public.carousels c on c.job_id = j.id
  where j.is_active
    and j.company_id is not null
    and (
      c.job_id is null
      or j.updated_at > c.generated_at
      -- A founder contact newer than the carousel → regen to add the slide.
      or exists (
        select 1 from public.company_contacts cc
        where cc.company_id = j.company_id
          and cc.created_at > c.generated_at
      )
    )
  order by (j.description is not null) desc, j.last_seen_at desc
  limit p_limit;
$$;

revoke all on function public.get_jobs_needing_carousel(int) from public, anon, authenticated;
grant execute on function public.get_jobs_needing_carousel(int) to service_role;
