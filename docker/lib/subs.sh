# Subscription handling: decode a payload, turn links into list rows.
# Depends on links.sh and xray.sh (link_to_outbound, link_to_xray_outbound)
# being sourced first.
#
# The row parser knows which engine built the outbound, but the engine string
# is resolved again per link in subs_list via engine_of_link, which is a
# lightweight query scan (no decode except for vmess).

# subs_entry <link> — "label|protocol|host|port", or non-zero if unparseable.
subs_entry() {
  link=$1
  if ob=$(link_to_outbound "$link" 2>/dev/null) && [ -n "$ob" ]; then
    proto=$(printf '%s' "$ob" | jq -r '.type // empty' 2>/dev/null)
    addr=$(printf '%s' "$ob" | jq -r '.server // empty' 2>/dev/null)
    port=$(printf '%s' "$ob" | jq -r '.server_port // empty' 2>/dev/null)
  elif ob=$(link_to_xray_outbound "$link" 2>/dev/null) && [ -n "$ob" ]; then
    proto=$(printf '%s' "$ob" | jq -r '.protocol // empty' 2>/dev/null)
    addr=$(printf '%s' "$ob" | jq -r '.settings.vnext[0].address // .settings.servers[0].address // empty' 2>/dev/null)
    port=$(printf '%s' "$ob" | jq -r '.settings.vnext[0].port // .settings.servers[0].port // empty' 2>/dev/null)
  else
    return 1
  fi
  [ -n "$proto" ] && [ -n "$addr" ] && [ -n "$port" ] || return 1

  label=""
  case "$link" in
    *"#"*) label=$(urldecode "${link##*#}") ;;
  esac
  [ -n "$label" ] || label="$proto $addr:$port"
  printf '%s|%s|%s|%s' "$label" "$proto" "$addr" "$port"
}

# subs_decode <raw-file> — one link per line, whatever the payload shape.
subs_decode() {
  raw=$1
  head=$(head -c 200 "$raw" 2>/dev/null | tr -d '\r\n')
  case "$head" in
    *://*) cat "$raw" ;;
    *) base64 -d "$raw" 2>/dev/null || cat "$raw" ;;
  esac \
    | tr -d '\r' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$'
}

# port_allowed <port> <csv-list>
port_allowed() {
  case ",${2:-}," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# subs_usable <link> — parseable and not a placeholder pointing at this host.
subs_usable() {
  row=$(subs_entry "$1" 2>/dev/null) || return 1
  host=${row#*|}; host=${host#*|}; host=${host%%|*}
  case "$host" in
    ""|127.*|0.0.0.0|localhost) return 1 ;;
  esac
  return 0
}

# subs_list <raw-file> <allowed-ports>
# Emits {"entries":[{i,label,proto,host,port,port_ok,engine}]}. `i` is the raw
# line index in the decoded payload — the same number /cgi-bin/test and
# /connect use with sed. Anything else drifts the moment one line fails to
# parse.
subs_list() {
  raw=$1
  allowed=${2:-}
  printf '{"entries":['
  first=1
  n=0
  tmp=$(mktemp)
  subs_decode "$raw" > "$tmp" 2>/dev/null || true
  while IFS= read -r link; do
    idx=$n
    n=$((n + 1))
    subs_usable "$link" || continue
    row=$(subs_entry "$link")
    label=${row%%|*}; rest=${row#*|}
    proto=${rest%%|*}; rest=${rest#*|}
    host=${rest%%|*}; port=${rest#*|}
    ok=false
    port_allowed "$port" "$allowed" && ok=true
    engine=$(engine_of_link "$link")
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"i":%s,"label":"%s","proto":"%s","host":"%s","port":"%s","port_ok":%s,"engine":"%s"}' \
      "$idx" "$(json_escape "$label")" "$(json_escape "$proto")" \
      "$(json_escape "$host")" "$(json_escape "$port")" "$ok" "$engine"
  done < "$tmp"
  rm -f "$tmp"
  printf ']}'
}

# subs_reject_reason <raw-file> — why a payload produced no usable links.
# The operator has to know which side to fix: the provider, the URL, or the
# panel. A sing-box JSON profile, for instance, is a valid subscription that
# this panel cannot use, and saying so is the difference between "broken" and
# "wrong link".
subs_reject_reason() {
  raw=$1
  [ -f "$raw" ] && [ -s "$raw" ] || { printf 'the subscription was empty'; return 0; }
  size=$(wc -c < "$raw" | tr -d ' ')
  head=$(head -c 400 "$raw" | tr -d '\r\n')
  case "$head" in
    '<'*)
      printf 'the subscription returned a web page, not configs (a block or login page?)'
      ;;
    *'"outbounds"'*|*'"inbounds"'*|*'"route"'*)
      printf 'that link is a sing-box JSON profile, not a list of links; pick the v2ray/links subscription in the provider panel'
      ;;
    *)
      lines=$(subs_decode "$raw" 2>/dev/null | grep -c '' || true)
      printf 'no usable configs in that subscription (%s bytes, %s lines)' \
        "$size" "${lines:-0}"
      ;;
  esac
}

# subs_count <raw-file> — how many usable links, robust to a missing file.
subs_count() {
  [ -f "$1" ] || { printf '0'; return 0; }
  tmp=$(mktemp)
  subs_decode "$1" > "$tmp"
  n=0
  while IFS= read -r link; do
    subs_usable "$link" && n=$((n + 1))
  done < "$tmp"
  rm -f "$tmp"
  printf '%s' "$n"
}
