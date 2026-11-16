#!/bin/sh
# The RouterOS import file: which image is pulled, and from where.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"
version=$(cat "$root/VERSION")

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }

# The default image is pinned to the version of this repository, so a router
# never runs a container the repository does not describe.
assert_eq "$(has ":global MikImage \"ghcr.io/zebka/v2raymik:$version\"")" "yes" \
  "the image is pinned to VERSION"
assert_eq "$(has ":global MikImageFallback \"azebka/v2raymik:$version\"")" "yes" \
  "the fallback names the Docker Hub repository"

# GitHub Container Registry first: it is what CI publishes to, and it has no
# rate limit that an Iranian user runs into.
assert_eq "$(has ':global MikRegistryUrl "https://ghcr.io"')" "yes" \
  "the primary registry is ghcr.io"

# The fallback has to name a different repository, not only a different
# registry: a Docker Hub mirror serves the Docker Hub namespace and has never
# heard of ghcr.io/zebka/v2raymik.
assert_match "$(cat "$rsc")" 'remote-image=\$MikImageFallback' \
  "the fallback pull uses the fallback image"

# A pull that dies half-way leaves the container stopped. Ask for it again.
assert_match "$(cat "$rsc")" '/container/repull' "a failed pull is retried"
