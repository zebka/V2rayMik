#!/bin/sh
# Task 4: subscription decoding and listing.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. ${APP_DIR:-/app}/lib/admin.sh
. ${APP_DIR:-/app}/lib/links.sh
. ${APP_DIR:-/app}/lib/xray.sh
. ${APP_DIR:-/app}/lib/subs.sh

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

# --- JSON list ---------------------------------------------------------------
# No port allowlist since 1.3.0: a port the panel would have called "blocked"
# (3001) is a normal entry now, and no entry carries port_ok at all.
out=$(subs_list "$D/plain.txt")
echo "$out" | jq -e '.entries | length == 2' >/dev/null || fail "list should have 2 usable entries"
echo "$out" | jq -e '.entries[0].label == "Good"' >/dev/null || fail "first label"
echo "$out" | jq -e '.entries[0].port == "443"' >/dev/null || fail "443 is listed"
echo "$out" | jq -e '.entries[1].port == "3001"' >/dev/null || fail "3001 is listed, no allowlist"
echo "$out" | jq -e 'all(.entries[]; has("port_ok") | not)' >/dev/null || fail "port_ok is gone"
echo "$out" | jq -e '.entries[0].host == "203.0.113.9"' >/dev/null || fail "host"
# the index is the raw line number, so /cgi-bin/test's sed lands on the same line
echo "$out" | jq -e '.entries[1].i == 2' >/dev/null || fail "index must be the raw line number"
# no secrets in the list
echo "$out" | grep -q '11111111' && fail "list leaked a UUID"

# a subscription often carries placeholder rows that point at localhost
printf '%s\n' 'ss://YWVzLTI1Ni1nY206cGFzcw==@127.0.0.1:1080#stats' > "$D/placeholder.txt"
assert_eq "$(subs_list "$D/placeholder.txt" | jq '.entries | length')" "0" "loopback placeholder dropped"
assert_eq "$(subs_count "$D/placeholder.txt")" "0" "loopback placeholder not counted"

assert_eq "$(subs_count "$D/plain.txt")" "2" "count counts usable links"
assert_eq "$(subs_count "$D/missing.txt")" "0" "missing file counts zero"

# --- why a payload was rejected ----------------------------------------------
# The operator has to be able to tell a dead provider from a wrong URL, so the
# wording is part of the interface.
printf '%s\n' '<html><body>login</body></html>' > "$D/page.html"
assert_match "$(subs_reject_reason "$D/page.html")" "web page" "an HTML answer is named"

# a sing-box profile is a valid subscription this panel cannot eat; saying so
# stops the hunt for a bug that is a wrong link.
cat > "$D/profile.json" <<'JSON'
{
  "dns": { "final": "local-dns" },
  "inbounds": [ { "type": "tun" } ],
  "outbounds": [ { "type": "vless", "server": "203.0.113.9", "server_port": 443 } ]
}
JSON
assert_match "$(subs_reject_reason "$D/profile.json")" "sing-box JSON profile" \
  "a sing-box profile is named, not called broken"
assert_match "$(subs_reject_reason "$D/profile.json")" "v2ray/links" \
  "the profile message says what to use instead"

assert_eq "$(subs_reject_reason "$D/missing.txt")" "the subscription was empty" \
  "a missing file is called empty"
: > "$D/empty.txt"
assert_eq "$(subs_reject_reason "$D/empty.txt")" "the subscription was empty" \
  "an empty file is called empty"

printf '%s\n' 'nothing here' > "$D/junk.txt"
assert_match "$(subs_reject_reason "$D/junk.txt")" "bytes" \
  "an unknown payload reports its size"
# --- dual engine in one list ---------------------------------------------
{ printf '%s\n' 'vless://u@203.0.113.9:443?type=xhttp&path=/x&security=reality&sni=r.test&pbk=pub&sid=abcd#Rly';
  printf '%s\n' 'vless://11111111-1111-4111-8111-111111111111@203.0.113.9:443?type=tcp&security=tls&sni=s.test#Plain';
  printf '%s\n' 'hy2://pw@198.51.100.7:22001?sni=h.test#HY2';
  printf '%s\n' 'tuic://abc:def@192.0.2.5:10443?sni=t.test#TUIC'; } > "$D/mixed.txt"
out=$(subs_list "$D/mixed.txt")
printf '%s' "$out" | jq -e '.entries | length == 4' >/dev/null || fail 'mixed list must keep all four rows'
printf '%s' "$out" | jq -e '.entries[0].engine == "xray"' >/dev/null || fail 'xhttp row must be tagged xray'
printf '%s' "$out" | jq -e '.entries[1].engine == "sing-box"' >/dev/null || fail 'vless/tcp row must be tagged sing-box'
printf '%s' "$out" | jq -e '.entries[2].engine == "sing-box"' >/dev/null || fail 'hysteria2 row must be tagged sing-box'
