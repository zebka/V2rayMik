# Route planning and container bring-up. Sourced by entrypoint.sh.

# detect_egress — the container's real interface name. RouterOS names the
# container's NIC after the veth (veth-xray), not eth0, so this must never be
# hard-coded.
detect_egress() {
  ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

# detect_gateway — the default gateway inside the container (172.17.0.1).
detect_gateway() {
  ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}'
}

# plan_routes <endpoint-ip> [tun] [eth] [gateway]
# The endpoint bypass MUST go via the default gateway. `dev <eth>` would make the
# endpoint on-link, and the container would ARP for a host that is not on its
# subnet — the route looks right and nothing works.
plan_routes() {
  ip=$1
  tun=${2:-tun0}
  eth=${3:-eth0}
  gw=${4:-}
  if [ -n "$gw" ]; then
    printf 'ip route replace %s/32 via %s dev %s\n' "$ip" "$gw" "$eth"
  else
    printf 'ip route replace %s/32 dev %s\n' "$ip" "$eth"
  fi
  printf 'ip route replace 0.0.0.0/1 dev %s\n' "$tun"
  printf 'ip route replace 128.0.0.0/1 dev %s\n' "$tun"
}

# endpoint_of <link|outbound-json> — prints host:port.
endpoint_of() {
  src=$1
  case "$src" in
    \{*) ob=$src ;;
    *) ob=$(link_to_outbound "$src") ;;
  esac
  addr=$(printf '%s' "$ob" | jq -r '((.settings.vnext // .settings.servers)[0] // {}) | .address // ""')
  port=$(printf '%s' "$ob" | jq -r '((.settings.vnext // .settings.servers)[0] // {}) | .port // ""')
  if [ -z "$addr" ] || [ -z "$port" ]; then
    echo "unsupported-outbound: the outbound has no vnext/servers address (freedom, wireguard and similar have no endpoint)" >&2
    exit 2
  fi
  printf '%s:%s\n' "$addr" "$port"
}

# is_ipv4 <string>
is_ipv4() {
  case "$1" in
    *[!0-9.]*|"") return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

# resolve_endpoint <host> — prints an IPv4 address.
# ENDPOINT_IP overrides resolution (multi-A/CDN endpoints, poisoned resolvers).
# A literal IPv4 is returned as-is; busybox nslookup cannot resolve one.
resolve_endpoint() {
  host=$1
  if [ -n "${ENDPOINT_IP:-}" ]; then
    printf '%s\n' "$ENDPOINT_IP"
    return 0
  fi
  if is_ipv4 "$host"; then
    printf '%s\n' "$host"
    return 0
  fi
  i=0
  while [ "$i" -lt 10 ]; do
    ip=$(nslookup "$host" 2>/dev/null \
         | awk '/^Address[ 0-9]*:/ {print $NF}' \
         | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
         | grep -v '^127\.' | head -n 1)
    if [ -n "$ip" ]; then
      printf '%s\n' "$ip"
      return 0
    fi
    i=$((i + 1))
    [ "$i" -lt 10 ] && sleep 3
  done
  echo "resolve-failed: $host (set ENDPOINT_IP to skip resolution)" >&2
  exit 3
}

# wait_for_tun <name> <pid> — waits up to 10s for the interface xray creates.
wait_for_tun() {
  name=$1
  pid=$2
  i=0
  while [ "$i" -lt 20 ]; do
    ip link show dev "$name" >/dev/null 2>&1 && return 0
    kill -0 "$pid" 2>/dev/null || return 1
    i=$((i + 1))
    sleep 0.5
  done
  return 1
}

# reapply_endpoint_route <host> <tun> <eth> — background loop; keeps the /32 in
# step with DNS. Does nothing when ENDPOINT_IP pins the address: a multi-A or
# CDN endpoint must be pinned, because only one address can hold the bypass.
reapply_endpoint_route() {
  host=$1
  tun=${2:-tun0}
  eth=${3:-eth0}
  gw=${4:-}
  [ -n "${ENDPOINT_IP:-}" ] && return 0
  last=""
  while :; do
    sleep 300
    ip=$(nslookup "$host" 2>/dev/null \
         | awk '/^Address[ 0-9]*:/ {print $NF}' \
         | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
         | grep -v '^127\.' | head -n 1)
    [ -n "$ip" ] || continue
    [ "$ip" = "$last" ] && continue
    if [ -n "$last" ]; then
      ip route del "$last/32" >/dev/null 2>&1 || true
    fi
    if [ -n "$gw" ]; then
      ip route replace "$ip/32" via "$gw" dev "$eth" || continue
    else
      ip route replace "$ip/32" dev "$eth" || continue
    fi
    last=$ip
    echo "xray-gw: endpoint ${host} -> ${ip}" >&2
  done
}

# verify_routes <tun> — the tunnel only works if traffic really enters the TUN.
# A container that says "healthy" while its routes are wrong is the one failure
# mode this project must not ship.
verify_routes() {
  tun=$1
  got=$(ip route get 1.1.1.1 2>/dev/null || true)
  case "$got" in
    *"dev $tun"*) return 0 ;;
    *)
      echo "route-not-installed: 'ip route get 1.1.1.1' says: ${got:-nothing}" >&2
      return 1
      ;;
  esac
}
