# Backend Cleanup Audit

## Why roles exist in two places

`profiles.role` is the real runtime role. It is the value the app actually reads after login.

`profile_role_assignments` exists for one specific reason: pre-signup provisioning by email. It lets you say "if `recruiter@company.com` signs in, make them `employer`" before that person has a `profiles` row. `handle_new_user()` reads that mapping on first sign in and writes the effective role into `profiles.role`.

So the model is:

- `profiles.role`: current effective role
- `profile_role_assignments`: optional email-based provisioning rule

This is useful for `admin` and `employer` because those roles should not be self-assignable by any random new account.

## Current active JobTok tables

These are active in the current iOS app and/or current Supabase edge functions.

| Table | Current use |
| --- | --- |
| `profiles` | Core identity record, effective role, display fields, avatar, onboarding state |
| `profile_role_assignments` | Pre-signup email-to-role assignment for employer/admin provisioning |
| `employer_profiles` | Employer/company metadata |
| `job_seeker_profiles` | Candidate profile metadata, discovery settings, social links, compensation, intro video pointer |
| `job_seeker_employers` | Candidate previous employers |
| `resume_uploads` | Candidate resumes and stored file paths |
| `candidate_videos` | Candidate pitch video records/history |
| `jobs` | Employer/admin-created role posts and job videos |
| `job_applications` | Candidate applications and application snapshots |
| `saved_jobs` | Candidate saved/bookmarked jobs |
| `candidate_outreach_messages` | Employer outreach to discoverable candidates |
| `notifications` | In-app notifications |

## Active views and helpers

| Object | Current use |
| --- | --- |
| `employer_candidate_discovery` | Employer browse/discovery feed for candidates |
| `mark_notifications_read()` | Marks notifications as read |
| `handle_new_user()` | Creates/syncs `profiles` row when auth user is created |
| `resolve_profile_role()` | Maps email to provisioned role |

## Active edge functions

| Function | Current use |
| --- | --- |
| `apply-to-job` | Creates application snapshot and emails employer |
| `reach-out-to-candidate` | Sends employer outreach email |
| `parse-resume` | Resume enrichment/parsing |
| `delete-account` | Deletes auth user and storage assets |

## Legacy Passport tables that are deprecation candidates

These appear to be from the old referral/interview product and are not part of current JobTok flows.

| Table | Original use case | Current status |
| --- | --- | --- |
| `referral_invites` | Employer-issued invite/referral codes for candidate onboarding | Not used by current iOS JobTok flows |
| `calendar_connections` | Stored Google Calendar tokens for scheduling sync | Not used by current JobTok flows |
| `candidate_likes` | Employer likes on candidate feed | Replaced by applications/outreach model |
| `availability_slots` | Employer interview availability windows | Legacy interview scheduling flow |
| `interview_requests` | Interview request lifecycle, slot selection, approvals | Legacy interview scheduling flow |

## Legacy functions and edge functions that are deprecation candidates

| Object | Original use case |
| --- | --- |
| `issue_referral_invite()` | Create referral invite |
| `consume_referral_invite()` | Redeem referral invite during signup |
| `like_candidate()` | Persist employer like |
| `request_interview()` | Create interview request |
| `select_interview_slot()` | Candidate selects slot |
| `respond_to_interview_request()` | Employer approves/declines slot |
| `approve-interview` | Legacy interview approval edge function |
| `consume-referral-invite` | Legacy referral redemption edge function |
| `create-referral-invite` | Legacy referral creation edge function |
| `sync-availability` | Legacy calendar/availability sync edge function |

## Legacy columns in still-active tables

These columns are worth reviewing because the table is still active, but the field is from the old product model.

| Table.Column | Original use case | Recommendation |
| --- | --- | --- |
| `employer_profiles.calendar_connected` | Google Calendar interview scheduling connection state | Deprecate if scheduling is gone |
| `employer_profiles.monthly_referral_limit` | Referral quota per employer | Deprecate if referrals are gone |
| `job_seeker_profiles.referral_badge` | Candidate came via referral / badge in old feed | Deprecate if referrals are gone |
| `job_seeker_profiles.referral_invite_id` | Link back to referral invite used at signup | Deprecate if referrals are gone |

## Active but optional-to-keep fields

These are not clearly harmful, but they are weaker candidates to keep long term if the product never uses them.

| Table.Column | Why it exists |
| --- | --- |
| `jobs.source_url` | Provenance for externally sourced role videos |
| `candidate_videos.poster_url` | Poster/thumbnail metadata |
| `candidate_videos.status` | Upload/moderation/status metadata |
| `resume_uploads.parse_status` | Resume parsing state |
| `resume_uploads.parsed_school_name` | Resume parsing output |
| `resume_uploads.parsed_employers` | Resume parsing output |

## Recommended cleanup order

### 1. Keep now

- `profiles`
- `profile_role_assignments`
- `employer_profiles`
- `job_seeker_profiles`
- `job_seeker_employers`
- `resume_uploads`
- `candidate_videos`
- `jobs`
- `job_applications`
- `saved_jobs`
- `candidate_outreach_messages`
- `notifications`

### 2. Deprecate next once you are sure the old Passport flow is dead

- `referral_invites`
- `calendar_connections`
- `candidate_likes`
- `availability_slots`
- `interview_requests`
- the related legacy RPCs and edge functions

### 3. Then prune old columns from active tables

- `employer_profiles.calendar_connected`
- `employer_profiles.monthly_referral_limit`
- `job_seeker_profiles.referral_badge`
- `job_seeker_profiles.referral_invite_id`

## Recommended role-management pattern going forward

For clarity:

- keep reading the current role from `profiles.role`
- keep `profile_role_assignments` only as an admin provisioning table
- do not let the app write `profiles.role` directly
- assign employer/admin access by email through admin-only helper functions or an internal admin UI

That preserves the security model while making the mental model simpler:

1. Admin assigns an email to a role.
2. User signs in.
3. `handle_new_user()` creates `profiles` with that role.
4. App reads `profiles.role` from then on.
