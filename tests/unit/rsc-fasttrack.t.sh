#!/bin/sh
# The RouterOS import file: FastTrack safety and the strict-forward fix.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }
block() { awk -v start="$1" -v stop="$2" '$0 ~ start {f=1} $0 ~ stop {f=0} f' "$rsc"; }

# Marked connections must skip fasttrack, or they leave through the WAN.
assert_eq "$(has '/ip firewall filter set $fasttrack connection-mark=no-mark')" "yes" \
  "fasttrack skips marked connections"
assert_eq "$(has ':global MikFasttrackSavedMark')" "yes" "the old mark is saved"
assert_eq "$(has ':global MikFasttrackSavedList')" "yes" "the old list is saved"

# A saved empty value has to be unset, not set to an empty string.
assert_eq "$(has '/ip firewall filter set $fasttrack !connection-mark')" "yes" \
  "an empty saved mark is unset with the documented !property syntax"
assert_eq "$(has '/ip firewall filter set $fasttrack !src-address-list')" "yes" \
  "an empty saved list is unset with the documented !property syntax"

# Each restore applies the two properties in its own guarded block.
assert_eq "$(has ':do { /ip firewall filter set $fasttrack connection-mark=$MikFasttrackSavedMark } on-error={}')" "yes" \
  "the mark is restored in its own :do block"
assert_eq "$(has ':do { /ip firewall filter set $fasttrack src-address-list=$MikFasttrackSavedList } on-error={}')" "yes" \
  "the list is restored in its own :do block"
assert_eq "$(has ':if ($MikScope = "manual") do={')" "yes" "manual restores before clearing saved values"
assert_eq "$(has '/system script environment remove [find where name="MikFasttrackSaved"]')" "yes" \
  "saved values are cleared after a restore"

# Strict forward chains that only allow WAN egress would drop LAN -> veth.
assert_eq "$(has 'out-interface=$MikVeth')" "yes" "the accept matches the veth"
assert_eq "$(has 'connection-state=new,established,related')" "yes" "the accept covers new and established flows"
assert_eq "$(has 'comment="mik: forward to container"')" "yes" "the accept is named"
assert_eq "$(has 'place-before=$firstFwdDrop')" "yes" "the accept sits above the first drop"

# The accept exists in all/lan/list and is removed for manual and uninstall.
manual_block=$(block '^# --- scope: manual ---' '^# --- FastTrack ---')
assert_no_match "$manual_block" 'mik: forward to container' "manual adds no forward accept"
count=$(grep -c 'mik: forward to container' "$rsc")
[ "$count" -ge 3 ] || fail "the forward accept needs an add, a normalize removal and an uninstall removal (got $count mentions)"
