# 02-routing.rsc — world route, marking, MSS clamp, health.
#
# Import after 01-container.rsc, in the same session.
# Safe to import twice.

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
    distance=1 check-gateway=ping comment="xray-world"
}

# fail-open keeps a direct route at distance 2, so the internet survives an
# outage at the cost of leaking the real IP. fail-closed removes it.
:if ($XrayFailOpen = true) do={
  :local fbGw $XrayFallbackGw
  :if ([:len $fbGw] = 0) do={
    :local mainRoute [/ip route find where dst-address="0.0.0.0/0" and routing-table=main]
    :if ([:len $mainRoute] > 0) do={ :set fbGw [/ip route get [:pick $mainRoute 0] gateway] }
  }
  :if ([:len $fbGw] > 0) do={
    :if ([:len [/ip route find where comment="xray-fallback"]] = 0) do={
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

# Mark LAN and router traffic for the world table — only when the device does
# not already do it, and never against an empty iran-ips list (that would send
# everything, including local destinations, into the tunnel).
:if ([:len [/ip firewall mangle find where new-routing-mark=$XrayTable]] = 0) do={
  :if ([:len [/ip firewall address-list find where list="iran-ips"]] = 0) do={
    :log warning "xray-gw: iran-ips is empty; import an Iran address list, then re-run 02-routing.rsc"
  } else={
    /ip firewall mangle add chain=prerouting dst-address-list=!iran-ips \
      dst-address-type=!local action=mark-routing new-routing-mark=$XrayTable passthrough=no \
      comment="World -> xray (LAN)"
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
    new-mss=1360 tcp-mss=1361-65535 out-interface=$XrayBridge comment="xray: MSS clamp"
}
:if ([:len [/ip firewall mangle find where comment="xray: MSS clamp back"]] = 0) do={
  /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss \
    new-mss=1360 tcp-mss=1361-65535 in-interface=$XrayBridge comment="xray: MSS clamp back"
}

# --- container health --------------------------------------------------------
# 7.23+: if the TUN disappears, the container is stopped and restarted by the
# restart policy instead of sitting "running" with no tunnel.
/container set [find where name=$XrayContainerName] healthcheck-cmd="/bin/sh -c 'ip link show tun0 >/dev/null 2>&1'" \
  healthcheck-interval=00:01:00 healthcheck-start-period=00:00:30 stop-on-unhealthy=yes

:log info "02-routing: world route, marking, MSS and healthcheck in place"
