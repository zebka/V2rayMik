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
      out-interface=$XrayWan protocol=tcp dst-port=443,80 \
      comment="xray: container tcp transport" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
      out-interface=$XrayWan protocol=tcp dst-port=443,80 \
      comment="xray: container tcp transport"
  }
}

:if ([:len [/ip firewall filter find where comment="xray: container udp transport"]] = 0) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
      out-interface=$XrayWan protocol=udp dst-port=443,53 \
      comment="xray: container udp transport" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
      out-interface=$XrayWan protocol=udp dst-port=443,53 \
      comment="xray: container udp transport"
  }
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

# LAN -> container: the container only ever sees the router as a peer, so it
# needs no route back to the LAN and no NAT of its own.
:if ([:len [/ip firewall nat find where comment="xray: LAN to container"]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade src-address=$XrayLanSubnet \
    dst-address=$XrayContainerIp comment="xray: LAN to container"
}

# --- fasttrack ---------------------------------------------------------------
# Fasttrack bypasses mangle marks and the MSS clamp. If a fasttrack rule exists
# for the forward chain, marked traffic may skip the clamp and stall on large
# TLS handshakes. Warn instead of silently changing the operator's firewall.
:if ([:len [/ip firewall filter find where action=fasttrack-connection]] > 0) do={
  :log warning "xray-gw: fasttrack rules exist; make sure they exclude routing-mark=$XrayTable or MSS clamping will be bypassed"
}

:log info "03-firewall: container is default-deny with transport-only egress"
