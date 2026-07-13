#!/bin/bash
# Item-2 verification: candidate-data exposure fixes, tested with real user
# JWTs directly against the hosted REST/RPC endpoints (not through the app).
#
# Self-cleaning: fixtures are created, asserted against over HTTP, and deleted
# in this single invocation (trap-guaranteed). Fixture users are namespaced
# (@auditverify.local), the fixture job is never published, and no real rows
# are touched. Secrets (management token, JWTs, fixture password) live only in
# this process's memory and are never printed.
set -u

PROJECT_REF="zqfurscyhmxlvrfendnc"
SUPA_URL="https://${PROJECT_REF}.supabase.co"
XCCONFIG="/Users/wendy/Dev/Passport/ios-native/JobTok/JobTok.local.xcconfig"

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

CLEANED=0
cleanup() {
  [ "$CLEANED" = 1 ] && return
  CLEANED=1
  echo "--- cleanup ---"
  run_sql <<'SQL'
delete from public.jobs where title = 'Audit Verification Role';
delete from auth.users where email like '%auditverify.local';
select
  (select count(*) from auth.users where email like '%auditverify.local') as users_left,
  (select count(*) from public.jobs where title = 'Audit Verification Role') as jobs_left,
  (select count(*) from public.profiles where email like '%auditverify.local') as profiles_left;
SQL
}
trap cleanup EXIT

FAILED=0
declare -a RESULTS
check() { # name expected actual [detail]
  if [ "$2" = "$3" ]; then
    RESULTS+=("PASS: $1")
  else
    RESULTS+=("FAIL: $1 (expected [$2], got [$3]) ${4:-}")
    FAILED=1
  fi
}

echo "--- setup fixtures ---"
SETUP_OUT=$(sed "s/__PW__/$PW/" "$(dirname "$0")/verify-rls-item2-fixtures.sql.tpl" | run_sql)
echo "$SETUP_OUT" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
r = rows[0]
assert r["cand_a"] and r["cand_b"] and r["emp_e"] and r["job_id"], rows
print(r["cand_a"], r["cand_b"], r["emp_e"], r["job_id"], r["applications"])
' > /tmp/ids.$$ || { echo "SETUP FAILED: $SETUP_OUT"; exit 1; }
read -r CAND_A CAND_B EMP_E JOB_ID APP_COUNT < /tmp/ids.$$
rm -f /tmp/ids.$$
echo "fixtures ready (application rows: $APP_COUNT)"

login() { # email -> access_token
  curl -s -X POST "$SUPA_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$PW\"}" |
    python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))'
}
JWT_A=$(login canda@auditverify.local)
JWT_B=$(login candb@auditverify.local)
JWT_E=$(login empe@auditverify.local)
[ -n "$JWT_A" ] && [ -n "$JWT_B" ] && [ -n "$JWT_E" ] || { echo "LOGIN FAILED"; exit 1; }
echo "3 fixture JWTs minted"

rest() { # jwt method path [json-body] -> body + last line = status
  local jwt="$1" method="$2" path="$3" body="${4:-}"
  if [ -n "$body" ]; then
    curl -s -w '\n%{http_code}' -X "$method" "$SUPA_URL$path" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $jwt" \
      -H "Content-Type: application/json" \
      -H "Prefer: resolution=merge-duplicates,return=minimal" \
      -d "$body"
  else
    curl -s -w '\n%{http_code}' -X "$method" "$SUPA_URL$path" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $jwt"
  fi
}
body_of() { sed '$d' <<<"$1"; }
code_of() { tail -n1 <<<"$1"; }

echo "--- asserts: DB-P1-3 (visibility) while candA is PRIVATE ---"
R=$(rest "$JWT_B" GET "/rest/v1/profiles?id=eq.$CAND_A&select=id,email")
check "candB cannot read candA profiles row (email)" "[]" "$(body_of "$R")"
R=$(rest "$JWT_B" GET "/rest/v1/job_seeker_profiles?profile_id=eq.$CAND_A&select=phone,desired_compensation_range")
check "candB cannot read candA phone/comp" "[]" "$(body_of "$R")"
R=$(rest "$JWT_B" GET "/rest/v1/job_seeker_employers?profile_id=eq.$CAND_A&select=employer_name")
check "candB cannot read candA employer history" "[]" "$(body_of "$R")"
R=$(rest "$JWT_B" GET "/rest/v1/candidate_videos?profile_id=eq.$CAND_A&select=video_url")
check "candB cannot read candA videos" "[]" "$(body_of "$R")"
R=$(rest "$JWT_E" GET "/rest/v1/job_seeker_profiles?profile_id=eq.$CAND_A&select=phone")
check "empE cannot read PRIVATE candA jsp (private trumps applied)" "[]" "$(body_of "$R")"
R=$(rest "$JWT_E" GET "/rest/v1/profiles?id=eq.$CAND_A&select=email")
check "empE cannot read PRIVATE candA profiles row" "[]" "$(body_of "$R")"

echo "--- asserts: legitimate owner paths still work ---"
R=$(rest "$JWT_A" GET "/rest/v1/job_seeker_profiles?profile_id=eq.$CAND_A&select=phone")
check "candA reads own jsp row" '[{"phone":"+1 555 0100"}]' "$(body_of "$R")"
R=$(rest "$JWT_A" GET "/rest/v1/profiles?id=eq.$CAND_A&select=email")
check "candA reads own profiles email" '[{"email":"canda@auditverify.local"}]' "$(body_of "$R")"
R=$(rest "$JWT_A" GET "/rest/v1/job_applications?candidate_profile_id=eq.$CAND_A&select=status")
check "candA reads own application (participants intact)" '[{"status":"submitted"}]' "$(body_of "$R")"

echo "--- asserts: DB-P1-2 (essay RPC) ---"
VEC=$(python3 -c 'print("[" + ",".join(["0"]*1536) + "]")')
R=$(rest "$JWT_B" POST "/rest/v1/rpc/match_candidate_essay" "{\"p_profile_id\":\"$CAND_A\",\"p_embedding\":\"$VEC\",\"p_min_score\":0,\"p_limit\":5}")
check "candB blocked from match_candidate_essay" "403" "$(code_of "$R")" "$(body_of "$R" | head -c 200)"
R=$(rest "$JWT_A" POST "/rest/v1/rpc/match_candidate_essay" "{\"p_profile_id\":\"$CAND_A\",\"p_embedding\":\"$VEC\",\"p_min_score\":0,\"p_limit\":5}")
check "even the owner is blocked client-side (service-role only)" "403" "$(code_of "$R")"
SR=$(run_sql <<SQL
set local role service_role;
select count(*) as n from public.match_candidate_essay('$CAND_A'::uuid, (select ('[' || array_to_string(array_fill(0, array[1536]), ',') || ']')::extensions.vector), 0.0, 5);
SQL
)
case "$SR" in
  *'"n"'*) RESULTS+=("PASS: service_role still executes match_candidate_essay");;
  *) RESULTS+=("FAIL: service_role essay RPC broke: $(head -c 200 <<<"$SR")"); FAILED=1;;
esac

echo "--- asserts: P1-9 / DB-P1-4 (internal notes) ---"
R=$(rest "$JWT_A" GET "/rest/v1/job_applications?candidate_profile_id=eq.$CAND_A&select=internal_notes")
check "internal_notes column is gone (400 on explicit select)" "400" "$(code_of "$R")"
APP_ID_JSON=$(rest "$JWT_E" GET "/rest/v1/job_applications?employer_profile_id=eq.$EMP_E&select=id")
APP_ID=$(body_of "$APP_ID_JSON" | python3 -c 'import json,sys;rows=json.load(sys.stdin);print(rows[0]["id"] if rows else "")')
[ -n "$APP_ID" ] || { RESULTS+=("FAIL: employer could not list own applications"); FAILED=1; }
R=$(rest "$JWT_E" POST "/rest/v1/application_notes?on_conflict=application_id" "{\"application_id\":\"$APP_ID\",\"employer_profile_id\":\"$EMP_E\",\"notes\":\"secret feedback\"}")
check "empE writes note to application_notes" "201" "$(code_of "$R")" "$(body_of "$R" | head -c 200)"
R=$(rest "$JWT_E" GET "/rest/v1/job_applications?employer_profile_id=eq.$EMP_E&select=id,application_notes(notes)")
case "$(body_of "$R")" in
  *'secret feedback'*) RESULTS+=("PASS: empE reads own note via embed");;
  *) RESULTS+=("FAIL: empE embed missing note: $(body_of "$R" | head -c 200)"); FAILED=1;;
esac
R=$(rest "$JWT_A" GET "/rest/v1/application_notes?select=notes")
check "candA sees zero application_notes rows" "[]" "$(body_of "$R")"
R=$(rest "$JWT_A" GET "/rest/v1/job_applications?candidate_profile_id=eq.$CAND_A&select=id,application_notes(notes)")
case "$(body_of "$R")" in
  *'secret feedback'*) RESULTS+=("FAIL: candA can see the employer note via embed!"); FAILED=1;;
  *) RESULTS+=("PASS: candA embed returns no note");;
esac
R=$(rest "$JWT_A" POST "/rest/v1/application_notes?on_conflict=application_id" "{\"application_id\":\"$APP_ID\",\"employer_profile_id\":\"$CAND_A\",\"notes\":\"candidate spoof\"}")
check "candA cannot write application_notes" "403" "$(code_of "$R")" "$(body_of "$R" | head -c 200)"

echo "--- flip candA to discoverable; employer paths must open, candB stays blocked ---"
run_sql >/dev/null <<SQL
update public.job_seeker_profiles
set discovery_visibility = 'discoverable_to_hiring_employers'
where profile_id = '$CAND_A'::uuid;
SQL
R=$(rest "$JWT_E" GET "/rest/v1/job_seeker_profiles?profile_id=eq.$CAND_A&select=phone")
check "empE reads DISCOVERABLE candA jsp" '[{"phone":"+1 555 0100"}]' "$(body_of "$R")"
R=$(rest "$JWT_E" GET "/rest/v1/employer_candidate_discovery?select=candidate_id&candidate_id=eq.$CAND_A")
check "discovery view returns candA to empE" "[{\"candidate_id\":\"$CAND_A\"}]" "$(body_of "$R")"
R=$(rest "$JWT_B" GET "/rest/v1/job_seeker_profiles?profile_id=eq.$CAND_A&select=phone")
check "candB still blocked even when candA discoverable" "[]" "$(body_of "$R")"

echo ""
echo "=== RESULTS ==="
printf '%s\n' "${RESULTS[@]}"
echo "==============="
[ "$FAILED" = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $FAILED
