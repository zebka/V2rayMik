# xray-mikrotik-gateway — RouterOS variables
#
# Import this file FIRST, in the same terminal session as the other .rsc files:
#   /import file-name=00-vars.rsc
#   /import file-name=01-container.rsc
# Every other script refuses to run if these globals are missing.
#
# Nothing here is a secret. Fill in addresses for your own network.

# WAN interface that carries the container's own egress (the Xray transport).
:global XrayWan "ether2-WAN"

# LAN bridge / subnet, used to keep the container away from local hosts.
:global XrayLanSubnet "192.168.88.0/24"

# Container plumbing.
:global XrayVeth "veth-xray"
:global XrayBridge "containers"
:global XraySubnet "172.17.0.0/24"
:global XrayGatewayIp "172.17.0.1"
:global XrayContainerIp "172.17.0.2"
:global XrayContainerName "xray-gw"

# Image to pull. The published multi-arch image lives here; replace the owner
# only if you fork or host your own.
:global XrayImage "azebka/mikrotik-xray-gateway:latest"

# Set to "no" only when pulling through a mirror whose CA the router does not
# trust (docker.arvancloud.ir needs this on RouterOS 7.25.1).
:global XrayCheckCertificate "yes"

# Side-loaded docker-archive tar on the disk (wins over XrayImage when set),
# for example "usb2/royal-xray-gateway.tar".
:global XrayImageFile ""

# --- admin page --------------------------------------------------------------
# Password for the LAN page. It is the only credential of the panel; set it
# before importing 01-container.rsc. The page is off while this is empty.
:global XrayAdminPassword ""

# Port inside the container, and the port clients use on the router's LAN IP.
:global XrayAdminPort "8080"
:global XrayAdminLanPort "8081"

# Disk that holds the container root-dir (must be a mounted external disk).
:global XrayDisk "usb2"

# Routing table that carries world-bound traffic.
:global XrayTable "to-world"

# fail-open (true): keep a direct fallback route at distance 2 when the tunnel is
#   down — the internet keeps working, but the real IP leaks.
# fail-closed (false): no fallback; marked traffic is dropped while the tunnel is
#   down. No leak, but the network is down for those destinations.
:global XrayFailOpen true

# Gateway for the fail-open fallback route. Leave empty to take it from the main
# table's default route at import time.
:global XrayFallbackGw ""

# Route to re-enable when 99-uninstall.rsc runs (id or comment). Empty = none.
:global XrayRestoreRoute ""

# Set to "yes" and re-import 02-routing.rsc to re-resolve the router-direct
# hostnames (IP-Cloud addresses change over time).
:global XrayRefreshRouterDirect ""

# Ports the container may reach on the WAN. This is an allowlist, not a filter
# you can forget about: anything the Xray transport dials must be listed, or the
# forward chain drops it and the tunnel looks broken with no error.
# The default covers every port Cloudflare's proxy accepts (80/8080/8880, 443/
# 8443, 2052/2053/2082/2083/2086/2087/2095/2096) plus 53 for the container's own
# DNS. A provider on a non-standard port must be added here.
:global XrayContainerToWanPorts "443,80,8080,8880,2052,2053,2082,2083,2086,2087,2095,2096,8443,53"

# A second list, because RouterOS accepts at most 15 ports per rule and a
# subscription can easily use more. Empty means "no second rule". Example:
#   "6161,8089,7443,8999,15851,2419,3263,4676"
:global XrayExtraWanPorts ""

# Allow the container into the LAN. Leave false unless you know why.
:global XrayAllowContainerToLan false
