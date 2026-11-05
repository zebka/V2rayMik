#!/bin/sh
# xray-mikrotik-gateway entrypoint.
#
#   entrypoint.sh render [-]   print the rendered config (or write it)
#   entrypoint.sh routes       print the ip route commands for the endpoint
#   entrypoint.sh run          configure the container and exec xray (default)
#
# The TUN inbound always comes from this file. Only `outbounds` comes from the
# operator: either a JSON file (XRAY_OUTBOUND_FILE) or a share link (XRAY_LINK).
set -eu

XRAY_CONFIG=${XRAY_CONFIG:-/etc/xray/config.json}
XRAY_OUTBOUND_FILE=${XRAY_OUTBOUND_FILE:-/etc/xray/outbound.json}
XRAY_LOG_LEVEL=${XRAY_LOG_LEVEL:-warning}
TUN_NAME=${TUN_NAME:-tun0}
TUN_MTU=${TUN_MTU:-1500}
TUN_GATEWAY=${TUN_GATEWAY:-198.18.0.1/15}
ENDPOINT_IP=${ENDPOINT_IP:-}

# Link parsing and route planning live in lib/ so the tests can source them.
for f in /app/lib/*.sh; do
  [ -e "$f" ] || continue
  # shellcheck source=/dev/null
  . "$f"
done

log() { echo "xray-gw: $*" >&2; }
die() { echo "$1" >&2; exit 2; }

# Prints one outbound object (JSON) on stdout.
load_outbound() {
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

# Prints the full config on stdout.
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

validate_config() {  # $1 = path to a config file
  if ! out=$(xray run -test -c "$1" 2>&1); then
    printf '%s\n' "$out" >&2
    die "invalid-config: xray rejected the rendered configuration"
  fi
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
    plan_routes "$(resolve_endpoint "${ep%:*}")" "$TUN_NAME" "${EGRESS_IF:-eth0}"
    ;;
  run)
    mkdir -p "$(dirname "$XRAY_CONFIG")"
    render_config > "$XRAY_CONFIG"
    validate_config "$XRAY_CONFIG"

    ob=$(load_outbound) || exit 2
    ep=$(endpoint_of "$ob") || exit 2
    host=${ep%:*}
    eth=${EGRESS_IF:-eth0}

    enable_forwarding
    ipv4=$(resolve_endpoint "$host")
    log "endpoint ${host} -> ${ipv4}, tun ${TUN_NAME}, egress ${eth}"

    xray run -c "$XRAY_CONFIG" &
    pid=$!
    trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; exit 0' TERM INT

    if wait_for_tun "$TUN_NAME" "$pid"; then
      plan_routes "$ipv4" "$TUN_NAME" "$eth" | while IFS= read -r cmdline; do
        sh -c "$cmdline" || log "route failed: $cmdline"
      done
      ip link set dev "$TUN_NAME" up 2>/dev/null || true
      if ! verify_routes "$TUN_NAME"; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        exit 1
      fi
      reapply_endpoint_route "$host" "$TUN_NAME" "$eth" &
    else
      log "tun-not-ready: $TUN_NAME did not appear; exiting"
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      exit 1
    fi

    wait "$pid"
    ;;
  *)
    die "usage: entrypoint.sh [render|routes|run]"
    ;;
esac
