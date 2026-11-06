# 05-auto-route.rsc — move the world route to Xray when the panel has a live node,
# and back to OpenVPN when it does not.
#
# The panel cannot touch RouterOS itself, so a scheduler asks the container's
# public health endpoint every 30 s. That endpoint answers plain text:
#
#   selected=1   a node was chosen in the panel
#   up=1         the tunnel started and tun0 exists
#   live=1       a 204 came back through the tunnel recently
#
# Only `selected=1 up=1 live=1` moves the route, so a dead node never takes the
# world route away from the fallback.
#
# NOTE: RouterOS scripts do not inherit the importing session's variables, so the
# endpoint URL below is a literal. If you changed XrayContainerIp or
# XrayAdminPort from their defaults (172.17.0.2 / 8080), edit the URL here.

:if ([:typeof $XrayVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

:if ([:len [/system script find where name="xray-auto-route"]] = 0) do={
  /system script add name=xray-auto-route policy=read,write,test source={
    :local body ""
    :do {
      :local r [/tool fetch url="http://172.17.0.2:8080/cgi-bin/health" output=user as-value duration=8s]
      :set body ($r->0->"data")
    } on-error={ :set body "" }

    :local want 0
    :if ([:len [:find $body "selected=1"]] > 0 and \
         [:len [:find $body "up=1"]] > 0 and \
         [:len [:find $body "live=1"]] > 0) do={ :set want 1 }

    :local xw [/ip route find where comment="xray-world"]
    :local ov [/ip route find where comment="World -> OpenVPN (soobaroTR)"]
    :if ([:len $xw] = 0) do={ :log warning "xray-auto: no xray-world route"; :return }
    :local xwid [:pick $xw 0]
    :local xon ([/ip route get $xwid disabled] = false)

    :if ($want = 1 and $xon = false) do={
      :foreach r in=$ov do={ /ip route disable $r }
      /ip route enable $xwid
      :log info "xray-auto: world traffic -> xray"
    }
    :if ($want = 0 and $xon = true) do={
      /ip route disable $xwid
      :foreach r in=$ov do={ /ip route enable $r }
      :log info "xray-auto: world traffic -> openvpn (node not live)"
    }
  }
}

:if ([:len [/system scheduler find where name="xray-auto-route"]] = 0) do={
  /system scheduler add name=xray-auto-route interval=30s on-event=xray-auto-route \
    policy=read,write,test comment="xray: follow the panel's active node"
}

:log info "05-auto-route: scheduler ready (30s)"
