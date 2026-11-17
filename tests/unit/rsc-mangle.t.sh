#!/bin/sh
# The RouterOS import file: the connection mark and the fasttrack rule.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }
line_of() { grep -nF -- "$1" "$rsc" | head -1 | cut -d: -f1; }

# A routing mark is set per packet; a connection mark is set once and sticks.
# The connection mark is what stops fasttrack from taking a connection out of
# the tunnel table.
assert_eq "$(has 'action=mark-connection')" "yes" "the connection is marked"
assert_eq "$(has 'new-connection-mark=mik-conn')" "yes" "the mark is named mik-conn"
assert_eq "$(has 'comment="mik: mark tunnel connections"')" "yes" "the rule is named"

# Without passthrough the chain stops at the mark and the routing rule below
# it never runs.
assert_eq "$(has 'passthrough=yes')" "yes" "the rule passes the packet on"

# The rule must sit above the routing rule, or nothing is routed into the
# tunnel table.
mk=$(line_of 'comment="mik: mark tunnel connections"')
wt=$(line_of 'comment="World -> tunnel"')
[ -n "$mk" ] && [ -n "$wt" ] && [ "$mk" -lt "$wt" ] || \
  fail "the mark-connection rule must come before the mark-routing rule"

# Fasttrack must skip the marked connections, or it routes around the tunnel.
assert_eq "$(has 'connection-mark=no-mark')" "yes" "fasttrack only takes unmarked connections"

# The rule belongs to RouterOS, so the values it had are saved and put back
# on uninstall.
assert_eq "$(has ':global MikFasttrackSavedMark')" "yes" "the old fasttrack mark is saved"
assert_eq "$(has ':global MikFasttrackSavedList')" "yes" "the old fasttrack list is saved"

# Uninstall has to take the rule away again.
assert_eq "$(has 'mik: mark tunnel connections')" "yes" "uninstall knows the rule"
