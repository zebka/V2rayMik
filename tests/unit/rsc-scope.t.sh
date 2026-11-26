#!/bin/sh
# The RouterOS import file: the four MikScope modes and their isolation.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"
site="$root/site/index.html"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }
block() { awk -v start="$1" -v stop="$2" '$0 ~ start {f=1} $0 ~ stop {f=0} f' "$rsc"; }

# The default must stay "all" so a re-import of an existing install changes
# nothing. The other three modes are opt-in globals.
assert_eq "$(has ':global MikScope "all"')" "yes" "all remains the default scope"
assert_eq "$(has ':global MikSrcAddress')" "yes" "list sources are a global"
assert_eq "$(has ':global MikTouchDns')" "yes" "DNS override is a global"

# An unknown scope has to fail loudly, not silently install nothing.
assert_eq "$(has 'MikScope must be all, lan, list or manual')" "yes" "bad scopes are rejected"

# Each mode has a clearly delimited block, so both readers and tests can see
# exactly which rules belong to which mode.
for s in all lan list manual; do
  assert_eq "$(has "# --- scope: $s ---")" "yes" "the $s block is marked"
done

# Only "all" touches the router's own DNS by default.
assert_eq "$(has ':if ($MikScope != "all") do={ :set touchDns false }')" "yes" \
  "DNS is left alone outside all unless overridden"
assert_eq "$(has 'MikTouchDns=true in scope')" "yes" "an override in a safe scope warns"

# Manual mode is the important negative test: no mangle, no DNS change, no
# FastTrack change inside its block.
manual=$(block '^# --- scope: manual ---' '^# --- FastTrack ---')
assert_no_match "$manual" '/ip firewall mangle add' "manual adds no mangle rules"
assert_no_match "$manual" '/ip dns set' "manual does not change /ip dns"
assert_no_match "$manual" '/ip firewall filter set' "manual does not change fasttrack"
assert_match "$manual" 'new-routing-mark=\$tableName' "manual documents the table operators should use"

# chain=output rules belong to "all" only; lan/list must not lock out Winbox,
# SSH or WireGuard.
all=$(block '^# --- scope: all ---' '^# --- scope: lan ---')
lan=$(block '^# --- scope: lan ---' '^# --- scope: list ---')
list=$(block '^# --- scope: list ---' '^# --- scope: manual ---')
assert_match "$all" '/ip firewall mangle add chain=output' "all marks router output"
assert_no_match "$lan" '/ip firewall mangle add chain=output' "lan has no output rules"
assert_no_match "$list" '/ip firewall mangle add chain=output' "list has no output rules"

# The generator defaults to the safest scope for a remotely managed router but
# does not change the import file's own default.
grep -qF '<option value="lan" selected>' "$site" || fail "the generator offers lan first"
assert_match "$(cat "$site")" 'MikScope' "the generator writes MikScope"
