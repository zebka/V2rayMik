#!/bin/sh
# xray-mikrotik-gateway entrypoint.
#
#   entrypoint.sh render [-]   print the rendered config (or write it)
#   entrypoint.sh routes       print the ip route commands for the endpoint
#   entrypoint.sh run          supervise Xray and the admin UI (default)
#
# The TUN inbound always comes from this file. Only `outbounds` comes from the
# operator: a JSON file, a share link, or the active entry in state.json (set by
# the admin page).
set -eu

XRAY_CONFIG=${XRAY_CONFIG:-/etc/xray/config.json}
XRAY_OUTBOUND_FILE=${XRAY_OUTBOUND_FILE:-/etc/xray/outbound.json}
XRAY_LOG_LEVEL=${XRAY_LOG_LEVEL:-warning}
TUN_NAME=${TUN_NAME:-tun0}
TUN_MTU=${TUN_MTU:-1500}
TUN_GATEWAY=${TUN_GATEWAY:-198.18.0.1/15}
ENDPOINT_IP=${ENDPOINT_IP:-}

# Admin UI state lives with the container's persistent root-dir.
DATA_DIR=${DATA_DIR:-/data}
ALLOWED_PORTS=${ALLOWED_PORTS:-443,80,8080,8880,2052,2053,2082,2083,2086,2087,2095,2096,8443,53}
STATE_FILE=${STATE_FILE:-$DATA_DIR/state.json}
STATUS_FILE=${STATUS_FILE:-$DATA_DIR/status.json}
CHECK_URL=${CHECK_URL:-http://connectivitycheck.gstatic.com/generate_204}
export DATA_DIR ALLOWED_PORTS STATE_FILE CHECK_URL

# Link parsing, route planning, admin helpers and the test harness live in lib/
# so the tests can source them.
for f in /app/lib/*.sh; do
  [ -e "$f" ] || continue
  # shellcheck source=/dev/null
  . "$f"
done

log() { echo "xray-gw: $*" >&2; }
die() { echo "$1" >&2; exit 2; }

# load_outbound — prints one outbound object.
load_outbound() {
  if [ -n "${XRAY_OUTBOUND_JSON:-}" ]; then
    printf '%s' "$XRAY_OUTBOUND_JSON"
    return 0
  fi
  if [ -n "${XRAY_LINK:-}" ]; then
    if [ -e "$XRAY_OUTBOUND_FILE" ]; then
      die "conflicting-config: set either XRAY_LINK or $XRAY_OUTBOUND_FILE, not both"
    fi
    if ! command -v link_to_outbound >/dev/null 2>&1; then
      die "unsupported-link: link support is not available in this image"
    fi
    link_to_outbound "$XRAY_LINK"
    return
  fi
  if [ ! -e "$XRAY_OUTBOUND_FILE" ]; then
    die "missing-config: neither XRAY_LINK nor $XRAY_OUTBOUND_FILE is set"
  fi
  cat "$XRAY_OUTBOUND_FILE"
}

# render_config — prints the full config on stdout.
render_config() {
  ob=$(load_outbound)
  printf '%s' "$ob" | jq -e . >/dev/null 2>&1 \
    || die "invalid-outbound-json: the outbound is not valid JSON"

  if printf '%s' "$ob" | jq -e 'type=="object" and (has("inbounds") or .protocol=="tun")' >/dev/null 2>&1; then
    die "invalid-outbound: give one outbound object; it must not contain inbounds or use the tun protocol"
  fi

  if printf '%s' "$ob" | jq -e '[((.settings.vnext // .settings.servers // [])[] | .address // "") | select(test(":"))] | length > 0' >/dev/null 2>&1; then
    die "ipv6-unsupported: this build has no IPv6; use an IPv4 or a domain"
  fi

  tmp=$(mktemp)
  printf '%s' "$ob" > "$tmp"
  jq -n \
    --arg lvl "$XRAY_LOG_LEVEL" \
    --arg name "$TUN_NAME" \
    --argjson mtu "$TUN_MTU" \
    --arg gw "$TUN_GATEWAY" \
    --slurpfile ob "$tmp" \
    '{log:{loglevel:$lvl},
      inbounds:[{tag:"tun-in",protocol:"tun",
                 settings:{name:$name,mtu:$mtu,gateway:[$gw]}}],
      outbounds:$ob}'
  rm -f "$tmp"
}

validate_config() {
  # $1 = path to a config file
  if ! out=$(xray run -test -c "$1" 2>&1); then
    printf '%s\n' "$out" >&2
    die "invalid-config: xray rejected the rendered configuration"
  fi
}

# Turns on IPv4 forwarding in the container's namespace. RouterOS containers
# normally allow this; if not, say so loudly instead of failing silently.
enable_forwarding() {
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]; then
    echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
  fi
  if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]; then
    log "ip-forward-unavailable: cannot enable IPv4 forwarding in this namespace; forwarded LAN traffic will not reach the tunnel"
  fi
}

# ---------------------------------------------------------------------------
# active config: state.json first, environment second
# ---------------------------------------------------------------------------

status_write() {
  # $1 up|false  $2 label
  mkdir -p "$DATA_DIR"
  printf '{"up":%s,"label":"%s","at":%s}\n' \
    "$1" "$(json_escape "${2:-}")" "$(date +%s)" > "$STATUS_FILE.tmp" \
    && mv -f "$STATUS_FILE.tmp" "$STATUS_FILE"
}

# build_active_config — sets OB, ACTIVE_LABEL, IPV4, ETH, GW and writes
# $XRAY_CONFIG. Returns non-zero when no usable config exists yet.
build_active_config() {
  ETH=${EGRESS_IF:-$(detect_egress)}
  GW=${EGRESS_GW:-$(detect_gateway)}
  [ -n "$ETH" ] || { log "no-egress: no default route inside the container"; return 1; }

  ACTIVE_LABEL="environment"
  ob=""
  if [ -f "$STATE_FILE" ]; then
    ob=$(jq -c '.outbound // empty' "$STATE_FILE" 2>/dev/null || true)
    ACTIVE_LABEL=$(jq -r '.label // "state"' "$STATE_FILE" 2>/dev/null || echo "state")
  fi

  if [ -n "$ob" ] && [ "$ob" != "null" ]; then
    XRAY_OUTBOUND_JSON=$ob
  else
    ob=$(load_outbound 2>/dev/null) || { return 1; }
  fi
  export XRAY_OUTBOUND_JSON="$ob"

  ep=$(endpoint_of "$ob" 2>/dev/null) || { log "no endpoint in the outbound"; return 1; }
  host=${ep%:*}

  ipv4=$(resolve_endpoint "$host") || return 1
  IPV4=$ipv4

  if ! is_ipv4 "$host"; then
    ob=$(printf '%s' "$ob" | jq --arg ip "$ipv4" '(.settings.vnext // .settings.servers)[0].address = $ip')
    XRAY_OUTBOUND_JSON=$ob
    export XRAY_OUTBOUND_JSON
  fi

  OB=$ob
  mkdir -p "$(dirname "$XRAY_CONFIG")"
  render_config > "$XRAY_CONFIG"
  validate_config "$XRAY_CONFIG"
  return 0
}

install_routes() {
  plan_routes "$IPV4" "$TUN_NAME" "$ETH" "$GW" | while IFS= read -r cmdline; do
    sh -c "$cmdline" || log "route failed: $cmdline"
  done
  ip link set dev "$TUN_NAME" up 2>/dev/null || true

  # Admin plane: the subscription fetch and the container's own resolver must
  # work even when the active node is dead, so they get their own bypass.
  for r in ${ADMIN_DNS:-1.1.1.1 8.8.8.8}; do
    if [ -n "$GW" ]; then
      ip route replace "$r/32" via "$GW" dev "$ETH" 2>/dev/null || true
    fi
  done

  verify_routes "$TUN_NAME"
}

# ---------------------------------------------------------------------------
# supervisor
# ---------------------------------------------------------------------------

supervise() {
  ADMIN_NAME=${CONTAINER_NAME:-}
  restart=0
  trap 'restart=1; [ -n "${xpid:-}" ] && kill -TERM "$xpid" 2>/dev/null' HUP
  trap 'kill -TERM "${xpid:-}" 2>/dev/null; exit 0' TERM INT

  while :; do
    status_write false ""
    if ! build_active_config; then
      log "no usable config yet; waiting"
      sleep 10
      continue
    fi
    log "starting: ${ACTIVE_LABEL} endpoint ${host} -> ${IPV4}, tun ${TUN_NAME}, egress ${ETH}, gw ${GW:-none}"

    xray run -c "$XRAY_CONFIG" &
    xpid=$!

    if wait_for_tun "$TUN_NAME" "$xpid"; then
      if install_routes; then
        status_write true "$ACTIVE_LABEL"
      else
        log "route-not-installed: traffic is not entering $TUN_NAME"
      fi
    else
      log "tun-not-ready: $TUN_NAME did not appear"
    fi

    wait "$xpid" || true
    xpid=""
    if [ "$restart" = 1 ]; then
      restart=0
      log "reloading on request"
      continue
    fi
    sleep 2
  done
}

cmd=${1:-run}
case "$cmd" in
  render)
    dest=${2:-$XRAY_CONFIG}
    cfg=$(render_config)
    if [ "$dest" = "-" ]; then
      printf '%s\n' "$cfg"
    else
      mkdir -p "$(dirname "$dest")"
      printf '%s\n' "$cfg" > "$dest"
      validate_config "$dest"
    fi
    ;;
  routes)
    ob=$(load_outbound) || exit 2
    ep=$(endpoint_of "$ob") || exit 2
    plan_routes "$(resolve_endpoint "${ep%:*}")" "$TUN_NAME" "${EGRESS_IF:-$(detect_egress)}" "$(detect_gateway)"
    ;;
  run)
    mkdir -p "$DATA_DIR" "$(dirname "$XRAY_CONFIG")"
    start_admin
    enable_forwarding
    supervise
    ;;
  *)
    die "usage: entrypoint.sh [render|routes|run]"
    ;;
esac
