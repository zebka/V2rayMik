#!/bin/sh
# Share-link parsing: every supported scheme becomes one sing-box outbound.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. /app/lib/links.sh

v='vless://11111111-1111-4111-8111-111111111111@203.0.113.9:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=artoBd_EJwWzPQ-eHFGlXzO0xbaWWUSwOPfCBq0FMt8&sid=ab12&type=tcp#name'
out=$(link_to_outbound "$v")
assert_eq "$(printf '%s' "$out" | jq -r '.type')" "vless" "vless type"
assert_eq "$(printf '%s' "$out" | jq -r '.server_port')" "443" "vless port"
assert_eq "$(printf '%s' "$out" | jq -r '.server')" "203.0.113.9" "vless server"
assert_eq "$(printf '%s' "$out" | jq -r '.flow')" "xtls-rprx-vision" "vless flow"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.reality.public_key')" "artoBd_EJwWzPQ-eHFGlXzO0xbaWWUSwOPfCBq0FMt8" "reality pbk"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.reality.short_id')" "ab12" "reality sid"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.utls.fingerprint')" "chrome" "reality utls fingerprint"
assert_eq "$(printf '%s' "$out" | jq -r '.tag')" "proxy" "outbound tag"

t='trojan://pass@203.0.113.9:443?security=tls&sni=x.test&type=ws&path=%2Fws&host=cdn.test'
out=$(link_to_outbound "$t")
assert_eq "$(printf '%s' "$out" | jq -r '.type')" "trojan" "trojan type"
assert_eq "$(printf '%s' "$out" | jq -r '.password')" "pass" "trojan password"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.server_name')" "x.test" "trojan sni"
assert_eq "$(printf '%s' "$out" | jq -r '.transport.type')" "ws" "trojan network"
assert_eq "$(printf '%s' "$out" | jq -r '.transport.path')" "/ws" "trojan ws path (percent-decoded)"
assert_eq "$(printf '%s' "$out" | jq -r '.transport.headers.Host[0]')" "cdn.test" "trojan ws host"

s='ss://YWVzLTI1Ni1nY206cGFzcw==@203.0.113.9:8388#label'
out=$(link_to_outbound "$s")
assert_eq "$(printf '%s' "$out" | jq -r '.type')" "shadowsocks" "ss type"
assert_eq "$(printf '%s' "$out" | jq -r '.method')" "aes-256-gcm" "ss method"
assert_eq "$(printf '%s' "$out" | jq -r '.password')" "pass" "ss password"
assert_eq "$(printf '%s' "$out" | jq -r '.server_port')" "8388" "ss port"

# a plain (non-base64) ss userinfo is legal too
out=$(link_to_outbound 'ss://2022-blake3-aes-128-gcm:secret@203.0.113.9:8388')
assert_eq "$(printf '%s' "$out" | jq -r '.method')" "2022-blake3-aes-128-gcm" "ss plain method"

# --- hysteria2 ---------------------------------------------------------------
h='hysteria2://secret@203.0.113.9:22001?security=tls&insecure=1&sni=bing.com&pinSHA256=8b09498b70ddc884a266048968f3ae60f19f1048822cd8857ee72df5cd5dd91d&obfs=salamander&obfs-password=guard#HY2'
out=$(link_to_outbound "$h")
assert_eq "$(printf '%s' "$out" | jq -r '.type')" "hysteria2" "hy2 type"
assert_eq "$(printf '%s' "$out" | jq -r '.password')" "secret" "hy2 password"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.insecure')" "true" "hy2 insecure"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.server_name')" "bing.com" "hy2 sni"
assert_eq "$(printf '%s' "$out" | jq -r '.obfs.type')" "salamander" "hy2 obfs"
assert_eq "$(printf '%s' "$out" | jq -r '.obfs.password')" "guard" "hy2 obfs password"
# `insecure=1` means the provider expects no verification, and its pin is often
# stale (measured: a live node whose pin named a key the server never sent). The
# pin must not be passed on, or the node tests as dead.
assert_eq "$(printf '%s' "$out" | jq -r '.tls.certificate_public_key_sha256')" \
  "null" "hy2 pin dropped when insecure"

# without `insecure`, the pin is the only verification and has to survive
hp='hysteria2://secret@203.0.113.9:22001?sni=bing.com&pinSHA256=8b09498b70ddc884a266048968f3ae60f19f1048822cd8857ee72df5cd5dd91d'
out=$(link_to_outbound "$hp")
assert_eq "$(printf '%s' "$out" | jq -r '.tls.certificate_public_key_sha256[0]')" \
  "iwlJi3DdyISiZgSJaPOuYPGfEEiCLNiFfuct9c1d2R0=" "hy2 pin kept without insecure"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.insecure')" "null" "hy2 not insecure"

# hy2 shorthand and a link without obfs
out=$(link_to_outbound 'hy2://p@203.0.113.9:8443?sni=a.test')
assert_eq "$(printf '%s' "$out" | jq -r '.type')" "hysteria2" "hy2 shorthand"
assert_eq "$(printf '%s' "$out" | jq -r '.obfs')" "null" "hy2 without obfs"

# --- tuic --------------------------------------------------------------------
out=$(link_to_outbound 'tuic://11111111-1111-4111-8111-111111111111:pw@203.0.113.9:8443?sni=a.test&alpn=h3')
assert_eq "$(printf '%s' "$out" | jq -r '.type')" "tuic" "tuic type"
assert_eq "$(printf '%s' "$out" | jq -r '.uuid')" "11111111-1111-4111-8111-111111111111" "tuic uuid"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.alpn | join(",")')" "h3" "tuic alpn"

# --- vmess -------------------------------------------------------------------
j='{"v":"2","ps":"n","add":"203.0.113.9","port":"443","id":"11111111-1111-4111-8111-111111111111","net":"ws","path":"/x","tls":"tls","sni":"x.test","scy":"auto"}'
vm="vmess://$(printf '%s' "$j" | base64 | tr -d '\n')"
out=$(link_to_outbound "$vm")
assert_eq "$(printf '%s' "$out" | jq -r '.type')" "vmess" "vmess type"
assert_eq "$(printf '%s' "$out" | jq -r '.server_port')" "443" "vmess port is numeric"
assert_eq "$(printf '%s' "$out" | jq -r '.security')" "auto" "vmess security"
assert_eq "$(printf '%s' "$out" | jq -r '.transport.type')" "ws" "vmess network"
assert_eq "$(printf '%s' "$out" | jq -r '.tls.server_name')" "x.test" "vmess sni"

# --- every outbound must satisfy sing-box itself -----------------------------
for link in "$v" "$t" "$s" "$h" 'tuic://11111111-1111-4111-8111-111111111111:pw@203.0.113.9:8443?sni=a.test' "$vm"; do
  link_to_outbound "$link" > /tmp/one.json
  jq -c '{log:{level:"warn"},inbounds:[{type:"mixed",tag:"in",listen:"127.0.0.1",listen_port:10999}],
          outbounds:[(. + {tag:"proxy"})],route:{final:"proxy"}}' \
    /tmp/one.json > /tmp/one2.json
  sing-box check -c /tmp/one2.json >/dev/null 2>&1 \
    || fail "sing-box rejected the outbound for ${link%%://*}"
done

# --- named rejections --------------------------------------------------------
set +e
err=$(link_to_outbound 'vless://u@203.0.113.9:6161?type=xhttp&security=tls&sni=a.test' 2>&1); code=$?
set -e
assert_eq "$code" "2" "xhttp exit"
assert_match "$err" "unsupported-transport: xhttp"

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

set +e
err=$(link_to_outbound 'wireguard://x@h:1' 2>&1); code=$?
set -e
assert_eq "$code" "2" "unknown scheme exit"
assert_match "$err" "unsupported-link: wireguard"
