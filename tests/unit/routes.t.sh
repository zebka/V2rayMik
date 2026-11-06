#!/bin/sh
# Task 5: split routes and endpoint handling.
set -eu
. "$(dirname "$0")/../lib/assert.sh"
. /app/lib/links.sh
. /app/lib/routes.sh

out=$(plan_routes 203.0.113.9 tun0 eth0)
assert_eq "$(printf '%s\n' "$out" | sed -n 1p)" "ip route replace 203.0.113.9/32 dev eth0" "first route"
assert_eq "$(printf '%s\n' "$out" | sed -n 2p)" "ip route replace 0.0.0.0/1 dev tun0" "second route"
assert_eq "$(printf '%s\n' "$out" | sed -n 3p)" "ip route replace 128.0.0.0/1 dev tun0" "third route"
assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "3" "exactly three routes"

# the endpoint bypass must go via the gateway: `dev eth0` alone makes an
# off-subnet host on-link and the container ARPs for nothing
out=$(plan_routes 203.0.113.9 tun0 veth-xray 172.17.0.1)
assert_eq "$(printf '%s\n' "$out" | sed -n 1p)" \
  "ip route replace 203.0.113.9/32 via 172.17.0.1 dev veth-xray" "route via gateway"

# the container's NIC is named after the veth, not eth0
mkdir -p /tmp/fakeip
cat > /tmp/fakeip/ip <<'EOF'
#!/bin/sh
# the real table, with a default dev tun0 listed first — the shape that broke
# detect_egress on the router
echo "0.0.0.0/1 dev tun0 scope link"
echo "default via 172.17.0.1 dev tun0"
echo "default via 172.17.0.1 dev veth-xray"
echo "198.18.0.0/15 dev tun0 scope link"
EOF
chmod +x /tmp/fakeip/ip
out=$(PATH=/tmp/fakeip:$PATH sh -c '. /app/lib/links.sh; . /app/lib/routes.sh; detect_egress')
assert_eq "$out" "veth-xray" "egress skips tun0"
out=$(PATH=/tmp/fakeip:$PATH sh -c '. /app/lib/links.sh; . /app/lib/routes.sh; detect_gateway')
assert_eq "$out" "172.17.0.1" "gateway detected from the default route"

# defaults
out=$(plan_routes 198.51.100.7)
assert_eq "$(printf '%s\n' "$out" | sed -n 2p)" "ip route replace 0.0.0.0/1 dev tun0" "default tun name"

# endpoint_of from outbound JSON
json='{"protocol":"vless","settings":{"vnext":[{"address":"a.test","port":443}]}}'
assert_eq "$(endpoint_of "$json")" "a.test:443" "endpoint from json"

# endpoint_of from a share link
assert_eq "$(endpoint_of 'vless://u@203.0.113.9:8443?security=tls&type=tcp')" \
  "203.0.113.9:8443" "endpoint from link"

# ENDPOINT_IP wins over resolution
out=$(ENDPOINT_IP=198.51.100.7 resolve_endpoint a.test)
assert_eq "$out" "198.51.100.7" "endpoint override"

# a literal IPv4 endpoint must not go through nslookup at all
mkdir -p /tmp/nodns
cat > /tmp/nodns/nslookup <<'EOF'
#!/bin/sh
echo "nslookup was called for $*" >&2
exit 1
EOF
chmod +x /tmp/nodns/nslookup
out=$(PATH=/tmp/nodns:$PATH sh -c '. /app/lib/links.sh; . /app/lib/routes.sh; resolve_endpoint 203.0.113.9' 2>/dev/null)
assert_eq "$out" "203.0.113.9" "literal ipv4 endpoint"

# an outbound with no endpoint (freedom, wireguard) is rejected, not rendered as ":"
set +e
msg=$(endpoint_of '{"protocol":"freedom"}' 2>&1); code=$?
set -e
assert_eq "$code" "2" "endpointless outbound exit"
assert_match "$msg" "unsupported-outbound"

# verify_routes fails loudly when traffic does not enter the tun
mkdir -p /tmp/fakebin
cat > /tmp/fakebin/ip <<'EOF'
#!/bin/sh
echo "1.1.1.1 via 172.17.0.1 dev eth0 src 172.17.0.2"
EOF
chmod +x /tmp/fakebin/ip
set +e
msg=$(PATH=/tmp/fakebin:$PATH verify_routes tun0 2>&1); code=$?
set -e
assert_eq "$code" "1" "verify_routes detects a bypassed tun"
assert_match "$msg" "route-not-installed"
