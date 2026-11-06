# Subscription handling: decode a payload, turn links into list rows.
# Depends on links.sh (link_to_outbound) being sourced first.

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

# subs_entry <link> — "label|protocol|host|port", or non-zero if unparseable.
subs_entry() {
  link=$1
  ob=$(link_to_outbound "$link" 2>/dev/null) || return 1
  [ -n "$ob" ] || return 1
  proto=$(printf '%s' "$ob" | jq -r '.protocol // empty' 2>/dev/null)
  addr=$(printf '%s' "$ob" | jq -r '((.settings.vnext // .settings.servers)[0] // {}) | .address // empty' 2>/dev/null)
  port=$(printf '%s' "$ob" | jq -r '((.settings.vnext // .settings.servers)[0] // {}) | .port // empty' 2>/dev/null)
  [ -n "$proto" ] && [ -n "$addr" ] && [ -n "$port" ] || return 1

  label=""
  case "$link" in
    *"#"*) label=$(urldecode "${link##*#}") ;;
  esac
  [ -n "$label" ] || label="$proto $addr:$port"
  printf '%s|%s|%s|%s' "$label" "$proto" "$addr" "$port"
}

# port_allowed <port> <csv-list>
port_allowed() {
  case ",${2:-}," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# subs_list <raw-file> <allowed-ports> <gen>
# Emits {"count":N,"rejected":M,"entries":[{i,label,proto,host,port,port_ok}]}
subs_list() {
  raw=$1
  allowed=${2:-}
  i=0
  rejected=0
  first=1
  printf '{"entries":['
  subs_decode "$raw" | while IFS= read -r link; do
    if row=$(subs_entry "$link"); then
      label=${row%%|*}; rest=${row#*|}
      proto=${rest%%|*}; rest=${rest#*|}
      host=${rest%%|*}; port=${rest#*|}
      ok=false
      port_allowed "$port" "$allowed" && ok=true
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '{"i":%s,"label":"%s","proto":"%s","host":"%s","port":"%s","port_ok":%s}' \
        "$i" "$(json_escape "$label")" "$(json_escape "$proto")" \
        "$(json_escape "$host")" "$(json_escape "$port")" "$ok"
      i=$((i + 1))
    fi
  done
  printf ']}'
}

# subs_count <raw-file> — how many *usable* links, robust to a missing file.
subs_count() {
  [ -f "$1" ] || { printf '0'; return 0; }
  tmp=$(mktemp)
  subs_decode "$1" > "$tmp"
  n=0
  while IFS= read -r link; do
    subs_entry "$link" >/dev/null 2>&1 && n=$((n + 1))
  done < "$tmp"
  rm -f "$tmp"
  printf '%s' "$n"
}
