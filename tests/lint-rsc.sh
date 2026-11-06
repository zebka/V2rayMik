#!/bin/sh
# Static checks for the RouterOS scripts. It cannot replace importing the files
# on a device (Task 12), but it catches the mistakes that are cheap to catch:
# unbalanced blocks, globals that were never declared, unguarded `add`, and
# invariants the design depends on.
set -u

dir=${1:-router}
rc=0
err() { echo "lint: $*" >&2; rc=1; }
have() { [ -f "$dir/$1" ]; }
declared=""
if have 00-vars.rsc; then
  declared=$(sed -n 's/^:global \([A-Za-z0-9_]*\).*/\1/p' "$dir/00-vars.rsc")
else
  err "missing $dir/00-vars.rsc"
fi

for f in "$dir"/*.rsc; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = "00-vars.rsc" ] && continue

  open=$(tr -cd '{' < "$f" | wc -c)
  close=$(tr -cd '}' < "$f" | wc -c)
  [ "$open" -eq "$close" ] || err "$f: unbalanced braces ($open open, $close close)"

  for g in $(grep -o '\$Mik[A-Za-z0-9_]*' "$f" | tr -d '$' | sort -u); do
    printf '%s\n' "$declared" | grep -qx "$g" || err "$f: undeclared global \$$g"
    # RouterOS scopes globals per script: a value set by 00-vars.rsc is invisible
    # in another file unless that file declares `:global name` itself.
    grep -q "^:global $g" "$f" || err "$f: reads \$$g without a \":global $g\" line (other imported files do not share scope)"
  done

  # every `add` needs a guard (someone imports this twice)
  line_no=0
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    case "$line" in
      *"/add "*) ;;
      *) continue ;;
    esac
    start=$((line_no - 6))
    [ "$start" -lt 1 ] && start=1
    if ! sed -n "${start},${line_no}p" "$f" | grep -qE ':if|find where'; then
      err "$f:$line_no: /add without an :if / find guard"
    fi
  done < "$f"
done

# --- naming: one name for the project, everywhere it is live -----------------
# `xr`/`Xr`/`XR` are split so this file does not match its own patterns.
xr='x''ray'
Xr='X''ray'
XR='X''RAY'
root=$(cd "$dir/.." 2>/dev/null && pwd) || root="."

# --- no byte-order marks ------------------------------------------------------
# RouterOS reads the first line of an imported file as a command. With a UTF-8
# BOM in front of it that line is not a command, and `/import` answers
# "expected command name (line 1 column 1)" and skips the file — while the next
# line of the operator's paste still prints, so an install stalls at 01-container
# without ever saying why. Editors add the BOM silently, so guard it here.
# BusyBox only: compare the first three bytes as text, no `od -t`, no `file`.
bom=$(printf '\357\273\277')
for f in "$dir"/*.rsc "$root"/tests/*.sh "$root"/tests/*/*.sh; do
  [ -f "$f" ] || continue
  first3=$(head -c 3 "$f")
  [ "$first3" = "$bom" ] || continue
  err "$f: starts with a UTF-8 BOM; RouterOS /import rejects it (expected command name)"
done

# Files where the engine is never named at all: one stale character is a bug.
# Every path is quoted on purpose: the checkout sits under "New OpenCode Project",
# and an unquoted list would split there and grep nothing (2>/dev/null hides it).
# The migration script is dropped with `grep -v` rather than `--exclude`: this
# runs inside the image, whose BusyBox grep rejects `--exclude` outright, and a
# grep that dies on its own arguments leaves $hits empty — a guard that silently
# checks nothing. Both halves are proved to bite in the plan's Task 7.
hits=$(grep -rni "$xr" \
  "$root/router" "$root/docker" "$root/tests" 2>/dev/null |
  grep -v "/90-migrate-from-${xr}\.rsc:")
[ -z "$hits" ] || { printf '%s\n' "$hits" >&2; err "stale project name above; the project is V2rayMik, the engine is sing-box"; }
hits=$(grep -ni "$xr" "$root/Makefile" "$root/SECURITY.md" "$root/LICENSE" \
  "$root/.github/workflows/build.yml" "$root/.github/ISSUE_TEMPLATE/bug.md" \
  "$root/docs/dockerhub.md" "$root/docs/security.md" "$root/docs/troubleshooting.md" \
  "$root/docs/architecture.md" "$root/docs/install-side-load.md" 2>/dev/null)
[ -z "$hits" ] || { printf '%s\n' "$hits" >&2; err "stale project name above; the project is V2rayMik, the engine is sing-box"; }

# User-facing docs may still name the engine (the project ran another proxy
# engine up to 0.4.x), but
# never an old identifier — except between the old-name markers, which is the
# migration section that has to name what it migrates away from.
# benchmarks.md and design/admin-ui.md are history and keep the names.
ident="(mikrotik-${xr}-gateway|${xr}-gw|veth-${xr}|/${xr}-data|MOUNT_${XR}_DATA|${xr}-world|${xr}-fallback|${xr}-auto-route|royal-${xr}-gateway|${XR}_(LINK|OUTBOUND_FILE|OUTBOUND_JSON|LOG_LEVEL)|${xr}: )"
legacy="${Xr}(AllowContainerToLan|RefreshRouterDirect|ContainerToWanPorts|CheckCertificate|AdminPassword|AdminLanPort|ContainerName|ContainerIp|ExtraWanPorts|ImageFile|LanSubnet|FallbackGw|RestoreRoute|GatewayIp|AdminPort|FailOpen|Bridge|Veth|Subnet|Image|Table|Disk|Wan)\b"
for f in "$root/README.md" "$root/README.fa.md" "$root/SECURITY.md" \
         "$root/.github/ISSUE_TEMPLATE/bug.md" "$root/docs"/*.md; do
  case $(basename "$f") in
    benchmarks.md|admin-ui.md) continue ;;
  esac
  hit=$(awk -v pat="$ident" '
    FNR == 1 { skip = 0 }
    /<!-- old-name-start -->/ { skip = 1; next }
    /<!-- old-name-end -->/ { skip = 0; next }
    !skip && $0 ~ pat { print FILENAME ":" FNR ": " $0 }
  ' "$f")
  [ -z "$hit" ] || { printf '%s\n' "$hit" >&2; err "old identifier in a live doc (only the old-name markers may carry one)"; }
  hit=$(grep -En "$legacy" "$f")
  [ -z "$hit" ] || { printf '%s\n' "$hit" >&2; err "old global name in a live doc; globals are Mik*"; }
  # A global whose name starts with the engine means a bulk rename ran over a
  # global (`sing-boxDisk` where `MikDisk` belongs), which the checks above miss
  # because no old name is left in it.
  hit=$(grep -n 'sing-box[A-Z]' "$f")
  [ -z "$hit" ] || { printf '%s: %s\n' "$f" "$hit" >&2; err "engine name glued to a name above; globals are Mik*"; }
done

# --- invariants -------------------------------------------------------------
have 01-container.rsc || err "01-container.rsc: missing"
have 02-routing.rsc || err "02-routing.rsc: missing"
have 03-firewall.rsc || err "03-firewall.rsc: missing"
have 99-uninstall.rsc || err "99-uninstall.rsc: missing"

if have 01-container.rsc; then  grep -q 'veth' "$dir/01-container.rsc" || err "01-container.rsc: no veth"
  grep -q 'container/config/set' "$dir/01-container.rsc" || err "01-container.rsc: tmpdir not set"
  grep -q 'mountlists=MOUNT_MIK_DATA' "$dir/01-container.rsc" || err "01-container.rsc: /data is not mounted outside the root-dir, so repull wipes the panel state"
  grep -q 'key=NODE_OUTBOUND_FILE' "$dir/01-container.rsc" || err "01-container.rsc: env key is not the engine-neutral NODE_OUTBOUND_FILE"
  grep -q 'value="/etc/sing-box/outbound.json"' "$dir/01-container.rsc" || err "01-container.rsc: NODE_OUTBOUND_FILE does not point at the sing-box default path the README documents"
fi

if have 02-routing.rsc; then
  grep -q 'gateway=\$MikContainerIp' "$dir/02-routing.rsc" || err "02-routing.rsc: route does not use the container as gateway"
  grep -q 'src-address=\$MikSubnet' "$dir/02-routing.rsc" || err "02-routing.rsc: no mangle exemption for the container subnet"
  grep -q 'change-mss' "$dir/02-routing.rsc" || err "02-routing.rsc: no MSS clamp"
  grep -q 'out-interface=\$MikVeth' "$dir/02-routing.rsc" || err "02-routing.rsc: MSS clamp must match the veth egress"
  grep -q 'MSS clamp (router output)' "$dir/02-routing.rsc" || err "02-routing.rsc: no output-chain MSS clamp (router traffic stalls without it)"
  grep -q 'comment="mik: connected to container"' "$dir/02-routing.rsc" || err "02-routing.rsc: missing the connected route that makes the gateway reachable inside the table"
  grep -q 'MikFailOpen' "$dir/02-routing.rsc" || err "02-routing.rsc: failover flag unused"
fi

if have 03-firewall.rsc; then
  grep -q 'action=drop' "$dir/03-firewall.rsc" || err "03-firewall.rsc: no default deny"
  grep -q 'out-interface=\$MikWan' "$dir/03-firewall.rsc" || err "03-firewall.rsc: no container→WAN masquerade"
  grep -q 'dst-port=\$MikContainerToWanPorts' "$dir/03-firewall.rsc" || err "03-firewall.rsc: transport port list is hard-coded"
  grep -q 'dst-port=\$MikExtraWanPorts' "$dir/03-firewall.rsc" || err "03-firewall.rsc: no second allowlist rule for extra ports"
  grep -q 'comment="mik: masquerade to container"' "$dir/03-firewall.rsc" || err "03-firewall.rsc: no general masquerade towards the container (router traffic is dropped without it)"
  grep -q 'dst-address=\$MikContainerIp' "$dir/03-firewall.rsc" && err "03-firewall.rsc: masquerade matches the destination, which is never the container"
fi

have 04-admin.rsc || err "04-admin.rsc: missing"
have 05-auto-route.rsc || err "05-auto-route.rsc: missing"

if have 05-auto-route.rsc; then
  grep -q 'cgi-bin/health' "$dir/05-auto-route.rsc" || err "05-auto-route.rsc: does not poll the health endpoint"
  grep -q 'selected=1' "$dir/05-auto-route.rsc" || err "05-auto-route.rsc: no selection check"
  grep -q 'live=1' "$dir/05-auto-route.rsc" || err "05-auto-route.rsc: does not require a live tunnel"
  grep -q 'comment="mik-world"' "$dir/05-auto-route.rsc" || err "05-auto-route.rsc: does not move the world route"
  grep -q 'wanGw' "$dir/05-auto-route.rsc" || err "05-auto-route.rsc: fallback does not identify the ISP gateway"
  grep -q 'routing-table=main' "$dir/05-auto-route.rsc" || err "05-auto-route.rsc: the ISP gateway is not read from the main table"
  grep -q 'World -> OpenVPN' "$dir/05-auto-route.rsc" && err "05-auto-route.rsc: names a tunnel as fallback; the fallback must be the ISP"
fi

if have 04-admin.rsc; then
  grep -q 'comment="mik: admin ui"' "$dir/04-admin.rsc" || err "04-admin.rsc: no admin dst-nat"
  grep -q 'in-interface-list=LAN' "$dir/04-admin.rsc" || err "04-admin.rsc: the admin port is not restricted to the LAN"
  grep -q 'dst-port=\$MikAdminLanPort' "$dir/04-admin.rsc" || err "04-admin.rsc: LAN port not driven by the variable"
fi

if have 99-uninstall.rsc; then
  for sym in MikVeth MikBridge MikContainerName; do
    grep -q "\$$sym" "$dir/99-uninstall.rsc" || err "99-uninstall.rsc: does not mention \$$sym"
  done
  grep -q 'iran-ips' "$dir/99-uninstall.rsc" && err "99-uninstall.rsc: touches iran-ips"
  grep -q 'local-nets' "$dir/99-uninstall.rsc" && err "99-uninstall.rsc: touches local-nets"
fi

# The migration script keeps the old name in its filename on purpose, so build
# it here: `tests/` is inside the strict set and must not spell it out.
mig="90-migrate-from-${xr}.rsc"
if have "$mig"; then
  m="$dir/$mig"
  grep -q "name=\"${xr}-gw\"" "$m" || err "90-migrate: does not find the old container by name"
  grep -q "MOUNT_${XR}_DATA" "$m" || err "90-migrate: does not remove the old mount list"
  grep -q "World -> ${xr} (LAN)" "$m" || err "90-migrate: the LAN mark rule has no prefix comment and would be orphaned"
  grep -q "World -> ${xr} (router)" "$m" || err "90-migrate: the router mark rule would be orphaned"
  grep -q "${xr}-auto-route" "$m" || err "90-migrate: the old scheduler and script would survive"
  grep -q 'dst="/data"' "$m" || err "90-migrate: does not discover the old data dir from the mount, so the disk is a guess"
  grep -q 'sub.txt' "$m" || err "90-migrate: does not carry the subscription over"
  grep -q '/file remove' "$m" && err "90-migrate: deletes files; the old dirs are the rollback path"
  grep -q ':log warning' "$m" || err "90-migrate: never warns, so a missing subscription would pass silently"
else
  err "90-migrate-from-${xr}.rsc: missing (existing installs have no upgrade path)"
fi

exit "$rc"
