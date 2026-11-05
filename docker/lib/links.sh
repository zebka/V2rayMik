# Share-link → outbound JSON. Sourced by entrypoint.sh (and by the tests).
# POSIX sh + jq. Every failure exits 2 with a named reason.

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

# link_to_outbound <link> — prints one outbound object.
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

stream_settings() {
  # $1 network, $2 security, $3 sni, $4 fingerprint, $5 publicKey,
  # $6 shortId, $7 path, $8 host header, $9 serviceName, $10 spiderX
  jq -n \
    --arg net "${1:-tcp}" \
    --arg sec "${2:-none}" \
    --arg sni "$3" \
    --arg fp "$4" \
    --arg pbk "$5" \
    --arg sid "$6" \
    --arg path "$7" \
    --arg hosthdr "$8" \
    --arg svc "$9" \
    --arg spx "${10:-}" \
    '({network:$net}
      + (if $sec == "tls" then
           {security:"tls",
            tlsSettings:({serverName:$sni}
                         + (if $fp != "" then {fingerprint:$fp} else {} end))}
         else {} end)
      + (if $sec == "reality" then
           {security:"reality",
            realitySettings:({serverName:$sni, publicKey:$pbk,
                              shortId:$sid, fingerprint:$fp}
                             + (if $spx != "" then {spiderX:$spx} else {} end))}
         else {} end)
      + (if $net == "ws" then
           {wsSettings:({path:(if $path == "" then "/" else $path end)}
                        + (if $hosthdr != "" then {headers:{Host:$hosthdr}} else {} end))}
         else {} end)
      + (if $net == "grpc" then {grpcSettings:{serviceName:$svc}} else {} end))'
}

link_vless() {
  split_userinfo "$1"
  split_host_port "$1"
  id=$(urldecode "$USERINFO")
  enc=$(qs "$2" encryption)
  flow=$(qs "$2" flow)
  jq -n \
    --arg addr "$HOST" --argjson port "$PORT" --arg id "$id" \
    --arg enc "${enc:-none}" --arg flow "$flow" \
    --argjson stream "$(stream_settings "$(qs "$2" type)" "$(qs "$2" security)" \
        "$(qs "$2" sni)" "$(qs "$2" fp)" "$(qs "$2" pbk)" "$(qs "$2" sid)" \
        "$(qs "$2" path)" "$(qs "$2" host)" "$(qs "$2" serviceName)" "$(qs "$2" spx)")" \
    '{protocol:"vless",
      settings:{vnext:[{address:$addr, port:$port,
                        users:[({id:$id, encryption:$enc}
                                + (if $flow != "" then {flow:$flow} else {} end))]}]},
      streamSettings:$stream}'
}

link_trojan() {
  split_userinfo "$1"
  split_host_port "$1"
  pass=$(urldecode "$USERINFO")
  jq -n \
    --arg addr "$HOST" --argjson port "$PORT" --arg pass "$pass" \
    --argjson stream "$(stream_settings "$(qs "$2" type)" "$(qs "$2" security)" \
        "$(qs "$2" sni)" "$(qs "$2" fp)" "" "" \
        "$(qs "$2" path)" "$(qs "$2" host)" "$(qs "$2" serviceName)" "$(qs "$2" spx)")" \
    '{protocol:"trojan",
      settings:{servers:[{address:$addr, port:$port, password:$pass}]},
      streamSettings:$stream}'
}

link_ss() {  split_userinfo "$1"
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

  jq -n \
    --arg addr "$HOST" --argjson port "$PORT" \
    --arg method "$method" --arg pass "$password" \
    '{protocol:"shadowsocks",
      settings:{servers:[{address:$addr, port:$port, method:$method, password:$pass}]}}'
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
  svc=$(printf '%s' "$decoded" | jq -r '.path // empty')

  [ -n "$addr" ] && [ -n "$port" ] && [ -n "$id" ] \
    || link_fail "bad-link: vmess is missing add/port/id"
  case "$port" in
    *[!0-9]*) link_fail "bad-link: vmess port is not a number" ;;
  esac

  HOST=$addr
  PORT=$port

  case "$tls" in
    tls|reality) sec=tls ;;
    *) sec=none ;;
  esac
  [ -n "$sni" ] || sni=$hosthdr

  jq -n \
    --arg addr "$addr" --argjson port "$port" --arg id "$id" --arg scy "$scy" \
    --argjson stream "$(stream_settings "$net" "$sec" "$sni" "" "" "" \
        "$path" "$hosthdr" "$svc")" \
    '{protocol:"vmess",
      settings:{vnext:[{address:$addr, port:$port,
                        users:[{id:$id, alterId:0, security:$scy}]}]},
      streamSettings:$stream}'
}
