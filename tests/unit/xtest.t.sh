#!/bin/sh
# The test plan and a bounded run.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. ${APP_DIR:-/app}/lib/admin.sh
. ${APP_DIR:-/app}/lib/links.sh
. ${APP_DIR:-/app}/lib/xray.sh
. ${APP_DIR:-/app}/lib/subs.sh
. ${APP_DIR:-/app}/lib/xtest.sh

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

# --- failure wording --------------------------------------------------------
# A bare `000` in the panel told the operator nothing. The reason must name the
# side that broke, and the engine's own words must survive the trip.
assert_eq "$(xtest_reason 97 0 /dev/null)" \
  "the proxy could not open the connection" "proxy refused the tunnel"
assert_eq "$(xtest_reason 7 0 /dev/null)" "connection refused" "direct refusal"
assert_eq "$(xtest_reason 28 0 /dev/null)" "timed out after 8s" "timeout is named"
assert_eq "$(xtest_reason 0 403 /dev/null)" "the check answered http 403" "answered but wrong"
assert_eq "$(xtest_reason 6 0 /dev/null)" "cannot resolve the check host" "dns failure"

LOG=/tmp/xtest-reason.log
# sing-box writes colour into the file and prefixes the line with the outbound
# that was used; neither belongs in front of the reason.
printf '%s\n' "$(printf '\033')[31mERROR$(printf '\033')[0m[0000] [[38;5;186m2456567597$(printf '\033')[0m 196ms] connection: open connection to connectivitycheck.gstatic.com:80 using outbound/vless[proxy]: reality verification failed" > "$LOG"
reason=$(xtest_reason 97 0 "$LOG")
assert_match "$reason" "reality verification failed" "engine's reason is kept"
assert_match "$reason" "^the proxy could not open the connection; sing-box: " "reason is framed"
assert_no_match "$reason" "using outbound" "outbound preamble removed"
assert_no_match "$reason" "38;5" "terminal colour removed"

# a missing log must not turn into a trailing empty clause
assert_eq "$(xtest_reason 97 0 /tmp/does-not-exist.log)" \
  "the proxy could not open the connection" "no log, no suffix"

# a hysteria2 node must produce a plan sing-box accepts too
HY='{"type":"hysteria2","server":"a.test","server_port":22001,"password":"p","tls":{"enabled":true,"server_name":"bing.com"}}'
plan=$(xtest_plan "$HY" 10801)
printf '%s' "$plan" | jq -e '.outbounds[0].type == "hysteria2"' >/dev/null || fail "hy2 outbound lost"
printf '%s' "$plan" > /tmp/xt-hy.json
sing-box check -c /tmp/xt-hy.json >/dev/null 2>&1 || fail "sing-box rejected the hysteria2 test plan"

# --- the xray side -------------------------------------------------------------
command -v xray >/dev/null 2>&1 || fail "xray binary missing from the image"

XOUT='{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"a.test","port":443,"users":[{"id":"u","encryption":"none"}]}]},"streamSettings":{"network":"xhttp","security":"reality","realitySettings":{"serverName":"a.test","publicKey":"pbk","shortId":"sid","fingerprint":"chrome","spiderX":""}},"xhttpSettings":{"path":"/x","mode":"auto"}}'
xp=$(xray_config "$XOUT" 10810)
printf '%s' "$xp" | jq -e '.inbounds[0].protocol == "socks"' >/dev/null || fail "xray plan has no socks inbound"
printf '%s' "$xp" | jq -e '.inbounds[0].port == 10810' >/dev/null || fail "xray plan wrong port"
printf '%s' "$xp" | jq -e '.inbounds[0].listen == "127.0.0.1"' >/dev/null || fail "xray plan must listen on localhost"
printf '%s' "$xp" | jq -e '.outbounds[0].protocol == "vless"' >/dev/null || fail "xray outbound not passed through"
printf '%s' "$xp" | jq -e '.outbounds | length == 1' >/dev/null || fail "extra xray outbounds"

assert_eq "$(engine_of_link 'vless://u@a.test:443?type=xhttp&security=reality&pbk=p&sni=b.test')" "xray" "xhttp goes to xray"
assert_eq "$(engine_of_link 'vless://u@a.test:443?type=ws&security=tls&sni=b.test')" "sing-box" "ws stays on sing-box"
assert_eq "$(engine_of_link 'hy2://p@a.test:443?sni=b.test')" "sing-box" "hysteria2 stays on sing-box"
assert_eq "$(engine_of_link 'hysteria2://p@a.test:443?sni=b.test')" "sing-box" "hysteria2 alias stays on sing-box"
assert_eq "$(engine_of_link 'tuic://i:p@a.test:443?sni=b.test')" "sing-box" "tuic stays on sing-box"
assert_eq "$(engine_of_link 'vless://u@a.test:443?encryption=ml-kem-768&security=tls&sni=b.test')" "xray" "vless encryption goes to xray"

xr=$(link_to_xray_outbound 'vless://u@a.test:443?type=xhttp&path=/sub&host=c.test&security=reality&sni=reality.test&pbk=pubkey&sid=abcd&fp=chrome')
printf '%s' "$xr" | jq -e '.protocol == "vless"' >/dev/null || fail "xray vless protocol"
printf '%s' "$xr" | jq -e '.settings.vnext[0].address == "a.test"' >/dev/null || fail "xray vless address"
printf '%s' "$xr" | jq -e '.settings.vnext[0].users[0].encryption == "none"' >/dev/null || fail "xray vless encryption default"
printf '%s' "$xr" | jq -e '.streamSettings.network == "xhttp"' >/dev/null || fail "xray xhttp network"
printf '%s' "$xr" | jq -e '.streamSettings.security == "reality"' >/dev/null || fail "xray reality security"
printf '%s' "$xr" | jq -e '.streamSettings.realitySettings.publicKey == "pubkey"' >/dev/null || fail "xray reality pbk"
printf '%s' "$xr" | jq -e '.streamSettings.xhttpSettings.path == "/sub"' >/dev/null || fail "xray xhttp path"
printf '%s' "$xr" | jq -e '.streamSettings.xhttpSettings.host == "c.test"' >/dev/null || fail "xray xhttp host"

xr=$(link_to_xray_outbound 'vless://u@a.test:443?type=splithttp&path=/s&security=tls&sni=t.test&alpn=h2,http/1.1')
printf '%s' "$xr" | jq -e '.streamSettings.network == "xhttp"' >/dev/null || fail "splithttp maps to xhttp"
printf '%s' "$xr" | jq -e '.streamSettings.tlsSettings.alpn == ["h2","http/1.1"]' >/dev/null || fail "xray tls alpn"

assert_eq "$(xray_endpoint_of "$XOUT")" "a.test:443" "xray endpoint_of"
pinned=$(xray_pin "$XOUT" 203.0.113.9)
printf '%s' "$pinned" | jq -e '.settings.vnext[0].address == "203.0.113.9"' >/dev/null || fail "xray_pin did not pin the vnext address"
