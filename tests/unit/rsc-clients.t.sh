#!/bin/sh
# The RouterOS import file: the user-editable mik-clients address-list.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }

assert_eq "$(has 'list="mik-clients"')" "yes" "the list is named mik-clients"
assert_eq "$(has 'comment="mik: client"')" "yes" "imported entries are tagged"
assert_eq "$(has '[:toarray $MikSrcAddress]')" "yes" "a comma string is accepted"
assert_eq "$(has '[:tostr $a]')" "yes" "elements are converted to strings before trimming"

# :foreach over a string does not iterate in RouterOS. The conversion must be
# in the list block and come BEFORE the loop, or mik-clients stays empty for a
# user who set a single IP or a comma-separated string.
conv=$(grep -nF ':set MikSrcAddress [:toarray $MikSrcAddress]' "$rsc" | head -1 | cut -d: -f1)
loop=$(grep -nF ':foreach a in=$MikSrcAddress' "$rsc" | head -1 | cut -d: -f1)
[ -n "$conv" ] && [ -n "$loop" ] && [ "$conv" -lt "$loop" ] || \
  fail "MikSrcAddress must be converted with [:toarray] before the :foreach"
assert_eq "$(has ':if ([:typeof $MikSrcAddress] != "array") do={')" "yes" \
  "a non-array after conversion is rejected"

# "192.168.10.0/24, 10.20.30.5" must not produce an address with a leading
# space. Both ends are trimmed.
assert_eq "$(has '[:pick $addr 0] = " "')" "yes" "leading spaces are trimmed"
assert_eq "$(has '[:pick $addr ([:len $addr] - 1)] = " "')" "yes" "trailing spaces are trimmed"

# A scope switch removes only our tagged entries, never the operator's own.
assert_eq "$(has 'address-list remove [find where comment="mik: client"]')" "yes" \
  "tagged entries are removed on re-import and uninstall"
assert_eq "$(has 'comment!="mik: client"')" "yes" "user entries are counted and kept"

# An empty list would tunnel nobody; fail at import time instead.
assert_eq "$(has 'MikScope=list requires :global MikSrcAddress')" "yes" \
  "list mode requires at least one source"
