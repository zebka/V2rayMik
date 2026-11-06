# 04-admin.rsc — expose the admin page to the LAN, and to the LAN only.
#
# Import after 03-firewall.rsc. Safe to import twice.

:if ([:typeof $XrayVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

# The container listens on $XrayAdminPort; the router answers on
# $XrayAdminLanPort of any LAN interface. in-interface-list=LAN is what keeps it
# off the WAN — there is no second guard behind it, so do not drop it.
:if ([:len [/ip firewall nat find where comment="xray: admin ui"]] = 0) do={
  /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp \
    dst-port=$XrayAdminLanPort in-interface-list=LAN \
    to-addresses=$XrayContainerIp to-ports=$XrayAdminPort \
    comment="xray: admin ui"
} else={
  /ip firewall nat set [find where comment="xray: admin ui"] \
    dst-port=$XrayAdminLanPort to-ports=$XrayAdminPort
}

# LAN clients reach it as http://<router-lan-ip>:<port>/ — one address, no WAN.
:log info ("04-admin: admin ui on the LAN at port " . $XrayAdminLanPort)
