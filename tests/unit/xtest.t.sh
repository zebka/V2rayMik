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

# Where the node exits is read from Cloudflare's trace. That URL has to be the
# HTTPS one: `http://1.1.1.1/cdn-cgi/trace` answers 301 to HTTPS, and a redirect
# page contains no `loc=` line at all, so every test used to report a blank
# country while the delay and speed were measured fine.
case "$TRACE_URL" in
  https://*) ;;
  *) fail "trace URL must be https, got [$TRACE_URL]" ;;
esac

assert_eq "$(trace_country 'ip=203.0.113.7
ts=1793981610.5
loc=US
colo=MCI
warp=off')" "US" "trace country"

# a redirect body (or any non-trace answer) must yield nothing, not a bogus code
assert_eq "$(trace_country '<html><head><title>301 Moved Permanently</title></head></html>')" \
  "" "redirect body yields no country"

# a hysteria2 node must produce a plan sing-box accepts too
HY='{"type":"hysteria2","server":"a.test","server_port":22001,"password":"p","tls":{"enabled":true,"server_name":"bing.com"}}'
plan=$(xtest_plan "$HY" 10801)
printf '%s' "$plan" | jq -e '.outbounds[0].type == "hysteria2"' >/dev/null || fail "hy2 outbound lost"
printf '%s' "$plan" > /tmp/xt-hy.json
sing-box check -c /tmp/xt-hy.json >/dev/null 2>&1 || fail "sing-box rejected the hysteria2 test plan"
