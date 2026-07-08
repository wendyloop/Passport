# scout22 Native iOS

This folder contains the primary SwiftUI iOS app for scout22.

> The Xcode project files, scheme, target, bundle identifiers, app group, and `jobtok://` deep link scheme still use the legacy `JobTok` / `jobtok` names. Renaming these would require an Xcode project rename, App Group migration, App Store Connect updates, and Supabase OAuth redirect changes — they're left as-is intentionally.

## Open in Xcode

Open:

- `ios-native/JobTok.xcodeproj`

Then choose the `JobTok` scheme and run it on an iPhone simulator.

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

Set these build settings on the `JobTok` target:

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
