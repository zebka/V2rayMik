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

  for g in $(grep -o '\$Xray[A-Za-z0-9_]*' "$f" | tr -d '$' | sort -u); do
    printf '%s\n' "$declared" | grep -qx "$g" || err "$f: undeclared global \$$g"
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

# --- invariants -------------------------------------------------------------
have 01-container.rsc || err "01-container.rsc: missing"
have 02-routing.rsc || err "02-routing.rsc: missing"
have 03-firewall.rsc || err "03-firewall.rsc: missing"
have 99-uninstall.rsc || err "99-uninstall.rsc: missing"

if have 01-container.rsc; then  grep -q 'veth' "$dir/01-container.rsc" || err "01-container.rsc: no veth"
  grep -q 'container/config/set' "$dir/01-container.rsc" || err "01-container.rsc: tmpdir not set"
  grep -q 'mountlists=MOUNT_XRAY_DATA' "$dir/01-container.rsc" || err "01-container.rsc: /data is not mounted outside the root-dir, so repull wipes the panel state"
fi

if have 02-routing.rsc; then
  grep -q 'gateway=\$XrayContainerIp' "$dir/02-routing.rsc" || err "02-routing.rsc: route does not use the container as gateway"
  grep -q 'src-address=\$XraySubnet' "$dir/02-routing.rsc" || err "02-routing.rsc: no mangle exemption for the container subnet"
  grep -q 'change-mss' "$dir/02-routing.rsc" || err "02-routing.rsc: no MSS clamp"
  grep -q 'out-interface=\$XrayVeth' "$dir/02-routing.rsc" || err "02-routing.rsc: MSS clamp must match the veth egress"
  grep -q 'MSS clamp (router output)' "$dir/02-routing.rsc" || err "02-routing.rsc: no output-chain MSS clamp (router traffic stalls without it)"
  grep -q 'comment="xray: connected to container"' "$dir/02-routing.rsc" || err "02-routing.rsc: missing the connected route that makes the gateway reachable inside the table"
  grep -q 'XrayFailOpen' "$dir/02-routing.rsc" || err "02-routing.rsc: failover flag unused"
fi

if have 03-firewall.rsc; then
  grep -q 'action=drop' "$dir/03-firewall.rsc" || err "03-firewall.rsc: no default deny"
  grep -q 'out-interface=\$XrayWan' "$dir/03-firewall.rsc" || err "03-firewall.rsc: no container→WAN masquerade"
  grep -q 'dst-port=\$XrayContainerToWanPorts' "$dir/03-firewall.rsc" || err "03-firewall.rsc: transport port list is hard-coded"
  grep -q 'dst-port=\$XrayExtraWanPorts' "$dir/03-firewall.rsc" || err "03-firewall.rsc: no second allowlist rule for extra ports"
  grep -q 'comment="xray: masquerade to container"' "$dir/03-firewall.rsc" || err "03-firewall.rsc: no general masquerade towards the container (router traffic is dropped without it)"
  grep -q 'dst-address=\$XrayContainerIp' "$dir/03-firewall.rsc" && err "03-firewall.rsc: masquerade matches the destination, which is never the container"
fi

have 04-admin.rsc || err "04-admin.rsc: missing"

if have 04-admin.rsc; then
  grep -q 'comment="xray: admin ui"' "$dir/04-admin.rsc" || err "04-admin.rsc: no admin dst-nat"
  grep -q 'in-interface-list=LAN' "$dir/04-admin.rsc" || err "04-admin.rsc: the admin port is not restricted to the LAN"
  grep -q 'dst-port=\$XrayAdminLanPort' "$dir/04-admin.rsc" || err "04-admin.rsc: LAN port not driven by the variable"
fi

if have 99-uninstall.rsc; then
  for sym in XrayVeth XrayBridge XrayContainerName; do
    grep -q "\$$sym" "$dir/99-uninstall.rsc" || err "99-uninstall.rsc: does not mention \$$sym"
  done
  grep -q 'iran-ips' "$dir/99-uninstall.rsc" && err "99-uninstall.rsc: touches iran-ips"
  grep -q 'local-nets' "$dir/99-uninstall.rsc" && err "99-uninstall.rsc: touches local-nets"
fi

exit "$rc"
