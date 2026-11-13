#!/bin/sh
# Admin helpers and the LAN-only, passwordless web server.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. ${APP_DIR:-/app}/lib/admin.sh

DATA_DIR=/tmp/admintest
rm -rf "$DATA_DIR"; mkdir -p "$DATA_DIR"

# --- json_escape -------------------------------------------------------------
assert_eq "$(json_escape 'a"b\c')" 'a\"b\\c' "quotes and backslashes"
out=$(json_escape 'line1
line2')
assert_eq "$out" 'line1\nline2' "newlines become \\n"

# --- gen_of ------------------------------------------------------------------
printf 'a\n' > "$DATA_DIR/f.txt"
g1=$(gen_of "$DATA_DIR/f.txt")
printf 'b\n' > "$DATA_DIR/f.txt"
g2=$(gen_of "$DATA_DIR/f.txt")
[ -n "$g1" ] || fail "gen empty"
[ "$g1" != "$g2" ] || fail "gen does not change with the file"
assert_eq "$(gen_of "$DATA_DIR/nope")" "" "gen of a missing file"

# --- form parsing ------------------------------------------------------------
assert_eq "$(form_get 'a=1&b=2&a=3' a)" "3" "last value wins"
assert_eq "$(form_get 'a=1&b=2' b)" "2" "second key"
assert_eq "$(form_get 'x=hello%20world' x)" "hello world" "percent decoding"
assert_eq "$(form_get 'x=a+b' x)" "a b" "plus decoding"
assert_eq "$(form_get 'x=a%5Cb' x)" "a\b" "percent backslash"
assert_eq "$(form_get 'a=1' missing)" "" "missing key"

# --- url_decode backslash stays a backslash -----------------------------------
assert_eq "$(url_decode 'a%5Cn')" "a\n" "literal backslash-n stays text"

# --- lock --------------------------------------------------------------------
lock_release
lock_try || fail "first lock refused"
lock_try && fail "second lock granted"
lock_release
lock_try || fail "lock not re-acquirable"
lock_release

# --- start_admin -------------------------------------------------------------
# the panel is passwordless: it starts whenever httpd and the web root exist
ADMIN_PORT=18081 WEB_ROOT=${APP_DIR:-/app}/web start_admin 2>/dev/null
sleep 1
if command -v nc >/dev/null 2>&1; then
  nc -z 127.0.0.1 18081 || fail "httpd did not open the port"
fi
[ -n "${ADMIN_PID:-}" ] && kill "$ADMIN_PID" 2>/dev/null || true
assert_match "$(WEB_ROOT=/nope start_admin 2>&1 || true)" "admin-disabled" "missing web root disables the panel"
