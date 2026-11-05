# Route planning and container bring-up. Sourced by entrypoint.sh.

# plan_routes <endpoint-ip> [tun] [eth] — prints the route commands to run.
# /32 keeps the transport out of the tunnel; the two /1 routes are the default
# without touching (and without depending on) the kernel's ip-rule order.
plan_routes() {
  ip=$1
  tun=${2:-tun0}
  eth=${3:-eth0}
  printf 'ip route replace %s/32 dev %s\n' "$ip" "$eth"
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
  printf '%s' "$ob" | jq -r '((.settings.vnext // .settings.servers)[0] // {})
                            | "\(.address // ""):\(.port // "")"'
}

# resolve_endpoint <host> — prints an IPv4 address.
# ENDPOINT_IP overrides resolution (CDN endpoints, poisoned resolvers).
resolve_endpoint() {
  host=$1
  if [ -n "${ENDPOINT_IP:-}" ]; then
    printf '%s\n' "$ENDPOINT_IP"
    return 0
  fi
  i=0
  while [ "$i" -lt 10 ]; do
    ip=$(nslookup "$host" 2>/dev/null \
         | awk '/^Address[ 0-9]*:/ {print $NF}' \
         | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
         | grep -v '^127\.' | tail -n 1)
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

# reapply_endpoint_route <host> <tun> <eth> — background loop; replaces only
# the /32 when the endpoint address moves.
reapply_endpoint_route() {
  host=$1
  tun=${2:-tun0}
  eth=${3:-eth0}
  last=""
  while :; do
    sleep 300
    ip=$(nslookup "$host" 2>/dev/null \
         | awk '/^Address[ 0-9]*:/ {print $NF}' \
         | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
         | grep -v '^127\.' | tail -n 1)
    [ -n "$ip" ] || continue
    [ "$ip" = "$last" ] && continue
    ip route replace "$ip/32" dev "$eth" || continue
    last=$ip
    echo "xray-gw: endpoint ${host} -> ${ip}" >&2
  done
}
