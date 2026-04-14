# Passport

Passport is an iOS-first mobile app for job discovery and candidate screening. Job seekers create a short profile and intro video, while employers browse a vertical video feed, like candidates, send interview requests, manage referral invites, and coordinate scheduling through Google Calendar.

## Project layout

```text
Passport/
├── frontend/
├── supabase/
├── README.md
├── .gitignore
```

## Stack

- `frontend/`: Expo + React Native + Expo Router
- `supabase/`: database migrations, RLS policies, seeds, and Edge Functions
- Supabase Auth for email/password and Google sign-in
- Supabase Storage for resumes, videos, and avatars
- Google Calendar integration via Supabase Edge Functions

## Local setup

1. Start Supabase locally from the repo root.
2. Copy `frontend/.env.example` to `frontend/.env`.
3. Fill in the Supabase URL and anon key.
4. Install dependencies in `frontend/`.
5. Start the Expo app with `npm run ios`.

## What is scaffolded

- Role-based mobile navigation for job seekers and employers
- Supabase schema for profiles, likes, interviews, referrals, availability, videos, and notifications
- RLS policies and RPC functions for the core product flow
- Edge Function scaffolding for referrals, resume parsing, availability sync, and interview approval

## Notes

- Resume parsing is scaffolded as a backend entry point, but real PDF/DOCX extraction still needs a production parser service.
- Google Calendar approval flow is scaffolded end-to-end, but you still need to wire real Google OAuth client credentials in Supabase and production secrets for calendar writes.
