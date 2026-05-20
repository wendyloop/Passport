# JobTok Phase 2 Notes

The MVP in this repo ships these features now:

- Admin job upload and publishing
- Candidate job feed with in-app apply
- Resume upload and 60-second pitch video
- Employer applicant portal
- Employer application email delivery from the backend

The next layer is now partially live:

## Candidate Discovery

- `job_seeker_profiles.discovery_visibility`
  Current default is `applied_roles_only`, but the profile editor now exposes all visibility states.
- `job_seeker_profiles.dream_role`
  Used by employer-side discovery filters and outreach defaults.
- `CandidateVisibility`
  Present in the iOS models, store, and profile editing UI.
- `employer_candidate_discovery`
  New backend view used by the employer discovery tab.

Shipped now:

- Backend discovery view returns only candidates with `discoverable_to_hiring_employers`.
- Employer portal includes filters for `job_function`, `dream_role`, school, and previous employers.
- Visibility is enforced in SQL/RLS, not just in SwiftUI.

## Employer Outreach

- `candidate_outreach_messages`
  Stores outbound employer outreach attempts and delivery metadata.
- `reach-out-to-candidate`
  Edge function sends the email and writes the audit row.
- Employer discovery cards can now trigger direct outreach from the app.

## Candidate Visibility Controls In UI

- The profile editor now exposes the picker and explanatory copy for:
  `private`
  `applied_roles_only`
  `discoverable_to_hiring_employers`
- Candidate saves already persist the chosen visibility state.

## Resume Access Hardening

- MVP emails the employer a signed resume URL at application time.
- The employer portal currently shows the resume filename snapshot, not a live download button.

Implementation direction:

- Add a signed resume download edge function for employers with application-based authorization.
- Avoid changing the resume bucket to public.

## Employer Workflow Expansion

- Add application states such as `reviewing`, `contacted`, `rejected`, `hired`.
- Add internal notes per application.
- Add job-level analytics on views, applies, and conversion.
