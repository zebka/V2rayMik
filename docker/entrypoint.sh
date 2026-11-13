#!/bin/sh
# v2raymik entrypoint. The engine is sing-box and it owns the TUN.
#
# When a node needs Xray (xhttp/splithttp transport, or a vless encryption=…
# link), Xray runs as a local SOCKS5 outlet and sing-box chains to it. One
# TUN, two engines; the node decides which one.
# sing-box: hysteria2, tuic, vless/vmess/trojan/ss, REALITY, ws/grpc/httpupgrade
# xray:     the same links that sing-box speaks, plus xhttp/splithttp and vless
#           encryption=…
#
#   entrypoint.sh render [-]   print the rendered config (or write it)
#   entrypoint.sh routes       print the ip route commands for the endpoint
#   entrypoint.sh run          supervise the engine and the admin UI (default)
set -eu

SINGBOX_CONFIG=${SINGBOX_CONFIG:-/etc/sing-box/config.json}
XRAY_CONFIG=${XRAY_CONFIG:-/etc/xray/config.json}
NODE_OUTBOUND_FILE=${NODE_OUTBOUND_FILE:-/etc/sing-box/outbound.json}
NODE_OUTBOUND_JSON=${NODE_OUTBOUND_JSON:-}
NODE_LINK=${NODE_LINK:-}
LOG_LEVEL=${SINGBOX_LOG_LEVEL:-warn}
TUN_NAME=${TUN_NAME:-tun0}
TUN_MTU=${TUN_MTU:-1500}
TUN_GATEWAY=${TUN_GATEWAY:-198.18.0.1/15}
XRAY_SOCKS_PORT=${XRAY_SOCKS_PORT:-10810}
ENDPOINT_IP=${ENDPOINT_IP:-}

case "$TUN_MTU" in
  ''|*[!0-9]*) TUN_MTU=1500 ;;
esac

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

log() { echo "v2raymik: $*" >&2; }
die() { echo "$1" >&2; exit 2; }

# load_outbound — prints one sing-box outbound object (environment path only).
load_outbound() {
  if [ -n "${NODE_OUTBOUND_JSON:-}" ]; then
    printf '%s' "$NODE_OUTBOUND_JSON"
    return 0
  fi
  if [ -n "${NODE_LINK:-}" ]; then
    if [ -e "$NODE_OUTBOUND_FILE" ]; then
      die "conflicting-config: set either NODE_LINK or $NODE_OUTBOUND_FILE, not both"
    fi
    if ! command -v link_to_outbound >/dev/null 2>&1; then
      die "unsupported-link: link support is not available in this image"
    fi
    link_to_outbound "$NODE_LINK"
    return
  fi
  if [ ! -e "$NODE_OUTBOUND_FILE" ]; then
    die "missing-config: neither NODE_LINK nor $NODE_OUTBOUND_FILE is set"
  fi
  cat "$NODE_OUTBOUND_FILE"
}

# render_config [outbound-json] [internal]
# Without arguments it renders the environment outbound (used by `render`).
# With an outbound argument it renders that one; internal=1 skips the
# user-outbound shape guards (used for the sing-box → xray chain).
render_config() {
  ob=${1:-}
  internal=${2:-0}
  if [ -z "$ob" ]; then
    ob=$(load_outbound)
    internal=0
  fi
  printf '%s' "$ob" | jq -e . >/dev/null 2>&1 \
    || die "invalid-outbound-json: the outbound is not valid JSON"

  if [ "$internal" != "1" ]; then
    if printf '%s' "$ob" | jq -e 'type=="object" and (has("inbounds") or .type=="tun" or .type=="mixed" or .type=="socks")' >/dev/null 2>&1; then
      die "invalid-outbound: give one outbound object; it must not contain inbounds or be a tun/socks address"
    fi

    if printf '%s' "$ob" | jq -e '(.server // "") | test(":")' >/dev/null 2>&1; then
      die "ipv6-unsupported: this build has no IPv6; use an IPv4 or a domain"
    fi
  fi

  tmp=$(mktemp)
  printf '%s' "$ob" > "$tmp"
  jq -n \
    --arg lvl "$LOG_LEVEL" \
    --arg name "$TUN_NAME" \
    --argjson mtu "$TUN_MTU" \
    --arg gw "$TUN_GATEWAY" \
    --slurpfile ob "$tmp" \
    '{log:{level:$lvl, timestamp:false},
      inbounds:[{type:"tun", tag:"tun-in",
                 interface_name:$name, mtu:$mtu, address:[$gw],
                 auto_route:false, strict_route:false, stack:"system"}],
      outbounds:[($ob[0] + {tag:"proxy"}), {type:"direct", tag:"direct"}],
      route:{final:"proxy"}}'
  rm -f "$tmp"
}

validate_config() {
  # $1 = path to a config file
  if ! out=$(sing-box check -c "$1" 2>&1); then
    printf '%s\n' "$out" >&2
    die "invalid-config: sing-box rejected the rendered configuration"
  fi
}

# chain_outbound — the sing-box side of an xray-backed node: the TUN stays in
# sing-box, everything that is not local goes to xray's localhost SOCKS outlet.
chain_outbound() {
  jq -cn --argjson port "$XRAY_SOCKS_PORT" \
    '{type:"socks", server:"127.0.0.1", server_port:$port, version:"5"}'
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
  # $1 up|false  $2 label  $3 engine
  mkdir -p "$DATA_DIR"
  printf '{"up":%s,"label":"%s","at":%s,"engine":"%s"}\n' \
    "$1" "$(json_escape "${2:-}")" "$(date +%s)" "$(json_escape "${3:-}")" > "$STATUS_FILE.tmp" \
    && mv -f "$STATUS_FILE.tmp" "$STATUS_FILE"
}

# activate_xray <outbound-json> <label> — pins the endpoint, writes the xray
# config and the chained sing-box config, renders and validates the latter.
# Sets OB, IPV4, ACTIVE_LABEL, ENGINE. Returns non-zero on failure.
activate_xray() {
  ob=$1
  label=$2
  ep=$(xray_endpoint_of "$ob" 2>/dev/null) || { log "no endpoint in the outbound"; return 1; }
  host=${ep%:*}
  ipv4=$(resolve_endpoint "$host") || return 1
  if ! is_ipv4 "$host"; then
    ob=$(xray_pin "$ob" "$ipv4") || { log "cannot pin the endpoint"; return 1; }
  fi
  mkdir -p "$(dirname "$XRAY_CONFIG")"
  xray_config "$ob" "$XRAY_SOCKS_PORT" > "$XRAY_CONFIG" || { log "cannot render the xray config"; return 1; }
  mkdir -p "$(dirname "$SINGBOX_CONFIG")"
  render_config "$(chain_outbound)" 1 > "$SINGBOX_CONFIG"
  validate_config "$SINGBOX_CONFIG"
  OB=$ob
  IPV4=$ipv4
  ACTIVE_LABEL=$label
  ENGINE=xray
  return 0
}

# activate_singbox <outbound-json> <label>
activate_singbox() {
  ob=$1
  label=$2
  ep=$(endpoint_of "$ob" 2>/dev/null) || { log "no endpoint in the outbound"; return 1; }
  host=${ep%:*}
  ipv4=$(resolve_endpoint "$host") || return 1
  if ! is_ipv4 "$host"; then
    ob=$(printf '%s' "$ob" | jq --arg ip "$ipv4" '.server = $ip')
    export NODE_OUTBOUND_JSON="$ob"
  fi
  mkdir -p "$(dirname "$SINGBOX_CONFIG")"
  render_config "$ob" 0 > "$SINGBOX_CONFIG"
  validate_config "$SINGBOX_CONFIG"
  OB=$ob
  IPV4=$ipv4
  ACTIVE_LABEL=$label
  ENGINE=sing-box
  return 0
}

# build_active_config — sets OB, IPV4, ACTIVE_LABEL, ENGINE, ETH, GW and
# writes $SINGBOX_CONFIG (and $XRAY_CONFIG for xray nodes).
# Returns non-zero when no usable config exists yet.
build_active_config() {
  ETH=${EGRESS_IF:-$(detect_egress)}
  GW=${EGRESS_GW:-$(detect_gateway)}
  [ -n "$ETH" ] || { log "no-egress: no default route inside the container"; return 1; }

  ACTIVE_LABEL="environment"
  ENGINE=sing-box
  ob=""
  if [ -f "$STATE_FILE" ]; then
    ob=$(jq -c '.outbound // empty' "$STATE_FILE" 2>/dev/null || true)
    ACTIVE_LABEL=$(jq -r '.label // "state"' "$STATE_FILE" 2>/dev/null || echo "state")
    ENGINE=$(jq -r '.engine // "sing-box"' "$STATE_FILE" 2>/dev/null || echo sing-box)
  fi

  if [ -n "$ob" ] && [ "$ob" != "null" ]; then
    if [ "$ENGINE" = "xray" ]; then
      activate_xray "$ob" "$ACTIVE_LABEL"
    else
      activate_singbox "$ob" "$ACTIVE_LABEL"
    fi
    return $?
  fi

  # environment path
  if [ -n "${NODE_LINK:-}" ]; then
    if [ -e "$NODE_OUTBOUND_FILE" ]; then
      log "conflicting-config: set either NODE_LINK or $NODE_OUTBOUND_FILE, not both"
      return 1
    fi
    ENGINE=$(engine_of_link "$NODE_LINK")
    if [ "$ENGINE" = "xray" ]; then
      ob=$(link_to_xray_outbound "$NODE_LINK") || return 1
      activate_xray "$ob" "environment"
    else
      ob=$(link_to_outbound "$NODE_LINK") || return 1
      activate_singbox "$ob" "environment"
    fi
    return $?
  fi

  if [ ! -e "$NODE_OUTBOUND_FILE" ]; then
    log "missing-config: neither NODE_LINK nor $NODE_OUTBOUND_FILE is set"
    return 1
  fi
  ob=$(cat "$NODE_OUTBOUND_FILE")
  activate_singbox "$ob" "environment"
  return $?
}

install_routes() {
  plan_routes "$IPV4" "$TUN_NAME" "$ETH" "$GW" | while IFS= read -r cmdline; do
    sh -c "$cmdline" || log "route failed: $cmdline"
  done
  ip link set dev "$TUN_NAME" up 2>/dev/null || true

  # Admin plane: the subscription fetch and the container's own DNS must work
  # even when the active node is dead. That has to be scoped to traffic the
  # container itself originates — a plain `/32` bypass also captures packets
  # forwarded *from the router*, which then bounce back out of the veth and loop
  # (measured: an `ip route get` for the bypass address said `dev veth-mik` on
  # the router, and every fetch to 1.1.1.1 timed out).
  cip=$(ip -4 addr show dev "$ETH" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
  if [ -n "$cip" ] && [ -n "$GW" ]; then
    ip rule del from "$cip" lookup 100 2>/dev/null || true
    ip rule add from "$cip" lookup 100 priority 1000 2>/dev/null || true
    ip route replace default via "$GW" dev "$ETH" table 100 2>/dev/null || true
  fi

  verify_routes "$TUN_NAME"
}

# ---------------------------------------------------------------------------
# supervisor
# ---------------------------------------------------------------------------

kill_children() {
  [ -n "${xpid_x:-}" ] && kill -TERM "$xpid_x" 2>/dev/null
  [ -n "${xpid:-}" ] && kill -TERM "$xpid" 2>/dev/null
  return 0
}

supervise() {
  ADMIN_NAME=${CONTAINER_NAME:-}
  restart=0
  xpid=""
  xpid_x=""
  trap 'restart=1; kill_children' HUP
  trap 'kill_children; exit 0' TERM INT

  while :; do
    status_write false "" ""
    if ! build_active_config; then
      log "no usable config yet; waiting"
      sleep 10
      continue
    fi
    log "starting: ${ACTIVE_LABEL} [${ENGINE}] endpoint ${host:-?} -> ${IPV4}, tun ${TUN_NAME}, egress ${ETH}, gw ${GW:-none}"

    if [ "$ENGINE" = "xray" ]; then
      xray run -c "$XRAY_CONFIG" &
      xpid_x=$!
      if ! xtest_wait_port "$XRAY_SOCKS_PORT" "$xpid_x"; then
        log "xray-not-ready: the xray outlet did not open; restarting"
        kill -TERM "$xpid_x" 2>/dev/null || true
        wait "$xpid_x" 2>/dev/null || true
        xpid_x=""
        sleep 2
        continue
      fi
    fi

    sing-box run -c "$SINGBOX_CONFIG" &
    xpid=$!

    if wait_for_tun "$TUN_NAME" "$xpid"; then
      if install_routes; then
        status_write true "$ACTIVE_LABEL" "$ENGINE"
      else
        log "route-not-installed: traffic is not entering $TUN_NAME"
      fi
    else
      log "tun-not-ready: $TUN_NAME did not appear"
    fi

    wait "$xpid" || true
    xpid=""
    if [ -n "${xpid_x:-}" ]; then
      wait "$xpid_x" 2>/dev/null || true
      xpid_x=""
    fi
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
    dest=${2:-$SINGBOX_CONFIG}
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
    mkdir -p "$DATA_DIR" "$(dirname "$SINGBOX_CONFIG")"
    start_admin
    enable_forwarding
    supervise
    ;;
  *)
    die "usage: entrypoint.sh [render|routes|run]"
    ;;
esac
