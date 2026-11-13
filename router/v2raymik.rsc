# v2raymik — the whole project in one RouterOS import.
#
#   Install / upgrade:   /import file-name=v2raymik.rsc
#   Uninstall:           :global MikMode "uninstall"
#                        /import file-name=v2raymik.rsc
#                        (open a new terminal afterwards; MikMode stays set in this one)
#
# Re-importing is safe and is how upgrades work: objects are created only when
# missing, and firewalled ports re-apply the values below.
#
# Everything goes through the tunnel: every IPv4 destination except the
# container subnet is carried by the tunnel. There is no Iran/foreign split,
# no address-list, no per-destination exception. When the tunnel is down the
# traffic is dropped (fail-closed); there is no ISP fallback route.
#
# The panel is a plain HTTP page on the LAN (http://<router>:<MikAdminLanPort>/),
# with no password — anyone on the LAN can switch the node. It is reachable only
# through the dst-nat at the bottom of this file, which is scoped to the LAN
# interface list. Do not expose it to the WAN.
#
# If you upgrade from a 1.x install, run uninstall first, then install again:
# the uninstall mode below also removes the objects the old 00–05 scripts made
# (table `to-world`, routes `mik-world`/`mik-fallback`, "MSS clamp (router
# output)", MOUNT_MIK_DATA).

# --- the knobs. everything else is derived. --------------------------------
:global MikMode
:global MikWan
:global MikLanSubnet
:global MikDisk
:global MikVeth
:global MikSubnet
:global MikContainerIp
:global MikGatewayIp
:global MikContainerName
:global MikImage
:global MikImageFile
:global MikCheckCertificate
:global MikRegistryUrl
:global MikAdminPort
:global MikAdminLanPort
:global MikContainerToWanPorts
:global MikExtraWanPorts
:global MikAllowContainerToLan
:global MikBridge

# Sensible defaults; override before the import in the same terminal session.
:if ([:typeof $MikWan] = "nothing") do={ :global MikWan "ether2-WAN" }
:if ([:typeof $MikLanSubnet] = "nothing") do={ :global MikLanSubnet "192.168.88.0/24" }
:if ([:typeof $MikDisk] = "nothing") do={ :global MikDisk "usb2" }
:if ([:typeof $MikVeth] = "nothing") do={ :global MikVeth "veth-mik" }
:if ([:typeof $MikSubnet] = "nothing") do={ :global MikSubnet "172.17.0.0/24" }
:if ([:typeof $MikContainerIp] = "nothing") do={ :global MikContainerIp "172.17.0.2" }
:if ([:typeof $MikGatewayIp] = "nothing") do={ :global MikGatewayIp "172.17.0.1" }
:if ([:typeof $MikContainerName] = "nothing") do={ :global MikContainerName "v2raymik" }
:if ([:typeof $MikImage] = "nothing") do={ :global MikImage "azebka/v2raymik:latest" }
:if ([:typeof $MikImageFile] = "nothing") do={ :global MikImageFile "" }
:if ([:typeof $MikCheckCertificate] = "nothing") do={ :global MikCheckCertificate "yes" }
# Registry used for the pull. docker.iranserver.com works in Iran; arvancloud
# needs MikCheckCertificate "no" on 7.25.1.
:if ([:typeof $MikRegistryUrl] = "nothing") do={ :global MikRegistryUrl "https://registry-1.docker.io" }
:if ([:typeof $MikAdminPort] = "nothing") do={ :global MikAdminPort "8080" }
:if ([:typeof $MikAdminLanPort] = "nothing") do={ :global MikAdminLanPort "8081" }
:if ([:typeof $MikContainerToWanPorts] = "nothing") do={ :global MikContainerToWanPorts "443,80,8080,8880,2052,2053,2082,2083,2086,2087,2095,2096,8443,53" }
:if ([:typeof $MikExtraWanPorts] = "nothing") do={ :global MikExtraWanPorts "" }
:if ([:typeof $MikAllowContainerToLan] = "nothing") do={ :global MikAllowContainerToLan false }
:if ([:typeof $MikBridge] = "nothing") do={ :global MikBridge "containers" }
:if ([:typeof $MikMode] = "nothing") do={ :global MikMode "install" }

:if ($MikMode = "uninstall") do={
# =========================================================================
# UNINSTALL — remove every object this file creates (and the legacy ones).
# Routing goes first, so traffic leaves the tunnel immediately.
# =========================================================================
  :log warning "v2raymik: uninstalling"

  # --- routes and tables ------------------------------------------------
  # Remove only routes this project creates (by comment). Connected routes in
  # a fib table are recreated dynamically by the veth itself, so a blanket
  # "every route in the table" would try (and fail) to remove those too.
  :foreach c in={"mik-world";"mik-fallback";"mik: connected to container";"mik: tunnel"} do={
    :if ([:len [/ip route find where comment=$c]] > 0) do={
      /ip route remove [find where comment=$c]
    }
  }
  :foreach t in={"mik-tunnel";"to-world"} do={
    :if ([:len [/ip route find where routing-table=$t and dynamic=no]] = 0) do={
      :do { /routing table remove [find where name=$t] } on-error={ :log warning ("v2raymik: could not remove table " . $t . " yet; it is removed at the end") }
    }
  }

  # --- mangle ------------------------------------------------------------
  :foreach c in={"mik: never mark the container";"mik: router to LAN";"mik: keep router-direct off the tunnel";"mik: MSS clamp";"mik: MSS clamp back";"mik: MSS clamp (router output)";"World -> mik (LAN)";"World -> mik (router)";"World -> tunnel";"World -> tunnel (router)"} do={
    :if ([:len [/ip firewall mangle find where comment=$c]] > 0) do={
      /ip firewall mangle remove [find where comment=$c]
    }
  }

  # legacy: router-direct address-list entries from ≤1.0.x; an operator's own
  # entries in that list are left alone
  :foreach h in={"cloud.mikrotik.com";"cloud2.mikrotik.com";"upgrade.mikrotik.com"} do={
    :if ([:len [/ip firewall address-list find where list="router-direct" and comment=$h]] > 0) do={
      /ip firewall address-list remove [find where list="router-direct" and comment=$h]
    }
  }

  # --- firewall filter ---------------------------------------------------
  :foreach c in={"mik: container tcp transport";"mik: container udp transport";"mik: container tcp transport (extra)";"mik: container udp transport (extra)";"mik: container to LAN (opt-in)";"mik: container default deny";"mik: container replies (established)"} do={
    :if ([:len [/ip firewall filter find where comment=$c]] > 0) do={
      /ip firewall filter remove [find where comment=$c]
    }
  }

  # --- NAT and the admin page ---------------------------------------------
  :foreach c in={"mik: masquerade to container";"mik: admin ui";"mik: LAN to container";"mik: router to container masq";"mik: container egress"} do={
    :if ([:len [/ip firewall nat find where comment=$c]] > 0) do={
      /ip firewall nat remove [find where comment=$c]
    }
  }

  # --- legacy scheduler (1.x) ---------------------------------------------
  :if ([:len [/system scheduler find where name="mik-auto-route"]] > 0) do={
    /system scheduler remove [find where name="mik-auto-route"]
  }
  :if ([:len [/system script find where name="mik-auto-route"]] > 0) do={
    /system script remove [find where name="mik-auto-route"]
  }

  # --- container and its plumbing ------------------------------------------
  :if ([:len [/container find where name=$MikContainerName]] > 0) do={
    :do { /container stop [find where name=$MikContainerName] } on-error={}
    :delay 3s
    /container remove [find where name=$MikContainerName]
  }
  :if ([:len [/container envs find where list=$MikContainerName]] > 0) do={
    /container envs remove [find where list=$MikContainerName]
  }
  :if ([:len [/container mounts find where list="MOUNT_MIK_DATA"]] > 0) do={
    /container mounts remove [find where list="MOUNT_MIK_DATA"]
  }

  # --- veth and legacy bridge -----------------------------------------------
  :if ([:len [/interface bridge port find where interface=$MikVeth]] > 0) do={
    /interface bridge port remove [find where interface=$MikVeth]
  }
  :if ([:len [/ip address find where interface=$MikVeth]] > 0) do={
    /ip address remove [find where interface=$MikVeth]
  }
  :if ([:len [/interface bridge find where name=$MikBridge]] > 0) do={
    # only the bridge this project created; a pre-existing one is left alone
    :if ([:len [/interface bridge find where name=$MikBridge and comment="container network"]] > 0) do={
      /interface bridge remove [find where name=$MikBridge and comment="container network"]
    } else={
      :log warning ("v2raymik: bridge " . $MikBridge . " was not created by this project; left in place")
    }
  }
  :if ([:len [/interface veth find where name=$MikVeth]] > 0) do={
    /interface veth remove [find where name=$MikVeth]
  }

  # now that the veth is gone, the fib tables have no routes left either
  :foreach t in={"mik-tunnel";"to-world"} do={
    :if ([:len [/routing table find where name=$t]] > 0) do={
      :do { /routing table remove [find where name=$t] } on-error={}
    }
  }

  :log info "v2raymik: uninstall finished"
} else={

# ==========================================================================
# INSTALL / UPGRADE
# ==========================================================================

:log info "v2raymik: installing"

# --- storage ---------------------------------------------------------------
:if ([:len [/file find where name=($MikDisk . "/tmp")]] = 0) do={
  /file add name=($MikDisk . "/tmp") type=directory
}
/container/config/set tmpdir=($MikDisk . "/tmp") registry-url=$MikRegistryUrl

# The panel's state (subscription, chosen node) lives outside the container's
# root-dir, because `/container/repull` wipes that directory on every update.
:if ([:len [/file find where name=($MikDisk . "/v2raymik-data")]] = 0) do={
  /file add name=($MikDisk . "/v2raymik-data") type=directory
}
:if ([:len [/container mounts find where list="MOUNT_MIK_DATA"]] = 0) do={
  /container mounts add list=MOUNT_MIK_DATA src=($MikDisk . "/v2raymik-data") dst=/data
}

# --- veth -------------------------------------------------------------------
# The address goes on the veth itself, with no bridge in between. Measured on
# RouterOS 7.25.1: with the veth in a bridge, the router could ARP the
# container but never delivered a packet to it. Direct on the veth, it works.
:if ([:len [/interface veth find where name=$MikVeth]] = 0) do={
  /interface veth add name=$MikVeth address=($MikContainerIp . "/24") \
    gateway=$MikGatewayIp comment="mik gateway"
}
:if ([:len [/ip address find where interface=$MikVeth and address=($MikGatewayIp . "/24")]] = 0) do={
  /ip address add address=($MikGatewayIp . "/24") interface=$MikVeth comment="mik gateway"
}

# --- container environment ---------------------------------------------------
# NODE_OUTBOUND_FILE points at the outbound file inside the container's
# root-dir (it survives a re-pull). Set NODE_LINK instead if you prefer a
# share link (do not set both).
:if ([:len [/container envs find where list=$MikContainerName and key="NODE_OUTBOUND_FILE"]] = 0) do={
  /container envs add list=$MikContainerName key=NODE_OUTBOUND_FILE \
    value="/etc/sing-box/outbound.json"
}

# The UI marks configs whose port is outside this list as blocked, so it must
# match the firewall allowlist exactly — both rules.
:local allowed $MikContainerToWanPorts
:if ([:len $MikExtraWanPorts] > 0) do={
  :set allowed ($allowed . "," . $MikExtraWanPorts)
}
:if ([:len [/container envs find where list=$MikContainerName and key="ALLOWED_PORTS"]] = 0) do={
  /container envs add list=$MikContainerName key=ALLOWED_PORTS value=$allowed
} else={
  /container envs set [find where list=$MikContainerName and key="ALLOWED_PORTS"] value=$allowed
}

# --- container ---------------------------------------------------------------
# Adding the container starts the image pull; it is not started automatically.
# Two paths: pull from a registry (MikImage) or side-load a docker-archive tar
# already uploaded to the disk (MikImageFile). The file path wins when set.
:if ([:len $MikImageFile] > 0) do={
  :if ([:len [/container find where name=$MikContainerName]] = 0) do={
    /container add name=$MikContainerName file=$MikImageFile interface=$MikVeth \
      root-dir=($MikDisk . "/" . $MikContainerName) dns=1.1.1.1 \
      envlist=$MikContainerName start-on-boot=yes restart-policy=always \
      check-certificate=$MikCheckCertificate mountlists=MOUNT_MIK_DATA \
      memory-high=100663296 logging=yes
  }
} else={
  :if ([:len [/container find where name=$MikContainerName]] = 0) do={
    /container add name=$MikContainerName remote-image=$MikImage interface=$MikVeth \
      root-dir=($MikDisk . "/" . $MikContainerName) dns=1.1.1.1 \
      envlist=$MikContainerName start-on-boot=yes restart-policy=always \
      check-certificate=$MikCheckCertificate mountlists=MOUNT_MIK_DATA \
      memory-high=100663296 logging=yes
  }
}

# 7.23+: if the TUN disappears, the container is restarted instead of sitting
# "running" with no tunnel.
:do {
  /container set [find where name=$MikContainerName] healthcheck-cmd="/bin/sh -c 'ip link show tun0 >/dev/null 2>&1'" \
    healthcheck-interval=00:01:00 healthcheck-start-period=00:00:30 stop-on-unhealthy=yes
} on-error={ :log warning "v2raymik: could not set a healthcheck (RouterOS too old?) — the container still runs" }

# --- routing ------------------------------------------------------------------
# The container's own egress must never enter the tunnel, or the transport
# carries itself. The accept must sit before every mark-routing rule.
# Likewise the router's own traffic to the LAN must travel directly; with the
# mark rules in place, a default install is otherwise unmanageable (SSH, ping,
# Winbox and DNS answers all go into the tunnel and never come back).
:local firstMark [:pick [/ip firewall mangle find where action=mark-routing] 0]
:if ([:len [/ip firewall mangle find where comment="mik: never mark the container"]] = 0) do={
  :if ([:len $firstMark] > 0) do={
    /ip firewall mangle add chain=prerouting src-address=$MikSubnet action=accept \
      comment="mik: never mark the container" place-before=$firstMark
  } else={
    /ip firewall mangle add chain=prerouting src-address=$MikSubnet action=accept \
      comment="mik: never mark the container"
  }
}
:if ([:len [/ip firewall mangle find where comment="mik: router to LAN"]] = 0) do={
  :if ([:len $firstMark] > 0) do={
    /ip firewall mangle add chain=output dst-address=$MikLanSubnet action=accept \
      comment="mik: router to LAN" place-before=$firstMark
  } else={
    /ip firewall mangle add chain=output dst-address=$MikLanSubnet action=accept \
      comment="mik: router to LAN"
  }
}

# A dedicated table carries everything that is not local and not the container.
# Everything means everything: no address-lists, no exceptions to manage or to
# rot. The connected route is what makes the tunnel's gateway reachable inside
# the table that uses it.
:local tableName "mik-tunnel"
:if ([:len [/routing table find where name=$tableName]] = 0) do={
  /routing table add name=$tableName fib
}
:if ([:len [/ip route find where comment="mik: connected to container"]] = 0) do={
  /ip route add dst-address=$MikSubnet gateway=$MikVeth routing-table=$tableName \
    comment="mik: connected to container"
}
:if ([:len [/ip route find where comment="mik: tunnel" and routing-table=$tableName]] = 0) do={
  /ip route add dst-address=0.0.0.0/0 gateway=$MikContainerIp routing-table=$tableName \
    distance=1 comment="mik: tunnel"
}

:if ([:len [/ip firewall mangle find where chain=prerouting and action=mark-routing and comment="World -> tunnel"]] = 0) do={
  /ip firewall mangle add chain=prerouting dst-address-type=!local \
    action=mark-routing new-routing-mark=$tableName passthrough=no \
    comment="World -> tunnel"
}
:if ([:len [/ip firewall mangle find where chain=output and action=mark-routing and comment="World -> tunnel (router)"]] = 0) do={
  /ip firewall mangle add chain=output dst-address-type=!local \
    action=mark-routing new-routing-mark=$tableName passthrough=no \
    comment="World -> tunnel (router)"
}

# --- MSS ----------------------------------------------------------------------
# The tunnel adds a header; without this, large TLS handshakes hang instead of
# failing, which looks like "the site is broken".
:if ([:len [/ip firewall mangle find where comment="mik: MSS clamp"]] = 0) do={
  /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss \
    new-mss=1360 tcp-mss=1361-65535 out-interface=$MikVeth comment="mik: MSS clamp"
}
:if ([:len [/ip firewall mangle find where comment="mik: MSS clamp back"]] = 0) do={
  /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss \
    new-mss=1360 tcp-mss=1361-65535 in-interface=$MikVeth comment="mik: MSS clamp back"
}
:if ([:len [/ip firewall mangle find where comment="mik: MSS clamp (router output)"]] = 0) do={
  /ip firewall mangle add chain=output protocol=tcp tcp-flags=syn action=change-mss \
    new-mss=1360 tcp-mss=1361-65535 comment="mik: MSS clamp (router output)"
}

# --- firewall: what the container may reach -----------------------------------
:local firstFwdDrop [:pick [/ip firewall filter find where chain=forward and action=drop] 0]

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

# Keep the rules in step with the variables on every import.
:foreach r in=[/ip firewall filter find where comment="mik: container tcp transport"] do={
  /ip firewall filter set $r dst-port=$MikContainerToWanPorts
}
:foreach r in=[/ip firewall filter find where comment="mik: container udp transport"] do={
  /ip firewall filter set $r dst-port=$MikContainerToWanPorts
}

# --- replies on established connections ----------------------------------------
# A LAN client that reaches the panel (or any future published service) needs
# the replies back. Devices with a stock "accept established" in the forward
# chain already allow them; stripped-down configs do not, and then the
# container's SYN-ACK hits "mik: container default deny" and the panel is
# unreachable. Connection-state accepts only here, so a fresh container still
# cannot reach out to the LAN.
:if ([:len [/ip firewall filter find where comment="mik: container replies (established)"]] = 0) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept connection-state=established,related,untracked \
      src-address=$MikSubnet comment="mik: container replies (established)" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept connection-state=established,related,untracked \
      src-address=$MikSubnet comment="mik: container replies (established)"
  }
}

# --- second pair of accept rules for extra ports (RouterOS caps at 15) --------
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

# --- default deny -------------------------------------------------------------
:if ([:len [/ip firewall filter find where comment="mik: container default deny"]] = 0) do={
  /ip firewall filter add chain=forward action=drop src-address=$MikSubnet \
    comment="mik: container default deny"
}

# --- NAT ----------------------------------------------------------------------
# One rule covers everything that enters the container: LAN clients and the
# router's own traffic. Measured on 7.25.1: the router's own packets left with
# the WAN address as source and were dropped inside the container, while the
# same packets masqueraded to the veth address went through.
:if ([:len [/ip firewall nat find where comment="mik: masquerade to container"]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade out-interface=$MikVeth \
    comment="mik: masquerade to container"
}

# --- admin page, LAN only -------------------------------------------------------
# The container listens on $MikAdminPort; the router answers on
# $MikAdminLanPort of any LAN interface. No password: anyone on the LAN can use
# the panel. There is no second guard behind in-interface-list=LAN — do not
# drop it.
:if ([:len [/ip firewall nat find where comment="mik: admin ui"]] = 0) do={
  /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp \
    dst-port=$MikAdminLanPort in-interface-list=LAN \
    to-addresses=$MikContainerIp to-ports=$MikAdminPort \
    comment="mik: admin ui"
} else={
  /ip firewall nat set [find where comment="mik: admin ui"] \
    dst-port=$MikAdminLanPort to-ports=$MikAdminPort
}

:log info "v2raymik: installed. Wait for /container/print status=stopped growing to running, then open http://<router>:$MikAdminLanPort/"
}
