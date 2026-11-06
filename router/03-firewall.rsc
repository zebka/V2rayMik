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

# --- a second rule for extra ports (RouterOS caps one list at 15) ------------
:if ([:len $XrayExtraWanPorts] > 0) do={
  :if ([:len [/ip firewall filter find where comment="xray: container tcp transport (extra)"]] = 0) do={
    :if ([:len $firstFwdDrop] > 0) do={
      /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
        out-interface=$XrayWan protocol=tcp dst-port=$XrayExtraWanPorts \
        comment="xray: container tcp transport (extra)" place-before=$firstFwdDrop
    } else={
      /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
        out-interface=$XrayWan protocol=tcp dst-port=$XrayExtraWanPorts \
        comment="xray: container tcp transport (extra)"
    }
  } else={
    /ip firewall filter set [find where comment="xray: container tcp transport (extra)"] \
      dst-port=$XrayExtraWanPorts
  }
  :if ([:len [/ip firewall filter find where comment="xray: container udp transport (extra)"]] = 0) do={
    :if ([:len $firstFwdDrop] > 0) do={
      /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
        out-interface=$XrayWan protocol=udp dst-port=$XrayExtraWanPorts \
        comment="xray: container udp transport (extra)" place-before=$firstFwdDrop
    } else={
      /ip firewall filter add chain=forward action=accept src-address=$XraySubnet \
        out-interface=$XrayWan protocol=udp dst-port=$XrayExtraWanPorts \
        comment="xray: container udp transport (extra)"
    }
  } else={
    /ip firewall filter set [find where comment="xray: container udp transport (extra)"] \
      dst-port=$XrayExtraWanPorts
  }
} else={
  :if ([:len [/ip firewall filter find where comment~"container (tcp|udp) transport \\(extra\\)"]] > 0) do={
    /ip firewall filter remove [find where comment~"container (tcp|udp) transport \\(extra\\)"]
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
# One rule covers everything that enters the container: LAN clients and the
# router's own traffic. This is not cosmetic — measured on 7.25.1, the router's
# own packets left with the WAN address as source and were dropped inside the
# container, while the same packets masqueraded to the veth address went through.
# The container therefore only ever sees 172.17.0.1 as a peer, needs no route
# back to the LAN, and needs no NAT of its own.
:if ([:len [/ip firewall nat find where comment="xray: masquerade to container"]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade out-interface=$XrayVeth \
    comment="xray: masquerade to container"
}
# Clean up the two narrower rules older versions installed.
:if ([:len [/ip firewall nat find where comment="xray: LAN to container"]] > 0) do={
  /ip firewall nat remove [find where comment="xray: LAN to container"]
}
:if ([:len [/ip firewall nat find where comment="xray: router to container masq"]] > 0) do={
  /ip firewall nat remove [find where comment="xray: router to container masq"]
}

# --- fasttrack ---------------------------------------------------------------
# Fasttrack bypasses mangle marks and the MSS clamp. If a fasttrack rule exists
# for the forward chain, marked traffic may skip the clamp and stall on large
# TLS handshakes. Warn instead of silently changing the operator's firewall.
:if ([:len [/ip firewall filter find where action=fasttrack-connection]] > 0) do={
  :log warning "xray-gw: fasttrack rules exist; make sure they exclude routing-mark=$XrayTable or MSS clamping will be bypassed"
}

:log info "03-firewall: container is default-deny with transport-only egress"
