# v2raymik — the whole project in one RouterOS import.
#
#   Install / upgrade:   /import file-name=v2raymik.rsc
#   Uninstall:           :global MikMode "uninstall"
#                        /import file-name=v2raymik.rsc
#                        (MikMode is reset to "install" when the uninstall finishes,
#                        so a reinstall in the same terminal works without a new one)
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
# through the dst-nat at the bottom of this file, and only from a private
# (RFC1918) source address. Do not expose it to the WAN.
#
# Nothing in this file names one of your interfaces or disks: there is no
# etherN, no interface list and no port list to adapt per router. The disk is
# detected; the LAN is the private address ranges; node ports belong to
# whoever runs the node and are not filtered.
#
# If you upgrade from a 1.x install, run uninstall first, then install again:
# the uninstall mode below also removes the objects the old 00–05 scripts made
# (table `to-world`, routes `mik-world`/`mik-fallback`, "MSS clamp (router
# output)", MOUNT_MIK_DATA).

# --- the knobs. everything else is derived. --------------------------------
:global MikMode
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
:global MikAllowContainerToLan
:global MikBridge

# Sensible defaults; override before the import in the same terminal session.
# MikDisk is the one knob that varies per device, so it is detected: the first
# candidate that exists as a disk directory, with the partitioned mount
# (`<disk>-part1`) as the fallback — a formatted USB stick usually mounts as
# `usb2-part1`, not `usb2`. Pinning MikDisk on USB storage is fragile: on some
# hardware the same stick enumerates as usb1 after a reboot. Auto-detect is
# the stable choice. Set it yourself only to pin a specific disk — then it
# must exist, and the import stops with an error that lists what IS there,
# instead of quietly creating a junk directory under a name that is not
# (measured on 7.25.1: `/file add name="nodisk/x"` succeeds and leaves junk).
:if ([:typeof $MikDisk] = "nothing") do={
  :local found ""
  :foreach d in={"usb1";"usb2";"usb3";"sata1";"sata2";"nvme1";"pcie1";"pcie2";"mmc1";"sd1";"nand1";"flash";"data"} do={
    :if ([:len $found] = 0) do={
      :if ([:len [/file find where name=$d and (type="directory" or type="disk")]] > 0) do={
        :set found $d
      } else={
        :if ([:len [/file find where name=($d . "-part1") and (type="directory" or type="disk")]] > 0) do={
          :set found ($d . "-part1")
        }
      }
    }
  }
  :global MikDisk $found
} else={
  :if ([:len $MikDisk] > 0) do={
    :if ([:len [/file find where name=$MikDisk and (type="directory" or type="disk")]] = 0) do={
      :local dirs ""
      :foreach f in=[/file find where (type="directory" or type="disk")] do={
        :local n [/file get $f name]
        :if ([:len [:find $n "/"]] = 0) do={ :set dirs ($dirs . " " . $n) }
      }
      :error ("v2raymik: MikDisk " . $MikDisk . " does not exist on this router; existing mounts:" . $dirs . " - unset :global MikDisk and import again to auto-detect")
    }
  }
}
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
:if ([:typeof $MikAllowContainerToLan] = "nothing") do={ :global MikAllowContainerToLan false }
:if ([:typeof $MikBridge] = "nothing") do={ :global MikBridge "containers" }
:if ([:typeof $MikMode] = "nothing") do={ :global MikMode "install" }

:if ($MikMode = "uninstall") do={
# =========================================================================
# UNINSTALL — remove every object this file creates (and the legacy ones).
# Routing goes first, so traffic leaves the tunnel immediately.
# =========================================================================
  :log warning "v2raymik: uninstalling"
  :local pfx ""
  :if ([:len $MikDisk] > 0) do={ :set pfx ($MikDisk . "/") }
  :local tmpDir ($pfx . "tmp")
  :local dataDir ($pfx . "v2raymik-data")
  :local rootDir ($pfx . $MikContainerName)

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
  :foreach c in={"mik: container tcp transport";"mik: container udp transport";"mik: container tcp transport (extra)";"mik: container udp transport (extra)";"mik: container to LAN (opt-in)";"mik: container default deny";"mik: container replies (established)";"mik: container egress"} do={
    :if ([:len [/ip firewall filter find where comment=$c]] > 0) do={
      /ip firewall filter remove [find where comment=$c]
    }
  }

  # --- private address list (the LAN boundary since 1.3.0) ------------------
  :if ([:len [/ip firewall address-list find where comment="mik: private"]] > 0) do={
    /ip firewall address-list remove [find where comment="mik: private"]
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
    :local removed false
    :for i from=1 to=40 do={
      :if ($removed = false) do={
        :do {
          /container remove [find where name=$MikContainerName]
          :set removed true
        } on-error={ :delay 1s }
      }
    }
    :if ($removed = false) do={
      :error "v2raymik: the container did not stop in time; run /container stop v2raymik, wait, then import again"
    }
  }
  # --- files and folders the install created --------------------------------
  # The image store (root-dir), the tmp dir and the data dir. The data dir holds
  # the subscription and the chosen node, so uninstall deletes them too.
  :foreach p in={$rootDir;$dataDir;$tmpDir} do={
    :for i from=1 to=20 do={
      :if ([:len [/file find where name=$p]] > 0) do={
        :do { /file remove [find where name=$p] } on-error={ :delay 1s }
      }
    }
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

  /system script environment remove [find where name="MikDisk"]
  :log info "v2raymik: uninstall finished"
  :global MikMode "install"
  # last: the script file that is running this uninstall
  :do { /file remove [find where name="v2raymik.rsc"] } on-error={ :log warning "v2raymik: could not remove v2raymik.rsc" }
} else={

# ==========================================================================
# INSTALL / UPGRADE
# ==========================================================================

:log info "v2raymik: installing"

# Paths: most devices mount their storage as a named disk (usb2, flash, ...), a
# few expose the root itself. $MikDisk is empty in the second case and every
# path below is then built without a prefix.
:local pfx ""
:if ([:len $MikDisk] > 0) do={ :set pfx ($MikDisk . "/") }
:local tmpDir ($pfx . "tmp")
:local dataDir ($pfx . "v2raymik-data")
:local rootDir ($pfx . $MikContainerName)

# --- the private ranges -------------------------------------------------------
# One fixed list stands for "the LAN" everywhere below: nothing about your
# network has to be guessed or typed in. Router-originated traffic to these
# ranges bypasses the tunnel, the container is kept out of them, and the panel
# answers only to a source in them.
:foreach a in={"127.0.0.0/8";"10.0.0.0/8";"172.16.0.0/12";"192.168.0.0/16";"169.254.0.0/16"} do={
  :if ([:len [/ip firewall address-list find where list="mik-private" and address=$a]] = 0) do={
    /ip firewall address-list add list="mik-private" address=$a comment="mik: private"
  }
}

# --- storage ---------------------------------------------------------------
:if ([:len [/file find where name=$tmpDir]] = 0) do={
  /file add name=$tmpDir type=directory
}
/container/config/set tmpdir=$tmpDir registry-url=$MikRegistryUrl

# The panel's state (subscription, chosen node) lives outside the container's
# root-dir, because `/container/repull` wipes that directory on every update.
:if ([:len [/file find where name=$dataDir]] = 0) do={
  /file add name=$dataDir type=directory
}
:if ([:len [/container mounts find where list="MOUNT_MIK_DATA"]] = 0) do={
  /container mounts add list=MOUNT_MIK_DATA src=$dataDir dst=/data
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

# The egress allowlist is gone (1.3.0): the firewall no longer filters by port
# and the panel no longer marks rows `port blocked`. Drop the env so an older
# image does not keep enforcing a list that nothing maintains anymore.
:if ([:len [/container envs find where list=$MikContainerName and key="ALLOWED_PORTS"]] > 0) do={
  /container envs remove [find where list=$MikContainerName and key="ALLOWED_PORTS"]
}

# --- container ---------------------------------------------------------------
# Adding the container starts the image pull; the pull runs in the background
# and nothing starts the container when it is done (measured on 7.25.1: a
# freshly added container sits "stopped" forever until started by hand).
# Two paths: pull from a registry (MikImage) or side-load a docker-archive tar
# already uploaded to the disk (MikImageFile). The file path wins when set.
:local fresh false
:if ([:len $MikImageFile] > 0) do={
  :if ([:len [/container find where name=$MikContainerName]] = 0) do={
    /container add name=$MikContainerName file=$MikImageFile interface=$MikVeth \
      root-dir=$rootDir dns=1.1.1.1 \
      envlist=$MikContainerName start-on-boot=yes restart-policy=always \
      check-certificate=$MikCheckCertificate mountlists=MOUNT_MIK_DATA \
      memory-high=100663296 logging=yes
    :set fresh true
  }
} else={
  :if ([:len [/container find where name=$MikContainerName]] = 0) do={
    /container add name=$MikContainerName remote-image=$MikImage interface=$MikVeth \
      root-dir=$rootDir dns=1.1.1.1 \
      envlist=$MikContainerName start-on-boot=yes restart-policy=always \
      check-certificate=$MikCheckCertificate mountlists=MOUNT_MIK_DATA \
      memory-high=100663296 logging=yes
    :set fresh true
  }
}

# Start a just-added container as soon as the pull has produced a startable
# one, retrying while the pull is still running. Up to ~3 minutes; on a very
# slow link the pull can outlast this — run /container start by hand then.
:if ($fresh) do={
  :log info "v2raymik: waiting for the image pull to finish, then starting the container"
  :local started false
  :for i from=1 to=40 do={
    :if ($started = false) do={
      :do {
        /container start [find where name=$MikContainerName]
        :delay 2s
        :if ([:len [/container find where name=$MikContainerName and stopped]] = 0) do={
          :set started true
        }
      } on-error={ :delay 3s }
    }
    :if ($started = false) do={ :delay 2s }
  }
  :if ($started = true) do={
    :log info "v2raymik: container started"
  } else={
    :log warning "v2raymik: the image pull is still running; run /container start $MikContainerName once it finishes"
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
# Router-originated traffic to a private destination (an LAN client's reply, a
# ping to the upstream gateway) must travel directly, or the answer disappears
# into the tunnel. Since 1.3.0 this matches the fixed mik-private ranges
# instead of a guessed MikLanSubnet, which on most routers was one wrong guess.
:if ([:len [/ip firewall mangle find where comment="mik: router to LAN" and dst-address-list!="mik-private"]] > 0) do={
  /ip firewall mangle remove [find where comment="mik: router to LAN"]
}
:if ([:len [/ip firewall mangle find where comment="mik: router to LAN"]] = 0) do={
  :if ([:len $firstMark] > 0) do={
    /ip firewall mangle add chain=output dst-address-list=mik-private action=accept \
      comment="mik: router to LAN" place-before=$firstMark
  } else={
    /ip firewall mangle add chain=output dst-address-list=mik-private action=accept \
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
# Since 1.3.0 there is no port allowlist: a node's ports are chosen by whoever
# runs the node and are never known in advance, so filtering by port only broke
# real configs silently (the engine redialed forever and nothing was logged).
# The container may reach any public destination; the private ranges in the
# fixed mik-private list stay closed — they are what MikLanSubnet used to guess.
# MikAllowContainerToLan=true widens the accept to those ranges as well.

# --- migration: the ≤1.2.x port rules are gone --------------------------------
:foreach c in={"mik: container tcp transport";"mik: container udp transport";"mik: container tcp transport (extra)";"mik: container udp transport (extra)";"mik: container to LAN (opt-in)"} do={
  :if ([:len [/ip firewall filter find where comment=$c]] > 0) do={
    /ip firewall filter remove [find where comment=$c]
  }
}

# --- replies on established connections ----------------------------------------
# A LAN client that reaches the panel (or any future published service) needs
# the replies back. Devices with a stock "accept established" in the forward
# chain already allow them; stripped-down configs do not, and then the
# container's SYN-ACK hits "mik: container default deny" and the panel is
# unreachable. Connection-state accepts only here, so a fresh container still
# cannot reach out to the LAN.
:local firstFwdDrop [:pick [/ip firewall filter find where chain=forward and action=drop] 0]
:if ([:len [/ip firewall filter find where comment="mik: container replies (established)"]] = 0) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept connection-state=established,related,untracked \
      src-address=$MikSubnet comment="mik: container replies (established)" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept connection-state=established,related,untracked \
      src-address=$MikSubnet comment="mik: container replies (established)"
  }
}

# --- egress --------------------------------------------------------------------
# No ports, no interface names: any public destination, only the private
# ranges are refused (mik-private). The pair is rebuilt on every import —
# two rules, and the knob can change between imports. MikAllowContainerToLan
# widens the accept to everything and then there is no deny rule: an accept
# behind someone else's drop would be dead weight.
:if ([:len [/ip firewall filter find where comment="mik: container egress"]] > 0) do={
  /ip firewall filter remove [find where comment="mik: container egress"]
}
:if ([:len [/ip firewall filter find where comment="mik: container default deny"]] > 0) do={
  /ip firewall filter remove [find where comment="mik: container default deny"]
}
# the removals above may have taken the rule firstFwdDrop pointed at
:set firstFwdDrop [:pick [/ip firewall filter find where chain=forward and action=drop] 0]
:if ($MikAllowContainerToLan = true) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      comment="mik: container egress" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      comment="mik: container egress"
  }
} else={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      dst-address-list=!mik-private comment="mik: container egress" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward action=accept src-address=$MikSubnet \
      dst-address-list=!mik-private comment="mik: container egress"
  }
  :if ([:len [/ip firewall filter find where comment="mik: container default deny"]] = 0) do={
    /ip firewall filter add chain=forward action=drop src-address=$MikSubnet \
      comment="mik: container default deny"
  }
}

# --- NAT ----------------------------------------------------------------------
# Two rules. The first covers everything that enters the container: LAN
# clients and the router's own traffic. Measured on 7.25.1: the router's own
# packets left with the WAN address as source and were dropped inside the
# container, while the same packets masqueraded to the veth address went
# through. The second NATs the container's own egress — the tunnel's
# transport — which leaves with the container's address as source and is
# dropped upstream unless masqueraded. A typical router's whole-WAN
# masquerade happens to cover it; the project does not rely on that.
:if ([:len [/ip firewall nat find where comment="mik: masquerade to container"]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade out-interface=$MikVeth \
    comment="mik: masquerade to container"
}
:if ([:len [/ip firewall nat find where comment="mik: container egress"]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade src-address=$MikSubnet \
    comment="mik: container egress"
}

# --- admin page, private sources only ------------------------------------------
# The container listens on $MikAdminPort; the router answers on
# $MikAdminLanPort for a source in mik-private (RFC1918 + link-local), which
# is what "the LAN" means without naming an interface list. No password:
# anyone on the LAN can use the panel. There is no second guard behind
# src-address-list=mik-private — do not drop it.
# A ≤1.2.x rule guarded by in-interface-list=LAN is rebuilt: on a router
# whose LAN list is empty or wrong, that guard is either absent or wrong.
:if ([:len [/ip firewall nat find where comment="mik: admin ui" and src-address-list!="mik-private"]] > 0) do={
  /ip firewall nat remove [find where comment="mik: admin ui"]
}
:if ([:len [/ip firewall nat find where comment="mik: admin ui"]] = 0) do={
  /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp \
    dst-port=$MikAdminLanPort src-address-list=mik-private \
    to-addresses=$MikContainerIp to-ports=$MikAdminPort \
    comment="mik: admin ui"
} else={
  /ip firewall nat set [find where comment="mik: admin ui"] \
    dst-port=$MikAdminLanPort to-ports=$MikAdminPort
}

:log info "v2raymik: installed; the panel comes up at http://<router>:$MikAdminLanPort/ once the container is running"
}
