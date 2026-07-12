-- DB-P0-2: non-board insert paths (Apify, shared reels, employer/admin
-- posting) predate source_kind/dedup_key and don't set them, so every such
-- insert has violated NOT NULL since 2026-06-18. Derive both in a BEFORE
-- INSERT trigger, mirroring the 20260627 backfill rules, so none of the four
-- client/function insert paths need to change. Fills NULLs only — the
-- upsert_board_jobs RPC sets both explicitly and is untouched.
create or replace function public.jobs_fill_ingest_defaults()
returns trigger
language plpgsql
as $$
begin
  if new.source_kind is null then
    new.source_kind := case
      when new.source_platform is not null then 'reel'
      else 'employer_post'
    end;
  end if;

  if new.dedup_key is null then
    new.dedup_key := case
      when new.ats_type is not null and new.external_id is not null
        then new.ats_type || ':' || new.external_id
      when new.apply_url is not null and length(new.apply_url) > 0
        then new.apply_url
      when new.source_url is not null and length(new.source_url) > 0
        then new.source_url
      else 'manual:' || new.id::text
    end;
  end if;

  return new;
end;
$$;

drop trigger if exists jobs_fill_ingest_defaults on public.jobs;
drop trigger if exists jobs_fill_ingest_defaults_before_insert on public.jobs;
create trigger jobs_fill_ingest_defaults_before_insert
before insert on public.jobs
for each row execute function public.jobs_fill_ingest_defaults();
