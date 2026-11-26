#!/bin/sh
# The "Check for update" command must name the new image before repulling.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
js="$root/docker/web/app.js"
doc="$root/docs/panel.md"

has() { grep -qF -- "$1" "$js" && echo yes || echo no; }

assert_eq "$(has '/container set ')" "yes" "the command sets the container"
assert_eq "$(has ' remote-image=ghcr.io/zebka/v2raymik:')" "yes" "the new image is named"
assert_eq "$(has 'azebka/v2raymik:')" "yes" "the mirror image is documented"

set_line=$(grep -nF '/container set ' "$js" | head -1 | cut -d: -f1)
pull_line=$(grep -nF '/container/repull ' "$js" | head -1 | cut -d: -f1)
[ -n "$set_line" ] && [ -n "$pull_line" ] && [ "$set_line" -lt "$pull_line" ] || \
  fail "remote-image must be set before /container/repull"

grep -qF 'A bare `/container/repull` keeps the old' "$doc" \
  || fail "docs/panel.md must explain why a bare repull is wrong"
