#!/bin/sh
# The version appears in three places that have to agree: VERSION, the image
# the import pulls, and the page that generates the import line.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
site="$root/site/index.html"
workflow="$root/.github/workflows/build.yml"
rsc="$root/router/v2raymik.rsc"

# The generator names the release its import URL points at. That release has to
# exist, or the page hands out a 404, and the image it writes has to carry that
# same version or the two would not match.
sitever=$(sed -n "s/.*const VERSION = '\([0-9][0-9.]*\)'.*/\1/p" "$site")
[ -n "$sitever" ] || fail "site/index.html has no VERSION constant"
grep -q "^## $sitever " "$root/CHANGELOG.md" \
  || fail "site/index.html names $sitever, which is not a released version"
grep -qF 'v${VERSION}/router/v2raymik.rsc' "$site" \
  || fail "the import URL must be built from the VERSION constant"
if grep -q 'v[0-9][0-9.]*/router/v2raymik' "$site"; then
  fail "site/index.html hardcodes an import tag instead of using VERSION"
fi

# The workflow publishes one repository; the import pulls from it. A fork edits
# IMAGE, so a mismatch means the router asks a registry nothing publishes to.
image=$(sed -n 's/^  IMAGE: \(.*\)$/\1/p' "$workflow")
pin=$(sed -n 's/.*:global MikImage "\([^"]*\):[0-9][0-9.]*".*/\1/p' "$rsc")
[ -n "$image" ] || fail "the workflow has no IMAGE"
[ -n "$pin" ] || fail "the import has no pinned image"
assert_eq "$image" "$pin" "the workflow publishes the image the import pulls"
