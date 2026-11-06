# 05-auto-route.rsc — follow the panel's active node, and fall back to the ISP.
#
# The panel cannot touch RouterOS itself, so a scheduler asks the container's
# public health endpoint every 30 s. That endpoint answers plain text:
#
#   selected=1   a node was chosen in the panel
#   up=1         the tunnel started and tun0 exists
#   live=1       a 204 came back through the tunnel recently
#
# Only `selected=1 up=1 live=1` keeps the world route on Xray. Anything else is
# a fallback to the **ISP directly** (traffic leaves Iran from the router's own
# address), never to another tunnel: another VPN would hide a dead Xray node and
# silently change the exit country. Other default routes in the table (OpenVPN,
# WireGuard) are left disabled while this scheduler runs.
#
# If you want to use a tunnel as the fallback instead, disable this scheduler and
# enable the route by hand: `xray-auto-route` owns the table while it runs.
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

    # The ISP's own gateway, read from the main table at every run, is what makes
    # a fallback "go home to Iran" instead of "go into another tunnel". A DHCP or
    # PPPoE change is picked up automatically.
    :local wanGw ""
    :local mainRt [/ip route find where dst-address="0.0.0.0/0" and routing-table=main]
    :if ([:len $mainRt] > 0) do={ :set wanGw [/ip route get [:pick $mainRt 0] gateway] }

    :local worlds [/ip route find where routing-table="to-world" and dst-address="0.0.0.0/0"]

    :if ($want = 1) do={
      # Xray is live: it is the only default route that may be enabled.
      :foreach r in=$worlds do={
        :if ($r != $xwid and [/ip route get $r disabled] = false) do={ /ip route disable $r }
      }
      :if ($xon = false) do={
        /ip route enable $xwid
        :log info "xray-auto: world traffic -> xray"
      }
    } else={
      # No live node: every 0.0.0.0/0 that leaves through the ISP gateway is
      # enabled, everything else (OpenVPN, WireGuard) stays disabled.
      :local direct 0
      :foreach r in=$worlds do={
        :if ($r != $xwid) do={
          :local toIsp false
          :if ([:len $wanGw] > 0) do={
            :if ([/ip route get $r gateway] = $wanGw) do={ :set toIsp true }
          }
          :if ($toIsp = true) do={
            :set direct ($direct + 1)
            :if ([/ip route get $r disabled] = true) do={ /ip route enable $r }
          } else={
            :if ([/ip route get $r disabled] = false) do={ /ip route disable $r }
          }
        }
      }
      :if ($xon = true) do={
        /ip route disable $xwid
        :if ($direct > 0) do={
          :log info "xray-auto: world traffic -> direct to the ISP (node not live)"
        } else={
          :log warning "xray-auto: node not live and no route through the ISP gateway; world traffic is dropped"
        }
      }
    }
  }
}

:if ([:len [/system scheduler find where name="xray-auto-route"]] = 0) do={
  /system scheduler add name=xray-auto-route interval=30s on-event=xray-auto-route \
    policy=ftp,read,write,policy,test comment="xray: follow the panel's active node"
}

:log info "05-auto-route: scheduler ready (30s)"
