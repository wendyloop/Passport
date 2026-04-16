# Passport Native iOS

This folder contains a standalone SwiftUI iOS app for Passport.

It is intentionally separate from the Expo app in `frontend/` so you can:

- keep `frontend/` for Android or cross-platform work
- open a native iOS project directly in Xcode
- iterate on iOS UI without Expo / CocoaPods / React Native build issues

## Open in Xcode

Open:

- `ios-native/PassportNative.xcodeproj`

Then choose the `PassportNative` scheme and run it on an iPhone simulator.

## Current state

- Native SwiftUI iPhone app
- Supabase email/password auth
- Google OAuth entry point using a native web auth session
- Onboarding for `job_seeker` and `employer`
- Resume upload to Supabase Storage
- Intro video upload to Supabase Storage
- Employer feed / liked / schedule tabs backed by Supabase
- Job seeker profile / interview requests tabs backed by Supabase
- Manual availability flow is active
- Google Calendar linkage is intentionally deferred for later

## Native app setup

Set these build settings on the `PassportNative` target:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_REDIRECT_SCHEME`

Default redirect scheme in the project is:

- `passportnative`

In Supabase Auth URL configuration, add:

- `passportnative://auth-callback`

For Google auth, also configure the Google provider in Supabase and allow the same redirect path.

## Backend setup

Push the SQL migrations in `supabase/migrations/` to your hosted project, then deploy the edge functions you need.

At minimum:

1. `supabase db push`
2. deploy `parse-resume`

You also need the `videos` and `resumes` buckets from the migration.
