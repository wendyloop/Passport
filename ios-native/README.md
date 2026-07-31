# scout22 Native iOS

This folder contains the primary SwiftUI iOS app for scout22.

> Project, scheme, targets, and Swift types were renamed to `scout22` on 2026-07-31. The `jobtok://` deep-link scheme, App Group `group.com.jobtok.shared`, and `com.jobtok.*` Keychain services deliberately keep the legacy name — renaming them would break Supabase OAuth redirects and strand signed-in sessions.

## Open in Xcode

Open:

- `ios-native/scout22.xcodeproj`

Then choose the `scout22` scheme and run it on an iPhone simulator.

## Current state

- Native SwiftUI iPhone app
- Supabase email/password auth
- Google OAuth entry point using a native web auth session
- Apple OAuth entry point using a native web auth session
- Onboarding for `job_seeker` and `employer`
- Resume upload to Supabase Storage
- Resume parsing enrichment
- Intro video creation and upload
- Candidate jobs feed with saved jobs and applications
- Employer jobs, applicants, candidate discovery, and outreach
- Admin social post import and job publishing
- ATS apply prefill and field history capture

## Native app setup

Set these build settings on the `scout22` target:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_REDIRECT_SCHEME`

Default redirect scheme in the project is:

- `jobtok`

In Supabase Auth URL configuration, add:

- `jobtok://auth-callback`

For Google auth, also configure the Google provider in Supabase and allow the same redirect path.

## Backend setup

Push the SQL migrations in `supabase/migrations/` to your hosted project, then deploy the edge functions you need.

At minimum:

1. `supabase db push`
2. deploy the active edge functions used by the native app

You also need the `videos` and `resumes` buckets from the migration.
