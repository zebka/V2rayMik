# 90-migrate-from-xray.rsc — carry a pre-1.0.0 install over to V2rayMik.
#
# Import this BEFORE the new 00-vars.rsc, in a session where the old globals are
# not loaded: it reads every value it needs from the device itself, not from a
# global. Its own filename keeps the old project name because the file has to be
# recognisable to the operator who is still running that version.
#
# It removes only the objects the old version created. The old data directory
# and the old container root-dir are left on the disk on purpose: they are the
# rollback path, and the printed block says how to remove them later.
#
# Run it twice and the second run prints "nothing to migrate" and changes nothing.

# --- 0. is there anything to migrate? ----------------------------------------
:local oldC [/container find where name="xray-gw"]
:local oldM [/container/mounts find where list="MOUNT_XRAY_DATA"]

:if ([:len $oldC] = 0 and [:len $oldM] = 0) do={
  :put "nothing to migrate"
} else={

  # --- 1. read every value before anything is deleted --------------------------
  # A global cannot be trusted here: the old 00-vars.rsc is not loaded, and after a
  # reboot the globals are gone. So each value comes from the object that carries it.

  # The WAN: the old filter allowlist names the interface the container dials out of.
  :local wan ""
  :local wid [/ip firewall filter find where comment="xray: container tcp transport"]
  :if ([:len $wid] > 0) do={
    :set wan [/ip firewall filter get [:pick $wid 0] out-interface]
  }

  # The LAN subnet: the opt-in rule carries it when it was created; otherwise take
  # the network of the first bridge that has an address and is not the veth.
  :local lan ""
  :local cid [/ip firewall filter find where comment="xray: container to LAN (opt-in)"]
  :if ([:len $cid] > 0) do={
    :set lan [/ip firewall filter get [:pick $cid 0] dst-address]
  }
  :if ([:len $lan] = 0) do={
    :foreach a in=[/ip address find where dynamic=no] do={
      :local ifc [/ip address get $a interface]
      :local net [/ip address get $a network]
      :if ([:len $lan] = 0 and $ifc != "veth-xray" and $ifc != $wan and $net != "172.17.0.0/24") do={
        :if ([:len [/interface bridge find where name=$ifc]] > 0) do={
          :set lan $net
        }
      }
    }
  }

  # The routing table, from the old world route.
  :local tbl "to-world"
  :local rwid [/ip route find where comment="xray-world"]
  :if ([:len $rwid] > 0) do={
    :set tbl [/ip route get [:pick $rwid 0] routing-table]
  }

  # Fail-open showed itself as the presence of the ISP fallback route.
  :local failOpen "true"
  :if ([:len [/ip route find where comment="xray-fallback"]] = 0) do={
    :set failOpen "false"
  }

  # The opt-in LAN rule existed or it did not.
  :local allowLan "false"
  :if ([:len $cid] > 0) do={
    :set allowLan "true"
  }

  # The LAN port of the panel, from its dst-nat rule.
  :local alan "8081"
  :local aid [/ip firewall nat find where comment="xray: admin ui"]
  :if ([:len $aid] > 0) do={
    :set alan [/ip firewall nat get [:pick $aid 0] dst-port]
  }

  # The panel password and the port allowlist live in the old env list.
  :local pw ""
  :local ports ""
  :foreach e in=[/container/envs find where list="xray-gw"] do={
    :local k [/container/envs get $e key]
    :if ($k = "ADMIN_PASSWORD") do={ :set pw [/container/envs get $e value] }
    :if ($k = "ALLOWED_PORTS") do={ :set ports [/container/envs get $e value] }
  }

  # The image the old install pulled, for the operator's reference only.
  :local oldImage ""
  :if ([:len $oldC] > 0) do={
    :do { :set oldImage [/container get [:pick $oldC 0] remote-image] } on-error={ :set oldImage "" }
  }

  # The disk: the mount src ends in /xray-data, so cut the path there instead of
  # assuming "usb2" — the old install may live on any disk.
  :local disk ""
  :local src ""
  :local mid [/container/mounts find where dst="/data"]
  :if ([:len $mid] > 0) do={
    :set src [/container/mounts get [:pick $mid 0] src]
  }
  :local cut [:find $src "/xray-data"]
  :if ([:len $src] > 0 and [:typeof $cut] = "num") do={
    :set disk [:pick $src 0 $cut]
  }
  :if ([:len $disk] > 0 and [:pick $disk 0 1] = "/") do={
    :set disk [:pick $disk 1 [:len $disk]]
  }

  # Everything that could not be read falls back to the shipped default, and says so.
  :local wanNote ""
  :if ([:len $wan] = 0) do={
    :set wan "ether2-WAN"
    :set wanNote "   # guessed: check it"
    :log warning "90-migrate: MikWan guessed as ether2-WAN, check the printed block"
  }
  :local lanNote ""
  :if ([:len $lan] = 0) do={
    :set lan "192.168.88.0/24"
    :set lanNote "   # guessed: check it"
    :log warning "90-migrate: MikLanSubnet guessed as 192.168.88.0/24, check the printed block"
  }
  :if ([:len $disk] = 0) do={
    :set disk "usb2"
    :log warning "90-migrate: MikDisk guessed as usb2, check the printed block"
  }

  # The allowlist is one flat string in the old env; split it back into the two
  # globals the new scripts expect, because a `dst-port` list holds at most 15.
  :if ([:len $ports] = 0) do={
    :set ports "443,80,8080,8880,2052,2053,2082,2083,2086,2087,2095,2096,8443,53"
  }
  :local main ""
  :local extra ""
  :local n 0
  :foreach p in=[:toarray $ports] do={
    :if ($n < 15) do={
      :if ([:len $main] = 0) do={ :set main $p } else={ :set main ($main . "," . $p) }
    } else={
      :if ([:len $extra] = 0) do={ :set extra $p } else={ :set extra ($extra . "," . $p) }
    }
    :set n ($n + 1)
  }

  # --- 2. the old container ----------------------------------------------------
  # Stop first: removing a running container leaves its process behind on 7.25.1.
  :if ([:len $oldC] > 0) do={
    /container stop [:pick $oldC 0]
    :delay 3s
    /container remove [:pick $oldC 0]
    :log info "90-migrate: old container stopped and removed"
  }

  # --- 3. the veth and its address ---------------------------------------------
  # The address 172.17.0.1/24 must go before the new import, or 01-container.rsc
  # fails with "address already have this" and the container comes up unreachable.
  :if ([:len [/interface bridge port find where interface="veth-xray"]] > 0) do={
    /interface bridge port remove [find where interface="veth-xray"]
  }
  :if ([:len [/ip address find where interface="veth-xray"]] > 0) do={
    /ip address remove [find where interface="veth-xray"]
  }
  :if ([:len [/interface veth find where name="veth-xray"]] > 0) do={
    /interface veth remove [find where name="veth-xray"]
    :log info "90-migrate: old veth and its 172.17.0.1/24 address removed"
  }

  # --- 4. the old mount list and env list --------------------------------------
  :if ([:len [/container/mounts find where list="MOUNT_XRAY_DATA"]] > 0) do={
    /container/mounts remove [find where list="MOUNT_XRAY_DATA"]
  }
  :if ([:len [/container/envs find where list="xray-gw"]] > 0) do={
    /container/envs remove [find where list="xray-gw"]
  }

  # --- 5. routes, firewall, scheduler ------------------------------------------
  :foreach c in={"xray-world";"xray-fallback";"xray: connected to container"} do={
    :if ([:len [/ip route find where comment=$c]] > 0) do={
      /ip route remove [find where comment=$c]
    }
  }

  :foreach c in={"xray: never mark the container";"xray: keep router-direct off the tunnel";"World -> xray (LAN)";"World -> xray (router)";"xray: MSS clamp";"xray: MSS clamp back";"xray: MSS clamp (router output)"} do={
    :if ([:len [/ip firewall mangle find where comment=$c]] > 0) do={
      /ip firewall mangle remove [find where comment=$c]
    }
  }

  :foreach c in={"xray: container tcp transport";"xray: container tcp transport (extra)";"xray: container udp transport";"xray: container udp transport (extra)";"xray: container to LAN (opt-in)";"xray: container default deny"} do={
    :if ([:len [/ip firewall filter find where comment=$c]] > 0) do={
      /ip firewall filter remove [find where comment=$c]
    }
  }

  :foreach c in={"xray: container egress";"xray: masquerade to container";"xray: LAN to container";"xray: router to container masq";"xray: admin ui"} do={
    :if ([:len [/ip firewall nat find where comment=$c]] > 0) do={
      /ip firewall nat remove [find where comment=$c]
    }
  }

  # The follower script and its scheduler share one name in the old version.
  :if ([:len [/system scheduler find where name="xray-auto-route"]] > 0) do={
    /system scheduler remove [find where name="xray-auto-route"]
  }
  :if ([:len [/system script find where name="xray-auto-route"]] > 0) do={
    /system script remove [find where name="xray-auto-route"]
  }

  # Anything else carrying the old prefix was not created by this project. Removing
  # it would undo someone's own tuning, so name it and leave it alone.
  :foreach id in=[/ip firewall mangle find where comment~"xray"] do={
    :log warning ("90-migrate: left in place, not created by this project: mangle \"" . [/ip firewall mangle get $id comment] . "\"")
  }
  :foreach id in=[/ip firewall filter find where comment~"xray"] do={
    :log warning ("90-migrate: left in place, not created by this project: filter \"" . [/ip firewall filter get $id comment] . "\"")
  }
  :foreach id in=[/ip firewall nat find where comment~"xray"] do={
    :log warning ("90-migrate: left in place, not created by this project: nat \"" . [/ip firewall nat get $id comment] . "\"")
  }

  # The old bridge is left alone: another container may be using it.

  # --- 6. the subscription -----------------------------------------------------
  # The panel's state.json is not carried: the next Connect rebuilds it. The
  # subscription itself is a plain file and is worth keeping, so the operator does
  # not have to find the link again.
  :local newDir ($disk . "/v2raymik-data")
  :if ([:len [/file find where name=$newDir]] = 0) do={
    /file add name=$newDir type=directory
  }
  :local srcFile ($disk . "/xray-data/sub.txt")
  :local dstFile ($disk . "/v2raymik-data/sub.txt")
  :local f [/file find where name=$srcFile]
  :if ([:len $f] = 0) do={
    :log warning "90-migrate: no sub.txt found; paste the subscription in the panel after the import"
  } else={
    :local c ""
    :do { :set c [/file get [:pick $f 0] contents] } on-error={ :set c "" }
    :if ([:len $c] = 0) do={
      :log warning ("90-migrate: could not read " . $srcFile . "; copy it to " . $dstFile . " by hand")
    } else={
      :if ([:len [/file find where name=$dstFile]] > 0) do={
        /file set [find where name=$dstFile] contents=$c
      } else={
        /file add name=$dstFile contents=$c
      }
      :local g [/file find where name=$dstFile]
      :if ([:len $g] = 0) do={
        :log warning ("90-migrate: could not create " . $dstFile . "; paste the subscription in the panel")
      } else={
        # Verify, but never let a failed read abort the run: the settings block
        # below is what the operator cannot get anywhere else.
        :do {
          :if ([:len [/file get [:pick $g 0] contents]] = [:len $c]) do={
            :log info ("90-migrate: subscription copied, " . [:len $c] . " bytes")
          } else={
            :log warning ("90-migrate: " . $dstFile . " differs in length from the old file; check the panel's subscription")
          }
        } on-error={
          :log warning ("90-migrate: could not verify " . $dstFile . "; check the panel's subscription")
        }
      }
    }
  }

  # --- 7. what the operator does next ------------------------------------------
  :put ""
  :put "# --- V2rayMik: settings recovered from this device --------------------------"
  :put "# Paste the lines below into your own copy of 00-vars.rsc. The repository"
  :put "# file keeps the shipped defaults and must not carry this router's values."
  :put (":global MikWan \"" . $wan . "\"" . $wanNote)
  :put (":global MikLanSubnet \"" . $lan . "\"" . $lanNote)
  :put (":global MikDisk \"" . $disk . "\"")
  :put (":global MikContainerToWanPorts \"" . $main . "\"")
  :put (":global MikExtraWanPorts \"" . $extra . "\"")
  :put (":global MikAdminLanPort \"" . $alan . "\"")
  :put (":global MikTable \"" . $tbl . "\"")
  :put (":global MikFailOpen " . $failOpen)
  :put (":global MikAllowContainerToLan " . $allowLan)
  :put (":global MikAdminPassword \"" . $pw . "\"")
  :put ""
  :put "# MikAdminPassword above is your panel password, printed once to this"
  :put "# console so the migration keeps the page working. If you pulled through a"
  :put "# mirror, also set MikCheckCertificate \"no\" as you did before."
  :put "# If you side-loaded the image from a .tar instead of pulling it, set"
  :put "# MikImageFile to the new tar before importing 01-container.rsc."
  :put ""
  :put "# Then, all in one terminal session:"
  :put "/import file-name=00-vars.rsc"
  :put "/import file-name=01-container.rsc"
  :put "/import file-name=02-routing.rsc"
  :put "/import file-name=03-firewall.rsc"
  :put "/import file-name=04-admin.rsc"
  :put "/import file-name=05-auto-route.rsc"
  :put "/container/start [find where name=\"v2raymik\"]"
  :put ""
  :put "# The old image is still on the disk, and these directories are the"
  :put "# rollback path. Remove them only after a week of normal use:"
  :put ("#   /file/remove [find where name~\"^" . $disk . "/xray-gw/\"]")
  :put ("#   /file/remove [find where name~\"^" . $disk . "/xray-data/\"]")
  :put ""

  :log info ("90-migrate: old install removed; settings printed above; rollback path kept in " . $disk . "/xray-gw and " . $disk . "/xray-data")
  :if ([:len $oldImage] > 0) do={
    :log info ("90-migrate: the old container ran " . $oldImage)
  }
}