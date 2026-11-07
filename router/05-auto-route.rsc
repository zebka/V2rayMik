# 05-auto-route.rsc — follow the panel's active node, and fall back to the ISP.
#
# The panel cannot touch RouterOS itself, so a scheduler asks the container's
# public health endpoint every 10 s. That endpoint answers plain text:
#
#   selected=1   a node was chosen in the panel, and its Stop button is not pressed
#   up=1         the tunnel started and tun0 exists
#   live=1       a 204 came back through the tunnel recently
#
# Only `selected=1 up=1 live=1` keeps the world route on the tunnel. Anything else is
# a fallback to the **ISP directly** (traffic leaves Iran from the router's own
# address), never to another tunnel: another VPN would hide a dead node and
# silently change the exit country. Other default routes in the table (OpenVPN,
# WireGuard) are left disabled while this scheduler runs.
#
# One sample decides, in both directions: a node that stops answering moves world
# traffic to the ISP on the next tick, and a node that answers again gets it back
# on the next tick — about 10 seconds each way, at the cost of one route flip per
# wobble. There is no counter here on purpose; a 3-sample return took a minute and
# a half, which is longer than a page load waits.
#
# Pressing **Stop** in the panel is not a special case: the container reports
# `selected=0` (and `bypass=1`) while the flag is set, so the same branch runs and
# traffic leaves through the ISP on purpose. sing-box keeps running and tun0 stays
# up, so the container's own healthcheck and `restart-policy=always` never fire —
# stopping the tunnel must not turn into restarting the container.
#
# If you want to use a tunnel as the fallback instead, disable this scheduler and
# enable the route by hand: `mik-auto-route` owns the table while it runs.
#
# NOTE: RouterOS scripts do not inherit the importing session's variables, so the
# values below are literals. If you changed MikContainerIp, MikAdminPort or
# MikTable from their defaults (172.17.0.2 / 8080 / to-world), edit them here.
#
# `/tool fetch` needs the `ftp` policy; without it the fetch fails silently and
# the scheduler looks like it does nothing.
#
# Upgrading: this file only creates the script and the scheduler, it does not
# replace them. Remove both first, then import:
#
#   /system script remove [find where name="mik-auto-route"]
#   /system scheduler remove [find where name="mik-auto-route"]
#   /import file-name=05-auto-route.rsc

# RouterOS scopes globals per script: reading $MikVeth without declaring it here
# yields "nothing", even when 00-vars.rsc already set it.
:global MikVeth

:if ([:typeof $MikVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

# The guards below only create what is missing. On a router that already runs an
# older mik-auto-route this import changes nothing, which is easy to miss, so say
# it out loud instead of leaving a 30 s scheduler and a 3-sample hysteresis in
# place while the file claims 10 s.
:if ([:len [/system script find where name="mik-auto-route"]] > 0) do={
  :log warning "05-auto-route: mik-auto-route already exists and was not replaced; remove the script and its scheduler, then import again"
}

:if ([:len [/system script find where name="mik-auto-route"]] = 0) do={
  /system script add name=mik-auto-route policy=ftp,read,write,policy,test source={
    :local body ""
    :do {
      :local r [/tool fetch url="http://172.17.0.2:8080/cgi-bin/health" output=user as-value duration=4s]
      :set body ($r->"data")
    } on-error={ :set body "" }

    :local want 0
    :if ([:len [:find $body "selected=1"]] > 0 and \
         [:len [:find $body "up=1"]] > 0 and \
         [:len [:find $body "live=1"]] > 0) do={ :set want 1 }

    # Stopped from the panel: same branch, different sentence in the log.
    :local byp 0
    :if ([:len [:find $body "bypass=1"]] > 0) do={ :set byp 1 }

    :local xw [/ip route find where comment="mik-world"]
    # `:return` without a value is an argument error on 7.25 ("missing value(s)
    # of argument(s) value"), and on the last line of a block the closing brace
    # is what it tries to read as one. Give it an explicit value.
    :if ([:len $xw] = 0) do={
      :log warning "mik-auto: no mik-world route"
      :return 0
    }
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
      # The node is live: it is the only default route that may be enabled.
      :foreach r in=$worlds do={
        :if ($r != $xwid and [/ip route get $r disabled] = false) do={ /ip route disable $r }
      }
      :if ($xon = false) do={
        /ip route enable $xwid
        :log info "mik-auto: world traffic -> the tunnel"
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
          :if ($byp = 1) do={
            :log info "mik-auto: stopped in the panel; world traffic -> direct to the ISP"
          } else={
            :log info "mik-auto: world traffic -> direct to the ISP (node not live)"
          }
        } else={
          :log warning "mik-auto: node not live and no route through the ISP gateway; world traffic is dropped"
        }
      }
    }
  }
}

:if ([:len [/system scheduler find where name="mik-auto-route"]] = 0) do={
  /system scheduler add name=mik-auto-route interval=10s on-event=mik-auto-route \
    policy=ftp,read,write,policy,test comment="mik: follow the panel's active node"
}

:log info "05-auto-route: scheduler ready (10s)"
