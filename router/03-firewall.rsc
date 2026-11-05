# 03-firewall.rsc — what the container may reach, and how it is NATed.
#
# Import after 02-routing.rsc, in the same session.
# Safe to import twice.

:if ([:typeof $XrayVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

:local firstFwdDrop [:pick [/ip firewall filter find where chain=forward and action=drop] 0]

# --- the container may leave, but only for its own transport -----------------
# Not pinned to an IP: a CDN-fronted or rotated endpoint must keep working.
:if ([:len [/ip firewall filter find where comment="xray: container tcp transport"]] = 0) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
      out-interface=$XrayWan protocol=tcp dst-port=$XrayContainerToWanPorts \
      comment="xray: container tcp transport" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
      out-interface=$XrayWan protocol=tcp dst-port=$XrayContainerToWanPorts \
      comment="xray: container tcp transport"
  }
}

:if ([:len [/ip firewall filter find where comment="xray: container udp transport"]] = 0) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
      out-interface=$XrayWan protocol=udp dst-port=$XrayContainerToWanPorts \
      comment="xray: container udp transport" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
      out-interface=$XrayWan protocol=udp dst-port=$XrayContainerToWanPorts \
      comment="xray: container udp transport"
  }
}

# Keep an existing rule in step with the variable: re-importing must change the
# allowed ports, not leave the old list behind.
:foreach r in=[/ip firewall filter find where comment="xray: container tcp transport"] do={
  /ip firewall filter set $r dst-port=$XrayContainerToWanPorts
}
:foreach r in=[/ip firewall filter find where comment="xray: container udp transport"] do={
  /ip firewall filter set $r dst-port=$XrayContainerToWanPorts
}

# --- optional: let the container reach the LAN (off by default) ---------------
:if ($XrayAllowContainerToLan = true) do={
  :if ([:len [/ip firewall filter find where comment="xray: container to LAN (opt-in)"]] = 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
      dst-address=$XrayLanSubnet comment="xray: container to LAN (opt-in)"
  }
} else={
  :if ([:len [/ip firewall filter find where comment="xray: container to LAN (opt-in)"]] > 0) do={
    /ip firewall filter remove [find where comment="xray: container to LAN (opt-in)"]
  }
}

# --- default deny ------------------------------------------------------------
# A compromised image is a shell on the router; it gets the transport and DNS,
# nothing else. This is the rule that makes the container's blast radius small.
:if ([:len [/ip firewall filter find where comment="xray: container default deny"]] = 0) do={
  /ip firewall filter add chain=forward action=drop src-address=$XraySubnet \
    comment="xray: container default deny"
}

# --- NAT ---------------------------------------------------------------------
# Container -> WAN: needed for the transport itself.
:if ([:len [/ip firewall nat find where comment="xray: container egress"]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade src-address=$XraySubnet \
    out-interface=$XrayWan comment="xray: container egress"
}

# LAN -> container: match on the egress interface, not the destination. A
# tunnelled packet is addressed to 8.8.8.8; 172.17.0.2 is the *gateway*, so a
# dst-address match would never fire and the container would receive the
# client's LAN address — whose replies fall into 128.0.0.0/1 and loop.
:if ([:len [/ip firewall nat find where comment="xray: LAN to container"]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade src-address=$XrayLanSubnet \
    out-interface=$XrayVeth dst-address-type=!local comment="xray: LAN to container"
}

# --- fasttrack ---------------------------------------------------------------
# Fasttrack bypasses mangle marks and the MSS clamp. If a fasttrack rule exists
# for the forward chain, marked traffic may skip the clamp and stall on large
# TLS handshakes. Warn instead of silently changing the operator's firewall.
:if ([:len [/ip firewall filter find where action=fasttrack-connection]] > 0) do={
  :log warning "xray-gw: fasttrack rules exist; make sure they exclude routing-mark=$XrayTable or MSS clamping will be bypassed"
}

:log info "03-firewall: container is default-deny with transport-only egress"
