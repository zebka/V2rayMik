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
