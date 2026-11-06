#!/bin/sh
# The test plan and a bounded run.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. /app/lib/admin.sh
. /app/lib/links.sh
. /app/lib/subs.sh
. /app/lib/xtest.sh

OUT='{"type":"vless","server":"a.test","server_port":443,"uuid":"u"}'

plan=$(xtest_plan "$OUT" 10800)
echo "$plan" | jq -e '.inbounds[0].type == "mixed"' >/dev/null || fail "no mixed inbound"
echo "$plan" | jq -e '.inbounds[0].listen_port == 10800' >/dev/null || fail "wrong port"
echo "$plan" | jq -e '.outbounds[0].type == "vless"' >/dev/null || fail "outbound not passed through"
echo "$plan" | jq -e '.outbounds | length == 1' >/dev/null || fail "extra outbounds"
echo "$plan" | jq -e '.route.final == "proxy"' >/dev/null || fail "route does not use the node"

# the plan must satisfy sing-box itself
printf '%s' "$plan" > /tmp/xt.json
sing-box check -c /tmp/xt.json >/dev/null 2>&1 || fail "sing-box rejected the test plan"

# a hysteria2 node must produce a plan sing-box accepts too
HY='{"type":"hysteria2","server":"a.test","server_port":22001,"password":"p","tls":{"enabled":true,"server_name":"bing.com"}}'
plan=$(xtest_plan "$HY" 10801)
printf '%s' "$plan" | jq -e '.outbounds[0].type == "hysteria2"' >/dev/null || fail "hy2 outbound lost"
printf '%s' "$plan" > /tmp/xt-hy.json
sing-box check -c /tmp/xt-hy.json >/dev/null 2>&1 || fail "sing-box rejected the hysteria2 test plan"
