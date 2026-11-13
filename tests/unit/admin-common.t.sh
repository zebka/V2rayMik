#!/bin/sh
# Every CGI sources _common; this pins the functions they rely on, because a
# missing source is invisible (the command simply does not exist at runtime).
set -eu
. "$(dirname "$0")/../lib/assert.sh"

DATA_DIR=/tmp/common
mkdir -p "$DATA_DIR"
CONTENT_LENGTH=0
. ${APP_DIR:-/app}/web/cgi-bin/_common

# connect's wait loop reads $STATUS_FILE; a missing definition silently made the
# loop test an empty path and roll back every successful connect after 12 s.
assert_eq "${STATUS_FILE:-}" "$DATA_DIR/status.json" "STATUS_FILE defaults next to state.json"
assert_eq "${STATE_FILE:-}" "$DATA_DIR/state.json" "STATE_FILE defaults into DATA_DIR"

for fn in json_escape gen_of read_body form_get url_decode \
          lock_try lock_release link_to_outbound endpoint_of resolve_endpoint \
          is_ipv4 detect_egress detect_gateway subs_decode subs_entry port_allowed \
          engine_of_link link_to_xray_outbound xray_endpoint_of xray_pin xray_config; do
  command -v "$fn" >/dev/null 2>&1 || fail "missing function: $fn"
done

assert_eq "$(endpoint_of '{"type":"vless","server":"1.2.3.4","server_port":443,"uuid":"u"}')" \
  "1.2.3.4:443" "endpoint_of available through _common"
