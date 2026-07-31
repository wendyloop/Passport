#!/bin/bash
# Item-3 verification (AUDIT P1-2): the apply-funnel "submitted" event.
# Replays the exact call sequence ApplyDrawerView.handleSubmission now makes —
# log-application-event(opened) on drawer open, log-application-event(submitted)
# on submit, store-application-fields on the submitted event — against the
# DEPLOYED edge functions with a real fixture candidate JWT, then asserts the
# application_events / application_fields rows landed.
#
# Self-cleaning: fixture user + unpublished fixture job are created and deleted
# in this single invocation (trap-guaranteed). No secrets are printed.
set -u

PROJECT_REF="zqfurscyhmxlvrfendnc"
SUPA_URL="https://${PROJECT_REF}.supabase.co"
XCCONFIG="/Users/wendy/Dev/Passport/ios-native/scout22/scout22.local.xcconfig"

MGMT_TOKEN=$(security find-generic-password -s "Supabase CLI" -w | sed 's/^go-keyring-base64://' | base64 -d)
ANON_KEY=$(grep '^SUPABASE_ANON_KEY' "$XCCONFIG" | sed 's/.*= *//' | tr -d ' "')
PW=$(openssl rand -hex 12)

run_sql() {
  local sql
  sql=$(cat)
  SUPA_MGMT_TOKEN="$MGMT_TOKEN" SQL_QUERY="$sql" python3 - <<'PYEOF'
import json, urllib.request, urllib.error, os
req = urllib.request.Request(
    "https://api.supabase.com/v1/projects/zqfurscyhmxlvrfendnc/database/query",
    data=json.dumps({"query": os.environ["SQL_QUERY"]}).encode(),
    headers={"Authorization": "Bearer " + os.environ["SUPA_MGMT_TOKEN"],
             "Content-Type": "application/json", "User-Agent": "curl/8.6.0"},
    method="POST",
)
try:
    print(urllib.request.urlopen(req).read().decode())
except urllib.error.HTTPError as e:
    print("SQL_HTTP_ERROR", e.code, e.read().decode())
PYEOF
}

CLEANED=0
cleanup() {
  [ "$CLEANED" = 1 ] && return
  CLEANED=1
  echo "--- cleanup ---"
  run_sql <<'SQL'
delete from public.jobs where title = 'Funnel Verification Role';
delete from auth.users where email = 'funnel@auditverify.local';
select
  (select count(*) from auth.users where email = 'funnel@auditverify.local') as users_left,
  (select count(*) from public.jobs where title = 'Funnel Verification Role') as jobs_left;
SQL
}
trap cleanup EXIT

echo "--- setup fixture (candidate + unpublished job) ---"
SETUP_OUT=$(run_sql <<SQL
delete from auth.users where email = 'funnel@auditverify.local';
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
) values (
  '00000000-0000-0000-0000-000000000000', extensions.gen_random_uuid(),
  'authenticated', 'authenticated', 'funnel@auditverify.local',
  extensions.crypt('$PW', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Funnel Tester"}'::jsonb, now(), now(),
  '', '', '', '', '', '', '', ''
);
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select extensions.gen_random_uuid(), u.id, u.id::text, 'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  now(), now(), now()
from auth.users u where u.email = 'funnel@auditverify.local';
update public.profiles set onboarding_complete = true where email = 'funnel@auditverify.local';
insert into public.job_seeker_profiles (profile_id)
select id from public.profiles where email = 'funnel@auditverify.local'
on conflict (profile_id) do nothing;
insert into public.jobs
  (employer_profile_id, posted_by_profile_id, title, company_name, description,
   application_email, video_url, is_published, apply_url)
select null, p.id, 'Funnel Verification Role', 'AuditCo', 'fixture',
  'jobs@auditverify.local', 'https://example.com/j.mp4', false,
  'https://boards.greenhouse.io/auditco/jobs/1'
from public.profiles p where p.email = 'funnel@auditverify.local';
select
  (select id from public.profiles where email = 'funnel@auditverify.local') as cand,
  (select id from public.jobs where title = 'Funnel Verification Role') as job;
SQL
)
read -r CAND JOB <<<"$(python3 -c '
import json, sys
rows = json.loads(sys.argv[1])
print(rows[0]["cand"], rows[0]["job"])
' "$SETUP_OUT")" || { echo "SETUP FAILED: $SETUP_OUT"; exit 1; }
[ -n "${JOB:-}" ] || { echo "SETUP FAILED: $SETUP_OUT"; exit 1; }
echo "fixture ready"

JWT=$(curl -s -X POST "$SUPA_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"funnel@auditverify.local\",\"password\":\"$PW\"}" |
  python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))')
[ -n "$JWT" ] || { echo "LOGIN FAILED"; exit 1; }

fn() { # name json-body
  curl -s -X POST "$SUPA_URL/functions/v1/$1" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" -d "$2"
}

echo "--- replay the app's call sequence ---"
OPENED=$(fn log-application-event "{\"jobId\":\"$JOB\",\"eventType\":\"opened\",\"atsType\":\"greenhouse\",\"applyUrl\":\"https://boards.greenhouse.io/auditco/jobs/1\"}")
OPENED_ID=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("id",""))' "$OPENED")
echo "opened event: ${OPENED_ID:+ok}"
SUBMITTED=$(fn log-application-event "{\"jobId\":\"$JOB\",\"eventType\":\"submitted\",\"atsType\":\"greenhouse\",\"applyUrl\":\"https://boards.greenhouse.io/auditco/jobs/1\"}")
SUBMITTED_ID=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("id",""))' "$SUBMITTED")
echo "submitted event: ${SUBMITTED_ID:+ok}"
[ -n "$OPENED_ID" ] && [ -n "$SUBMITTED_ID" ] || { echo "FAIL: event logging broke: $OPENED / $SUBMITTED"; exit 1; }
FIELDS=$(fn store-application-fields "{\"eventId\":\"$SUBMITTED_ID\",\"shortFields\":[{\"label\":\"Email\",\"value\":\"funnel@auditverify.local\"}],\"essays\":[]}")
echo "fields stored: $FIELDS"

echo "--- assert DB rows ---"
ASSERT=$(run_sql <<SQL
select
  (select count(*) from public.application_events
     where job_id = '$JOB' and candidate_profile_id = '$CAND' and event_type = 'opened') as opened_rows,
  (select count(*) from public.application_events
     where job_id = '$JOB' and candidate_profile_id = '$CAND' and event_type = 'submitted') as submitted_rows,
  (select count(*) from public.application_fields
     where event_id = '$SUBMITTED_ID') as field_rows;
SQL
)
echo "$ASSERT"
python3 -c '
import json, sys
r = json.loads(sys.argv[1])[0]
ok = r["opened_rows"] == 1 and r["submitted_rows"] == 1 and r["field_rows"] == 1
print("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED")
sys.exit(0 if ok else 1)
' "$ASSERT"
