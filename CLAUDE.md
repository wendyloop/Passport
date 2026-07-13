# CLAUDE.md

scout22 (codename **JobTok**) — a TikTok-style recruiting app. Job seekers scroll a
vertical feed of job videos/carousels and apply with a resume + 60-second pitch video.
Employers post jobs, review applicants, discover candidates, and send outreach emails.
Admins bulk-import jobs from social posts and Apify scrape pipelines.

The product was renamed scout22, but every code-level name (targets, schemes, bundle
IDs, `jobtok://` deep link, App Group) is still JobTok. This is intentional — renaming
touches App Store Connect and Supabase OAuth. Do not rename.

## Architecture

Two halves, no middle tier:

- **iOS client** (`ios-native/`) — SwiftUI, iOS 17+, MVVM-ish. **Zero package
  dependencies**: Supabase access is a hand-rolled URLSession client
  ([SupabaseTransport.swift](ios-native/JobTok/SupabaseTransport.swift),
  [SupabaseService.swift](ios-native/JobTok/SupabaseService.swift)). `AppSessionStore`
  is the single `@MainActor ObservableObject` holding session/role state;
  [NativeRootView.swift](ios-native/JobTok/NativeRootView.swift) routes to
  JobSeeker/Employer/Admin home views by role.
- **Supabase backend** (`supabase/`) — Postgres 17 with **RLS as the real enforcement
  boundary** (the anon key ships in the IPA by design), timestamped SQL migrations,
  Deno/TypeScript Edge Functions, Storage buckets (`videos`, `resumes`), Auth
  (email/password + Google + Apple OAuth via `jobtok://auth-callback`).

The client hits PostgREST directly for reads and simple writes. Anything privileged —
applying, outreach/founder emails, resume parsing, ingestion — goes through an edge
function using the service-role client.

## Layout

- `ios-native/JobTok/` — all app source, deliberately flat (~26 Swift files, no
  subfolders). Largest: `JobSeekerHomeView`, `VideoStudio` (recording/editing),
  `EmployerHomeView`, `Models.swift`, `AppSessionStore`.
- `ios-native/JobTokShareExtension/` — share-sheet target: share an Instagram/TikTok
  reel into the app; hands off via App Group `group.com.jobtok.shared` to the
  `ingest-shared-reel` function.
- `ios-native/JobTokTests/` — XCTest unit tests (hosted in the app, no UI tests).
- `supabase/migrations/` — append-only timestamped SQL; never edit an applied one.
- `supabase/functions/` — ~20 edge functions + `_shared/` helpers (`client.ts` user &
  admin clients, `cors.ts`, `email.ts` Resend, `cron_auth.ts`, `openai.ts`).
  Rough groups: apply/outreach (`apply-to-job`, `reach-out-to-candidate`,
  `send-founder-email`, `resend-webhook`), ingestion (`ingest-jobs`,
  `trigger-apify-scrape`, `process-apify-results`, `ingest-shared-reel`), enrichment
  (`enrich-descriptions`, `enrich-company-contacts`, `generate-carousel`,
  `parse-resume`), sharing (`job-share` public OG landing page).
- `scripts/drain-carousels.sh` — manually drain the carousel-generation backlog.
- `docs/DEFERRED_WORK.md` — **the** planning doc: consolidated backlog + build order.
- `services/` — empty; the legacy Node carousel service was folded into the
  `generate-carousel` edge function.

## Build, run, test

One-time setup: copy the keys from
[JobTok.xcconfig](ios-native/JobTok/JobTok.xcconfig) into
`ios-native/JobTok/JobTok.local.xcconfig` (gitignored) with real values from the
Supabase dashboard. The app won't reach the backend without it.

Run: open `ios-native/JobTok.xcodeproj`, `JobTok` scheme, iPhone simulator. CLI:

```bash
cd ios-native
xcodebuild build -project JobTok.xcodeproj -scheme JobTok \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test  -project JobTok.xcodeproj -scheme JobTok \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # 34 unit tests
```

Edge-function tests (pure-logic helpers in `_shared/`):

```bash
deno test --allow-env supabase/functions/_shared/shared_test.ts   # 16 tests
```

Backend deploy targets the hosted project (`zqfurscyhmxlvrfendnc`):

```bash
supabase db push                     # apply new migrations
supabase functions deploy <name>     # deploy one function
```

Local stack via `supabase start` (API :54321, DB :54322) works, but day-to-day dev
points the simulator at the hosted project through the local xcconfig.

## Deploy pitfall: verify_jwt

Cron-invoked functions (`ingest-jobs`, `enrich-descriptions`, `generate-carousel`,
`enrich-company-contacts`) authenticate with an `x-pitch-cron-secret` header
(fail-closed in `_shared/cron_auth.ts`) — pg_net cron calls carry no JWT. Same for
`resend-webhook` (signature auth) and `job-share` (public). Their
`[functions.<name>] verify_jwt = false` entries in `supabase/config.toml` keep a
plain `supabase functions deploy` from re-enabling gateway JWT verification — a bare
deploy on 2026-07-08 did exactly that and every cron call 401'd. Add an entry there
for any new non-JWT function.

## Conventions

- **project.pbxproj is hand-maintained.** Object IDs are deterministic hex (e.g.
  `A50000010000000000000001`). When adding a Swift file, edit the pbxproj directly —
  file ref, build file, group child, sources phase — instead of relying on Xcode.
- Shared scheme lives in `xcshareddata/xcschemes/JobTok.xcscheme` and includes the
  test target; keep it shared so CLI builds/tests work.
- Deferred work is tracked as `TODO(deferred)` / `FIRST-100-USERS` code markers, each
  matching a row in `docs/DEFERRED_WORK.md`. Keep marker and row in sync; delete both
  when an item ships. List them: `grep -rn "TODO(deferred)" ios-native/JobTok supabase/functions`.
- Visibility/permission rules (e.g. candidate discovery) are enforced in SQL/RLS
  first; SwiftUI only mirrors them.
- New privileged operations get an edge function + audit row, not a client-side
  service-role call.

## More docs

- [README.md](README.md) + [ios-native/README.md](ios-native/README.md) — setup
  detail (Supabase Auth redirect config, storage buckets).
- [JOBTOK_PHASE2_NOTES.md](JOBTOK_PHASE2_NOTES.md) — candidate discovery / employer
  outreach feature notes.
- [docs/DEFERRED_WORK.md](docs/DEFERRED_WORK.md) — backlog; check here before
  starting "new" work, it may already be specced.
