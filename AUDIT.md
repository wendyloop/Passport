# Pre-launch audit — scout22 / JobTok

Full scan 2026-07-11 (no prior AUDIT.md; all findings OPEN, none resolved).
Scope: `ios-native/` (26 Swift files), all 21 edge functions, `_shared/`, RLS
migrations. Line numbers are against commit `2df32c8` working tree.

> **Reconciliation pass, 2026-07-11 (later the same day).** Verified against
> git: **no code has changed since this audit was written** — HEAD and
> origin/main are both still `2df32c8`, the same tree the audit scanned. The
> backlog execution pass (M1–M4, PRs #15–#18) merged *before* the audit, so
> its code was already covered; that is why nothing was marked RESOLVED —
> nothing has been fixed yet. All three P0s re-verified OPEN at their cited
> lines. There is no `PLAN.md`; the backlog lives in
> `docs/DEFERRED_WORK.md` ("Build order" milestones). Every ✅-shipped
> milestone claim was verified present and working in code (M1: F5/F3/F8/F2/
> T4/T2 · M2: F10a/F10c/F1/F7/F4/F6 · M3: T8-partial/P1-resume/P2-pipeline/
> T7 · M4: T3/T9-partial). The pass DID add smoke tests (`bf88e5a`), but the
> shared scheme's empty `<Testables>` made CLI test runs impossible at ship
> time (fixed in-session; suite now passes 34/34 XCTest + 16/16 Deno). A
> focused diff review of the M1–M4 code added one new finding: **P1-9**.

Verified clean, for the record: no hardcoded secrets anywhere (xcconfig
placeholder flow works, `.local` is gitignored and untracked); RLS on
`jobs`/`job_applications` correctly scoped; `job_applications` has a
`unique (job_id, candidate_profile_id)` dup guard; `ingest-shared-reel` and
`parse-shared-job-posting` enforce admin server-side; `parse-resume` scopes by
owner; `get-resume-url` authorizes by application ownership with a 10-min TTL;
`resend-webhook` verifies Svix signatures timing-safely and fails closed;
`send-founder-email` has atomic quota reservation, per-company caps, masked
contacts, URL-stripped notes; `job-share` escapes everything and 404s
unpublished jobs; all 4 cron functions use the fail-closed cron secret.

---

## P0 — blocks launch

### P0-1 · Any offline launch destroys the persisted session — RESOLVED 2026-07-13
[AppSessionStore.swift:124-139](ios-native/JobTok/AppSessionStore.swift#L124)
`bootstrap()` treats *every* error from `ensureValidSession` /
`loadCurrentUserState` — including plain network unreachability — as fatal:
`clearSession()` wipes the stored refresh token and drops to the sign-in
screen. Open the app in airplane mode (or with an expired ~1h token and bad
signal) and you are logged out, every time. **Fix:** distinguish
`URLError`-class failures from auth failures — keep the session, enter a
"retry" state, and only clear on a definitive 400/401 from the refresh
endpoint.
**RESOLVED:** the transport now surfaces HTTP status codes
(`SupabaseServiceError.httpError`); `refreshSession` maps a definitive
400/401/403 from the refresh endpoint to `AuthServiceError.refreshRejected` —
the *only* error that clears the persisted session. Every other bootstrap
failure (URLError, 5xx, decode) keeps the session and enters a new
`Phase.offline` state with an offline screen; `NWPathMonitor` retries the
moment a network path appears, backed by an exponential-backoff timer (5s→60s
cap) for reachable-but-failing servers, plus a manual Retry button. Covered by
6 new unit tests in `AppSessionStoreBootstrapTests` (offline keeps
session+persistence, 5xx keeps session, rejected refresh clears both, no-op
without persisted session, and URLProtocol-stubbed proof that a real HTTP 400
from `/auth/v1/token` maps to `refreshRejected` while URLErrors pass through).
Suite 40/40 + 16/16.

### P0-2 · `trigger-apify-scrape` is invokable by anyone holding the anon key — RESOLVED 2026-07-11
[trigger-apify-scrape/index.ts:183-186](supabase/functions/trigger-apify-scrape/index.ts#L183)
Every other cron-invoked function calls `requireCronSecret()`; this one has no
caller check at all — the only gate is gateway JWT verification, which the
public anon key (ships in the IPA) satisfies. Anyone can script it to start
paid Apify actor runs in a loop: direct spend abuse plus scrape-pipeline
pollution. **Fix:** add the same `requireCronSecret(request)` short-circuit as
its siblings and move its dashboard schedule to send the secret header.
**RESOLVED:** added the `requireCronSecret` import + short-circuit (matching
the four sibling functions), added `[functions.trigger-apify-scrape]
verify_jwt = false` to config.toml, and moved the schedule off the dashboard
onto pg_cron+Vault (migration `20260711210000_apify_cron_secret.sql`, reusing
the existing `pitch_cron_secret`). Deployed + pushed. Verified live: anon-key,
no-auth, and wrong-secret all return 401; the real pg_cron path (Vault secret
via pg_net) returns 200 and executed. Update 2026-07-13: both apify cron
schedules (the legacy dashboard schedule and the pg_cron `apify-daily-scrape`
job) have since been **intentionally removed** — there is no active apify
schedule right now, by choice. The cron-secret gate stays in place for manual
and any future scheduled invocations.

### P0-3 · Share-extension CFBundleVersion is hardcoded to "1" — RESOLVED 2026-07-11
[JobTokShareExtension/Info.plist:17-20](ios-native/JobTokShareExtension/Info.plist#L17)
The app uses `$(CURRENT_PROJECT_VERSION)` (currently 3); the extension pins
`1`. Xcode already warns; App Store Connect validation flags mismatched
extension versions at upload (ITMS-90473 class), so this surfaces exactly at
the moment you try to ship. **Fix:** set the extension's `CFBundleVersion` to
`$(CURRENT_PROJECT_VERSION)` so both targets always agree.
**RESOLVED:** rather than hardcode, hoisted `CURRENT_PROJECT_VERSION = 3` and
`MARKETING_VERSION = 1.2` to the **project-level** build config so all three
targets (app, extension, tests) inherit one source of truth; removed the
per-target overrides; the extension plist now reads
`$(CURRENT_PROJECT_VERSION)` / `$(MARKETING_VERSION)`. Build succeeds, the
"must match … containing parent app" warning is gone, and both built bundles
report CFBundleVersion 3 / short 1.2. They can no longer drift.

---

## P1 — fix before real users

### P1-1 · Auth tokens live in UserDefaults, not the Keychain — RESOLVED 2026-07-13
[AppSessionStore.swift:44-46](ios-native/JobTok/AppSessionStore.swift#L44),
[807-817](ios-native/JobTok/AppSessionStore.swift#L807)
The full session (access + refresh token) is JSON-encoded into
`UserDefaults.standard`, and the access token is mirrored into the App Group
defaults for the share extension — plaintext plists, included in unencrypted
backups. **Fix:** persist the session in the Keychain
(`kSecAttrAccessibleAfterFirstUnlock` + shared keychain access group so the
extension can still read it).
**RESOLVED:** new `KeychainStore` (compiled into both targets) holds the
session as one generic-password item with
`kSecAttrAccessibleAfterFirstUnlock`, shared via the App Group ID as the
keychain access group (valid on iOS; both targets already had the group
entitlement, so no entitlement changes). `AppSessionStore` persists through a
`SessionPersisting` seam (Keychain in prod, in-memory in tests); the share
extension decodes just the access token from the shared item. The App Group
plist token mirror is gone and pre-Keychain leftovers (standard-defaults
session + mirrored token) are scrubbed on next sign-in. No read-migration by
design — wiping test devices / re-login is fine pre-launch. Covered by a
Keychain save/load/overwrite/delete roundtrip test in the hosted app (same
access group the extension uses). Manual follow-up: exercise one share-sheet
import on a signed-in build. Suite 44/44 + 16/16.

### P1-2 · The "submitted" funnel event is never logged on the happy path — RESOLVED 2026-07-13
[ApplyDrawerView.swift:140-160](ios-native/JobTok/ApplyDrawerView.swift#L140)
`handleSubmission` only logs an event of type `"submitted"` when the earlier
`"opened"` log *failed* (`eventId == nil`); otherwise it reuses the opened
event's id and just attaches fields to it. `application_events` — the base for
the planned apply-funnel analytics per
[log-application-event/index.ts:1-4](supabase/functions/log-application-event/index.ts#L1)
— will record ~zero submissions. **Fix:** always log a `submitted` event on
submission (carrying the opened event's id as a parent, or attach fields to
the new event).
**RESOLVED:** `handleSubmission` now always logs a `submitted` event; captured
fields attach to the submitted event (opened event only as fallback if that
log fails). Verified end-to-end against the deployed functions with a real
fixture candidate JWT + test job, replaying the app's exact call sequence
(`scripts/verify-funnel-item3.sh`, self-cleaning): one `opened` + one
`submitted` row in `application_events`, one `application_fields` row on the
submitted event.

### P1-3 · No timeouts or retries on any Supabase request
[SupabaseTransport.swift:216](ios-native/JobTok/SupabaseTransport.swift#L216)
All traffic goes through `URLSession.shared` with the 60-second default and no
retry, and the app is 100% network-backed — one stalled request leaves a
spinner (or a disabled `isBusy` UI) hanging for a minute with no recovery.
**Fix:** give the transport its own `URLSession` with
`timeoutIntervalForRequest` ≈ 15–30 s and a single retry for idempotent GETs.

### P1-4 · Employer "open resume" fails silently — RESOLVED 2026-07-15
[EmployerHomeView.swift:256-262](ios-native/JobTok/EmployerHomeView.swift#L256)
`try? await onRequestResumeURL(...)` swallows every failure (expired session,
403, network), so tapping the resume button does visibly nothing — a dead-end
on the employer's single most important action. **Fix:** route the error into
the store's `errorMessage` alert instead of `try?`.
**RESOLVED:** the `try?` is now a do/catch that sets a `resumeErrorMessage`
state shown in a "Couldn't open resume" alert (friendly-mapped message).
Verified at the API boundary with a real employer-role JWT against the
deployed gateway — which surfaced the REAL root cause: **`get-resume-url` has
never been deployed to the hosted project** (gateway 404 "Requested function
was not found"), so every resume tap failed, invisibly until this alert.
Update 2026-07-17: `get-resume-url` and `job-share` were deployed 2026-07-16
(resume button + share links now live), and the five legacy Passport-era
functions the sweep found (`approve-interview`, `consume-referral-invite`,
`create-referral-invite`, `crawl-rosters`, `sync-availability` — all
verified orphaned, four broken against dropped schema) were deleted from the
hosted project after a per-function inventory review.

### P1-5 · Employer outreach has no rate limit or size cap
[reach-out-to-candidate/index.ts:73-158](supabase/functions/reach-out-to-candidate/index.ts#L73)
Visibility/authz checks are good, but an employer can email the same candidate
unlimited times (each call sends a real email), with unbounded
subject/message length. The founder-email path has weekly quotas, per-company
caps, and once-per-contact rules; this path has none — spam vector aimed at
your own candidates. **Fix:** add a per-employer daily cap and
per-candidate cooldown mirroring `send-founder-email`, and cap
subject/message lengths.

### P1-6 · ATS autofill fills and captures invisible fields — RESOLVED 2026-07-13
[ApplyDrawerView.swift:301-307](ios-native/JobTok/ApplyDrawerView.swift#L301)
(fill: [317-337](ios-native/JobTok/ApplyDrawerView.swift#L317), capture:
[391-413](ios-native/JobTok/ApplyDrawerView.swift#L391))
`isFillable` excludes `type=hidden` but not CSS-hidden inputs
(`display:none`, zero-size, off-screen). A malicious or compromised apply page
can plant invisible inputs labeled "email"/"phone"/"salary expectation", let
the injected prefill populate them, and harvest the PII on submit — the
submit listener also captures every filled field back to
`store-application-fields`. **Fix:** require visibility (e.g.
`el.offsetParent !== null` and non-zero client rect) in both `isFillable` and
the capture pass.
**RESOLVED (both halves):** (1) `isVisible()` — non-zero client rect +
`checkVisibility()` (computed display/visibility/opacity fallback) — is now
required by `isFillable`, which gates the fill pass, the essay collector,
`fillEssayMatch`, and the submit-capture pass alike. (2) Injection is
allowlisted to the 14 known ATS domains (`ATSAutofillPolicy`, single source
of truth mirrored into the JS): both WKUserScripts start with a per-document,
per-frame host gate — exact-or-dot-suffix match, so `greenhouse.io.evil.com`
fails — and on any other host there is no fill, no capture, and no message
posts at all. `ATSPlatform.detect` also moved from spoofable `contains` to
suffix matching (+ smartrecruiters/recruitee coverage). 6 new tests, incl.
executing the real injected JS gate in JavaScriptCore. Suite 50/50 + 16/16.

### P1-7 · Profile save can wipe the employer-history list
[CandidateService.swift:83-101](ios-native/JobTok/CandidateService.swift#L83)
`replaceJobSeekerEmployers` deletes all rows, then inserts the new set as a
second request — if the insert fails (timeout, RLS hiccup, app kill), the
user's previous-employers list is gone. **Fix:** replace both calls with one
transactional RPC (`replace_job_seeker_employers`).

### P1-8 · Failed application emails dead-end with no retry or alert — RESOLVED 2026-07-15
[apply-to-job/index.ts:341-363](supabase/functions/apply-to-job/index.ts#L341)
If Resend fails, the application row is stamped
`email_delivery_status: "failed"` and the candidate still sees "submitted" —
but nothing ever retries, and no one is notified, so the employer never learns
the candidate exists. **Fix:** add a small cron pass that retries
`email_delivery_status = 'failed'` rows (or at minimum surface them in the
admin view).
**RESOLVED (both halves):** (1) new `retry-application-emails` cron function
(cron-secret gated, hourly at :20 via pg_cron+Vault — migration
`20260715121000`) re-sends failed rows from their snapshot columns using the
same email builder as apply-to-job (extracted to
`_shared/application_email.ts`, +2 Deno tests), capped by a new
`email_delivery_attempts` column (max 5), and records a `pipeline_runs` row
per run. Migration applied; column + active cron confirmed live.
(2) Truthful candidate state: the application card now shows
"Sent to employer" / orange "Delivery issue — retrying" / "Sending…" instead
of a cryptic gray status word. Both functions deployed 2026-07-16; the
hourly cron is live and recording clean pipeline_runs rows (25 no-op runs,
0 errors, as of 2026-07-17).

### P1-9 · Employer "private" notes are readable by the candidate — RESOLVED 2026-07-13 *(added in reconciliation pass — new in M3 code)*
[20260711130000_m3_trust.sql:33](supabase/migrations/20260711130000_m3_trust.sql#L33),
select policy [20260519100000_jobtok_mvp.sql:160-174](supabase/migrations/20260519100000_jobtok_mvp.sql#L160),
UI promise [EmployerHomeView.swift:1410](ios-native/JobTok/EmployerHomeView.swift#L1410)
M3 added `job_applications.internal_notes` with an employer-scoped UPDATE
policy, but the SELECT policy is row-scoped to *participants* — including the
candidate — and there are no column-level grants. The candidate app fetches
its applications with `select=*` (and `JobApplicationRecord` now decodes
`internalNotes`), so an employer's "Rejected — bad culture fit" note is
delivered verbatim to the person it's about, while the notes editor promises
"only your team sees these." **Fix:** move `internal_notes` out of candidate
reach — either a candidate-facing view/column grant that excludes it, or a
separate employer-only `application_notes` table.
**RESOLVED:** migration `20260713120000_application_notes_table.sql` — new
employer-only `application_notes` table (RLS `for all` scoped to the owning
employer, with-check ties rows to the employer's own applications), existing
notes migrated, `internal_notes` column dropped. iOS reads notes via the
PostgREST embed `select=*,application_notes(notes)` on employer fetches
(`JobApplicationRecord.internalNotes` is now a computed property over the
embed) and writes via upsert to `application_notes`. Verified over live REST
with real candidate/employer JWTs: candidate sees no notes rows, no embed
content, gets 400 selecting the dropped column, and cannot write; employer
write/read paths work. See DB_AUDIT DB-P1-4.

---

## P2 — cleanup

### P2-1 · ~50 lines of commented-out Instagram DM code
[apply-to-job/index.ts:12-16, 133-165](supabase/functions/apply-to-job/index.ts#L133)
Documented as awaiting Meta app review, but it's dead weight in a production
function. **Fix:** move the snippet to `docs/DEFERRED_WORK.md` and delete the
comment block (same for the commented TikTok runs in
[trigger-apify-scrape/index.ts:194-215](supabase/functions/trigger-apify-scrape/index.ts#L194)).

### P2-2 · Webhook secret still accepted via query param
[process-apify-results/index.ts:350-360](supabase/functions/process-apify-results/index.ts#L350)
The code's own comment says the `?secret=` fallback should be dropped once the
header path lands; query strings end up in gateway/proxy logs. **Fix:** delete
the fallback and rotate the secret before launch.

### P2-3 · Force cast in the transport decode path
[SupabaseTransport.swift:199-201](ios-native/JobTok/SupabaseTransport.swift#L199)
`EmptyPayload() as! T` is guarded by the `T.self == EmptyPayload.self` check
today but is one refactor away from a crash. **Fix:** `as? T` with a thrown
`invalidResponse` fallback.

### P2-4 · Multi-MB synchronous disk reads on the main actor
[AppSessionStore.swift:237, 367, 503, 584, 774](ios-native/JobTok/AppSessionStore.swift#L237)
`try Data(contentsOf:)` for compressed videos (~10–30 MB) runs inside a
`@MainActor` class and briefly blocks the UI on every upload. **Fix:** hop the
read to a detached task, or stream uploads with
`URLSession.upload(for:fromFile:)`.

### P2-5 · Concurrent busy-tasks fight over `isBusy`/`errorMessage`
[AppSessionStore.swift:846-870](ios-native/JobTok/AppSessionStore.swift#L846)
Two overlapping `runBusyTask` calls: the first to finish flips `isBusy = false`
(re-enabling buttons) and can clear/overwrite the other's error. **Fix:** use
an in-flight counter instead of a boolean.

### P2-6 · Raw backend response dumped into a user-facing alert
[SupabaseService.swift:324-330](ios-native/JobTok/SupabaseService.swift#L324)
`parseSharedJobPosting` errors embed up to 2 000 chars of raw response body.
Admin-only surface, but still debug output in an alert. **Fix:** log the raw
body via `AppLog` and show a short message.

### P2-7 · Force-unwrapped deep-link URL from build config
[NativeRootView.swift:24](ios-native/JobTok/NativeRootView.swift#L24)
`URL(string: "\(config.redirectScheme)://auth-callback")!` crashes at sign-in
tap if `SUPABASE_REDIRECT_SCHEME` is ever set to something URL-invalid —
developer-error only, but a guard costs two lines. **Fix:** `guard let` with a
configuration-error alert.

### P2-8 · Deprecated AVFoundation APIs and Sendable violations
[VideoStudio.swift:2284-2325](ios-native/JobTok/VideoStudio.swift#L2284)
`preferredTransform`/`naturalSize` (deprecated since iOS 16) and an
`AVAssetExportSession` captured in a `@Sendable` closure produce a wall of
build warnings and will bite on a future SDK bump. **Fix:** migrate to
`load(.preferredTransform)` async accessors.

### P2-9 · Cold start runs 6+ dependent network calls serially
[AppSessionStore.swift:683-689](ios-native/JobTok/AppSessionStore.swift#L683)
`loadCurrentUserState` awaits profile, seeker profile, employer profile,
employers, resume, notifications one at a time before role data even starts.
**Fix:** group the independent fetches with `async let`.

### P2-10 · Unbounded employer-side queries
[SupabaseService.swift:369-389](ios-native/JobTok/SupabaseService.swift#L369)
`fetchDiscoverableCandidates` / `fetchCandidateOutreachMessages` have no
`limit`; fine today, quietly heavy at scale (the candidate feed is capped at
200+200 by design). **Fix:** add limits matching what the UI actually renders.

---

## Counts

| Severity | Open | Resolved |
|----------|------|----------|
| P0       | 0    | 3        |
| P1       | 3    | 6        |
| P2       | 10   | 0        |

(Reconciliation 2026-07-11 added P1-9. Fix session 2026-07-11 resolved P0-2
and P0-3 — both verified live/at build. Fix session 2026-07-13 resolved P0-1
and P1-9. **All P0s are closed.**)

## Addendum — 2026-07-26 session finds (found + fixed same day)

- **Saved tab silently dropped bookmarks** outside the 200+200 feed window
  (`AppSessionStore.savedJobs` resolved against `jobFeed` only). Fixed:
  chunked `id=in.()` fetch for missing saved jobs + `SavedJobsOrdering`
  (unapplied by save recency, then applied by application recency).
- **Founder button dead-ended on ~82% of jobs** (no contact-existence
  signal client-side). Fixed via `companies.founder_contactable` — see
  DB_AUDIT addendum and migration `20260726120000`.

## Recommended order

1. ~~**P0-3**~~ RESOLVED · ~~**P0-2**~~ RESOLVED
2. ~~**P0-1**~~ RESOLVED 2026-07-13
3. ~~**P1-1**~~ RESOLVED 2026-07-13 (Keychain via App Group access group)
4. ~~**P1-2**~~ RESOLVED 2026-07-13 (always logs; e2e-verified on hosted)
5. ~~**P1-4**~~ RESOLVED 2026-07-15 (alert + found get-resume-url was never
   deployed), ~~**P1-8**~~ RESOLVED 2026-07-15 (hourly retry cron + truthful
   candidate state)
6. ~~**P1-9**~~ RESOLVED 2026-07-13 (application_notes table, REST-verified),
   **P1-5** outreach caps, ~~**P1-6**~~ RESOLVED 2026-07-13 (visibility gate
   + 14-domain allowlist)
7. **P1-3** timeouts, **P1-7** atomic employer replace
8. P2s opportunistically, in listed order.
