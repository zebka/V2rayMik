#!/bin/sh
# The RouterOS import file: the tun MTU and the container healthcheck.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }

# The MTU the tunnel uses. 1400, not 1500: a Hysteria2 packet carries its own
# header, so a 1500-byte inner packet does not fit a 1500-byte WAN MTU and is
# dropped or fragmented. The router's MSS clamp covers TCP that enters from
# the LAN; it does not cover UDP inside the tunnel.
assert_eq "$(has ':global MikTunMtu "1400"')" "yes" "default tun MTU is 1400"
assert_eq "$(has 'key=TUN_MTU')" "yes" "TUN_MTU is set on the container"
assert_eq "$(has 'value=$MikTunMtu')" "yes" "TUN_MTU takes the knob's value"

# The healthcheck must make a real request. Checking only that tun0 exists
# says the process is alive, not that the tunnel carries anything.
assert_eq "$(has 'generate_204')" "yes" "healthcheck makes a real request"
assert_eq "$(has 'healthcheck-cmd=')" "yes" "healthcheck is set"
