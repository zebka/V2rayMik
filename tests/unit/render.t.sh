#!/bin/sh
# Task 2: render a TUN inbound around a user-supplied outbound file.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

E=/app/entrypoint.sh

OB=/tmp/ob.json
cat > "$OB" <<'JSON'
{"protocol":"vless","settings":{"vnext":[{"address":"203.0.113.9","port":443,
 "users":[{"id":"11111111-1111-4111-8111-111111111111","encryption":"none"}]}]},
 "streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"example.com"}}}
JSON

out=$(XRAY_OUTBOUND_FILE=$OB sh "$E" render -)
assert_eq "$(printf '%s' "$out" | jq -r '.inbounds[0].protocol')" "tun" "inbound protocol"
assert_eq "$(printf '%s' "$out" | jq -r '.inbounds[0].settings.name')" "tun0" "tun name"
assert_eq "$(printf '%s' "$out" | jq -r '.inbounds[0].settings.gateway[0]')" "198.18.0.1/15" "tun gateway"
assert_eq "$(printf '%s' "$out" | jq -r '.outbounds[0].protocol')" "vless" "outbound protocol"
assert_eq "$(printf '%s' "$out" | jq -r '.outbounds | length')" "1" "single outbound"

# given config must pass xray's own parser
printf '%s' "$out" > /tmp/rendered.json
if ! xray run -test -c /tmp/rendered.json >/tmp/xray-test.log 2>&1; then
  echo "xray rejected the rendered config:" >&2
  cat /tmp/xray-test.log >&2
  exit 1
fi

set +e
err=$(XRAY_OUTBOUND_FILE=/nonexistent sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "missing-config exit"
assert_match "$err" "missing-config"

set +e
err=$(XRAY_OUTBOUND_FILE=$OB XRAY_LINK='vless://u@h:1' sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "conflicting-config exit"
assert_match "$err" "conflicting-config"

echo '{"protocol":"tun","settings":{}}' > /tmp/bad.json
set +e
err=$(XRAY_OUTBOUND_FILE=/tmp/bad.json sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "tun-outbound exit"
assert_match "$err" "invalid-outbound"

echo '{"inbounds":[]}' > /tmp/bad2.json
set +e
err=$(XRAY_OUTBOUND_FILE=/tmp/bad2.json sh "$E" render - 2>&1); code=$?
set -e
assert_eq "$code" "2" "inbounds-in-outbound exit"
assert_match "$err" "invalid-outbound"
