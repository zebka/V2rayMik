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

# RouterOS only accepts `!=` inside :if / find-where expressions, never as an
# argument value on add/set. An interface negation has to be built as a value:
# in-interface=("!" . $MikVeth), not in-interface!=$MikVeth.
line_no=0
while IFS= read -r line; do
  line_no=$((line_no + 1))
  case "$line" in
    *"/add "*|*"/set "*) ;;
    *) continue ;;
  esac
  case "$line" in
    *"!="*) err "$f:$line_no: '!=' used on an /add or /set line: $line" ;;
  esac
done < "$f"

# RouterOS rewrites \" and \$ inside healthcheck-cmd="..." (measured on 7.25.1:
# quotes turned into commas and the shell died with an unterminated string).
# Keep the probe free of escaped quotes and of $ expansions; use env|grep for
# environment checks instead.
line_no=0
while IFS= read -r line; do
  line_no=$((line_no + 1))
  case "$line" in
    *"healthcheck-cmd="*) ;;
    *) continue ;;
  esac
  case "$line" in
    *'\"'*|*'\$'*) err "$f:$line_no: escaped quote or dollar in healthcheck-cmd: $line" ;;
  esac
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

# The four scopes and the objects that make them safe.
need ':global MikScope "all"'                # backward-compatible default
need ':global MikSrcAddress'                 # the list-mode client sources
need ':global MikTouchDns'                   # DNS override
need ':global MikDnsSavedAllowRemote'        # a clean DNS restore needs both values
need '# --- scope: all ---'
need '# --- scope: lan ---'
need '# --- scope: list ---'
need '# --- scope: manual ---'
need 'src-address-list=mik-clients'          # list mode has its own source set
need 'dst-address-type=local'                # DNS to the router is local at mangle time
need 'in-interface=("!" . $MikVeth)'         # the container must not hit the DNS redirect
need 'mik: dns to tunnel'                    # the DNS redirect and its marks
need 'mik: forward to container'             # strict forward chains need the accept
need '/ip firewall filter set $fasttrack !connection-mark'
need '/ip firewall filter set $fasttrack !src-address-list'
need '/system script environment remove [find where name="MikFasttrackSaved"]'  # uninstall clears saved originals

# A string MikSrcAddress must become an array before :foreach, or list mode
# creates no clients at all.
need ':set MikSrcAddress [:toarray $MikSrcAddress]'

# Our prerouting rules must sit above an operator's mark-routing rules, and the
# anchor must be a prerouting rule (an output rule is not a valid anchor here).
need 'find where chain=prerouting and action=mark-routing'
placed=$(grep -c 'place-before=\$firstMark' "$f")
[ "$placed" -ge 14 ] || err "$f: only $placed rules use place-before=\$firstMark (want at least 14)"

# The image the import pulls is pinned to the version of the repository. A
# pin that names another version would run a container the repository does
# not describe.
pin=$(sed -n 's/.*:global MikImage "ghcr\.io\/zebka\/v2raymik:\([0-9.]*\)".*/\1/p' "$f")
want=$(cat "$root/VERSION")
[ -n "$pin" ] || err "$f: the image is not pinned to a version"
[ "$pin" = "$want" ] || err "$f: the image is pinned to $pin, VERSION says $want"

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
