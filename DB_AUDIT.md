# DB_AUDIT.md — Supabase production-readiness audit

**Created 2026-07-12** — no prior DB_AUDIT.md existed; this is a full audit from
scratch. All findings are OPEN unless marked otherwise.

Scope: all 50 migrations in `supabase/migrations/`, all 20 edge functions +
`_shared/`, `supabase/config.toml`, and the iOS client's PostgREST queries
(read to determine what the feed actually filters/sorts on). Method: **static
analysis only — nothing was executed against the database.** Where a finding's
live impact depends on hosted state, the "Verify live" section at the bottom
gives read-only SQL to confirm.

Related docs: [AUDIT.md](AUDIT.md) is the general pre-launch audit (mostly iOS
+ function behavior). Overlapping items are cross-referenced, not duplicated —
except AUDIT P1-9 (internal notes), which is fundamentally a schema problem
and gets its fix SQL here.

---

## Verified clean, for the record

- **Every table has a primary key** (incl. composite PKs on `company_funds`,
  `candidate_field_history`) and RLS is **enabled on every table**, including
  the deliberately no-client-policy ones (`company_contacts`, `app_config`).
- No policy grants anon anything: after `20260711130000_m3_trust.sql` every
  read policy is `to authenticated` or predicated on `auth.uid()`.
- Privileged writes (apply, outreach, founder email, ingestion) all go through
  edge functions with the service role; `job_applications` and
  `founder_outreach_messages` have **no client INSERT policy** — correct.
- `reserve_founder_email_send` is race-safe (advisory lock), quota excludes
  failed sends, once-per-contact is a partial unique index — solid.
- `upsert_board_jobs` write-once semantics (content frozen on conflict) keep
  `job_applications.job_id` stable across re-ingests, and in-batch dedupe +
  500-row chunking make re-runs idempotent.
- Cron functions are fail-closed on `PITCH_CRON_SECRET`
  (`_shared/cron_auth.ts`); `resend-webhook` verifies Svix signatures
  timing-safely and fails closed; `job-share` 404s unpublished/inactive jobs
  and escapes all output.
- ATS/board dedupe keys are well designed (`ats_type:external_id` beats
  URL-with-tracking-params; partial unique indexes let reel/employer rows
  coexist).
- Migration hygiene: append-only, timestamped, idempotent re-run guards
  (`if not exists`, drop-before-create) throughout.

---

## P0 — exploitable or silently losing data right now

### DB-P0-1 · `upsert_board_jobs` is callable by anyone with the anon key

**RESOLVED 2026-07-12** — `20260712100000_lock_down_rpc_acls.sql` applied to the
hosted project. Verified live before the fix (anon-key RPC call with an empty
array returned HTTP 200; proacl showed `=X` / `anon=X` / `authenticated=X`) and
after: anon call now gets `42501 permission denied for function
upsert_board_jobs`, while the same call with the service role (the exact path
ingest-jobs uses) still returns 200. Post-fix sweep: no privileged RPC retains
PUBLIC EXECUTE — remaining PUBLIC-executable SECURITY DEFINER functions are
trigger/event-trigger functions (not client-callable), `mark_notifications_read`
(self-scoped via `auth.uid()` by design), and the two already tracked as
DB-P1-2 (`match_candidate_essay`) and DB-P2-3 (`request_interview`), still open.

[20260627120000_pitch_v2_unified.sql:185](supabase/migrations/20260627120000_pitch_v2_unified.sql#L185)
(and re-created in `20260627140000`, `20260709120000`, `20260709130000`).

Postgres grants `EXECUTE` on new functions to `PUBLIC` **by default**. Every
other privileged RPC in this schema explicitly revokes it
(`get_jobs_needing_carousel`, `get_stale_enrichable_companies`,
`get_companies_needing_contact_scrape`, `reserve_founder_email_send`) — but
`upsert_board_jobs` only ever ran `grant execute … to service_role` and never
revoked `PUBLIC`. `CREATE OR REPLACE` preserves the ACL, so the later
re-definitions didn't change this.

Consequence: `POST /rest/v1/rpc/upsert_board_jobs` with the **anon key** (ships
in the IPA by design) lets anyone bulk-insert arbitrary rows into `jobs` with
`is_published = true, is_active = true` — i.e. inject arbitrary content
(including malicious `apply_url`s) directly into every user's feed — and
reactivate any expired job by replaying its `dedup_key` (`is_active = true,
closed_at = null`). The function is `SECURITY DEFINER`, so RLS is bypassed.

**Fix (migration `2026XXXXXXXXXX_lock_down_rpc_acls.sql`):**

```sql
-- P0: upsert_board_jobs was callable by PUBLIC (default fn ACL, never revoked).
revoke all on function public.upsert_board_jobs(jsonb) from public, anon, authenticated;
-- service_role grant already exists; re-assert for clarity.
grant execute on function public.upsert_board_jobs(jsonb) to service_role;
```

Also sweep for the same bug class (see DB-P1-2 for `match_candidate_essay`,
DB-P2-4 for `resolve_profile_role`). Rule going forward: every
`create function` migration ends with an explicit `revoke … from public, anon,
authenticated` plus the narrowest grant.

### DB-P0-2 · Every non-board jobs insert path violates NOT NULL — Apify ingest is silently writing nothing

**RESOLVED 2026-07-12** — `20260712101000_fill_ingest_defaults.sql` applied to
the hosted project (as specced below, with the `drop trigger` syntax corrected).
Verified live before the fix: zero `reel` rows since 2026-06-09 and zero
`employer_post` rows since 2026-05-21. Verified after, in a single self-cleaning
transaction replicating each path's exact column set: Apify-shaped insert →
`source_kind='reel'`, `dedup_key=source_url`, and a duplicate re-send under
`ON CONFLICT (source_url) DO NOTHING` inserts 0 rows; shared-reel-shaped insert
→ `reel`/`source_url`; iOS employer post and admin social import (executed as
the `authenticated` role with real employer/admin JWT claims, so RLS was
exercised) → `employer_post`/`manual:<id>` and `reel`/`source_url`; explicitly
set `source_kind`/`dedup_key` pass through untouched; `upsert_board_jobs` still
lands `board` rows with its own dedup_key, replays return `inserted=false` with
content frozen and `last_seen_at` bumped. One caveat found during verification:
`scrape_query_stats` has **no rows at all** since 06-09 — the Apify webhook is
currently 401ing at the gateway (see DB-P1-1), and the `daily-apify-scrape`
cron job is disabled (`active=false`), so the "next scrape_query_stats row has
inserted > 0" check can only run once those are back on.

Two constraints, added for the board pipeline, have no default and no trigger:

- `source_kind text NOT NULL` since
  [20260618000000_pitch_v1.sql:86](supabase/migrations/20260618000000_pitch_v1.sql#L86)
- `dedup_key text NOT NULL` since
  [20260627120000_pitch_v2_unified.sql:83](supabase/migrations/20260627120000_pitch_v2_unified.sql#L83)

The only writer that sets them is the `upsert_board_jobs` RPC (hardcodes
`'board'` + takes `dedup_key` as input). Every other insert path sets
**neither** column, so every such insert fails with a NOT NULL violation:

| Path | Where | Failure mode |
|---|---|---|
| Apify scrape results | [process-apify-results/index.ts:456-496](supabase/functions/process-apify-results/index.ts#L456) | **Silent** — bulk-upsert error is only `console.error`'d ([:492](supabase/functions/process-apify-results/index.ts#L492)), function returns 200 to Apify, `scrape_query_stats.inserted` records 0 |
| Shared reel (share extension) | [ingest-shared-reel/index.ts:240](supabase/functions/ingest-shared-reel/index.ts#L240) | Error returned to the admin's share sheet |
| Admin social import + employer job posting (iOS, direct PostgREST) | [SupabaseService.swift:247-303](ios-native/JobTok/SupabaseService.swift#L247) | PostgREST 400 surfaced in the app |

Net: since 2026-06-18 (source_kind) no reel/employer/admin/Apify job can have
been inserted; the Apify pipeline in particular has been paying for actor runs
and discarding every result without any alert. (M4 "apify bulk ingest" shipped
against a broken insert — the pipeline_rescue diagnosis only covered board
rows.)

**Fix (migration `2026XXXXXXXXXX_fill_ingest_defaults.sql`)** — a BEFORE INSERT
trigger that derives both columns exactly like the v2 backfill did, so none of
the four client/function insert paths need to change:

```sql
-- Non-board insert paths (Apify, shared reels, employer/admin posting) predate
-- source_kind/dedup_key and don't set them. Derive both, mirroring the
-- 20260627 backfill rules, so those inserts stop violating NOT NULL.
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

drop trigger if exists jobs_fill_ingest_defaults before insert on public.jobs;
drop trigger if exists jobs_fill_ingest_defaults_before_insert on public.jobs;
create trigger jobs_fill_ingest_defaults_before_insert
before insert on public.jobs
for each row execute function public.jobs_fill_ingest_defaults();
```

Notes: `new.id` is already populated in a BEFORE trigger (column default
applies first). Reels get `dedup_key = source_url`, which cannot collide with
the legacy backfill (pre-v2 reels got `legacy:<id>`), and `jobs_source_url_unique`
already guarantees URL uniqueness on that path. After deploying, re-test one
share-extension import and one employer post, and check the next
`scrape_query_stats` row has `inserted > 0`.

---

## P1 — fix before real users

### DB-P1-1 · `process-apify-results` missing from config.toml's `verify_jwt` list

**RESOLVED 2026-07-12** — config entry added and committed. Verified live that
this was not just a future-deploy hazard: the deployed function has
`verify_jwt = true` right now (Management API), and a webhook-shaped request
(no JWT) is rejected at the gateway with `UNAUTHORIZED_NO_AUTH_HEADER` — every
Apify webhook since the 2026-07-08 bare deploy has been dropped before reaching
the function, which is why `scrape_query_stats` is empty since 06-09.
**Remaining step (one command):** `supabase functions deploy
process-apify-results` — it now picks up `verify_jwt = false` from config.toml
and unbreaks the live webhook.

[config.toml:392-417](supabase/config.toml#L392) lists `resend-webhook`,
the four cron functions, `trigger-apify-scrape`, and `job-share` — but not
`process-apify-results`. Apify webhooks carry only the
`x-apify-webhook-secret` header, no Supabase JWT, so the function must run
with gateway JWT verification off. Without the config entry, the next plain
`supabase functions deploy` re-enables verification and every webhook 401s at
the gateway — the exact incident CLAUDE.md documents for 2026-07-08, and
doubly silent because Apify just logs the failed webhook and moves on.

**Fix (config.toml, no migration):**

```toml
# Apify result webhooks authenticate via x-apify-webhook-secret, not a JWT.
[functions.process-apify-results]
verify_jwt = false
```

Then redeploy the function once so the setting is applied.

### DB-P1-2 · `match_candidate_essay` lets any authenticated user read any candidate's essay answers

**RESOLVED 2026-07-13** — `20260713121000_lock_down_essay_rpc.sql` applied to
the hosted project. Verified over live REST with real JWTs: the RPC returns
403 for a signed-in user probing another candidate's id AND for the essay's
own author (service-role only, matching the edge-function path); a
`set local role service_role` execution still succeeds.

[20260629010000_autofill_v2.sql:122](supabase/migrations/20260629010000_autofill_v2.sql#L122)
grants it `to authenticated, service_role`. The function is `SECURITY
DEFINER`, takes `p_profile_id` as a **parameter**, and never checks
`auth.uid()` — so any signed-in user can call
`/rest/v1/rpc/match_candidate_essay` with someone else's profile id and probe
their saved application essays (personal statements, salary answers, visa
status…) with arbitrary embeddings. The edge function
(`match-essay-answer`) calls it with the service role, so the client grant is
unnecessary.

**Fix (same `lock_down_rpc_acls` migration as DB-P0-1):**

```sql
revoke all on function public.match_candidate_essay(uuid, extensions.vector, float, int)
  from public, anon, authenticated;
grant execute on function public.match_candidate_essay(uuid, extensions.vector, float, int)
  to service_role;
```

### DB-P1-3 · `discovery_visibility` is not enforced by RLS — "private" candidates are fully readable, including email and phone

**RESOLVED 2026-07-13** — `20260713122000_enforce_discovery_visibility.sql` +
`20260713123000_fix_visibility_policy_recursion.sql` applied to the hosted
project. As specced below, with two deltas: (1) the `profiles` employer arm is
*also* gated by the candidate's visibility (not role-wide as sketched), so a
private candidate's email is hidden from employers too; (2) the
applied-to-employer probe runs through a new SECURITY DEFINER helper
`candidate_applied_to_employer(uuid)` because the plain `job_applications`
subquery recursed (job_applications' own select policy subqueries profiles →
42P17 infinite recursion — caught by the REST verification harness, first
push briefly broke all four tables' reads until the follow-up migration).
Verified over live REST with real JWTs (private candidate with phone/comp who
applied to the employer's job): another job seeker reads nothing from any of
the four tables; the applied employer reads nothing while the candidate is
private; flipping to discoverable opens the employer paths (base rows + the
discovery view) while the other job seeker stays blocked; owner reads all
their own rows throughout.

The `employer_candidate_discovery` view filters on
`discovery_visibility = 'discoverable_to_hiring_employers'` and viewer role,
but it's `security_invoker` — the real gate is the base-table policies, and
those let **any authenticated user** (including every other job seeker) read
every onboarded candidate's row regardless of visibility setting:

- `profiles` "readable by owner or public job seekers"
  ([init_passport.sql:662-670](supabase/migrations/20260413150000_init_passport.sql#L662))
  — exposes `email` (citext, on the row!), full name, handle, avatar.
- `job_seeker_profiles` "readable by owner or public"
  ([:709-723](supabase/migrations/20260413150000_init_passport.sql#L709)) —
  exposes `phone`, `city`, `desired_compensation_range`,
  `desired_compensation_annual`, `linkedin_url`, `instagram_username`,
  `tiktok_username`, `github_url`, `portfolio_url`.
- Same shape on `job_seeker_employers` and `candidate_videos`.

A candidate who sets visibility to `private` (or the default
`applied_roles_only`) is still harvestable via direct PostgREST reads with any
job-seeker account. Current clients don't need cross-candidate reads: the job
feed reads `jobs`/`companies`/`carousels` only, and employer discovery goes
through the view (which keeps working under the tighter policies below).

**Fix (migration `2026XXXXXXXXXX_enforce_discovery_visibility.sql`):**

```sql
-- Helper: role check that bypasses RLS (a profiles policy can't subquery
-- profiles directly — infinite recursion).
create or replace function public.auth_role_in(p_roles text[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role::text = any (p_roles)
  );
$$;
revoke all on function public.auth_role_in(text[]) from public, anon;
grant execute on function public.auth_role_in(text[]) to authenticated;

-- profiles: owner, or hiring-side roles. Job seekers can no longer read
-- other job seekers' rows (email!).
drop policy if exists "Profiles are readable by owner or public job seekers" on public.profiles;
create policy "Profiles readable by owner or hiring roles"
on public.profiles
for select
to authenticated
using (
  auth.uid() = id
  or public.auth_role_in(array['employer', 'admin'])
);

-- job_seeker_profiles: owner, admin, or employer — and employers only see
-- candidates who are discoverable, or who applied to one of their jobs
-- (applied_roles_only semantics).
drop policy if exists "Job seeker profiles readable by owner or public" on public.job_seeker_profiles;
create policy "Job seeker profiles readable per visibility"
on public.job_seeker_profiles
for select
to authenticated
using (
  auth.uid() = profile_id
  or public.auth_role_in(array['admin'])
  or (
    public.auth_role_in(array['employer'])
    and (
      discovery_visibility = 'discoverable_to_hiring_employers'
      or (
        discovery_visibility <> 'private'
        and exists (
          select 1 from public.job_applications ja
          where ja.candidate_profile_id = job_seeker_profiles.profile_id
            and ja.employer_profile_id = auth.uid()
        )
      )
    )
  )
);

-- Same gate for the two satellite tables the discovery view joins.
drop policy if exists "Job seeker employers readable by owner or public" on public.job_seeker_employers;
create policy "Job seeker employers readable per visibility"
on public.job_seeker_employers
for select
to authenticated
using (
  auth.uid() = profile_id
  or public.auth_role_in(array['admin'])
  or (
    public.auth_role_in(array['employer'])
    and exists (
      select 1 from public.job_seeker_profiles jsp
      where jsp.profile_id = job_seeker_employers.profile_id
        and (
          jsp.discovery_visibility = 'discoverable_to_hiring_employers'
          or (
            jsp.discovery_visibility <> 'private'
            and exists (
              select 1 from public.job_applications ja
              where ja.candidate_profile_id = job_seeker_employers.profile_id
                and ja.employer_profile_id = auth.uid()
            )
          )
        )
    )
  )
);

drop policy if exists "Candidate videos are readable by owner or public" on public.candidate_videos;
create policy "Candidate videos readable per visibility"
on public.candidate_videos
for select
to authenticated
using (
  auth.uid() = profile_id
  or public.auth_role_in(array['admin'])
  or (
    public.auth_role_in(array['employer'])
    and exists (
      select 1 from public.job_seeker_profiles jsp
      where jsp.profile_id = candidate_videos.profile_id
        and (
          jsp.discovery_visibility = 'discoverable_to_hiring_employers'
          or (
            jsp.discovery_visibility <> 'private'
            and exists (
              select 1 from public.job_applications ja
              where ja.candidate_profile_id = candidate_videos.profile_id
                and ja.employer_profile_id = auth.uid()
            )
          )
        )
    )
  )
);
```

Before shipping: grep the iOS app for any candidate-role read of another
user's `profiles`/`candidate_videos` row (none found in this audit — the feed
and apply paths never do it), and note `profiles.email` remains visible to
employers; if that's unwanted, move email behind a view next.

### DB-P1-4 · Employer "private" notes are readable by the candidate (= AUDIT P1-9) — schema fix

**RESOLVED 2026-07-13** — `20260713120000_application_notes_table.sql` applied
(as specced below) together with the iOS change: `updateApplication` writes
notes via upsert to `application_notes`, employer application fetches embed
`application_notes(notes)`, and `JobApplicationRecord.internalNotes` is a
computed property over the embed. Verified over live REST with real JWTs:
candidate gets 400 selecting the dropped column, zero `application_notes`
rows, an empty embed, and a 403 writing to the table; the employer's
write + embedded read both work.

`job_applications.internal_notes`
([m3_trust.sql:33](supabase/migrations/20260711130000_m3_trust.sql#L33)) is on
a row the candidate can SELECT (participants policy,
[jobtok_mvp.sql:160-174](supabase/migrations/20260519100000_jobtok_mvp.sql#L160)),
and the iOS client fetches `select=*`. RLS is row-level; a column can't be
hidden per-viewer. Move notes to an employer-only table:

**Fix (migration `2026XXXXXXXXXX_application_notes_table.sql`):**

```sql
create table if not exists public.application_notes (
  application_id       uuid primary key references public.job_applications(id) on delete cascade,
  employer_profile_id  uuid not null references public.profiles(id) on delete cascade,
  notes                text,
  created_at           timestamptz not null default timezone('utc', now()),
  updated_at           timestamptz not null default timezone('utc', now())
);

drop trigger if exists set_application_notes_updated_at on public.application_notes;
create trigger set_application_notes_updated_at
before update on public.application_notes
for each row execute function public.set_current_timestamp_updated_at();

alter table public.application_notes enable row level security;

create policy "application_notes_employer_only"
on public.application_notes
for all
to authenticated
using (employer_profile_id = (select auth.uid()))
with check (
  employer_profile_id = (select auth.uid())
  and exists (
    select 1 from public.job_applications ja
    where ja.id = application_notes.application_id
      and ja.employer_profile_id = (select auth.uid())
  )
);

-- Migrate existing notes, then remove the leaking column.
insert into public.application_notes (application_id, employer_profile_id, notes)
select id, employer_profile_id, internal_notes
from public.job_applications
where internal_notes is not null
  and employer_profile_id is not null
on conflict (application_id) do nothing;

alter table public.job_applications drop column if exists internal_notes;
```

Requires a matching iOS change (read/write `application_notes` instead of the
column) — ship together.

### DB-P1-5 · Carousel queue re-wedges: every nightly ingest marks all ~30k jobs as "needs regeneration"

**RESOLVED 2026-07-15** — `20260715123000_jobs_content_updated_at.sql`
applied: `jobs.updated_at` now means *content* changed (lifecycle columns —
last_seen_at / is_active / closed_at / last_founder_touch_at — no longer
bump it). Verified live in a self-cleaning transaction: a lifecycle-only
update leaves a pinned 2020 updated_at untouched; a title change bumps it.
Belt-and-braces code change shipped too: generate-carousel's hash-skip
branch now bumps `carousels.generated_at`, so hash-matched jobs leave the
queue under either trigger semantics (`generate-carousel` deployed
2026-07-16; 99 clean runs recorded by 2026-07-17).

Chain: `upsert_board_jobs` bumps `last_seen_at` on every re-seen job → the
generic `set_jobs_updated_at` trigger
([jobtok_mvp.sql:109-112](supabase/migrations/20260519100000_jobtok_mvp.sql#L109))
stamps `updated_at = now()` → `get_jobs_needing_carousel`'s
`j.updated_at > c.generated_at` arm
([founder_slide.sql](supabase/migrations/20260711120000_founder_slide.sql)) is
true for **every active job** after each 06:00 ingest → the queue returns an
arbitrary 90 of ~30k (all bumped in the same batch share `last_seen_at`, so
the ordering is arbitrary within a fund) → generate-carousel hash-skips most of
them ([generate-carousel/index.ts:265-268](supabase/functions/generate-carousel/index.ts#L265))
**without bumping `generated_at`**, so the same 90 come back every 30-minute
run, and genuinely new/changed jobs behind the window may never be reached.
This is the same failure shape pipeline_rescue fixed on 2026-07-09, recreated
one level up.

**Fix (migration `2026XXXXXXXXXX_jobs_content_updated_at.sql`)** — make
`jobs.updated_at` mean *content* changed by ignoring lifecycle-only updates:

```sql
-- Lifecycle bumps (last_seen_at / is_active / closed_at /
-- last_founder_touch_at) fire on every nightly ingest for every active job;
-- letting them move updated_at re-marks the whole catalog as
-- "needs carousel regeneration" daily. Only content changes should.
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
```

Belt-and-braces code change (no migration): in generate-carousel's hash-match
skip branch, `update carousels set generated_at = now() where job_id = …` so a
hash-matched job also leaves the queue under the old trigger semantics.

### DB-P1-6 · `founder_email_sent` notification type doesn't exist in the enum — insert silently fails

**RESOLVED 2026-07-15** — `20260715122000_founder_email_sent_notification.sql`
applied (`add value if not exists 'founder_email_sent'`). Confirmed live in a
self-cleaning transaction: an insert with the exact shape send-founder-email
uses succeeds and the enum label is present. Code follow-up shipped too: the
insert error is now checked and logged so enum drift can't be silent again
(`send-founder-email` deployed 2026-07-16).

[send-founder-email/index.ts:221](supabase/functions/send-founder-email/index.ts#L221)
inserts `type: "founder_email_sent"`, but `notification_type` only has the 10
labels from init/mvp/phase2 (checked all `alter type … add value` migrations).
Every insert fails with `invalid input value for enum`, and the result is
**unchecked**, so the send succeeds while the candidate's "Founder intro sent"
notification never appears. (Same unchecked-insert pattern exists in
apply-to-job and reach-out-to-candidate, but those use valid labels.)

**Fix (migration `2026XXXXXXXXXX_founder_email_sent_notification.sql`):**

```sql
alter type public.notification_type add value if not exists 'founder_email_sent';
```

Code follow-up: check the `insert` error in send-founder-email (and log it) so
enum drift can't be silent again.

### DB-P1-7 · A single bad board response can soft-close an entire fund's jobs

In ingest-jobs, an **empty** adapter result is indistinguishable from a
drained board: `batch.length === 0` → `drained = true` → `nextCursor = null` →
the expiry sweep runs ([ingest-jobs/index.ts:252-259](supabase/functions/ingest-jobs/index.ts#L252)).
If Getro/Consider has an incident that returns 200-with-zero-jobs (seen in the
wild on both platforms), no `last_seen_at` gets bumped and everything older
than the 48h grace (i.e. after just two such daily runs, or one run after a
skipped cron day) is marked `is_active = false`. Recovery is automatic on the
next good run (upsert reactivates), but meanwhile the feed empties and
`closed_at` analytics are polluted.

**Fix (code, no migration):** skip the sweep when the run saw zero jobs —
e.g. in `ingestFund`, only call `sweepExpired` when `result.nextCursor === null
&& result.jobs.length > 0`. Optionally also raise `EXPIRY_GRACE_MS` to 72h so
one bad day + one skipped cron can't combine.

### DB-P1-8 · Deleting a job or account cascades away candidates' application history

- `job_applications.job_id → jobs ON DELETE CASCADE`: an employer deleting
  their own job (RLS `for all` allows it) or an admin cleanup **deletes every
  candidate's application row** — the snapshot columns (`job_title`,
  `company_name`, …) exist precisely so applications outlive jobs, but the
  cascade deletes the whole row before they can help.
- `application_events.job_id → jobs ON DELETE CASCADE` similarly erases funnel
  analytics; `application_fields` cascades off events in turn.
- `jobs.posted_by_profile_id → profiles ON DELETE CASCADE`: `delete-account`
  by an employer deletes their jobs → cascades applications.

**Fix (migration `2026XXXXXXXXXX_preserve_application_history.sql`)** — keep
candidate-visible history when a job goes away:

```sql
alter table public.job_applications
  alter column job_id drop not null;

alter table public.job_applications
  drop constraint if exists job_applications_job_id_fkey;
alter table public.job_applications
  add constraint job_applications_job_id_fkey
  foreign key (job_id) references public.jobs(id) on delete set null;

alter table public.application_events
  drop constraint if exists application_events_job_id_fkey;
alter table public.application_events
  alter column job_id drop not null;
alter table public.application_events
  add constraint application_events_job_id_fkey
  foreign key (job_id) references public.jobs(id) on delete set null;
```

Note: the `unique (job_id, candidate_profile_id)` dup-guard treats NULLs as
distinct, so nulled-out history rows can't block future applications. This is
partly a product decision (maybe employer-deleted jobs *should* erase
applications?) — decide explicitly, don't leave it to the default.

### DB-P1-9 · Pipeline failures are only visible in ephemeral function logs; cron HTTP results are discarded

**RESOLVED 2026-07-13; fully live 2026-07-16** —
`20260713124000_pipeline_runs.sql` applied to the hosted project (as specced,
with the admin-read policy using the `auth_role_in` helper from DB-P1-3's
fix). Verified live in a self-cleaning transaction: service-role insert
works, a non-admin authenticated user sees zero rows. New
`_shared/pipeline_runs.ts` (`recordPipelineRun`, fail-open + pure
`buildPipelineRunRow` covered by 2 Deno tests); one insert call added to all
four cron functions **and** `process-apify-results` (success and error paths
— gateway-level drops surface as row *absence*, which is the query that
catches them). All five functions were deployed 2026-07-16 (which also completed DB-P1-1's
pending redeploy). Confirmed end-to-end 2026-07-17: all five record rows —
99 generate-carousel runs (0 errors), 50 enrich-descriptions runs (130
company-level errors logged — real signal, worth investigating),
2 ingest-jobs runs (0 errors), 25 retry-application-emails runs (0 errors),
2 enrich-company-contacts runs (9 errors).

- ingest-jobs / enrich-descriptions / generate-carousel / enrich-company-contacts
  all report rich per-run summaries — as `console.log` JSON only. Supabase
  function logs rotate quickly; there is no queryable history. (Contrast:
  the Apify path persists `scrape_query_stats`.) The June "every run processed
  zero jobs for 10 days" incident was invisible for exactly this reason.
- The pg_cron jobs `select net.http_post(…)` and drop the result; a 401/500
  from the function (the 2026-07-08 verify_jwt incident) is only in
  `net._http_response`, which nobody reads and which pg_net prunes.

**Fix (migration `2026XXXXXXXXXX_pipeline_runs.sql` + one code line per function):**

```sql
create table if not exists public.pipeline_runs (
  id            uuid primary key default extensions.gen_random_uuid(),
  function_name text not null,
  started_at    timestamptz not null default timezone('utc', now()),
  duration_ms   integer,
  summary       jsonb not null default '{}'::jsonb,
  error_count   integer not null default 0
);

create index if not exists pipeline_runs_fn_started_idx
  on public.pipeline_runs (function_name, started_at desc);

alter table public.pipeline_runs enable row level security;

create policy "pipeline_runs_admin_read"
on public.pipeline_runs
for select
to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role::text = 'admin'
  )
);
-- writes: service role only (no client policies)
```

Code: each cron function already builds a `summary` object — add one
`admin.from("pipeline_runs").insert({ function_name, summary, duration_ms,
error_count })` before returning. Then a stale-run check ("no successful
ingest-jobs run in 36h") becomes one SQL query / future admin-screen widget.

---

## P2 — worth doing, not blocking

### DB-P2-1 · Feed queries have no matching index

The iOS feed ([SupabaseService.swift:169-221](ios-native/JobTok/SupabaseService.swift#L169))
runs two queries: `is_published=true AND is_active=true AND source_kind IN
(…) ORDER BY created_at DESC LIMIT 200`. The only relevant index,
`jobs_published_created_at_idx (is_published, created_at)`, forces the
reel/employer query to walk past tens of thousands of newer board rows to
collect 200 reels. At ~33k rows it's tolerable; it degrades linearly with
catalog growth.

```sql
create index if not exists jobs_feed_reels_idx
  on public.jobs (created_at desc)
  where is_published and is_active and source_kind in ('reel', 'employer_post');

create index if not exists jobs_feed_board_idx
  on public.jobs (created_at desc)
  where is_published and is_active and source_kind in ('ats', 'board');

-- The original is now redundant with the two partials + employer index:
drop index if exists public.jobs_published_created_at_idx;
```

ATS-sync hot paths checked and already covered: enrichment pending-jobs and
company-queue probes hit `jobs_needs_enrichment_idx`, the expiry sweep hits
`jobs_board_seen_idx`, Apify dedupe hits `jobs_source_url_unique`, upserts hit
`jobs_dedup_key_unique`, company dedupe hits `companies` domain/ATS/board
indexes, `get_jobs_needing_carousel` is a seq-scan+left-join (fine at this
scale, revisit past ~100k jobs).

### DB-P2-2 · Missing index for the founder-email per-company cap

send-founder-email counts `founder_outreach_messages` by `company_id` +
`created_at` window on every preview/send; only candidate/contact/resend
indexes exist.

```sql
create index if not exists founder_outreach_company_created_idx
  on public.founder_outreach_messages (company_id, created_at desc);
```

### DB-P2-3 · Dead schema: two orphaned columns, one dead column+code pair, one broken function, stale enum labels

- `jobs.carousel_slide_urls` (jsonb) and `jobs.company_stage` — v0 leftovers
  from `20260602000000_carousel_and_ats.sql`; zero references in Swift or TS.
- `jobs.content_hash` — the ATS adapters still compute `content_hash` per job,
  but nothing ever writes it to the table (enrich-descriptions only writes
  description/description_raw/posting_contact_email). Drop the column and the
  now-dead `computeContentHash` calls, or start persisting it — not the
  current half-state.
- `public.request_interview(uuid)` (from `20260417120000`) survived the
  legacy-Passport drop but references the dropped `candidate_likes` +
  `interview_requests` tables — any caller gets a runtime error; it's also
  PUBLIC-executable (same ACL class as DB-P0-1).
- `notification_type` still carries 7 legacy labels (`slot_selected`,
  `calendar_sync_needed`, …). Harmless (enum labels can't be dropped without a
  type rebuild) — document and ignore.

```sql
alter table public.jobs
  drop column if exists carousel_slide_urls,
  drop column if exists company_stage,
  drop column if exists content_hash;

drop function if exists public.request_interview(uuid);
```

### DB-P2-4 · `resolve_profile_role` is PUBLIC-executable — email→role probing

Default fn ACL again: any authenticated user can call
`/rpc/resolve_profile_role` with an arbitrary email and learn whether it's
pre-assigned employer/admin. Low impact, but it's a free enumeration oracle
and only `handle_new_user`/the sync trigger (definer context) need it.

```sql
revoke all on function public.resolve_profile_role(text) from public, anon, authenticated;
revoke all on function public.resolve_profile_role(extensions.citext) from public, anon, authenticated;
```

### DB-P2-5 · `upsertCompanyAndLink` is check-then-insert

[_shared/boards/upsert.ts](supabase/functions/_shared/boards/upsert.ts) does
three SELECT probes then INSERT with no ON CONFLICT. Two overlapping ingest
runs (manual + cron) can race to a unique violation on `companies.domain` or
`(ats_type, ats_token)`; the error is caught, that company's jobs are skipped
for the run, and the next run self-heals. Acceptable, but a
`upsert … on conflict (domain) do update` (or catching `23505` and re-reading)
would remove the noise.

### DB-P2-6 · Apify webhook secret still accepted via query param

= AUDIT P2-2 ([process-apify-results/index.ts:350-360](supabase/functions/process-apify-results/index.ts#L350)).
The header path has been live since the webhook re-registration; delete the
`?secret=` fallback and rotate `APIFY_WEBHOOK_SECRET`.

### DB-P2-7 · Storage posture — documented accepted risk + one gap

- `avatars`, `videos`, `job-videos` buckets are `public = true`: objects are
  fetchable with no auth given the URL. This is load-bearing (founder/employer
  emails link pitch videos to non-users), and paths are UUID-prefixed, but it
  means "delete my video" never really revokes access to a copied URL, and the
  `for select to authenticated` policies on those buckets are dead letters
  (public buckets bypass them). Document as accepted for launch; longer-term,
  move email links to long-TTL signed URLs on a private bucket.
- No owner UPDATE/DELETE policies exist on `storage.objects` for any bucket:
  clients can only ever add objects. `delete-account` cleans up server-side,
  but replaced avatars/videos/resumes accumulate forever. Add owner-scoped
  delete policies or a periodic orphan sweep:

```sql
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'storage' and table_name = 'objects') then
    execute 'drop policy if exists "Owners can delete own uploads" on storage.objects';
    execute 'create policy "Owners can delete own uploads" on storage.objects '
         || 'for delete to authenticated '
         || 'using (bucket_id in (''avatars'',''videos'',''resumes'',''job-videos'') '
         || 'and (storage.foldername(name))[1] = auth.uid()::text)';
  end if;
end $$;
```

### DB-P2-8 · Employer UPDATE policy on `job_applications` is row-scoped but not column-scoped

`job_applications_employer_update` (m3_trust) lets an employer PATCH **any**
column of an application row — including candidate snapshot fields
(`candidate_name`, `candidate_video_url`, `resume_file_path`,
`email_delivery_status`). The app only patches `status` (+ notes, see
DB-P1-4), but the API allows more. Add a column guard trigger, or grant-level
column security once DB-P1-4 removes the notes column:

```sql
create or replace function public.restrict_employer_application_updates()
returns trigger
language plpgsql
as $$
begin
  -- Service role (edge functions) may update anything; clients may only
  -- change workflow status.
  if auth.uid() is not null
     and (to_jsonb(new) - 'status' - 'updated_at')
         is distinct from (to_jsonb(old) - 'status' - 'updated_at')
  then
    raise exception 'Only application status may be updated by clients';
  end if;
  return new;
end;
$$;

drop trigger if exists restrict_employer_application_updates on public.job_applications;
create trigger restrict_employer_application_updates
before update on public.job_applications
for each row execute function public.restrict_employer_application_updates();
```

(If you adopt this after DB-P1-4, employers edit notes via the new table, so
status-only is correct. `email_delivery_status` updates happen via service
role, which has `auth.uid() IS NULL` here.)

### DB-P2-9 · Small FK-index gaps

Cascade/delete paths that will seq-scan as tables grow: no index on
`application_fields.event_id` (cascade from `application_events`), none on
`company_funds.fund_id` (fund deletes/joins by fund), none on
`jobs.posted_by_profile_id` (delete-account path). All small tables today.

```sql
create index if not exists application_fields_event_idx
  on public.application_fields (event_id);
create index if not exists company_funds_fund_idx
  on public.company_funds (fund_id);
create index if not exists jobs_posted_by_idx
  on public.jobs (posted_by_profile_id)
  where posted_by_profile_id is not null;
```

### DB-P2-10 · `scrape_query_stats.inserted` over-counts

[process-apify-results/index.ts:485-495](supabase/functions/process-apify-results/index.ts#L485):
after the bulk upsert succeeds, `inserted` is incremented for **every**
candidate, including rows the `ignoreDuplicates` upsert skipped in a race.
Use the upsert's returned row count (add `.select("id")`) if the stat is meant
to be trusted. Cosmetic today (and moot until DB-P0-2 lands — currently it
records 0 because the insert always fails).

---

## Checklist coverage

### Schema

- **Primary keys**: all 24 live tables have PKs — pass.
- **NOT NULL**: appropriate throughout; the one *inappropriate* pair
  (`source_kind`, `dedup_key` without defaults across all insert paths) is
  DB-P0-2. `companies.name`, snapshot columns on applications, and lifecycle
  timestamps are all correctly NOT NULL.
- **Foreign keys / ON DELETE**: everything is FK'd; deliberate `set null` on
  audit-ish references (essay sources, outreach contact) — good. The
  destructive cascades worth revisiting are DB-P1-8. `founder_outreach_messages
  .company_id → companies CASCADE` also erases outreach audit rows if a
  company is ever deleted (admins can) — same decision, same migration.
- **Indexes vs. real queries**: feed gaps in DB-P2-1, founder-cap gap in
  DB-P2-2, FK gaps in DB-P2-9; ATS-sync paths are well covered (see DB-P2-1
  notes).
- **Orphaned objects**: no orphaned *tables* (legacy Passport was properly
  dropped); orphaned columns/function/enum labels in DB-P2-3.

### Security / RLS

- RLS enabled everywhere; anon can read/write nothing via tables — pass.
- The anon/authenticated-reachable holes are all **function ACLs**, not table
  policies: DB-P0-1 (anon feed injection), DB-P1-2 (cross-user essay reads),
  DB-P2-4 (role probing). Table-policy issues: DB-P1-3 (visibility not
  enforced, PII exposure), DB-P1-4 (notes column), DB-P2-8 (column scope).
- iOS-client needs vs. grants: feed (jobs/companies/funds/carousels
  authenticated read ✓), saved jobs + applications + notifications
  (owner-scoped ✓), employer job management (owner/admin ✓), discovery
  (view ✓ — base tables currently over-grant, DB-P1-3).

### Edge functions (Greenhouse / Lever / Ashby + boards)

- **Provider errors & rate limits**: all ATS fetches go through
  `fetchWithRetry` — 10s timeout, 3 retries with jittered backoff on 5xx/429,
  4xx fail fast ([_shared/ats/http.ts](supabase/functions/_shared/ats/http.ts)).
  No `Retry-After` handling and no per-host circuit breaker, but per-company
  isolation in enrich-descriptions means one 429-ing company costs only its
  own slot; `last_synced_at` is bumped even on failure so a dead token can't
  wedge the queue (it just retries at queue cadence). Board adapters
  (Getro/Consider) abort the fund on fetch error; the cursor is *not*
  advanced, so the next run resumes the same pages.
- **Half-updated data**: no torn states found that a re-run doesn't heal.
  Job upserts are chunked but idempotent by `dedup_key` with content frozen on
  conflict; description writes are per-row write-once (`description IS NULL`
  guard); carousels upsert whole rows keyed by `job_id`; Apify inserts are
  one statement with `ON CONFLICT DO NOTHING`. Worst case on mid-run death is
  redone work, not corruption. The one dangerous write is the expiry sweep on
  a false "drained" signal — DB-P1-7.
- **Re-run safety**: ingest-jobs, enrich-descriptions, generate-carousel,
  enrich-company-contacts, process-apify-results are all safe to re-invoke;
  send-founder-email is protected by the advisory-lock RPC + once-per-contact
  unique index; apply-to-job by the `(job_id, candidate_profile_id)` unique.
- **Failure visibility**: weakest area — structured logs only, cron responses
  dropped, two confirmed *silent* failures (DB-P0-2 Apify inserts, DB-P1-6
  notifications). DB-P1-9 is the systemic fix. Cross-ref AUDIT P1-8 (failed
  application emails never retried).

---

## Verify live (read-only; run in SQL editor)

```sql
-- DB-P0-1 / P1-2 / P2-4: who can execute the RPCs?
select p.proname, p.proacl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('upsert_board_jobs', 'match_candidate_essay',
                    'resolve_profile_role', 'request_interview');
-- proacl NULL means default ACL = PUBLIC execute (the bug).

-- DB-P0-2: has anything non-board been inserted since the constraints landed?
select source_kind, count(*), max(created_at)
from public.jobs
group by source_kind;
-- expect: zero reel/employer_post rows created after 2026-06-18.

select run_date, sum(passed_screening) as passed, sum(inserted) as inserted
from public.scrape_query_stats
group by run_date order by run_date desc limit 14;
-- expect: inserted = 0 on every run since 2026-06-27 despite passed > 0.

-- DB-P1-6: enum labels
select enumlabel from pg_enum e
join pg_type t on t.oid = e.enumtypid
where t.typname = 'notification_type';

-- DB-P1-5: is the whole catalog perpetually "needing" carousels?
select count(*) from public.jobs j
left join public.carousels c on c.job_id = j.id
where j.is_active and j.company_id is not null
  and (c.job_id is null or j.updated_at > c.generated_at);

-- Cron health right now
select jobname, schedule, active from cron.job;
select status, count(*) from net._http_response group by status;
```

---

## Counts

| Severity | Open | Resolved |
|----------|------|----------|
| P0       | 0    | 2        |
| P1       | 2    | 7        |
| P2       | 10   | 0        |

## Recommended order

1. ~~**DB-P0-1**~~ done 2026-07-12 — one revoke statement; anon-key feed injection is live now.
2. ~~**DB-P0-2**~~ done 2026-07-12 — restores the entire non-board ingest surface; Apify spend is
   currently pure waste.
3. ~~**DB-P1-1**~~ done 2026-07-12, redeploy landed 2026-07-16, and
   ~~**DB-P1-2**~~ done 2026-07-13 (revoked, REST-verified).
4. ~~**DB-P1-3 / DB-P1-4**~~ done 2026-07-13 — both REST-verified with real JWTs.
5. ~~**DB-P1-5 + DB-P1-6**~~ done 2026-07-15 — trigger + hash-skip bump;
   enum label + checked insert.
6. ~~**DB-P1-9**~~ done 2026-07-13, fully live 2026-07-16 (all five functions
   recording runs) then **DB-P1-7/P1-8** — observability first, it verifies
   the rest.
7. P2s opportunistically; DB-P2-1/P2-2 whenever query latency starts showing.
