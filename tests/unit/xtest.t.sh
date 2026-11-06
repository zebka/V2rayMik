#!/bin/sh
# Task 5: the test plan and a bounded run.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. /app/lib/admin.sh
. /app/lib/links.sh
. /app/lib/subs.sh
. /app/lib/xtest.sh

OUT='{"protocol":"vless","settings":{"vnext":[{"address":"a.test","port":443,"users":[{"id":"u","encryption":"none"}]}]}}'

plan=$(xtest_plan "$OUT" 10800)
echo "$plan" | jq -e '.inbounds[0].protocol == "socks"' >/dev/null || fail "no socks inbound"
echo "$plan" | jq -e '.inbounds[0].port == 10800' >/dev/null || fail "wrong port"
echo "$plan" | jq -e '.outbounds[0].protocol == "vless"' >/dev/null || fail "outbound not passed through"
echo "$plan" | jq -e '.outbounds | length == 1' >/dev/null || fail "extra outbounds"

# the plan must satisfy xray itself
printf '%s' "$plan" > /tmp/xt.json
xray run -test -c /tmp/xt.json >/dev/null 2>&1 || fail "xray rejected the test plan"
