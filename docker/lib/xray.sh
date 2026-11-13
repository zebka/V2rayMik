# xray engine support. Sourced by the entrypoint, the live switch and the test
# harness — the TUN always belongs to sing-box; when a node needs Xray we run it
# as a local SOCKS5 outlet and chain sing-box to it (see entrypoint.sh).
#
# Why Xray exists in the image at all: sing-box cannot speak xhttp/splithttp,
# and vless "encryption=…" links exist. Anything either engine can carry is
# decided per node by engine_of_link.

XRAY_SOCKS_PORT=${XRAY_SOCKS_PORT:-10810}

# engine_of_link <link> — prints sing-box or xray.
# Xray only earns its keep when the node needs xhttp/splithttp or vless
# encryption; everything else stays on sing-box.
engine_of_link() {
  link=$1
  case "$link" in
    vmess://*)
      decoded=$(printf '%s' "${link#vmess://}" | base64 -d 2>/dev/null || true)
      net=$(printf '%s' "$decoded" | jq -r '.net // "tcp"' 2>/dev/null || true)
      case "$net" in xhttp|splithttp) printf 'xray' ;; *) printf 'sing-box' ;; esac
      return 0
      ;;
    vless://*|trojan://*)
      query=${link#*\?} ; query=${query%%#*}
      case "$link" in *\?*) ;; *) query="" ;; esac
      net=$(qs "$query" type)
      case "$net" in xhttp|splithttp) printf 'xray'; return 0 ;; esac
      enc=$(qs "$query" encryption)
      case "$enc" in ""|none) printf 'sing-box' ;; *) printf 'xray' ;; esac
      return 0
      ;;
    *) printf 'sing-box' ; return 0 ;;
  esac
}

# xray_stream <type> <path> <host> <serviceName> <sni> <allowInsecure> <fp>
#            <publicKey> <shortId> <alpn> — prints the streamSettings object.
xray_stream() {
  net=${1:-tcp}
  path=${2:-/}
  host=${3:-}
  svc=${4:-}
  sni=${5:-}
  insec=${6:-}
  fp=${7:-}
  pbk=${8:-}
  sid=${9:-}
  alpn=${10:-}

  case "$net" in ""|tcp|raw) net=tcp ;; esac

  sec=""
  if [ -n "$pbk" ]; then
    sec=$(jq -cn --arg sni "$sni" --arg pbk "$pbk" --arg sid "$sid" --arg fp "${fp:-chrome}" \
      '{security:"reality",realitySettings:{serverName:$sni,publicKey:$pbk,shortId:$sid,fingerprint:$fp,spiderX:""}}')
  elif [ -n "$sni" ] || [ -n "$insec" ] || [ -n "$fp" ] || [ -n "$alpn" ]; then
    ail=false
    case "$insec" in 1|true|TRUE|yes) ail=true ;; esac
    sec=$(jq -cn --arg sni "$sni" --argjson ail "$ail" --arg fp "$fp" --arg alpn "$alpn" \
      '{security:"tls",
        tlsSettings:({serverName:$sni, allowInsecure:$ail}
                     + (if $fp != "" then {fingerprint:$fp} else {} end)
                     + (if $alpn != "" then {alpn:($alpn | split(",") | map(gsub("^\\s+|\\s+$";"")))} else {} end))}')
  fi

  transport="null"
  case "$net" in
    tcp) transport="null" ;;
    ws)
      transport=$(jq -cn --arg p "$path" --arg h "$host" \
        '{wsSettings:({path:(if $p == "" then "/" else $p end)}
                      + (if $h != "" then {headers:{Host:$h}} else {} end))}') ;;
    grpc)
      transport=$(jq -cn --arg s "$svc" \
        '{grpcSettings:({ } + (if $s != "" then {serviceName:$s} else {} end))}') ;;
    httpupgrade)
      transport=$(jq -cn --arg p "$path" --arg h "$host" \
        '{httpupgradeSettings:({path:(if $p == "" then "/" else $p end)}
                               + (if $h != "" then {host:$h} else {} end))}') ;;
    xhttp|splithttp)
      # xhttp is what xray calls the successor of splithttp; one spelling in the
      # config, both accepted in links.
      transport=$(jq -cn --arg p "$path" --arg h "$host" \
        '{network:"xhttp",
          xhttpSettings:({path:(if $p == "" then "/" else $p end), mode:"auto"}
                         + (if $h != "" then {host:$h} else {} end))}') ;;
    *)
      echo "unsupported-transport: $net (xray path)" >&2
      return 2
      ;;
  esac

  case "$net" in xhttp|splithttp) netj=xhttp ;; *) netj=$net ;; esac
  secj=${sec:-null}; [ -n "$sec" ] || secj=null
  jq -cn --arg net "$netj" --argjson sec "$secj" --argjson tr "$transport" \
    '{network:$net} + (if $sec != null then $sec else {} end) + (if $tr != null then $tr else {} end)'
}

link_vless_xray() {
  split_userinfo "$1"
  split_host_port "$1"
  id=$(urldecode "$USERINFO")
  flow=$(qs "$2" flow)
  enc=$(qs "$2" encryption)
  [ -n "$enc" ] || enc=none

  sec=$(qs "$2" security)
  sni=$(qs "$2" sni)
  [ -n "$sni" ] || sni=$(qs "$2" host)
  fp=$(qs "$2" fp)
  pbk=$(qs "$2" pbk)
  sid=$(qs "$2" sid)
  alpn=$(qs "$2" alpn)

  case "$sec" in
    tls|reality|""|none) ;;
    *) link_fail "unsupported-security: $sec" ;;
  esac
  # A tls/reality node with no pin demands the transport security be there.
  case "$sec" in
    tls|reality) [ -n "$sni" ] || [ -n "$pbk" ] || link_fail "bad-link: $sec without sni" ;;
  esac

  stream=$(xray_stream "$(qs "$2" type)" "$(qs "$2" path)" "$(qs "$2" host)" \
    "$(qs "$2" serviceName)" "$sni" "" "$fp" "$pbk" "$sid" "$alpn") \
    || link_fail "unsupported-transport: $(qs "$2" type)"

  jq -cn --arg addr "$HOST" --argjson port "$PORT" --arg id "$id" --arg flow "$flow" --arg enc "$enc" \
    --argjson stream "$stream" \
    '{protocol:"vless", tag:"proxy",
      settings:{vnext:[{address:$addr, port:$port,
                        users:[({id:$id, encryption:$enc}
                                + (if $flow != "" then {flow:$flow} else {} end))]}]},
      streamSettings:$stream}'
}

link_vmess_xray() {
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
  fp=$(printf '%s' "$decoded" | jq -r '.fp // empty')
  scy=$(printf '%s' "$decoded" | jq -r '.scy // "auto"')

  [ -n "$addr" ] && [ -n "$port" ] && [ -n "$id" ] \
    || link_fail "bad-link: vmess is missing add/port/id"
  case "$port" in *[!0-9]*) link_fail "bad-link: vmess port is not a number" ;; esac

  HOST=$addr
  PORT=$port

  tsni=$sni
  [ -n "$tsni" ] || tsni=$hosthdr
  tinsec=""
  case "$tls" in tls|reality) ;; *) tsni="" ;; esac

  stream=$(xray_stream "$net" "$path" "$hosthdr" "$path" "$tsni" "$tinsec" "$fp" "" "" "") \
    || link_fail "unsupported-transport: $net"

  jq -cn --arg addr "$addr" --argjson port "$port" --arg id "$id" --arg scy "${scy:-auto}" \
    --argjson stream "$stream" \
    '{protocol:"vmess", tag:"proxy",
      settings:{vnext:[{address:$addr, port:$port,
                        users:[{id:$id, alterId:0, security:$scy}]}]},
      streamSettings:$stream}'
}

link_trojan_xray() {
  split_userinfo "$1"
  split_host_port "$1"
  pass=$(urldecode "$USERINFO")
  sec=$(qs "$2" security)
  sni=$(qs "$2" sni)
  [ -n "$sni" ] || sni=$(qs "$2" host)
  fp=$(qs "$2" fp)
  alpn=$(qs "$2" alpn)
  insec=$(qs "$2" allowInsecure)

  case "$sec" in ""|tls|reality) ;; *) link_fail "unsupported-security: $sec" ;; esac
  # Trojan is TLS by definition in practice; keep the link honest.
  [ -n "$sni" ] || link_fail "bad-link: trojan without sni"

  stream=$(xray_stream "$(qs "$2" type)" "$(qs "$2" path)" "$(qs "$2" host)" \
    "$(qs "$2" serviceName)" "$sni" "$insec" "$fp" "" "" "$alpn") \
    || link_fail "unsupported-transport: $(qs "$2" type)"

  jq -cn --arg addr "$HOST" --argjson port "$PORT" --arg pass "$pass" \
    --argjson stream "$stream" \
    '{protocol:"trojan", tag:"proxy",
      settings:{servers:[{address:$addr, port:$port, password:$pass}]},
      streamSettings:$stream}'
}

# link_to_xray_outbound <link> — prints one xray outbound object.
link_to_xray_outbound() {
  link=$1
  scheme=${link%%://*}
  body=${link#*://}
  body=${body%%#*}
  query=""
  case "$body" in
    *\?*) query=${body#*\?}; body=${body%%\?*} ;;
  esac

  case "$scheme" in
    vless) link_vless_xray "$body" "$query" ;;
    vmess) link_vmess_xray "$body" ;;
    trojan) link_trojan_xray "$body" "$query" ;;
    *) link_fail "unsupported-link: $scheme on the xray path (xray covers vless, vmess and trojan)" ;;
  esac
}

# xray_endpoint_of <outbound-json> — prints host:port of an xray outbound.
xray_endpoint_of() {
  src=$1
  printf '%s' "$src" | is_json || link_fail "bad-outbound: not JSON"
  addr=$(printf '%s' "$src" | jq -r '.settings.vnext[0].address // .settings.servers[0].address // empty')
  port=$(printf '%s' "$src" | jq -r '.settings.vnext[0].port // .settings.servers[0].port // empty')
  [ -n "$addr" ] && [ -n "$port" ] || link_fail "unsupported-outbound: the xray outbound has no address/port"
  printf '%s:%s\n' "$addr" "$port"
}

# is_json <string>
is_json() { printf '%s' "$1" | jq -e . >/dev/null 2>&1 || return 1; }

# xray_pin <outbound-json> <ipv4> — prints the outbound with the endpoint
# pinned to the resolved address. Dialing by name would re-resolve inside the
# engine and can dodge the /32 bypass (CDN endpoints).
xray_pin() {
  ob=$1
  ip=$2
  if printf '%s' "$ob" | jq -e '.settings.vnext' >/dev/null 2>&1; then
    printf '%s' "$ob" | jq --arg ip "$ip" '.settings.vnext[0].address = $ip'
  else
    printf '%s' "$ob" | jq --arg ip "$ip" '.settings.servers[0].address = $ip'
  fi
}

# xray_config <outbound-json> <port> — a full xray config with a local SOCKS5
# inbound. Xray is the outlet; sing-box keeps the TUN.
xray_config() {
  printf '%s' "$1" | jq -e . >/dev/null 2>&1 || {
    echo "xray_config: the outbound is not valid JSON" >&2
    return 2
  }
  tmp=$(mktemp)
  printf '%s' "$1" > "$tmp"
  jq -c --argjson port "$2" --slurpfile ob "$tmp" \
    '{log:{loglevel:"warning"},
      inbounds:[{protocol:"socks", listen:"127.0.0.1", port:$port,
                 settings:{auth:"noauth", udp:true, ip:"127.0.0.1"}}],
      outbounds:[$ob[0]]}'
  rc=$?
  rm -f "$tmp"
  return $rc
}
