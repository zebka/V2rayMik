#!/bin/sh
# A CGI script with a BOM or CRLF fails silently: busybox httpd cannot exec it
# (the shebang is no longer the first two bytes) and answers 404. That happened
# once to `health`, so every script in the directory is now checked byte by byte.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

bin=${CGI_DIR:-/app/web/cgi-bin}
[ -d "$bin" ] || fail "missing $bin"

# The subscription fetch must not advertise v2ray in its User-Agent. Some
# provider edges (and DPI between us and them) drop such a request without
# answering at all: curl waits until --max-time, gets zero bytes, and the
# operator reads that as a dead subscription. Measured on a real panel:
# curl/x and clash/x answer 200 in ~0.4 s, v2raymik-admin and v2rayNG/1.8.5 hang.
ua=$(sed -n '/-A "/p' "$bin/sub")
[ -n "$ua" ] || fail "sub: the subscription fetch has no User-Agent"
case "$ua" in
  *v2ray*) fail "sub: the fetch User-Agent contains v2ray, which DPI drops silently" ;;
esac
assert_match "$ua" "Mozilla/5.0" "sub: the fetch sends a browser User-Agent"

for f in "$bin"/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")

  # First two bytes must be '#!' — no UTF-8 BOM (EF BB BF) before them.
  head2=$(dd if="$f" bs=1 count=2 2>/dev/null || true)
  assert_eq "$head2" "#!" "$name: shebang must be the first two bytes"

  # No CR anywhere: POSIX sh sees '\r' as part of the last word on every line.
  if LC_ALL=C grep -q "$(printf '\r')" "$f" 2>/dev/null; then
    fail "$name: contains CR (CRLF line endings)"
  fi
done
