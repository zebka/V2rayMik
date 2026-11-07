#!/bin/sh
# power: the panel's Stop button. Stop must be a flag next to state.json - not a
# killed process - because the router reacts to health, and because the container
# healthcheck would restart a tunnel that was stopped on purpose.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. /app/lib/admin.sh

bin=${CGI_DIR:-/app/web/cgi-bin}
D=/tmp/powertest
rm -rf "$D"; mkdir -p "$D"
DATA_DIR=$D
export DATA_DIR
tok=$(session_new)

run_power() {
  # run_power <state-value> [cookie]
  body="state=$1"
  printf '%s' "$body" | \
    CONTENT_LENGTH=${#body} \
    REQUEST_METHOD=POST \
    HTTP_COOKIE="${2-sid=$tok}" \
    BYPASS_FILE=$D/bypass.flag \
    DATA_DIR=$D \
    sh "$bin/power"
}

# --- Stop ---------------------------------------------------------------------
out=$(run_power stop)
assert_match "$out" '"ok":true' "stop answered ok"
assert_match "$out" '"bypassed":true' "stop reported bypassed"
[ -f "$D/bypass.flag" ] || fail "stop did not create $D/bypass.flag"

# Idempotent: pressing Stop twice is not an error.
out=$(run_power stop)
assert_match "$out" '"ok":true' "second stop"
[ -f "$D/bypass.flag" ] || fail "second stop removed the flag"

# --- Start --------------------------------------------------------------------
out=$(run_power start)
assert_match "$out" '"ok":true' "start answered ok"
assert_match "$out" '"bypassed":false' "start reported not bypassed"
[ -e "$D/bypass.flag" ] && fail "start left the flag behind"

# Start with nothing to start is not an error either.
out=$(run_power start)
assert_match "$out" '"ok":true' "second start"

# --- rejections change nothing ------------------------------------------------
out=$(run_power stop)
[ -f "$D/bypass.flag" ] || fail "setup: flag missing"

out=$(run_power middle)
assert_match "$out" '"ok":false' "bad state rejected"
assert_match "$out" '400' "bad state is a 400"
[ -f "$D/bypass.flag" ] || fail "bad state cleared the flag"

out=$(run_power start "sid=00000000000000000000000000000000")
assert_match "$out" '"ok":false' "unknown session rejected"
assert_match "$out" '401' "unknown session is a 401"
[ -f "$D/bypass.flag" ] || fail "unauthenticated call cleared the flag"

# A GET is not a state change, even with a good cookie.
out=$(printf '' | CONTENT_LENGTH=0 REQUEST_METHOD=GET HTTP_COOKIE="sid=$tok" \
        BYPASS_FILE=$D/bypass.flag DATA_DIR=$D sh "$bin/power")
assert_match "$out" '405' "GET refused"
