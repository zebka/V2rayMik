# 02-routing.rsc — world route, marking, MSS clamp, health.
#
# Import after 01-container.rsc, in the same session.
# Safe to import twice.

# A global has to be declared in the file that reads it (see 01-container.rsc).
:global XrayVeth
:global XrayTable
:global XraySubnet
:global XrayContainerIp
:global XrayContainerName
:global XrayFailOpen
:global XrayFallbackGw
:global XrayRefreshRouterDirect

:if ([:typeof $XrayVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

# --- routing table -----------------------------------------------------------
:if ([:len [/routing table find where name=$XrayTable]] = 0) do={
  /routing table add name=$XrayTable fib
}

# --- the world route ---------------------------------------------------------
:if ([:len [/ip route find where comment="xray-world"]] = 0) do={
  /ip route add dst-address=0.0.0.0/0 gateway=$XrayContainerIp routing-table=$XrayTable \
    distance=1 comment="xray-world"
}

# fail-open keeps a direct route through the ISP at distance 2: when the tunnel
# is down, marked traffic leaves from the router's own address — the old, direct
# path — instead of dying. It never points at another tunnel: a VPN fallback would
# hide a dead node and silently change the exit country. fail-closed removes the
# route, so marked traffic is dropped instead.
:if ($XrayFailOpen = true) do={
  :local fbGw $XrayFallbackGw
  :if ([:len $fbGw] = 0) do={
    :local mainRoute [/ip route find where dst-address="0.0.0.0/0" and routing-table=main]
    :if ([:len $mainRoute] > 0) do={ :set fbGw [/ip route get [:pick $mainRoute 0] gateway] }
  }
  :if ([:len $fbGw] > 0) do={
    # One direct route is enough. Reuse whatever already points at the ISP (many
    # devices have their own "backup if the VPN dies" row); only add ours when
    # nothing else does the job.
    :local direct 0
    :foreach r in=[/ip route find where routing-table=$XrayTable and dst-address="0.0.0.0/0"] do={
      :if ([/ip route get $r gateway] = $fbGw) do={
        :if ([/ip route get $r comment] != "xray-world") do={ :set direct ($direct + 1) }
      }
    }
    :if ([:len [/ip route find where comment="xray-fallback"]] = 0 and $direct = 0) do={
      /ip route add dst-address=0.0.0.0/0 gateway=$fbGw routing-table=$XrayTable \
        distance=2 comment="xray-fallback"
    }
  } else={
    :log warning "xray-gw: fail-open requested but no WAN gateway found; set XrayFallbackGw"
  }
} else={
  :if ([:len [/ip route find where comment="xray-fallback"]] > 0) do={
    /ip route remove [find where comment="xray-fallback"]
  }
}

# A competing distance-1 route in the same table makes the choice per-connection
# and unpredictable. Refuse to guess: tell the operator which one to disable.
:foreach c in=[/ip route find where routing-table=$XrayTable] do={
  :if ([/ip route get $c distance] = 1) do={
    :if ([/ip route get $c comment] != "xray-world") do={
      :if ([/ip route get $c disabled] = false) do={
        :log warning ("xray-gw: another distance-1 route is active in " . $XrayTable . ": " . [/ip route get $c comment] . " — disable it or the exit is per-connection random")
      }
    }
  }
}

# The gateway must be reachable inside the table that uses it. RouterOS keeps
# connected routes in `main`, and a marked route whose gateway is only reachable
# there silently drops locally-originated traffic (measured on 7.25.1: active
# route, packets never leave). This row is what makes it work.
:if ([:len [/ip route find where comment="xray: connected to container"]] = 0) do={
  /ip route add dst-address=$XraySubnet gateway=$XrayVeth routing-table=$XrayTable \
    comment="xray: connected to container"
}

# --- marking -----------------------------------------------------------------
# The container's own egress must never be marked: the transport carries itself
# otherwise. This rule must sit before every mark-routing rule.
:local firstMark [:pick [/ip firewall mangle find where action=mark-routing] 0]
:if ([:len [/ip firewall mangle find where comment="xray: never mark the container"]] = 0) do={
  :if ([:len $firstMark] > 0) do={
    /ip firewall mangle add chain=prerouting src-address=$XraySubnet action=accept \
      comment="xray: never mark the container" place-before=$firstMark
  } else={
    /ip firewall mangle add chain=prerouting src-address=$XraySubnet action=accept \
      comment="xray: never mark the container"
  }
}

# Router-originated traffic for these hosts stays on the WAN: IP-Cloud would
# otherwise publish the exit IP as the device's public address and lock Winbox
# out of the DDNS name (this happened on the reference device in 2026-11).
:if ([:len [/ip firewall address-list find where list="router-direct"]] = 0 or [:len $XrayRefreshRouterDirect] > 0) do={
  :foreach h in={"cloud.mikrotik.com";"cloud2.mikrotik.com";"upgrade.mikrotik.com"} do={
    :if ([:len [/ip firewall address-list find where list="router-direct" and comment=$h]] = 0) do={
      :do {
        :local a [:resolve $h]
        /ip firewall address-list add list=router-direct address=$a comment=$h
      } on-error={ :log warning ("xray-gw: could not resolve " . $h) }
    }
  }
}
:if ([:len [/ip firewall mangle find where comment="xray: keep router-direct off the tunnel"]] = 0) do={
  :local fm [:pick [/ip firewall mangle find where action=mark-routing] 0]
  :if ([:len $fm] > 0) do={
    /ip firewall mangle add chain=output dst-address-list=router-direct action=accept \
      comment="xray: keep router-direct off the tunnel" place-before=$fm
  } else={
    /ip firewall mangle add chain=output dst-address-list=router-direct action=accept \
      comment="xray: keep router-direct off the tunnel"
  }
}

# Mark LAN and router traffic for the world table — per chain, because a device
# may already mark one of them. Never against an empty iran-ips list (that would
# send everything, including local destinations, into the tunnel).
:if ([:len [/ip firewall address-list find where list="iran-ips"]] = 0) do={
  :log warning "xray-gw: iran-ips is empty; import an Iran address list, then re-run 02-routing.rsc"
} else={
  :if ([:len [/ip firewall mangle find where chain=prerouting and action=mark-routing and new-routing-mark=$XrayTable]] = 0) do={
    /ip firewall mangle add chain=prerouting dst-address-list=!iran-ips \
      dst-address-type=!local action=mark-routing new-routing-mark=$XrayTable passthrough=no \
      comment="World -> xray (LAN)"
  }
  # Router-originated traffic: only a *general* enabled rule counts. A narrow
  # rule (DNS to port 53, an endpoint bypass) must not make the script think the
  # router is already covered, and neither must a disabled leftover.
  :local liveOut 0
  :foreach r in=[/ip firewall mangle find where chain=output and action=mark-routing and new-routing-mark=$XrayTable] do={
    :if ([/ip firewall mangle get $r disabled] = false) do={
      :local dp ""
      :do { :set dp [/ip firewall mangle get $r dst-port] } on-error={ :set dp "" }
      :if ([:len $dp] = 0) do={ :set liveOut 1 }
    }
  }
  :if ($liveOut = 0) do={
    /ip firewall mangle add chain=output dst-address-list=!iran-ips \
      dst-address-type=!local action=mark-routing new-routing-mark=$XrayTable passthrough=no \
      comment="World -> xray (router)"
  }
}

# --- MSS ---------------------------------------------------------------------
# The tunnel adds a header; without this, large TLS handshakes hang instead of
# failing, which looks like "the site is broken".
:if ([:len [/ip firewall mangle find where comment="xray: MSS clamp"]] = 0) do={
  /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss \
    new-mss=1360 tcp-mss=1361-65535 out-interface=$XrayVeth comment="xray: MSS clamp"
}
:if ([:len [/ip firewall mangle find where comment="xray: MSS clamp back"]] = 0) do={
  /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss \
    new-mss=1360 tcp-mss=1361-65535 in-interface=$XrayVeth comment="xray: MSS clamp back"
}
# Traffic the router itself sends needs the clamp too: `chain=forward` never sees
# it, and without this a 10 MB download stalls at zero bytes while small pages
# work fine (measured).
:if ([:len [/ip firewall mangle find where comment="xray: MSS clamp (router output)"]] = 0) do={
  /ip firewall mangle add chain=output protocol=tcp tcp-flags=syn action=change-mss \
    new-mss=1360 tcp-mss=1361-65535 comment="xray: MSS clamp (router output)"
}

# --- container health --------------------------------------------------------
# 7.23+: if the TUN disappears, the container is stopped and restarted by the
# restart policy instead of sitting "running" with no tunnel.
/container set [find where name=$XrayContainerName] healthcheck-cmd="/bin/sh -c 'ip link show tun0 >/dev/null 2>&1'" \
  healthcheck-interval=00:01:00 healthcheck-start-period=00:00:30 stop-on-unhealthy=yes

:log info "02-routing: world route, marking, MSS and healthcheck in place"
