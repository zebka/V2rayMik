#!/bin/sh
# Task 3: share-link parsing for vless, trojan and ss.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. /app/lib/links.sh

v='vless://11111111-1111-4111-8111-111111111111@203.0.113.9:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBKEY&sid=ab12&type=tcp#name'
out=$(link_to_outbound "$v")
assert_eq "$(printf '%s' "$out" | jq -r '.protocol')" "vless" "vless protocol"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.vnext[0].port')" "443" "vless port"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.vnext[0].address')" "203.0.113.9" "vless address"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.vnext[0].users[0].flow')" "xtls-rprx-vision" "vless flow"
assert_eq "$(printf '%s' "$out" | jq -r '.streamSettings.security')" "reality" "vless security"
assert_eq "$(printf '%s' "$out" | jq -r '.streamSettings.realitySettings.shortId')" "ab12" "reality sid"
assert_eq "$(printf '%s' "$out" | jq -r '.streamSettings.realitySettings.publicKey')" "PUBKEY" "reality pbk"

t='trojan://pass@203.0.113.9:443?security=tls&sni=x.test&type=ws&path=%2Fws&host=cdn.test'
out=$(link_to_outbound "$t")
assert_eq "$(printf '%s' "$out" | jq -r '.protocol')" "trojan" "trojan protocol"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.servers[0].password')" "pass" "trojan password"
assert_eq "$(printf '%s' "$out" | jq -r '.streamSettings.network')" "ws" "trojan network"
assert_eq "$(printf '%s' "$out" | jq -r '.streamSettings.wsSettings.path')" "/ws" "trojan ws path (percent-decoded)"
assert_eq "$(printf '%s' "$out" | jq -r '.streamSettings.wsSettings.headers.Host')" "cdn.test" "trojan ws host"

s='ss://YWVzLTI1Ni1nY206cGFzcw==@203.0.113.9:8388#label'
out=$(link_to_outbound "$s")
assert_eq "$(printf '%s' "$out" | jq -r '.protocol')" "shadowsocks" "ss protocol"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.servers[0].method')" "aes-256-gcm" "ss method"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.servers[0].password')" "pass" "ss password"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.servers[0].port')" "8388" "ss port"

set +e
err=$(link_to_outbound 'hysteria2://x@h:1' 2>&1); code=$?
set -e
assert_eq "$code" "2" "unsupported scheme exit"
assert_match "$err" "unsupported-link: hysteria2"

# a plain (non-base64) ss userinfo is legal too
out=$(link_to_outbound 'ss://2022-blake3-aes-128-gcm:secret@203.0.113.9:8388')
assert_eq "$(printf '%s' "$out" | jq -r '.settings.servers[0].method')" "2022-blake3-aes-128-gcm" "ss plain method"

# --- Task 4: vmess and named rejections -------------------------------------
j='{"v":"2","ps":"n","add":"203.0.113.9","port":"443","id":"11111111-1111-4111-8111-111111111111","net":"ws","path":"/x","tls":"tls","sni":"x.test","scy":"auto"}'
vm="vmess://$(printf '%s' "$j" | base64 | tr -d '\n')"
out=$(link_to_outbound "$vm")
assert_eq "$(printf '%s' "$out" | jq -r '.protocol')" "vmess" "vmess protocol"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.vnext[0].port')" "443" "vmess port is numeric"
assert_eq "$(printf '%s' "$out" | jq -r '.settings.vnext[0].users[0].security')" "auto" "vmess security"
assert_eq "$(printf '%s' "$out" | jq -r '.streamSettings.network')" "ws" "vmess network"
assert_eq "$(printf '%s' "$out" | jq -r '.streamSettings.tlsSettings.serverName')" "x.test" "vmess sni"

set +e
err=$(link_to_outbound 'vless://u@[2001:db8::1]:443?type=tcp' 2>&1); code=$?
set -e
assert_eq "$code" "2" "ipv6 exit"
assert_match "$err" "ipv6-unsupported"

set +e
err=$(link_to_outbound 'vless://u@2001:db8::1:443?type=tcp' 2>&1); code=$?
set -e
assert_eq "$code" "2" "unbracketed ipv6 exit"
assert_match "$err" "ipv6-unsupported"

set +e
err=$(link_to_outbound 'vless://nope' 2>&1); code=$?
set -e
assert_eq "$code" "2" "bad-link exit"
assert_match "$err" "bad-link"

set +e
err=$(link_to_outbound 'vmess://not-base64!!' 2>&1); code=$?
set -e
assert_eq "$code" "2" "bad vmess exit"
assert_match "$err" "bad-link"

