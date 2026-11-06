# 03-firewall.rsc — what the container may reach, and how it is NATed.
#
# Import after 02-routing.rsc, in the same session.
# Safe to import twice.

# A global has to be declared in the file that reads it (see 01-container.rsc).
:global MikVeth
:global MikTable
:global MikSubnet
:global MikWan
:global MikLanSubnet
:global MikAllowContainerToLan
:global MikContainerToWanPorts
:global MikExtraWanPorts

:if ([:typeof $MikVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

:local firstFwdDrop [:pick [/ip firewall filter find where chain=forward and action=drop] 0]

# --- the container may leave, but only for its own transport -----------------
# Not pinned to an IP: a CDN-fronted or rotated endpoint must keep working.
:if ([:len [/ip firewall filter find where comment="mik: container tcp transport"]] = 0) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      out-interface=$MikWan protocol=tcp dst-port=$MikContainerToWanPorts \
      comment="mik: container tcp transport" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      out-interface=$MikWan protocol=tcp dst-port=$MikContainerToWanPorts \
      comment="mik: container tcp transport"
  }
}

:if ([:len [/ip firewall filter find where comment="mik: container udp transport"]] = 0) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      out-interface=$MikWan protocol=udp dst-port=$MikContainerToWanPorts \
      comment="mik: container udp transport" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      out-interface=$MikWan protocol=udp dst-port=$MikContainerToWanPorts \
      comment="mik: container udp transport"
  }
}

# Keep an existing rule in step with the variable: re-importing must change the
# allowed ports, not leave the old list behind.
:foreach r in=[/ip firewall filter find where comment="mik: container tcp transport"] do={
  /ip firewall filter set $r dst-port=$MikContainerToWanPorts
}
:foreach r in=[/ip firewall filter find where comment="mik: container udp transport"] do={
  /ip firewall filter set $r dst-port=$MikContainerToWanPorts
}

# --- a second rule for extra ports (RouterOS caps one list at 15) ------------
:if ([:len $MikExtraWanPorts] > 0) do={
  :if ([:len [/ip firewall filter find where comment="mik: container tcp transport (extra)"]] = 0) do={
    :if ([:len $firstFwdDrop] > 0) do={
      /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
        out-interface=$MikWan protocol=tcp dst-port=$MikExtraWanPorts \
        comment="mik: container tcp transport (extra)" place-before=$firstFwdDrop
    } else={
      /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
        out-interface=$MikWan protocol=tcp dst-port=$MikExtraWanPorts \
        comment="mik: container tcp transport (extra)"
    }
  } else={
    /ip firewall filter set [find where comment="mik: container tcp transport (extra)"] \
      dst-port=$MikExtraWanPorts
  }
  :if ([:len [/ip firewall filter find where comment="mik: container udp transport (extra)"]] = 0) do={
    :if ([:len $firstFwdDrop] > 0) do={
      /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
        out-interface=$MikWan protocol=udp dst-port=$MikExtraWanPorts \
        comment="mik: container udp transport (extra)" place-before=$firstFwdDrop
    } else={
      /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
        out-interface=$MikWan protocol=udp dst-port=$MikExtraWanPorts \
        comment="mik: container udp transport (extra)"
    }
  } else={
    /ip firewall filter set [find where comment="mik: container udp transport (extra)"] \
      dst-port=$MikExtraWanPorts
  }
} else={
  :if ([:len [/ip firewall filter find where comment~"container (tcp|udp) transport \\(extra\\)"]] > 0) do={
    /ip firewall filter remove [find where comment~"container (tcp|udp) transport \\(extra\\)"]
  }
}

# --- optional: let the container reach the LAN (off by default) ---------------
:if ($MikAllowContainerToLan = true) do={
  :if ([:len [/ip firewall filter find where comment="mik: container to LAN (opt-in)"]] = 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      dst-address=$MikLanSubnet comment="mik: container to LAN (opt-in)"
  }
} else={
  :if ([:len [/ip firewall filter find where comment="mik: container to LAN (opt-in)"]] > 0) do={
    /ip firewall filter remove [find where comment="mik: container to LAN (opt-in)"]
  }
}

# --- default deny ------------------------------------------------------------
# A compromised image is a shell on the router; it gets the transport and DNS,
# nothing else. This is the rule that makes the container's blast radius small.
:if ([:len [/ip firewall filter find where comment="mik: container default deny"]] = 0) do={
  /ip firewall filter add chain=forward action=drop src-address=$MikSubnet \
    comment="mik: container default deny"
}

# --- NAT ---------------------------------------------------------------------
# One rule covers everything that enters the container: LAN clients and the
# router's own traffic. This is not cosmetic — measured on 7.25.1, the router's
# own packets left with the WAN address as source and were dropped inside the
# container, while the same packets masqueraded to the veth address went through.
# The container therefore only ever sees 172.17.0.1 as a peer, needs no route
# back to the LAN, and needs no NAT of its own.
:if ([:len [/ip firewall nat find where comment="mik: masquerade to container"]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade out-interface=$MikVeth \
    comment="mik: masquerade to container"
}
# Clean up the two narrower rules older versions installed.
:if ([:len [/ip firewall nat find where comment="mik: LAN to container"]] > 0) do={
  /ip firewall nat remove [find where comment="mik: LAN to container"]
}
:if ([:len [/ip firewall nat find where comment="mik: router to container masq"]] > 0) do={
  /ip firewall nat remove [find where comment="mik: router to container masq"]
}

# --- fasttrack ---------------------------------------------------------------
# Fasttrack bypasses mangle marks and the MSS clamp. If a fasttrack rule exists
# for the forward chain, marked traffic may skip the clamp and stall on large
# TLS handshakes. Warn instead of silently changing the operator's firewall.
:if ([:len [/ip firewall filter find where action=fasttrack-connection]] > 0) do={
  :log warning "v2raymik: fasttrack rules exist; make sure they exclude routing-mark=$MikTable or MSS clamping will be bypassed"
}

:log info "03-firewall: container is default-deny with transport-only egress"
