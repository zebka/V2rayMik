#!/bin/sh
# Static checks for the project. It cannot replace importing the file on a
# device, but it catches the mistakes that are cheap to catch: unbalanced
# blocks, BOMs, undeclared globals, unguarded `add`, and names that must never
# come back.
set -u

dir=${1:-router}
rc=0
err() { echo "lint: $*" >&2; rc=1; }
have() { [ -f "$dir/$1" ]; }
root=$(cd "$dir/.." 2>/dev/null && pwd) || root="."

# --- no byte-order marks ------------------------------------------------------
# BusyBox only: compare the first three bytes as text.
bom=$(printf '\357\273\277')
for f in "$dir"/*.rsc "$root"/tests/*.sh "$root"/tests/*/*.sh; do
  [ -f "$f" ] || continue
  first3=$(head -c 3 "$f")
  [ "$first3" = "$bom" ] || continue
  err "$f: starts with a UTF-8 BOM; RouterOS /import rejects it"
done

# --- the single RouterOS file -------------------------------------------------
f="$dir/v2raymik.rsc"
if ! have v2raymik.rsc; then
  err "$dir/v2raymik.rsc: the one and only RouterOS file is missing"
  exit 1
fi

open=$(tr -cd '{' < "$f" | wc -c)
close=$(tr -cd '}' < "$f" | wc -c)
[ "$open" -eq "$close" ] || err "$f: unbalanced braces ($open open, $close close)"

# Variables declared once at the top, then used by both modes.
declared=$(sed -n 's/^:global \([A-Za-z0-9_]*\).*/\1/p' "$f" | sort -u)
for g in $(grep -o '\$Mik[A-Za-z0-9_]*' "$f" | tr -d '$' | sort -u); do
  printf '%s\n' "$declared" | grep -qx "$g" || err "$f: reads \$$g without a \":global $g\" line"
done

# The two modes must both be there — an uninstall path that silently does
# nothing is worse than no uninstall path.
grep -q 'MikMode "uninstall"' "$f" || err "$f: no uninstall branch (MikMode \"uninstall\")"
grep -q 'MikMode "install"' "$f" || err "$f: no install default"

# Every `add` needs a guard (someone imports this twice).
line_no=0
while IFS= read -r line; do
  line_no=$((line_no + 1))
  case "$line" in
    *"/add "*) ;;
    *) continue ;;
  esac
  start=$((line_no - 8))
  [ "$start" -lt 1 ] && start=1
  if ! sed -n "${start},${line_no}p" "$f" | grep -qE ':if|find where|:do'; then
    err "$f:$line_no: /add without an :if / find guard"
  fi
done < "$f"

# Invariants the design stands on. If one of these goes, the device misroutes.
need() { grep -qF "$1" "$f" || err "$f: missing invariant: $1"; }
need 'dst-address-type=!local'                # everything, not a list
need 'mik: never mark the container'         # the transport must not carry itself
need 'mik: masquerade to container'          # the container sees only the veth peer
need 'mik: container default deny'           # the container is default-deny
need 'mik: MSS clamp (router output)'        # router-originated traffic needs it
need 'src-address-list=mik-private'          # the panel stays on private sources
need 'dst-address-list=!mik-private'         # the container stays out of private space

# Names that left the project and must not come back. Read with `$`: the
# migration sections still name what they migrate away from, in comments and
# in the ALLOWED_PORTS env removal, and that is deliberate.
for pat in '$MikWan' '$MikLanSubnet' '$MikContainerToWanPorts' '$MikExtraWanPorts' \
           iran-ips MikFailOpen MikFallbackGw MikRefreshRouterDirect MikTable \
           'mikrotik-xray-gateway' 'xray-gw' 'veth-xray' '/xray-data' \
           'xray-auto-route' 'royal-xray-gateway' ; do
  if grep -qF "$pat" "$f"; then err "$f: stale reference to $pat"; fi
done

# The interface list and the port allowlist are gone; a live rule using them
# would be a regression (a comment naming them is how migrations read).
if grep -vE '^[[:space:]]*#' "$f" | grep -qE 'in-interface-list=[A-Za-z]'; then
  err "$f: a rule still matches on an interface list"
fi
if grep -vE '^[[:space:]]*#' "$f" | grep -qE 'dst-port=\$Mik(ExtraWanPorts|ContainerToWanPorts)'; then
  err "$f: a rule still filters on a port knob"
fi

# --- the engine split must be everywhere it is used ---------------------------
# xray.sh defines the engine branch; entrypoint and xtest must call it.
grep -q 'engine_of_link' "$root/docker/entrypoint.sh" || err "entrypoint.sh: does not pick an engine"
grep -q 'link_to_xray_outbound' "$root/docker/lib/xray.sh" || err "lib/xray.sh: missing link_to_xray_outbound"
grep -q 'engine_of_link' "$root/docker/lib/xtest.sh" || err "lib/xtest.sh: tests only the sing-box path"
grep -q 'ENGINE' "$root/docker/entrypoint.sh" || err "entrypoint.sh: does not supervise per engine"

# --- naming: one name for the project, everywhere it is live -------------------
# Split so this file does not match its own patterns. Only the old-name markers
# may carry a legacy name: the migration sections must name what they migrate
# away from.
xr='x''ray'
ident="(mikrotik-${xr}-gateway|royal-${xr}-gateway|veth-${xr}|/${xr}-data|MOUNT_XRAY_DATA)"
for f in "$root/README.md" "$root/README.fa.md" "$root/SECURITY.md" \
         "$root"/docs/*.md "$root/docs/design"/*.md ; do
  [ -f "$f" ] || continue
  hit=$(awk -v pat="$ident" '
    FNR == 1 { skip = 0 }
    /<!-- old-name-start -->/ { skip = 1; next }
    /<!-- old-name-end -->/ { skip = 0; next }
    !skip && $0 ~ pat { print FILENAME ":" FNR ": " $0 }
  ' "$f")
  [ -z "$hit" ] || { printf '%s\n' "$hit" >&2; err "old project name in a live doc: $f"; }
done

exit $rc
