#!/bin/bash
# Email-pipeline verification: sends ONE real founder email and ONE real
# application email through the deployed edge functions, using a namespaced
# fixture candidate + fixture company/job/contact, then reports exactly what
# Resend said (delivery_status / delivery_error on the recorded rows).
#
# The founder-contact fixture points at a real inbox you control, so a
# successful run puts two real emails in that inbox:
#   RECIPIENT (default winniebear288@gmail.com)
#
# Self-cleaning (trap-guaranteed): fixture user + rows are deleted on exit,
# even on failure. KEEP_FIXTURE=1 keeps the (unpublished) company/contact/job
# as a standing test target; the fixture user is always removed.
# Secrets (management token, JWTs, password) never leave process memory.
set -u

PROJECT_REF="zqfurscyhmxlvrfendnc"
SUPA_URL="https://${PROJECT_REF}.supabase.co"
XCCONFIG="/Users/wendy/Dev/Passport/ios-native/JobTok/JobTok.local.xcconfig"
RECIPIENT="${RECIPIENT:-winniebear288@gmail.com}"
KEEP_FIXTURE="${KEEP_FIXTURE:-0}"
FIXTURE_EMAIL="candt@emailverify.local"
FIXTURE_CO="zztest scout22 email co"
FIXTURE_JOB="zztest Email Pipeline Check"

MGMT_TOKEN=$(security find-generic-password -s "Supabase CLI" -w | sed 's/^go-keyring-base64://' | base64 -d)
ANON_KEY=$(grep '^SUPABASE_ANON_KEY' "$XCCONFIG" | sed 's/.*= *//' | tr -d ' "')
PW=$(openssl rand -hex 12)

run_sql() { # SQL on stdin; prints JSON rows
  local sql
  sql=$(cat)
  SUPA_MGMT_TOKEN="$MGMT_TOKEN" SQL_QUERY="$sql" python3 - <<'PYEOF'
import json, sys, urllib.request, urllib.error, os
sql = os.environ["SQL_QUERY"]
req = urllib.request.Request(
    "https://api.supabase.com/v1/projects/zqfurscyhmxlvrfendnc/database/query",
    data=json.dumps({"query": sql}).encode(),
    headers={"Authorization": "Bearer " + os.environ["SUPA_MGMT_TOKEN"],
             "Content-Type": "application/json",
             "User-Agent": "curl/8.6.0"},
    method="POST",
)
try:
    with urllib.request.urlopen(req) as r:
        print(r.read().decode())
except urllib.error.HTTPError as e:
    print("SQL_HTTP_ERROR", e.code, e.read().decode())
    sys.exit(1)
PYEOF
}

RES_PATH=""
CLEANED=0
cleanup() {
  [ "$CLEANED" = 1 ] && return
  CLEANED=1
  echo "--- cleanup (KEEP_FIXTURE=$KEEP_FIXTURE) ---"
  if [ -n "$RES_PATH" ]; then
    SRK=$(curl -s "https://api.supabase.com/v1/projects/$PROJECT_REF/api-keys?reveal=true" \
      -H "Authorization: Bearer $MGMT_TOKEN" | python3 -c '
import json,sys
for k in json.load(sys.stdin):
    if k.get("name")=="service_role": print(k["api_key"])')
    [ -n "$SRK" ] && curl -s -o /dev/null -X DELETE \
      "$SUPA_URL/storage/v1/object/resumes/$RES_PATH" -H "Authorization: Bearer $SRK"
  fi
  if [ "$KEEP_FIXTURE" = 1 ]; then
    run_sql <<SQL
update public.jobs set is_published = false where title = '$FIXTURE_JOB';
delete from public.founder_outreach_messages
  where company_id in (select id from public.companies where name = '$FIXTURE_CO');
delete from auth.users where email = '$FIXTURE_EMAIL';
select (select count(*) from auth.users where email = '$FIXTURE_EMAIL') users_left,
       (select is_published from public.jobs where title = '$FIXTURE_JOB') job_published;
SQL
  else
    run_sql <<SQL
delete from public.founder_outreach_messages
  where company_id in (select id from public.companies where name = '$FIXTURE_CO');
delete from public.jobs where title = '$FIXTURE_JOB';
delete from public.company_contacts
  where company_id in (select id from public.companies where name = '$FIXTURE_CO');
delete from public.companies where name = '$FIXTURE_CO';
delete from auth.users where email = '$FIXTURE_EMAIL';
select (select count(*) from auth.users where email = '$FIXTURE_EMAIL') users_left,
       (select count(*) from public.companies where name = '$FIXTURE_CO') companies_left,
       (select count(*) from public.jobs where title = '$FIXTURE_JOB') jobs_left;
SQL
  fi
}
trap cleanup EXIT

echo "--- setup fixtures (founder inbox: $RECIPIENT) ---"
SETUP_OUT=$(run_sql <<SQL
delete from auth.users where email = '$FIXTURE_EMAIL';
delete from public.founder_outreach_messages
  where company_id in (select id from public.companies where name = '$FIXTURE_CO');
delete from public.jobs where title = '$FIXTURE_JOB';
delete from public.company_contacts
  where company_id in (select id from public.companies where name = '$FIXTURE_CO');
delete from public.companies where name = '$FIXTURE_CO';

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
) values (
  '00000000-0000-0000-0000-000000000000', extensions.gen_random_uuid(),
  'authenticated', 'authenticated', '$FIXTURE_EMAIL',
  extensions.crypt('$PW', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Scout Test Candidate"}'::jsonb, now(), now(),
  '', '', '', '', '', '', '', ''
);

insert into auth.identities (
  id, user_id, provider_id, provider, identity_data,
  last_sign_in_at, created_at, updated_at
)
select extensions.gen_random_uuid(), u.id, u.id::text, 'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  now(), now(), now()
from auth.users u where u.email = '$FIXTURE_EMAIL';

update public.profiles set onboarding_complete = true, full_name = 'Scout Test Candidate'
where email = '$FIXTURE_EMAIL';

-- Use a REAL video object when one exists so the attachment path is
-- exercised end to end; placeholder URL otherwise (falls back to a link).
insert into public.job_seeker_profiles (profile_id, school_name, job_function, intro_video_url)
select id, 'UC Berkeley', 'engineering',
  coalesce(
    (select 'https://$PROJECT_REF.supabase.co/storage/v1/object/public/videos/' || name
     from storage.objects where bucket_id = 'videos' and name not like 'zztest%'
     order by created_at desc limit 1),
    'https://$PROJECT_REF.supabase.co/storage/v1/object/public/videos/zztest/intro.mp4')
from public.profiles where email = '$FIXTURE_EMAIL'
on conflict (profile_id) do update set intro_video_url = excluded.intro_video_url;

with co as (
  insert into public.companies (name) values ('$FIXTURE_CO') returning id
), ct as (
  insert into public.company_contacts
    (company_id, full_name, first_name, role_title, source, email, email_status, confidence)
  select id, 'Test Founder', 'Test', 'CEO', 'manual', '$RECIPIENT', 'verified', 1.0
  from co returning id
), jb as (
  insert into public.jobs
    (title, company_name, company_id, description, application_email, is_published, is_active)
  select '$FIXTURE_JOB', '$FIXTURE_CO', co.id,
    'Fixture job used to verify the outbound email pipeline end to end.',
    '$RECIPIENT', false, true
  from co returning id
)
select (select id from co) company_id, (select id from ct) contact_id,
       (select id from jb) job_id,
       (select id from public.profiles where email = '$FIXTURE_EMAIL') cand_id;
SQL
)
read -r COMPANY_ID CONTACT_ID JOB_ID CAND_ID < <(printf '%s' "$SETUP_OUT" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
r = rows[0]
assert r["company_id"] and r["contact_id"] and r["job_id"] and r["cand_id"], rows
print(r["company_id"], r["contact_id"], r["job_id"], r["cand_id"])
') || { echo "SETUP FAILED: $SETUP_OUT"; exit 1; }
echo "fixtures ready (job $JOB_ID)"

JWT=$(curl -s -X POST "$SUPA_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$FIXTURE_EMAIL\",\"password\":\"$PW\"}" |
  python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))')
[ -n "$JWT" ] || { echo "LOGIN FAILED"; exit 1; }
echo "fixture JWT minted"

fn() { # name json-body -> body + last line = status
  curl -s -w '\n%{http_code}' -X POST "$SUPA_URL/functions/v1/$1" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" -d "$2"
}
body_of() { sed '$d' <<<"$1"; }
code_of() { tail -n1 <<<"$1"; }

FAILED=0
declare -a RESULTS
note() { RESULTS+=("$1"); }
require() { # label expected actual
  if [ "$2" = "$3" ]; then note "PASS: $1"; else note "FAIL: $1 (expected [$2], got [$3])"; FAILED=1; fi
}

echo "--- founder email: resume gate (M-B) ---"
R=$(fn send-founder-email "{\"jobId\":\"$JOB_ID\",\"mode\":\"preview\"}")
case "$(body_of "$R")" in
  *'"reason":"resume_required"'*) note "PASS: preview blocks on missing resume (M-B gate)";;
  *) note "FAIL: expected resume_required without a resume, got: $(body_of "$R" | head -c 200)"; FAILED=1;;
esac

echo "--- resume fixture (also unblocks the founder gate) ---"
printf '%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\nxref\n0 4\ntrailer<</Size 4/Root 1 0 R>>\n%%%%EOF\n' > /tmp/zztest-resume.$$.pdf
RES_PATH="$CAND_ID/zztest-resume.pdf"
UP=$(curl -s -w '\n%{http_code}' -X POST "$SUPA_URL/storage/v1/object/resumes/$RES_PATH" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/pdf" --data-binary @/tmp/zztest-resume.$$.pdf)
rm -f /tmp/zztest-resume.$$.pdf
require "resume storage upload 200" "200" "$(code_of "$UP")"
RU=$(curl -s -w '\n%{http_code}' -X POST "$SUPA_URL/rest/v1/resume_uploads" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d "{\"profile_id\":\"$CAND_ID\",\"file_path\":\"$RES_PATH\"}")
require "resume_uploads insert 201" "201" "$(code_of "$RU")"
RESUME_ID=$(body_of "$RU" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)[0]["id"])
except Exception: print("")')
if [ -n "$RESUME_ID" ]; then
  PR=$(fn parse-resume "{\"resumeId\":\"$RESUME_ID\",\"rawText\":\"Scout Test Candidate. UC Berkeley BS CS 2026. SWE intern at Stripe summer 2025 working on payments infrastructure in Go. Skills: Swift, Go, Python, SQL.\"}")
  echo "parse-resume HTTP $(code_of "$PR"): $(body_of "$PR" | head -c 300)"
  require "parse-resume HTTP 200" "200" "$(code_of "$PR")"
else
  note "FAIL: no resume id returned"; FAILED=1
fi

echo "--- founder email: preview ---"
R=$(fn send-founder-email "{\"jobId\":\"$JOB_ID\",\"mode\":\"preview\"}")
require "preview HTTP 200" "200" "$(code_of "$R")"
echo "preview: $(body_of "$R")"
case "$(body_of "$R")" in
  *'"eligible":true'*) note "PASS: preview eligible with manual contact";;
  *) note "FAIL: preview not eligible: $(body_of "$R" | head -c 300)"; FAILED=1;;
esac

echo "--- founder email: SEND (real email to $RECIPIENT) ---"
R=$(fn send-founder-email "{\"jobId\":\"$JOB_ID\",\"mode\":\"send\",\"note\":\"End-to-end test of the scout22 founder email path. Safe to ignore.\"}")
echo "send HTTP $(code_of "$R"): $(body_of "$R" | head -c 400)"
FOUNDER_ROW=$(run_sql <<SQL
select delivery_status, coalesce(delivery_error,'') delivery_error,
       coalesce(resend_email_id,'') resend_id
from public.founder_outreach_messages
where company_id = '$COMPANY_ID'::uuid
order by created_at desc limit 1;
SQL
)
echo "founder_outreach_messages: $FOUNDER_ROW"
case "$FOUNDER_ROW" in
  *'"delivery_status": "sent"'* | *'"delivery_status":"sent"'*) note "PASS: founder email SENT via Resend (tryscout22 path works)";;
  *) note "FAIL: founder email not sent — see delivery_error above"; FAILED=1;;
esac

echo "--- application email: publish + apply (real email to $RECIPIENT) ---"
run_sql >/dev/null <<SQL
update public.jobs set is_published = true where id = '$JOB_ID'::uuid;
SQL
R=$(fn apply-to-job "{\"jobId\":\"$JOB_ID\",\"resumeFilePath\":\"$RES_PATH\"}")
echo "apply HTTP $(code_of "$R"): $(body_of "$R" | head -c 400)"
run_sql >/dev/null <<SQL
update public.jobs set is_published = false where id = '$JOB_ID'::uuid;
SQL
APP_ROW=$(run_sql <<SQL
select status, email_delivery_status, coalesce(email_delivery_error,'') email_error
from public.job_applications
where job_id = '$JOB_ID'::uuid and candidate_profile_id = '$CAND_ID'::uuid
order by applied_at desc limit 1;
SQL
)
echo "job_applications: $APP_ROW"
case "$APP_ROW" in
  *'"email_delivery_status": "sent"'* | *'"email_delivery_status":"sent"'*) note "PASS: application email SENT via Resend (applications@ path works)";;
  *) note "FAIL: application email not sent — see email_error above"; FAILED=1;;
esac

echo ""
echo "=== RESULTS ==="
printf '%s\n' "${RESULTS[@]}"
echo "==============="
[ "$FAILED" = 0 ] && echo "ALL CHECKS PASSED — check $RECIPIENT inbox for 2 emails" || echo "SOME CHECKS FAILED"
exit $FAILED
