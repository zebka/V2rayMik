#!/bin/sh
# health: the only input the router's scheduler reads. selected must be 1 only
# when a node is chosen AND the panel's Stop flag is absent - that is the whole
# Stop feature, so it is worth a test of its own.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

bin=${CGI_DIR:-/app/web/cgi-bin}
D=/tmp/healthtest
rm -rf "$D"; mkdir -p "$D"

run_health() {
  DATA_DIR=$D \
  STATE_FILE=$D/state.json \
  STATUS_FILE=$D/status.json \
  CACHE_FILE=$D/live.cache \
  BYPASS_FILE=$D/bypass.flag \
    sh "$bin/health"
}

last_line() { printf '%s\n' "$1" | tail -n 1; }

# --- nothing chosen, nothing stopped -----------------------------------------
out=$(run_health)
assert_eq "$(last_line "$out")" "selected=0 up=0 live=0 bypass=0" "empty data dir"

# The headers must still be a header block: busybox httpd answers 500 otherwise.
printf '%s\n' "$out" | head -n 3 | grep -q '^Content-Type: text/plain' \
  || fail "missing Content-Type header"

# --- a node is chosen ---------------------------------------------------------
printf '{"outbound":{"type":"vless","tag":"proxy"},"label":"n1"}\n' > "$D/state.json"
out=$(run_health)
assert_eq "$(last_line "$out")" "selected=1 up=0 live=0 bypass=0" "node chosen, tunnel down"

# up stays 0 in a container without tun0, so no probe runs and the test needs no
# network: live must not claim a tunnel that does not exist.
assert_no_match "$(last_line "$out")" "live=1" "live without a tunnel"

# --- Stop pressed -------------------------------------------------------------
: > "$D/bypass.flag"
out=$(run_health)
assert_eq "$(last_line "$out")" "selected=0 up=0 live=0 bypass=1" "Stop pressed"

# The node is still recorded: Start must not lose it.
assert_eq "$(jq -r '.label' "$D/state.json")" "n1" "state.json survives Stop"

# --- Start pressed ------------------------------------------------------------
rm -f "$D/bypass.flag"
out=$(run_health)
assert_eq "$(last_line "$out")" "selected=1 up=0 live=0 bypass=0" "Start pressed"

# --- a state file without an outbound is not a selection ----------------------
printf '{"label":"half written"}\n' > "$D/state.json"
out=$(run_health)
assert_eq "$(last_line "$out")" "selected=0 up=0 live=0 bypass=0" "state.json without an outbound"
