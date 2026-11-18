#!/bin/sh
# The RouterOS import file: the checks it prints after the install.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }

# The import ends by telling the operator what to look at. The MTU is the one
# that silently breaks large downloads.
assert_eq "$(has 'grep mtu /etc/sing-box/config.json')" "yes" "the MTU check is printed"
assert_eq "$(has 'connection-mark=mik-conn')" "yes" "the connection-mark check is printed"
assert_eq "$(has 'defconf: fasttrack')" "yes" "the fasttrack check is printed"
