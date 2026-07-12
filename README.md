# Passport

Passport is the repo for the native scout22 iOS app and its backend services. Job seekers create a short profile, upload a resume and intro video, browse jobs, and apply. Employers publish jobs, review applicants, discover candidates, and send outreach. Admins can import and manage social job posts.

## Project layout

```text
Passport/
├── ios-native/
├── services/
├── supabase/
├── README.md
├── .gitignore
```

## Stack

- `ios-native/`: standalone SwiftUI iOS app for running directly in Xcode
- `services/`: empty — the legacy Node carousel service was folded into the `generate-carousel` edge function
- `supabase/`: database migrations, RLS policies, seeds, and Edge Functions
- Supabase Auth for email/password and Google sign-in
- Supabase Storage for resumes, videos, and avatars
- Social import and scrape pipelines for admin-managed job ingestion

## Local setup

1. Start Supabase locally from the repo root.
2. Open `ios-native/JobTok.xcodeproj` in Xcode.
3. Set the Supabase build settings for the `JobTok` target.
4. Run the `JobTok` scheme in the simulator.

## Current product surface

- Native SwiftUI iPhone app for job seekers, employers, and admins
- Supabase schema for profiles, jobs, applications, saved jobs, outreach, notifications, videos, and resume parsing
- Edge functions for applying, outreach, resume parsing, ATS autofill telemetry, account deletion, social import, scrape ingestion, and carousel generation

## Notes

- Resume parsing is scaffolded as a backend entry point, but real PDF/DOCX extraction still needs a production parser service.
- The legacy Expo Passport client and the older referral/interview scheduling backend flow have been removed from this repo.
