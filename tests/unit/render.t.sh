#!/bin/sh
# Render a sing-box TUN inbound around a user-supplied outbound file.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

E=${APP_DIR:-/app}/entrypoint.sh

OB=/tmp/ob.json
cat > "$OB" <<'JSON'
{"type":"vless","server":"203.0.113.9","server_port":443,
 "uuid":"11111111-1111-4111-8111-111111111111",
 "tls":{"enabled":true,"server_name":"example.com"}}
JSON

out=$(NODE_OUTBOUND_FILE=$OB sh "$E" render -)
# the image's ENTRYPOINT must be executable, not just readable (a Linux checkout
# keeps COPY's 0644 mode, and `exec` then fails with permission denied)
[ -x "$E" ] || { echo "entrypoint is not directly executable" >&2; exit 1; }
assert_eq "$(printf '%s' "$out" | jq -r '.inbounds[0].type')" "tun" "inbound type"
assert_eq "$(printf '%s' "$out" | jq -r '.inbounds[0].interface_name')" "tun0" "tun name"
assert_eq "$(printf '%s' "$out" | jq -r '.inbounds[0].address[0]')" "198.18.0.1/15" "tun address"
assert_eq "$(printf '%s' "$out" | jq -r '.inbounds[0].auto_route')" "false" "no auto_route (RouterOS owns the routes)"
assert_eq "$(printf '%s' "$out" | jq -r '.outbounds[0].type')" "vless" "outbound type"
assert_eq "$(printf '%s' "$out" | jq -r '.outbounds[0].tag')" "proxy" "outbound tag is normalised"
assert_eq "$(printf '%s' "$out" | jq -r '.outbounds[1].type')" "direct" "direct outbound is added"
assert_eq "$(printf '%s' "$out" | jq -r '.route.final')" "proxy" "final route"

# the rendered config must pass sing-box's own parser
printf '%s' "$out" > /tmp/rendered.json
if ! sing-box check -c /tmp/rendered.json >/tmp/sb-check.log 2>&1; then
  echo "sing-box rejected the rendered config:" >&2
  cat /tmp/sb-check.log >&2
  exit 1
fi

set +e
err=$(NODE_OUTBOUND_FILE=/nonexistent sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "missing-config exit"
assert_match "$err" "missing-config"

set +e
err=$(NODE_OUTBOUND_FILE=$OB NODE_LINK='vless://u@h:1' sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "conflicting-config exit"
assert_match "$err" "conflicting-config"

echo '{"type":"tun","interface_name":"x"}' > /tmp/bad.json
set +e
err=$(NODE_OUTBOUND_FILE=/tmp/bad.json sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "tun-outbound exit"
assert_match "$err" "invalid-outbound"

echo '{"inbounds":[]}' > /tmp/bad2.json
set +e
err=$(NODE_OUTBOUND_FILE=/tmp/bad2.json sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "inbounds-in-outbound exit"
assert_match "$err" "invalid-outbound"

echo '{"type":"vless","server":"2001:db8::1","server_port":443,"uuid":"u"}' > /tmp/v6.json
set +e
err=$(NODE_OUTBOUND_FILE=/tmp/v6.json sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "ipv6 outbound exit"
assert_match "$err" "ipv6-unsupported"

# a hysteria2 outbound renders just as well (the whole reason for sing-box)
cat > /tmp/hy2.json <<'JSON'
{"type":"hysteria2","server":"203.0.113.9","server_port":22001,"password":"p",
 "tls":{"enabled":true,"server_name":"bing.com","insecure":true}}
JSON
out=$(NODE_OUTBOUND_FILE=/tmp/hy2.json sh "$E" render -)
assert_eq "$(printf '%s' "$out" | jq -r '.outbounds[0].type')" "hysteria2" "hy2 outbound type"
printf '%s' "$out" > /tmp/rendered-hy2.json
sing-box check -c /tmp/rendered-hy2.json >/dev/null 2>&1 \
  || fail "sing-box rejected the rendered hysteria2 config"
