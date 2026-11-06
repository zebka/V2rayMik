# 04-admin.rsc — expose the admin page to the LAN, and to the LAN only.
#
# Import after 03-firewall.rsc. Safe to import twice.

# A global has to be declared in the file that reads it (see 01-container.rsc).
:global MikVeth
:global MikContainerIp
:global MikAdminPort
:global MikAdminLanPort

:if ([:typeof $MikVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

# The container listens on $MikAdminPort; the router answers on
# $MikAdminLanPort of any LAN interface. in-interface-list=LAN is what keeps it
# off the WAN — there is no second guard behind it, so do not drop it.
:if ([:len [/ip firewall nat find where comment="mik: admin ui"]] = 0) do={
  /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp \
    dst-port=$MikAdminLanPort in-interface-list=LAN \
    to-addresses=$MikContainerIp to-ports=$MikAdminPort \
    comment="mik: admin ui"
} else={
  /ip firewall nat set [find where comment="mik: admin ui"] \
    dst-port=$MikAdminLanPort to-ports=$MikAdminPort
}

# LAN clients reach it as http://<router-lan-ip>:<port>/ — one address, no WAN.
:log info ("04-admin: admin ui on the LAN at port " . $MikAdminLanPort)
