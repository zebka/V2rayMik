# 99-uninstall.rsc — put the device back the way it was.
#
# Import in the same session as 00-vars.rsc. Order matters: the route goes
# first, so marked traffic leaves the tunnel immediately instead of waiting for
# the rest of the cleanup.
#
# It removes only the objects this project created (all of them carry an
# xray- comment or a known name) and never touches lists it does not own.

:if ([:typeof $XrayVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

# --- 1. routing --------------------------------------------------------------
:if ([:len [/ip route find where comment="xray-world"]] > 0) do={
  /ip route remove [find where comment="xray-world"]
}
:if ([:len [/ip route find where comment="xray-fallback"]] > 0) do={
  /ip route remove [find where comment="xray-fallback"]
}

# --- 2. mangle ---------------------------------------------------------------
:foreach c in={"xray: never mark the container";"xray: keep router-direct off the tunnel";"xray: MSS clamp";"World -> xray (LAN)";"World -> xray (router)"} do={
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
:foreach c in={"xray: container tcp transport";"xray: container udp transport";"xray: container to LAN (opt-in)";"xray: container default deny"} do={
  :if ([:len [/ip firewall filter find where comment=$c]] > 0) do={
    /ip firewall filter remove [find where comment=$c]
  }
}

# --- 4. NAT ------------------------------------------------------------------
:foreach c in={"xray: container egress";"xray: LAN to container"} do={
  :if ([:len [/ip firewall nat find where comment=$c]] > 0) do={
    /ip firewall nat remove [find where comment=$c]
  }
}

# --- 5. container and its plumbing -------------------------------------------
:if ([:len [/container find where name=$XrayContainerName]] > 0) do={
  /container stop [find where name=$XrayContainerName]
  :delay 3s
  /container remove [find where name=$XrayContainerName]
}

:if ([:len [/container envs find where list=$XrayContainerName]] > 0) do={
  /container envs remove [find where list=$XrayContainerName]
}

:if ([:len [/interface bridge port find where bridge=$XrayBridge and interface=$XrayVeth]] > 0) do={
  /interface bridge port remove [find where bridge=$XrayBridge and interface=$XrayVeth]
}
:if ([:len [/ip address find where interface=$XrayVeth and address=($XrayGatewayIp . "/24")]] > 0) do={
  /ip address remove [find where interface=$XrayVeth and address=($XrayGatewayIp . "/24")]
}
# Older versions put the address on a bridge; clean that up if it is still there.
:if ([:len [/ip address find where interface=$XrayBridge and address=($XrayGatewayIp . "/24")]] > 0) do={
  /ip address remove [find where interface=$XrayBridge and address=($XrayGatewayIp . "/24")]
}
:if ([:len [/interface bridge find where name=$XrayBridge]] > 0) do={
  # only the bridge this project created; a pre-existing one is left alone
  :if ([:len [/interface bridge find where name=$XrayBridge and comment="container network"]] > 0) do={
    /interface bridge remove [find where name=$XrayBridge and comment="container network"]
  } else={
    :log warning ("99-uninstall: bridge " . $XrayBridge . " was not created by this project; left in place")
  }
}
:if ([:len [/interface veth find where name=$XrayVeth]] > 0) do={
  /interface veth remove [find where name=$XrayVeth]
}

# The routing table is left in place on purpose: other operators may use it.

# --- 6. optional: restore a previous world route -----------------------------
# Put the id or comment of the route that used to carry world traffic in
# XrayRestoreRoute (for example the OpenVPN route you disabled earlier).
:if ([:len $XrayRestoreRoute] > 0) do={
  :local r [/ip route find where comment=$XrayRestoreRoute]
  :if ([:len $r] > 0) do={
    /ip route enable [:pick $r 0]
    :log info ("99-uninstall: re-enabled route " . $XrayRestoreRoute)
  } else={
    :log warning ("99-uninstall: no route matches " . $XrayRestoreRoute)
  }
}

:log info "99-uninstall: xray gateway removed; marked traffic follows the remaining routes"
