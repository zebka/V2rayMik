# 05-auto-route.rsc — move the world route to Xray when the panel has a live node,
# and back to the fallback route(s) when it does not.
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
# values below are literals. If you changed XrayContainerIp, XrayAdminPort or
# XrayTable from their defaults (172.17.0.2 / 8080 / to-world), edit them here.
#
# `/tool fetch` needs the `ftp` policy; without it the fetch fails silently and
# the scheduler looks like it does nothing.

# RouterOS scopes globals per script: reading $XrayVeth without declaring it here
# yields "nothing", even when 00-vars.rsc already set it.
:global XrayVeth

:if ([:typeof $XrayVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

:if ([:len [/system script find where name="xray-auto-route"]] = 0) do={
  /system script add name=xray-auto-route policy=ftp,read,write,policy,test source={
    :local body ""
    :do {
      :local r [/tool fetch url="http://172.17.0.2:8080/cgi-bin/health" output=user as-value duration=8s]
      :set body ($r->"data")
    } on-error={ :set body "" }

    :local want 0
    :if ([:len [:find $body "selected=1"]] > 0 and \
         [:len [:find $body "up=1"]] > 0 and \
         [:len [:find $body "live=1"]] > 0) do={ :set want 1 }

    :local xw [/ip route find where comment="xray-world"]
    :if ([:len $xw] = 0) do={ :log warning "xray-auto: no xray-world route"; :return }
    :local xwid [:pick $xw 0]
    :local xon ([/ip route get $xwid disabled] = false)

    # Every other default route in the table is a fallback (WireGuard, OpenVPN,
    # direct WAN at a higher distance...). Naming them here would tie this script
    # to one setup, so they are found by shape instead: same destination, not the
    # xray route, and not the route that reaches the container itself.
    :local fb [:toarray ""]
    :foreach r in=[/ip route find where routing-table="to-world" and dst-address="0.0.0.0/0"] do={
      :if ($r != $xwid and [/ip route get $r gateway] != "172.17.0.2") do={
        :set fb ($fb, $r)
      }
    }

    :if ($want = 1 and $xon = false) do={
      :foreach r in=$fb do={ /ip route disable $r }
      /ip route enable $xwid
      :log info "xray-auto: world traffic -> xray"
    }
    :if ($want = 0 and $xon = true) do={
      /ip route disable $xwid
      :foreach r in=$fb do={ /ip route enable $r }
      :log info "xray-auto: world traffic -> fallback (node not live)"
    }
  }
}

:if ([:len [/system scheduler find where name="xray-auto-route"]] = 0) do={
  /system scheduler add name=xray-auto-route interval=30s on-event=xray-auto-route \
    policy=ftp,read,write,policy,test comment="xray: follow the panel's active node"
}

:log info "05-auto-route: scheduler ready (30s)"
