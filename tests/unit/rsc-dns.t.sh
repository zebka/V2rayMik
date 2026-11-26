#!/bin/sh
# The RouterOS import file: DNS redirect in lan/list, DNS untouched elsewhere.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }
block() { awk -v start="$1" -v stop="$2" '$0 ~ start {f=1} $0 ~ stop {f=0} f' "$rsc"; }

# The four mangle rules make the redirected packets enter mik-tunnel: mangle
# prerouting runs before dstnat, so a local-bound DNS query needs its own
# routing mark before the destination is rewritten.
for tag in 'mik: dns to tunnel (mark udp)' 'mik: dns to tunnel (mark tcp)' \
           'mik: dns to tunnel (route udp)' 'mik: dns to tunnel (route tcp)' \
           'mik: dns to tunnel (udp)' 'mik: dns to tunnel (tcp)'; do
  assert_eq "$(has "$tag")" "yes" "the rule $tag exists"
done

# A query to the router is local at mangle time and must be redirected only
# for the selected clients, never for the container itself.
assert_eq "$(has 'dst-address-type=local')" "yes" "the redirect matches the router's own address"
assert_eq "$(has 'in-interface=("!" . $MikVeth)')" "yes" "the container is excluded from the redirect"
assert_eq "$(has 'to-addresses=1.1.1.1')" "yes" "DNS is redirected to a public resolver"

lan=$(block '^# --- scope: lan ---' '^# --- scope: list ---')
list=$(block '^# --- scope: list ---' '^# --- scope: manual ---')
all=$(block '^# --- scope: all ---' '^# --- scope: lan ---')
for scope in lan list; do
  eval "body=\$$scope"
  assert_match "$body" 'mik: dns to tunnel' "$scope redirects DNS"
  assert_match "$body" 'src-address-list=' "$scope restricts the redirect by source"
  assert_no_match "$body" '/ip dns set' "$scope leaves /ip dns alone"
done
assert_no_match "$all" 'dns to tunnel' "all does not need the redirect (its router output is marked)"

# Both original DNS values are saved and put back on a mode switch/uninstall.
assert_eq "$(has ':global MikDnsSavedAllowRemote')" "yes" "allow-remote-requests is saved"
assert_eq "$(has '/ip dns set allow-remote-requests=$MikDnsSavedAllowRemote')" "yes" \
  "allow-remote-requests is restored"
