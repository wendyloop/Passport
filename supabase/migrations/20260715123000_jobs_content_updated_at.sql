-- DB-P1-5: every nightly ingest bumps last_seen_at on every re-seen job; the
-- generic updated_at trigger stamped updated_at for all ~30k rows, which made
-- get_jobs_needing_carousel's `j.updated_at > c.generated_at` arm true for
-- the whole catalog after each 06:00 run — the carousel queue re-processed
-- an arbitrary 90 forever while genuinely new jobs could starve behind the
-- window. Lifecycle-only updates (last_seen_at / is_active / closed_at /
-- last_founder_touch_at) no longer move updated_at; content changes still do.
-- Pairs with the generate-carousel change that bumps carousels.generated_at
-- on hash-skips.

create or replace function public.set_jobs_updated_at_on_content_change()
returns trigger
language plpgsql
as $$
begin
  if (to_jsonb(new) - 'updated_at' - 'last_seen_at' - 'is_active' - 'closed_at' - 'last_founder_touch_at')
     is distinct from
     (to_jsonb(old) - 'updated_at' - 'last_seen_at' - 'is_active' - 'closed_at' - 'last_founder_touch_at')
  then
    new.updated_at = timezone('utc', now());
  end if;
  return new;
end;
$$;

drop trigger if exists set_jobs_updated_at on public.jobs;
create trigger set_jobs_updated_at
before update on public.jobs
for each row execute function public.set_jobs_updated_at_on_content_change();
