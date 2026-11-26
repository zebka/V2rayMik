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
:global MikImageFallback
:global MikImageFile
:global MikCheckCertificate
:global MikRegistryUrl
:global MikAdminPort
:global MikAdminLanPort
:global MikAllowContainerToLan
:global MikBridge
:global MikRegistryFallback
:global MikTunMtu
:global MikMemoryHigh
:global MikDnsSavedServers
:global MikFasttrackSaved
:global MikFasttrackSavedMark
:global MikFasttrackSavedList
:global MikScope
:global MikSrcAddress
:global MikTouchDns
:global MikDnsSavedAllowRemote

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
# The image is pinned to the version of this file: a router must never run a
# container the repository does not describe. The tag is bumped with every
# release, and CI checks that it matches VERSION.
:if ([:typeof $MikImage] = "nothing") do={ :global MikImage "ghcr.io/zebka/v2raymik:1.3.31" }
# The fallback names the Docker Hub repository on purpose. A Docker Hub mirror
# serves the Docker Hub namespace and has never heard of ghcr.io/zebka/...,
# so swapping only the registry would silently pull nothing.
:if ([:typeof $MikImageFallback] = "nothing") do={ :global MikImageFallback "azebka/v2raymik:1.3.31" }
:if ([:typeof $MikImageFile] = "nothing") do={ :global MikImageFile "" }
:if ([:typeof $MikCheckCertificate] = "nothing") do={ :global MikCheckCertificate "yes" }
# Registry used for the pull. If you set MikRegistryUrl yourself, that registry
# is used and there is no fallback — and MikImage has to name an image that
# registry actually has (a Docker Hub mirror serves azebka/v2raymik, not
# ghcr.io/zebka/v2raymik). Otherwise GitHub Container Registry is tried first
# and, if the image does not start, MikRegistryFallback is tried with
# MikImageFallback. "" turns the fallback off.
:local registryPinned ([:typeof $MikRegistryUrl] != "nothing")
:if ([:typeof $MikRegistryUrl] = "nothing") do={ :global MikRegistryUrl "https://ghcr.io" }
:if ([:typeof $MikRegistryFallback] = "nothing") do={ :global MikRegistryFallback "https://docker.arvancloud.ir" }
# The MTU of the tunnel interface. 1400, not 1500: the transport adds its own
# header, so a 1500-byte inner packet no longer fits the WAN MTU and is
# dropped or fragmented. The router's MSS clamp only covers TCP that enters
# from the LAN; it does not cover UDP inside the tunnel, so the clamp cannot
# fix this. Set MikTunMtu to 1500 only if the path really has the room.
:if ([:typeof $MikTunMtu] = "nothing") do={ :global MikTunMtu "1400" }
# The container's memory ceiling, in bytes. 256 MiB is the ceiling the 1.3.x
# builds use and what docs/benchmarks.md measured (~113 MiB RSS under load), so
# it stays the default. On a 256 MB device it is the whole router's RAM: lower
# it (134217728 = 128 MiB is the first value worth measuring there) rather than
# letting the kernel OOM the container.
:if ([:typeof $MikMemoryHigh] = "nothing") do={ :global MikMemoryHigh "268435456" }
:if ([:typeof $MikAdminPort] = "nothing") do={ :global MikAdminPort "8080" }
:if ([:typeof $MikAdminLanPort] = "nothing") do={ :global MikAdminLanPort "8081" }
:if ([:typeof $MikAllowContainerToLan] = "nothing") do={ :global MikAllowContainerToLan false }
:if ([:typeof $MikBridge] = "nothing") do={ :global MikBridge "containers" }
:if ([:typeof $MikMode] = "nothing") do={ :global MikMode "install" }

# --- scope: what this install is allowed to route ------------------------------
# "all"    = full LAN + router output (the 1.3.x behaviour; the default so an
#            existing install never changes on re-import).
# "lan"    = all private LAN sources, no chain=output rules; port-53 DNS from
#            the LAN is redirected into the tunnel for unpoisoned answers.
# "list"   = only the sources in the user-editable mik-clients address-list,
#            with the same DNS redirect; /ip dns is never touched.
# "manual" = container, veth, table, NAT, isolation and the panel only. No
#            mangle, no FastTrack change, no /ip dns change.
:if ([:typeof $MikScope] = "nothing") do={ :global MikScope "all" }
:if ($MikScope != "all" and $MikScope != "lan" and \
     $MikScope != "list" and $MikScope != "manual") do={
  :error ("v2raymik: MikScope must be all, lan, list or manual; got " . $MikScope)
}
:local touchDns true
:if ($MikScope != "all") do={ :set touchDns false }
:if ([:typeof $MikTouchDns] != "nothing") do={
  :set touchDns $MikTouchDns
  :if ($touchDns = true and $MikScope != "all") do={
    :log warning ("v2raymik: MikTouchDns=true in scope " . $MikScope . " changes DNS for the whole router")
  }
}
:if ($MikMode != "uninstall" and $MikScope = "list" and \
     ([:typeof $MikSrcAddress] = "nothing" or [:len [:toarray $MikSrcAddress]] = 0)) do={
  :error "v2raymik: MikScope=list requires :global MikSrcAddress with at least one IP/CIDR"
}

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
  :foreach c in={"mik: never mark the container";"mik: router to LAN";"mik: keep router-direct off the tunnel";"mik: MSS clamp";"mik: MSS clamp back";"mik: MSS clamp (router output)";"World -> mik (LAN)";"World -> mik (router)";"World -> tunnel";"World -> tunnel (router)";"mik: mark tunnel connections";"mik: no tunnel for LAN/mDNS";"mik: dns to tunnel (mark udp)";"mik: dns to tunnel (mark tcp)";"mik: dns to tunnel (route udp)";"mik: dns to tunnel (route tcp)"} do={
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
  :foreach c in={"mik: container tcp transport";"mik: container udp transport";"mik: container tcp transport (extra)";"mik: container udp transport (extra)";"mik: container to LAN (opt-in)";"mik: container default deny";"mik: container replies (established)";"mik: container egress";"mik: forward to container"} do={
    :if ([:len [/ip firewall filter find where comment=$c]] > 0) do={
      /ip firewall filter remove [find where comment=$c]
    }
  }

  # --- RouterOS's own fasttrack rule (the install changed it) ---------------
  # Put the rule back the way it was found. A value that was empty when it was
  # captured comes back as an empty string, and setting a property to an empty
  # string removes it again, which is the state RouterOS ships.
  :local fasttrack [:pick [/ip firewall filter find where action=fasttrack-connection and chain=forward] 0]
  :if ([:len $fasttrack] = 0) do={
    :set fasttrack [:pick [/ip firewall filter find where comment="defconf: fasttrack"] 0]
  }
  :if ([:len $fasttrack] > 0) do={
    :if ([:typeof $MikFasttrackSaved] != "nothing") do={
      :if ([:len $MikFasttrackSavedMark] > 0) do={
        :do { /ip firewall filter set $fasttrack connection-mark=$MikFasttrackSavedMark } on-error={}
      } else={
        :do { /ip firewall filter set $fasttrack !connection-mark } on-error={}
      }
      :if ([:len $MikFasttrackSavedList] > 0) do={
        :do { /ip firewall filter set $fasttrack src-address-list=$MikFasttrackSavedList } on-error={}
      } else={
        :do { /ip firewall filter set $fasttrack !src-address-list } on-error={}
      }
    }
  }
  # Nothing to restore on a later uninstall: drop the saved originals even if
  # the fasttrack rule itself is already gone.
  :if ([:typeof $MikFasttrackSaved] != "nothing") do={
    /system script environment remove [find where name="MikFasttrackSaved"]
    /system script environment remove [find where name="MikFasttrackSavedMark"]
    /system script environment remove [find where name="MikFasttrackSavedList"]
  }

  # --- private address list (the LAN boundary since 1.3.0) ------------------
  :if ([:len [/ip firewall address-list find where comment="mik: private"]] > 0) do={
    /ip firewall address-list remove [find where comment="mik: private"]
  }
  # The client list belongs to the user as well: remove only the entries this
  # import put there. An entry edited in Winbox keeps its own (empty) comment
  # and is left in place, with a warning.
  :local userClients [:len [/ip firewall address-list find where list="mik-clients" and comment!="mik: client"]]
  :if ([:len [/ip firewall address-list find where comment="mik: client"]] > 0) do={
    /ip firewall address-list remove [find where comment="mik: client"]
  }
  :if ($userClients > 0) do={
    :log warning ("v2raymik: kept " . $userClients . " user-defined mik-clients entries; remove them by hand if you want them gone")
  }

  # --- NAT and the admin page ---------------------------------------------
  :foreach c in={"mik: masquerade to container";"mik: admin ui";"mik: LAN to container";"mik: router to container masq";"mik: container egress";"mik: dns to tunnel (udp)";"mik: dns to tunnel (tcp)"} do={
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
  # DNS: put back both values that were saved at install time. An empty saved
  # server list means the router had none; assigning "" clears the setting.
  :if ([:typeof $MikDnsSavedServers] != "nothing") do={
    :do { /ip dns set servers=$MikDnsSavedServers } on-error={}
    :if ([:typeof $MikDnsSavedAllowRemote] = "bool") do={
      :do { /ip dns set allow-remote-requests=$MikDnsSavedAllowRemote } on-error={}
    }
    :do { /ip dns cache flush } on-error={}
    /system script environment remove [find where name="MikDnsSavedServers"]
    /system script environment remove [find where name="MikDnsSavedAllowRemote"]
  }
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

# --- normalize mode-sensitive objects ----------------------------------------
# A re-import can switch scopes. Remove every rule any scope may have created
# before adding back only what the current scope needs. Objects that are common
# to all four scopes (container, veth, NAT, isolation, table, routes) are left
# alone here — re-importing keeps the running container and the chosen node.
:foreach c in={"mik: never mark the container";"mik: router to LAN";"mik: keep router-direct off the tunnel";"mik: MSS clamp";"mik: MSS clamp back";"mik: MSS clamp (router output)";"World -> mik (LAN)";"World -> mik (router)";"World -> tunnel";"World -> tunnel (router)";"mik: mark tunnel connections";"mik: no tunnel for LAN/mDNS";"mik: dns to tunnel (mark udp)";"mik: dns to tunnel (mark tcp)";"mik: dns to tunnel (route udp)";"mik: dns to tunnel (route tcp)"} do={
  :if ([:len [/ip firewall mangle find where comment=$c]] > 0) do={
    /ip firewall mangle remove [find where comment=$c]
  }
}
:foreach c in={"mik: dns to tunnel (udp)";"mik: dns to tunnel (tcp)"} do={
  :if ([:len [/ip firewall nat find where comment=$c]] > 0) do={
    /ip firewall nat remove [find where comment=$c]
  }
}
:if ([:len [/ip firewall filter find where comment="mik: forward to container"]] > 0) do={
  /ip firewall filter remove [find where comment="mik: forward to container"]
}
# Remove only the entries this import created in mik-clients; a user's own
# entries (no "mik: client" comment) survive a switch away from "list".
:if ([:len [/ip firewall address-list find where comment="mik: client"]] > 0) do={
  /ip firewall address-list remove [find where comment="mik: client"]
}

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

# The MTU the tunnel interface gets. The entrypoint reads TUN_MTU and writes
# it into the sing-box tun inbound; unset it means 1500, which is too large
# for a tunnel that adds a header.
:if ([:len [/container envs find where list=$MikContainerName and key="TUN_MTU"]] = 0) do={
  /container envs add list=$MikContainerName key=TUN_MTU value=$MikTunMtu
} else={
  :do { /container envs set [find where list=$MikContainerName and key="TUN_MTU"] value=$MikTunMtu } on-error={}
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
      memory-high=$MikMemoryHigh logging=yes
    :set fresh true
  }
} else={
  :if ([:len [/container find where name=$MikContainerName]] = 0) do={
    /container add name=$MikContainerName remote-image=$MikImage interface=$MikVeth \
      root-dir=$rootDir dns=1.1.1.1 \
      envlist=$MikContainerName start-on-boot=yes restart-policy=always \
      check-certificate=$MikCheckCertificate mountlists=MOUNT_MIK_DATA \
      memory-high=$MikMemoryHigh logging=yes
    :set fresh true
  }
}

# Start a just-added container as soon as the pull has produced a startable
# one, retrying while the pull is still running. A pull that dies half-way
# (Connection reset by peer, HTTP 502) leaves the container stopped and
# nothing starts it, so the pull is asked for again once before the registry
# is given up on.
:if ($fresh) do={
  :log info "v2raymik: waiting for the image pull to finish, then starting the container"
  :local started false
  :local attempt 0
  :while ($attempt < 2) do={
    :set attempt ($attempt + 1)
    :if ($started = false) do={
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
      :if ($started = false) do={
        # The pull is asked for again once, after the first failed wait. The
        # second failure must not start another pull: the fallback below stops
        # and removes this container, and a pull in flight fights the removal.
        :if ($attempt < 2) do={
          :log warning ("v2raymik: the image did not start (attempt " . $attempt . "); pulling it again")
          :do { /container/repull [find where name=$MikContainerName] } on-error={ :log warning "v2raymik: this RouterOS cannot re-pull an image; trying the fallback registry" }
        } else={
          :log warning ("v2raymik: the image did not start (attempt " . $attempt . "); giving up on this registry, using the fallback")
        }
      }
    }
  }
  :if ($started = true) do={
    :log info "v2raymik: container started"
  } else={
    :if ($registryPinned = false and [:len $MikRegistryFallback] > 0 and [:len $MikImageFile] = 0) do={
      :log warning ("v2raymik: the official registry did not deliver the image; trying " . $MikRegistryFallback . " with certificate checks off")
      :do { /container stop [find where name=$MikContainerName] } on-error={}
      :local gone false
      :for i from=1 to=40 do={
        :if ($gone = false) do={
          :do {
            /container remove [find where name=$MikContainerName]
            :set gone true
          } on-error={ :delay 1s }
        }
      }
      /container/config/set registry-url=$MikRegistryFallback
      # The mirror serves the image with a certificate the router does not
      # trust (measured on 7.25.1), so the check is off here — the log line
      # above already says so.
      /container add name=$MikContainerName remote-image=$MikImageFallback interface=$MikVeth \
        root-dir=$rootDir dns=1.1.1.1 \
        envlist=$MikContainerName start-on-boot=yes restart-policy=always \
        check-certificate=no mountlists=MOUNT_MIK_DATA \
        memory-high=$MikMemoryHigh logging=yes
      :for i from=1 to=60 do={
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
    }
    :if ($started = true) do={
      :log info "v2raymik: container started"
    } else={
      :log warning "v2raymik: the image pull is still running; run /container start $MikContainerName once it finishes"
    }
  }
}

# 7.23+: if the TUN disappears, the container is restarted instead of sitting
# "running" with no tunnel. The check looks for tun0 AND makes one small
# request, because a live process with a dead tunnel still passes the first
# test. wget is in the image (busybox-extras). One request is not a
# throughput test: a healthy container can still be too slow for big
# downloads. The longer timeout (wget -T 10) and start-period (90s) keep a
# slow boot from killing the container on the first check. Before a node is
# configured there is no tunnel to check, so the probe passes: RouterOS must
# not count failed tries and restart the container while the user is still
# adding a node in the panel.
:do {
  /container set [find where name=$MikContainerName] healthcheck-cmd="/bin/sh -c 'if [ ! -f /data/state.json ] && ! env | grep -q ^NODE_LINK=. && [ ! -f /etc/sing-box/outbound.json ]; then exit 0; fi; ip link show tun0 >/dev/null 2>&1 && pidof sing-box >/dev/null 2>&1 && wget -q -T 10 -O /dev/null http://www.gstatic.com/generate_204'" \
    healthcheck-interval=00:01:00 healthcheck-start-period=00:01:30 healthcheck-retries=8 stop-on-unhealthy=yes memory-high=$MikMemoryHigh
} on-error={ :log warning "v2raymik: could not set a healthcheck (RouterOS too old?) — the container still runs" }

# --- routing ------------------------------------------------------------------
# A dedicated table carries the traffic this install marks. The connected route
# makes the tunnel's gateway reachable inside it; the default route is
# fail-closed (no ISP fallback). Which packets get marked is decided by
# $MikScope in the blocks below. Common plumbing is installed in every mode.
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

# The first prerouting mark-routing rule — operator-owned or ours. Declared
# outside the scope blocks so every block can place its rules above it, and
# restricted to prerouting so an existing output rule is never matched.
:local firstMark [:pick [/ip firewall mangle find where chain=prerouting and action=mark-routing] 0]

# --- scope: common (all, lan, list) -------------------------------------------
# The container's own traffic must never enter the tunnel, multicast/mDNS stays
# on the LAN, and TCP through the tunnel needs the MSS clamp. "manual" installs
# no mangle rules at all; the operator writes these if wanted.
:if ($MikScope != "manual") do={
  :if ([:len [/ip firewall mangle find where comment="mik: never mark the container"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address=$MikSubnet action=accept \
        comment="mik: never mark the container" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address=$MikSubnet action=accept \
        comment="mik: never mark the container"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: no tunnel for LAN/mDNS"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting dst-address=224.0.0.0/4 action=accept \
        comment="mik: no tunnel for LAN/mDNS" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting dst-address=224.0.0.0/4 action=accept \
        comment="mik: no tunnel for LAN/mDNS"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: MSS clamp"]] = 0) do={
    /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss \
      new-mss=1360 tcp-mss=1361-65535 out-interface=$MikVeth comment="mik: MSS clamp"
  }
  :if ([:len [/ip firewall mangle find where comment="mik: MSS clamp back"]] = 0) do={
    /ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss \
      new-mss=1360 tcp-mss=1361-65535 in-interface=$MikVeth comment="mik: MSS clamp back"
  }
}

# --- scope: all ---------------------------------------------------------------
# Full tunnel: every non-local, non-private destination from any LAN source and
# from the router itself. This is the 1.3.x behaviour and the default.
:if ($MikScope = "all") do={
  :if ([:len [/ip firewall mangle find where comment="mik: mark tunnel connections"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting dst-address-type=!local dst-address-list=!mik-private \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: mark tunnel connections" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting dst-address-type=!local dst-address-list=!mik-private \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: mark tunnel connections"
    }
  }
  :if ([:len [/ip firewall mangle find where chain=prerouting and action=mark-routing and comment="World -> tunnel"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting dst-address-type=!local dst-address-list=!mik-private \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="World -> tunnel" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting dst-address-type=!local dst-address-list=!mik-private \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="World -> tunnel"
    }
  }
  :local firstOutMark [:pick [/ip firewall mangle find where chain=output and action=mark-routing] 0]
  :if ([:len [/ip firewall mangle find where comment="mik: router to LAN"]] = 0) do={
    :if ([:len $firstOutMark] > 0) do={
      /ip firewall mangle add chain=output dst-address-list=mik-private action=accept \
        comment="mik: router to LAN" place-before=$firstOutMark
    } else={
      /ip firewall mangle add chain=output dst-address-list=mik-private action=accept \
        comment="mik: router to LAN"
    }
  }
  :if ([:len [/ip firewall mangle find where chain=output and action=mark-routing and comment="World -> tunnel (router)"]] = 0) do={
    /ip firewall mangle add chain=output dst-address-type=!local \
      action=mark-routing new-routing-mark=$tableName passthrough=no \
      comment="World -> tunnel (router)"
  }
  :if ([:len [/ip firewall mangle find where comment="mik: MSS clamp (router output)"]] = 0) do={
    /ip firewall mangle add chain=output protocol=tcp tcp-flags=syn action=change-mss \
      new-mss=1360 tcp-mss=1361-65535 comment="mik: MSS clamp (router output)"
  }
}

# --- scope: lan ---------------------------------------------------------------
# Every private LAN source, but no chain=output rules: Winbox, SSH, WireGuard
# and other router-originated traffic keep the main table. Port 53 sent to the
# router by a LAN client is redirected into the tunnel so the answer cannot be
# poisoned; in-interface=("!" . veth) keeps the container's own DNS out of it.
:if ($MikScope = "lan") do={
  :if ([:len [/ip firewall mangle find where comment="mik: mark tunnel connections"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=!local dst-address-list=!mik-private \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: mark tunnel connections" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=!local dst-address-list=!mik-private \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: mark tunnel connections"
    }
  }
  :if ([:len [/ip firewall mangle find where chain=prerouting and action=mark-routing and comment="World -> tunnel"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=!local dst-address-list=!mik-private \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="World -> tunnel" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=!local dst-address-list=!mik-private \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="World -> tunnel"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: dns to tunnel (mark udp)"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=local protocol=udp dst-port=53 \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: dns to tunnel (mark udp)" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=local protocol=udp dst-port=53 \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: dns to tunnel (mark udp)"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: dns to tunnel (mark tcp)"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=local protocol=tcp dst-port=53 \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: dns to tunnel (mark tcp)" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=local protocol=tcp dst-port=53 \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: dns to tunnel (mark tcp)"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: dns to tunnel (route udp)"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=local protocol=udp dst-port=53 \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="mik: dns to tunnel (route udp)" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=local protocol=udp dst-port=53 \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="mik: dns to tunnel (route udp)"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: dns to tunnel (route tcp)"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=local protocol=tcp dst-port=53 \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="mik: dns to tunnel (route tcp)" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-private \
        dst-address-type=local protocol=tcp dst-port=53 \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="mik: dns to tunnel (route tcp)"
    }
  }
  :if ([:len [/ip firewall nat find where comment="mik: dns to tunnel (udp)"]] = 0) do={
    /ip firewall nat add chain=dstnat action=dst-nat protocol=udp dst-port=53 \
      src-address-list=mik-private dst-address-type=local in-interface=("!" . $MikVeth) \
      to-addresses=1.1.1.1 to-ports=53 comment="mik: dns to tunnel (udp)"
  }
  :if ([:len [/ip firewall nat find where comment="mik: dns to tunnel (tcp)"]] = 0) do={
    /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-port=53 \
      src-address-list=mik-private dst-address-type=local in-interface=("!" . $MikVeth) \
      to-addresses=1.1.1.1 to-ports=53 comment="mik: dns to tunnel (tcp)"
  }
}

# --- scope: list --------------------------------------------------------------
# Only the addresses in mik-clients. The import owns the entries it tagged
# "mik: client" and rewrites them from MikSrcAddress on every import; entries a
# user adds in Winbox without that comment are never removed.
:if ($MikScope = "list") do={
  # :foreach over a string is not iteration in RouterOS: a single IP or a
  # comma-separated string stays one element and mik-clients would be empty.
  # Convert both accepted forms to an array before the loop below.
  :if ([:typeof $MikSrcAddress] = "str") do={
    :set MikSrcAddress [:toarray $MikSrcAddress]
  }
  :if ([:typeof $MikSrcAddress] != "array") do={
    :error "v2raymik: MikSrcAddress must be an array or a comma-separated string"
  }
  :foreach a in=$MikSrcAddress do={
    :local addr [:tostr $a]
    # [:toarray] of "a, b" leaves a leading space on " b"; strip it or the
    # address-list add below fails on a value such as " 10.20.30.5".
    :while ([:len $addr] > 0 and ([:pick $addr 0] = " " or [:pick $addr 0] = "\t")) do={
      :set addr [:pick $addr 1 [:len $addr]]
    }
    :while ([:len $addr] > 0 and ([:pick $addr ([:len $addr] - 1)] = " " or [:pick $addr ([:len $addr] - 1)] = "\t")) do={
      :set addr [:pick $addr 0 ([:len $addr] - 1)]
    }
    :if ([:len $addr] > 0) do={
      :if ([:len [/ip firewall address-list find where list="mik-clients" and address=$addr and comment="mik: client"]] = 0) do={
        /ip firewall address-list add list="mik-clients" address=$addr comment="mik: client"
      }
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: mark tunnel connections"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=!local dst-address-list=!mik-private \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: mark tunnel connections" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=!local dst-address-list=!mik-private \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: mark tunnel connections"
    }
  }
  :if ([:len [/ip firewall mangle find where chain=prerouting and action=mark-routing and comment="World -> tunnel"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=!local dst-address-list=!mik-private \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="World -> tunnel" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=!local dst-address-list=!mik-private \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="World -> tunnel"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: dns to tunnel (mark udp)"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=local protocol=udp dst-port=53 \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: dns to tunnel (mark udp)" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=local protocol=udp dst-port=53 \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: dns to tunnel (mark udp)"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: dns to tunnel (mark tcp)"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=local protocol=tcp dst-port=53 \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: dns to tunnel (mark tcp)" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=local protocol=tcp dst-port=53 \
        action=mark-connection new-connection-mark=mik-conn passthrough=yes \
        comment="mik: dns to tunnel (mark tcp)"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: dns to tunnel (route udp)"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=local protocol=udp dst-port=53 \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="mik: dns to tunnel (route udp)" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=local protocol=udp dst-port=53 \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="mik: dns to tunnel (route udp)"
    }
  }
  :if ([:len [/ip firewall mangle find where comment="mik: dns to tunnel (route tcp)"]] = 0) do={
    :if ([:len $firstMark] > 0) do={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=local protocol=tcp dst-port=53 \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="mik: dns to tunnel (route tcp)" place-before=$firstMark
    } else={
      /ip firewall mangle add chain=prerouting src-address-list=mik-clients \
        dst-address-type=local protocol=tcp dst-port=53 \
        action=mark-routing new-routing-mark=$tableName passthrough=no \
        comment="mik: dns to tunnel (route tcp)"
    }
  }
  :if ([:len [/ip firewall nat find where comment="mik: dns to tunnel (udp)"]] = 0) do={
    /ip firewall nat add chain=dstnat action=dst-nat protocol=udp dst-port=53 \
      src-address-list=mik-clients dst-address-type=local in-interface=("!" . $MikVeth) \
      to-addresses=1.1.1.1 to-ports=53 comment="mik: dns to tunnel (udp)"
  }
  :if ([:len [/ip firewall nat find where comment="mik: dns to tunnel (tcp)"]] = 0) do={
    /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-port=53 \
      src-address-list=mik-clients dst-address-type=local in-interface=("!" . $MikVeth) \
      to-addresses=1.1.1.1 to-ports=53 comment="mik: dns to tunnel (tcp)"
  }
}

# --- scope: manual ------------------------------------------------------------
# No mangle rules, no FastTrack change and no /ip dns change. The operator's own
# rules point at new-routing-mark=$tableName.

# --- FastTrack ---------------------------------------------------------------
# RouterOS's fasttrack rule sends established connections past mangle. Marked
# connections must skip it or they leave by the WAN. In manual mode nothing is
# marked by us, so the rule is left as found and saved originals are put back.
:local fasttrack [:pick [/ip firewall filter find where action=fasttrack-connection and chain=forward] 0]
:if ([:len $fasttrack] = 0) do={
  :set fasttrack [:pick [/ip firewall filter find where comment="defconf: fasttrack"] 0]
}
:if ($MikScope = "manual") do={
  :if ([:len $fasttrack] > 0 and [:typeof $MikFasttrackSaved] != "nothing") do={
    :if ([:len $MikFasttrackSavedMark] > 0) do={
      :do { /ip firewall filter set $fasttrack connection-mark=$MikFasttrackSavedMark } on-error={}
    } else={
      :do { /ip firewall filter set $fasttrack !connection-mark } on-error={}
    }
    :if ([:len $MikFasttrackSavedList] > 0) do={
      :do { /ip firewall filter set $fasttrack src-address-list=$MikFasttrackSavedList } on-error={}
    } else={
      :do { /ip firewall filter set $fasttrack !src-address-list } on-error={}
    }
  }
  :if ([:typeof $MikFasttrackSaved] != "nothing") do={
    /system script environment remove [find where name="MikFasttrackSaved"]
    /system script environment remove [find where name="MikFasttrackSavedMark"]
    /system script environment remove [find where name="MikFasttrackSavedList"]
  }
} else={
  :if ([:len $fasttrack] > 0) do={
    :if ([:typeof $MikFasttrackSaved] = "nothing") do={
      :global MikFasttrackSaved true
      :do { :global MikFasttrackSavedMark [/ip firewall filter get $fasttrack connection-mark] } on-error={ :global MikFasttrackSavedMark "" }
      :do { :global MikFasttrackSavedList [/ip firewall filter get $fasttrack src-address-list] } on-error={ :global MikFasttrackSavedList "" }
    }
    /ip firewall filter set $fasttrack connection-mark=no-mark
  }
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
# A strict forward chain that only permits out-interface-list=WAN would drop
# LAN -> veth traffic and the panel would be unreachable. One accept above the
# first drop fixes that without opening anything else (the container's own
# filter rules decide what it may reach). Manual mode owns its own forward chain.
:if ($MikScope != "manual" and [:len [/ip firewall filter find where comment="mik: forward to container"]] = 0) do={
  :if ([:len $firstFwdDrop] > 0) do={
    /ip firewall filter add chain=forward out-interface=$MikVeth \
      connection-state=new,established,related action=accept \
      comment="mik: forward to container" place-before=$firstFwdDrop
  } else={
    /ip firewall filter add chain=forward out-interface=$MikVeth \
      connection-state=new,established,related action=accept \
      comment="mik: forward to container"
  }
}
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

# --- DNS upstream -------------------------------------------------------------
# Only scope "all" (or an explicit MikTouchDns=true) changes the router's own
# resolver: its queries leave in chain=output, which is marked in that scope.
# In lan/list/manual the router's DNS and management stay on the main table;
# lan and list give their clients unpoisoned DNS with the port-53 redirect
# above instead. Both original values are saved for mode switches/uninstall.
:if ($touchDns = true) do={
  :if ([:typeof $MikDnsSavedServers] = "nothing") do={
    :global MikDnsSavedServers [/ip dns get servers]
    :global MikDnsSavedAllowRemote [/ip dns get allow-remote-requests]
  }
  :if ([/ip dns get servers] != "1.1.1.1,8.8.8.8" or [:typeof $MikDnsSavedAllowRemote] = "nothing") do={
    /ip dns set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes
    /ip dns cache flush
  }
} else={
  :if ([:typeof $MikDnsSavedServers] != "nothing") do={
    :do { /ip dns set servers=$MikDnsSavedServers } on-error={}
    :if ([:typeof $MikDnsSavedAllowRemote] = "bool") do={
      :do { /ip dns set allow-remote-requests=$MikDnsSavedAllowRemote } on-error={}
    }
    :do { /ip dns cache flush } on-error={}
    /system script environment remove [find where name="MikDnsSavedServers"]
    /system script environment remove [find where name="MikDnsSavedAllowRemote"]
  }
}

:log info ("v2raymik: installed in scope " . $MikScope . "; the panel comes up at http://<router>:$MikAdminLanPort/ once the container is running")
# What to look at afterwards. The MTU is the one that fails quietly: pages load
# and large downloads hang, which reads as "the tunnel is slow" and is not.
:log info "v2raymik: verify 1 - the tunnel MTU must be 1400: /container shell $MikContainerName cmd=\"grep mtu /etc/sing-box/config.json\""
:log info "v2raymik: verify 2 - the marked connections: /ip firewall connection print count-only where connection-mark=mik-conn"
:log info "v2raymik: verify 3 - fasttrack only takes unmarked connections: /ip firewall filter print where comment=\"defconf: fasttrack\""
:log info "v2raymik: verify 4 - connections opened before this import keep their old route; /ip firewall connection remove [find] clears them"
}
