#!/bin/sh
# Every CGI sources _common; this pins the functions they rely on, because a
# missing source is invisible (the command simply does not exist at runtime).
set -eu
. "$(dirname "$0")/../lib/assert.sh"

DATA_DIR=/tmp/common
mkdir -p "$DATA_DIR"
HTTP_COOKIE=""
CONTENT_LENGTH=0
. /app/web/cgi-bin/_common

for fn in json_escape gen_of session_new session_valid read_body form_get \
          lock_try lock_release link_to_outbound endpoint_of resolve_endpoint \
          is_ipv4 detect_egress detect_gateway subs_decode subs_entry port_allowed; do
  command -v "$fn" >/dev/null 2>&1 || fail "missing function: $fn"
done

assert_eq "$(endpoint_of '{"protocol":"vless","settings":{"vnext":[{"address":"1.2.3.4","port":443}]}}')" \
  "1.2.3.4:443" "endpoint_of available through _common"
