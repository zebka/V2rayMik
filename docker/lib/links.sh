# Share-link → sing-box outbound JSON. Sourced by entrypoint.sh and the tests.
# POSIX sh + jq. Every failure exits 2 with a named reason.
#
# The engine is sing-box (it speaks vless, vmess, trojan, shadowsocks, hysteria2
# and tuic); an outbound is a flat object with `type`, `server`, `server_port`
# and protocol-specific fields. There is no Xray-shaped nesting here on purpose:
# one shape, one renderer, one place to look.

urldecode() {
  printf '%b' "$(printf '%s' "$1" | sed -e 's/+/ /g' -e 's/%/\\x/g')"
}

# qs <query> <key> — prints the decoded value, or nothing.
qs() {
  rest=$1
  while [ -n "$rest" ]; do
    pair=${rest%%&*}
    case "$rest" in
      *"&"*) rest=${rest#*&} ;;
      *) rest="" ;;
    esac
    key=${pair%%=*}
    if [ "$key" = "$2" ]; then
      val=${pair#*=}
      [ "$val" = "$pair" ] && val=""
      urldecode "$val"
      return 0
    fi
  done
  return 0
}

link_fail() { echo "$1" >&2; exit 2; }

# hex_to_b64 <hex> — sing-box wants base64 for a certificate pin, links use hex.
hex_to_b64() {
  [ -n "$1" ] || return 0
  case "$1" in
    *[!0-9a-fA-F]*) return 0 ;;
  esac
  [ $(( ${#1} % 2 )) -eq 0 ] || return 0
  printf '%s' "$1" | xxd -r -p 2>/dev/null | base64 2>/dev/null | tr -d '\n'
}

# link_to_outbound <link> — prints one sing-box outbound object.
link_to_outbound() {
  link=$1
  case "$link" in
    *://*) ;;
    *) link_fail "bad-link: not a share link" ;;
  esac

  scheme=${link%%://*}
  body=${link#*://}
  body=${body%%#*}

  query=""
  case "$body" in
    *\?*) query=${body#*\?}; body=${body%%\?*} ;;
  esac

  case "$scheme" in
    vless) link_vless "$body" "$query" ;;
    trojan) link_trojan "$body" "$query" ;;
    ss) link_ss "$body" "$query" ;;
    vmess) link_vmess "$body" ;;
    hysteria2|hy2) link_hysteria2 "$body" "$query" ;;
    tuic) link_tuic "$body" "$query" ;;
    *) link_fail "unsupported-link: $scheme" ;;
  esac
}

# host_port <userinfo@host:port> → sets HOST and PORT
split_host_port() {
  hp=${1##*@}
  HOST=${hp%:*}
  PORT=${hp##*:}
  case "$HOST" in
    *:*) link_fail "ipv6-unsupported: this build has no IPv6" ;;
    \[*) link_fail "ipv6-unsupported: brackets in host" ;;
  esac
  [ -n "$HOST" ] && [ -n "$PORT" ] || link_fail "bad-link: missing host or port"
  case "$PORT" in
    *[!0-9]*) link_fail "bad-link: port is not a number" ;;
  esac
}

split_userinfo() {
  case "$1" in
    *@*) USERINFO=${1%@*} ;;
    *) link_fail "bad-link: missing user info" ;;
  esac
}

# tls_settings <sni> <insecure> <fingerprint> <publicKey> <shortId> <alpn> <pin>
# One place for every TLS flavour sing-box understands.
tls_settings() {
  jq -cn \
    --arg sni "${1:-}" \
    --arg insecure "${2:-}" \
    --arg fp "${3:-}" \
    --arg pbk "${4:-}" \
    --arg sid "${5:-}" \
    --arg alpn "${6:-}" \
    --arg pin "${7:-}" \
    '{enabled:true}
     + (if $sni != "" then {server_name:$sni} else {} end)
     + (if $insecure != "" and $insecure != "0" then {insecure:true} else {} end)
     + (if $alpn != "" then
          {alpn:($alpn | split(",") | map(gsub("^\\s+|\\s+$";"")))}
        else {} end)
     + (if $pin != "" then {certificate_public_key_sha256:[$pin]} else {} end)
     + (if $pbk != "" then
          {reality:{enabled:true, public_key:$pbk, short_id:$sid},
           utls:{enabled:true, fingerprint:(if $fp == "" then "chrome" else $fp end)}}
        else (if $fp != "" then {utls:{enabled:true, fingerprint:$fp}} else {} end)
        end)'
}

# transport_settings <type> <path> <host> <serviceName>
transport_settings() {
  case "${1:-tcp}" in
    ""|tcp|raw) printf 'null' ;;
    ws)
      jq -cn --arg path "${2:-/}" --arg host "${3:-}" \
        '{type:"ws", path:(if $path == "" then "/" else $path end)}
         + (if $host != "" then {headers:{"Host":[$host]}} else {} end)'
      ;;
    grpc)
      jq -cn --arg svc "${4:-}" '{type:"grpc"} + (if $svc != "" then {service_name:$svc} else {} end)'
      ;;
    httpupgrade)
      jq -cn --arg path "${2:-/}" --arg host "${3:-}" \
        '{type:"httpupgrade", path:(if $path == "" then "/" else $path end)}
         + (if $host != "" then {host:$host} else {} end)'
      ;;
    xhttp|splithttp)
      link_fail "unsupported-transport: $1 (sing-box has no xhttp; ask the provider for ws/grpc)"
      ;;
    *)
      link_fail "unsupported-transport: $1"
      ;;
  esac
}

link_vless() {
  split_userinfo "$1"
  split_host_port "$1"
  id=$(urldecode "$USERINFO")
  flow=$(qs "$2" flow)
  enc=$(qs "$2" encryption)
  case "$enc" in
    ""|none) ;;
    *) link_fail "unsupported-link: vless encryption=$enc (xray extension)" ;;
  esac

  sec=$(qs "$2" security)
  sni=$(qs "$2" sni)
  fp=$(qs "$2" fp)
  pbk=$(qs "$2" pbk)
  sid=$(qs "$2" sid)
  alpn=$(qs "$2" alpn)

  tls=null
  case "$sec" in
    tls|reality)
      [ -n "$sni" ] || sni=$(qs "$2" host)
      tls=$(tls_settings "$sni" "" "$fp" "$pbk" "$sid" "$alpn" "")
      ;;
    ""|none) ;;
    *) link_fail "unsupported-security: $sec" ;;
  esac

  jq -cn \
    --arg addr "$HOST" --argjson port "$PORT" --arg id "$id" --arg flow "$flow" \
    --argjson tls "$tls" \
    --argjson tr "$(transport_settings "$(qs "$2" type)" "$(qs "$2" path)" "$(qs "$2" host)" "$(qs "$2" serviceName)")" \
    '{type:"vless", tag:"proxy", server:$addr, server_port:$port, uuid:$id}
     + (if $flow != "" then {flow:$flow} else {} end)
     + (if $tls != null then {tls:$tls} else {} end)
     + (if $tr != null then {transport:$tr} else {} end)'
}

link_trojan() {
  split_userinfo "$1"
  split_host_port "$1"
  pass=$(urldecode "$USERINFO")
  sec=$(qs "$2" security)
  sni=$(qs "$2" sni)
  fp=$(qs "$2" fp)
  alpn=$(qs "$2" alpn)

  tls=null
  case "$sec" in
    ""|tls|reality)
      [ -n "$sni" ] || sni=$(qs "$2" host)
      tls=$(tls_settings "$sni" "$(qs "$2" allowInsecure)" "$fp" "" "" "$alpn" "")
      ;;
    *) link_fail "unsupported-security: $sec" ;;
  esac

  jq -cn \
    --arg addr "$HOST" --argjson port "$PORT" --arg pass "$pass" \
    --argjson tls "$tls" \
    --argjson tr "$(transport_settings "$(qs "$2" type)" "$(qs "$2" path)" "$(qs "$2" host)" "$(qs "$2" serviceName)")" \
    '{type:"trojan", tag:"proxy", server:$addr, server_port:$port, password:$pass}
     + (if $tls != null then {tls:$tls} else {} end)
     + (if $tr != null then {transport:$tr} else {} end)'
}

link_ss() {
  split_userinfo "$1"
  split_host_port "$1"

  case "$USERINFO" in
    *:*) decoded=$(urldecode "$USERINFO") ;;
    *) decoded=$(printf '%s' "$USERINFO" | base64 -d 2>/dev/null) \
         || link_fail "bad-link: ss user info is neither method:password nor base64" ;;
  esac

  case "$decoded" in
    *:*) ;;
    *) link_fail "bad-link: ss user info has no password" ;;
  esac
  method=${decoded%%:*}
  password=${decoded#*:}

  jq -cn \
    --arg addr "$HOST" --argjson port "$PORT" \
    --arg method "$method" --arg pass "$password" \
    '{type:"shadowsocks", tag:"proxy", server:$addr, server_port:$port,
      method:$method, password:$pass}'
}

link_vmess() {
  decoded=$(printf '%s' "$1" | base64 -d 2>/dev/null) \
    || link_fail "bad-link: vmess body is not base64"
  printf '%s' "$decoded" | jq -e . >/dev/null 2>&1 \
    || link_fail "bad-link: vmess body is not JSON"

  addr=$(printf '%s' "$decoded" | jq -r '.add // empty')
  port=$(printf '%s' "$decoded" | jq -r '.port // empty')
  id=$(printf '%s' "$decoded" | jq -r '.id // empty')
  net=$(printf '%s' "$decoded" | jq -r '.net // "tcp"')
  path=$(printf '%s' "$decoded" | jq -r '.path // empty')
  hosthdr=$(printf '%s' "$decoded" | jq -r '.host // empty')
  tls=$(printf '%s' "$decoded" | jq -r '.tls // empty')
  sni=$(printf '%s' "$decoded" | jq -r '.sni // empty')
  scy=$(printf '%s' "$decoded" | jq -r '.scy // "auto"')

  [ -n "$addr" ] && [ -n "$port" ] && [ -n "$id" ] \
    || link_fail "bad-link: vmess is missing add/port/id"
  case "$port" in
    *[!0-9]*) link_fail "bad-link: vmess port is not a number" ;;
  esac

  HOST=$addr
  PORT=$port

  tlsjson=null
  case "$tls" in
    tls|reality)
      [ -n "$sni" ] || sni=$hosthdr
      tlsjson=$(tls_settings "$sni" "" "" "" "" "" "")
      ;;
    *) ;;
  esac
  [ "$scy" = "auto" ] || [ -n "$scy" ] || scy=auto

  jq -cn \
    --arg addr "$addr" --argjson port "$port" --arg id "$id" --arg scy "$scy" \
    --argjson tls "$tlsjson" \
    --argjson tr "$(transport_settings "$net" "$path" "$hosthdr" "$path")" \
    '{type:"vmess", tag:"proxy", server:$addr, server_port:$port, uuid:$id,
      security:$scy, alter_id:0}
     + (if $tls != null then {tls:$tls} else {} end)
     + (if $tr != null then {transport:$tr} else {} end)'
}

# hysteria2://password@host:port?sni=…&insecure=1&obfs=salamander&obfs-password=…&pinSHA256=hex
link_hysteria2() {
  split_userinfo "$1"
  split_host_port "$1"
  pass=$(urldecode "$USERINFO")

  sni=$(qs "$2" sni)
  insecure=$(qs "$2" insecure)
  pin=$(hex_to_b64 "$(qs "$2" pinSHA256)")
  # A provider that puts `insecure=1` next to a pin expects clients to skip
  # verification, and its pin is often stale: on the reference node the pin named
  # a key the server no longer presents, sing-box refused the handshake, and the
  # same link was fine in the hysteria2 client (which honours `insecure` over the
  # pin). Trust the explicit `insecure` and drop the pin, so one stale field does
  # not turn a working node into a dead one.
  case "$insecure" in
    1|true|TRUE|yes) pin="" ;;
  esac
  obfs=$(qs "$2" obfs)
  obfsPass=$(qs "$2" obfs-password)

  jq -cn \
    --arg addr "$HOST" --argjson port "$PORT" --arg pass "$pass" \
    --argjson tls "$(tls_settings "$sni" "$insecure" "" "" "" "$(qs "$2" alpn)" "$pin")" \
    --arg obfs "$obfs" --arg obfsPass "$obfsPass" \
    --arg obfsMin "$(qs "$2" obfs-min-packet-size)" --arg obfsMax "$(qs "$2" obfs-max-packet-size)" \
    '{type:"hysteria2", tag:"proxy", server:$addr, server_port:$port,
      password:$pass, tls:$tls}
     + (if $obfs != "" then
          {obfs:({type:$obfs, password:$obfsPass}
                 + (if $obfsMin != "" then {min_packet_size:($obfsMin|tonumber)} else {} end)
                 + (if $obfsMax != "" then {max_packet_size:($obfsMax|tonumber)} else {} end))}
        else {} end)'
}

# tuic://uuid:password@host:port?sni=…&alpn=…&congestion_control=bbr
link_tuic() {
  split_userinfo "$1"
  split_host_port "$1"
  info=$(urldecode "$USERINFO")
  uuid=${info%%:*}
  pass=${info#*:}
  [ -n "$uuid" ] || link_fail "bad-link: tuic has no uuid"
  [ -n "$pass" ] && [ "$pass" != "$uuid" ] || link_fail "bad-link: tuic has no password"

  cc=$(qs "$2" congestion_control)

  jq -cn \
    --arg addr "$HOST" --argjson port "$PORT" --arg id "$uuid" --arg pass "$pass" \
    --argjson tls "$(tls_settings "$(qs "$2" sni)" "$(qs "$2" allow_insecure)" "$(qs "$2" fp)" "" "" "$(qs "$2" alpn)" "")" \
    --arg cc "${cc:-bbr}" \
    '{type:"tuic", tag:"proxy", server:$addr, server_port:$port,
      uuid:$id, password:$pass, tls:$tls, congestion_control:$cc}'
}
