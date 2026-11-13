#!/bin/sh
# A CGI script with a BOM or CRLF fails silently: busybox httpd cannot exec it
# (the shebang is no longer the first two bytes) and answers 404, so every
# script in the directory is checked byte by byte.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

bin=${CGI_DIR:-${APP_DIR:-/app}/web/cgi-bin}
[ -d "$bin" ] || fail "missing $bin"

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
