# 99-uninstall.rsc — put the device back the way it was.
#
# Import in the same session as 00-vars.rsc. Order matters: the route goes
# first, so marked traffic leaves the tunnel immediately instead of waiting for
# the rest of the cleanup.
#
# It removes only the objects this project created (all of them carry a
# "mik: " comment or a known name) and never touches lists it does not own.

# A global has to be declared in the file that reads it (see 01-container.rsc).
:global MikVeth
:global MikBridge
:global MikContainerName
:global MikGatewayIp
:global MikRestoreRoute

:if ([:typeof $MikVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

# --- 1. routing --------------------------------------------------------------
:if ([:len [/ip route find where comment="mik-world"]] > 0) do={
  /ip route remove [find where comment="mik-world"]
}
:if ([:len [/ip route find where comment="mik-fallback"]] > 0) do={
  /ip route remove [find where comment="mik-fallback"]
}

# --- 2. mangle ---------------------------------------------------------------
:foreach c in={"mik: never mark the container";"mik: keep router-direct off the tunnel";"mik: MSS clamp";"World -> mik (LAN)";"World -> mik (router)"} do={
  :if ([:len [/ip firewall mangle find where comment=$c]] > 0) do={
    /ip firewall mangle remove [find where comment=$c]
  }
}

# The address-list entries we added for the router's own traffic (only ours:
# they carry a hostname comment).
:foreach h in={"cloud.mikrotik.com";"cloud2.mikrotik.com";"upgrade.mikrotik.com"} do={
  :if ([:len [/ip firewall address-list find where list="router-direct" and comment=$h]] > 0) do={
    /ip firewall address-list remove [find where list="router-direct" and comment=$h]
  }
}
# Drop the list itself only when nothing else is left in it.
:if ([:len [/ip firewall address-list find where list="router-direct"]] = 0) do={
  /ip firewall address-list remove [find where list="router-direct"]
}

# --- 3. filter ---------------------------------------------------------------
:foreach c in={"mik: container tcp transport";"mik: container udp transport";"mik: container to LAN (opt-in)";"mik: container default deny"} do={
  :if ([:len [/ip firewall filter find where comment=$c]] > 0) do={
    /ip firewall filter remove [find where comment=$c]
  }
}

# --- 4. NAT and the auto-route follower --------------------------------------
:foreach c in={"mik: container egress";"mik: masquerade to container";"mik: LAN to container";"mik: admin ui"} do={
  :if ([:len [/ip firewall nat find where comment=$c]] > 0) do={
    /ip firewall nat remove [find where comment=$c]
  }
}

:if ([:len [/system scheduler find where name="mik-auto-route"]] > 0) do={
  /system scheduler remove [find where name="mik-auto-route"]
}
:if ([:len [/system script find where name="mik-auto-route"]] > 0) do={
  /system script remove [find where name="mik-auto-route"]
}

# --- 5. container and its plumbing -------------------------------------------
:if ([:len [/container find where name=$MikContainerName]] > 0) do={
  /container stop [find where name=$MikContainerName]
  :delay 3s
  /container remove [find where name=$MikContainerName]
}

:if ([:len [/container envs find where list=$MikContainerName]] > 0) do={
  /container envs remove [find where list=$MikContainerName]
}

:if ([:len [/interface bridge port find where bridge=$MikBridge and interface=$MikVeth]] > 0) do={
  /interface bridge port remove [find where bridge=$MikBridge and interface=$MikVeth]
}
:if ([:len [/ip address find where interface=$MikVeth and address=($MikGatewayIp . "/24")]] > 0) do={
  /ip address remove [find where interface=$MikVeth and address=($MikGatewayIp . "/24")]
}
# Older versions put the address on a bridge; clean that up if it is still there.
:if ([:len [/ip address find where interface=$MikBridge and address=($MikGatewayIp . "/24")]] > 0) do={
  /ip address remove [find where interface=$MikBridge and address=($MikGatewayIp . "/24")]
}
:if ([:len [/interface bridge find where name=$MikBridge]] > 0) do={
  # only the bridge this project created; a pre-existing one is left alone
  :if ([:len [/interface bridge find where name=$MikBridge and comment="container network"]] > 0) do={
    /interface bridge remove [find where name=$MikBridge and comment="container network"]
  } else={
    :log warning ("99-uninstall: bridge " . $MikBridge . " was not created by this project; left in place")
  }
}
:if ([:len [/interface veth find where name=$MikVeth]] > 0) do={
  /interface veth remove [find where name=$MikVeth]
}

# The routing table is left in place on purpose: other operators may use it.

# --- 6. optional: restore a previous world route -----------------------------
# Put the id or comment of the route that used to carry world traffic in
# MikRestoreRoute (for example the OpenVPN route you disabled earlier).
:if ([:len $MikRestoreRoute] > 0) do={
  :local r [/ip route find where comment=$MikRestoreRoute]
  :if ([:len $r] > 0) do={
    /ip route enable [:pick $r 0]
    :log info ("99-uninstall: re-enabled route " . $MikRestoreRoute)
  } else={
    :log warning ("99-uninstall: no route matches " . $MikRestoreRoute)
  }
}

:log info "99-uninstall: gateway removed; marked traffic follows the remaining routes"
