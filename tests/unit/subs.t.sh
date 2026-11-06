#!/bin/sh
# Task 4: subscription decoding and listing.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. /app/lib/admin.sh
. /app/lib/links.sh
. /app/lib/subs.sh

D=/tmp/substest
rm -rf "$D"; mkdir -p "$D"

# --- base64 payload, three links --------------------------------------------
printf '%s\n%s\n%s\n' \
  'vless://11111111-1111-4111-8111-111111111111@203.0.113.9:443?security=tls&type=tcp&sni=a.test#Node%20A' \
  'trojan://pw@198.51.100.7:8443?security=tls&sni=b.test#Node%20B' \
  'ss://YWVzLTI1Ni1nY206cGFzcw==@192.0.2.5:8388#Node%20C' \
  | base64 > "$D/b64.txt"

assert_eq "$(subs_decode "$D/b64.txt" | wc -l | tr -d ' ')" "3" "base64 decodes to three links"

# --- plain payload with blanks and garbage ----------------------------------
{ printf '%s\n' \
  'vless://11111111-1111-4111-8111-111111111111@203.0.113.9:443?security=tls&type=tcp#Good'; \
  printf '\n'; \
  printf '%s\n' 'this is not a link'; \
  printf '%s\n' 'trojan://pw@198.51.100.7:3001?security=tls#Blocked'; } > "$D/plain.txt"

assert_eq "$(subs_decode "$D/plain.txt" | wc -l | tr -d ' ')" "3" "plain keeps non-blank lines"

row=$(subs_entry 'vless://11111111-1111-4111-8111-111111111111@203.0.113.9:443?security=tls&type=tcp#Node%20A')
assert_eq "$row" "Node A|vless|203.0.113.9|443" "label decoded from the fragment"

subs_entry 'garbage' >/dev/null 2>&1 && fail "garbage parsed as a link"

# --- port_ok ----------------------------------------------------------------
port_allowed 443 "443,80,2053" || fail "443 should be allowed"
port_allowed 3001 "443,80,2053" && fail "3001 should be blocked"
port_allowed 53 "443,53" || fail "last element must match"

# --- JSON list ---------------------------------------------------------------
out=$(subs_list "$D/plain.txt" "443,80,53" "abc123")
echo "$out" | jq -e '.entries | length == 2' >/dev/null || fail "list should have 2 usable entries"
echo "$out" | jq -e '.entries[0].label == "Good"' >/dev/null || fail "first label"
echo "$out" | jq -e '.entries[0].port_ok == true' >/dev/null || fail "443 must be allowed"
echo "$out" | jq -e '.entries[1].port_ok == false' >/dev/null || fail "3001 must be blocked"
echo "$out" | jq -e '.entries[0].host == "203.0.113.9"' >/dev/null || fail "host"
# the index is the raw line number, so /cgi-bin/test's sed lands on the same line
echo "$out" | jq -e '.entries[1].i == 2' >/dev/null || fail "index must be the raw line number"
# no secrets in the list
echo "$out" | grep -q '11111111' && fail "list leaked a UUID"

# a subscription often carries placeholder rows that point at localhost
printf '%s\n' 'ss://YWVzLTI1Ni1nY206cGFzcw==@127.0.0.1:1080#stats' > "$D/placeholder.txt"
assert_eq "$(subs_list "$D/placeholder.txt" "1080" | jq '.entries | length')" "0" "loopback placeholder dropped"
assert_eq "$(subs_count "$D/placeholder.txt")" "0" "loopback placeholder not counted"

assert_eq "$(subs_count "$D/plain.txt")" "2" "count counts usable links"
assert_eq "$(subs_count "$D/missing.txt")" "0" "missing file counts zero"
