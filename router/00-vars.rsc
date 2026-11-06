# v2raymik — RouterOS variables
#
# Import this file FIRST, in the same terminal session as the other .rsc files:
#   /import file-name=00-vars.rsc
#   /import file-name=01-container.rsc
# Every other script refuses to run if these globals are missing.
#
# Nothing here is a secret. Fill in addresses for your own network.

# WAN interface that carries the container's own egress (the node's transport).
:global MikWan "ether2-WAN"

# LAN bridge / subnet, used to keep the container away from local hosts.
:global MikLanSubnet "192.168.88.0/24"

# Container plumbing.
:global MikVeth "veth-mik"
:global MikBridge "containers"
:global MikSubnet "172.17.0.0/24"
:global MikGatewayIp "172.17.0.1"
:global MikContainerIp "172.17.0.2"
:global MikContainerName "v2raymik"

# Image to pull. The published multi-arch image lives here; replace the owner
# only if you fork or host your own.
#
# `latest` is republished only from release tags, so it always equals the newest
# released version and the repository's VERSION file. `edge` is the current
# `main` build; do not run it on a router you depend on. Pin a version
# (`...:0.4.2`) when you want the image and the scripts to be a known pair.
:global MikImage "azebka/v2raymik:latest"

# Set to "no" only when pulling through a mirror whose CA the router does not
# trust (docker.arvancloud.ir needs this on RouterOS 7.25.1).
:global MikCheckCertificate "yes"

# Side-loaded docker-archive tar on the disk (wins over MikImage when set),
# for example "usb2/v2raymik.tar".
:global MikImageFile ""

# --- admin page --------------------------------------------------------------
# Password for the LAN page. It is the only credential of the panel; set it
# before importing 01-container.rsc. The page is off while this is empty.
:global MikAdminPassword ""

# Port inside the container, and the port clients use on the router's LAN IP.
:global MikAdminPort "8080"
:global MikAdminLanPort "8081"

# Disk that holds the container root-dir (must be a mounted external disk).
:global MikDisk "usb2"

# Routing table that carries world-bound traffic.
:global MikTable "to-world"

# fail-open (true): when the tunnel is down, world traffic falls back to the ISP
#   directly — the router's own address, the country you are in. The internet
#   keeps working, but the real IP is exposed.
# fail-closed (false): no fallback; marked traffic is dropped while the tunnel is
#   down. No leak, but the network is down for those destinations.
:global MikFailOpen true

# Gateway for the fail-open fallback route. Leave empty to take it from the main
# table's default route at import time.
:global MikFallbackGw ""

# Route to re-enable when 99-uninstall.rsc runs (id or comment). Empty = none.
:global MikRestoreRoute ""

# Set to "yes" and re-import 02-routing.rsc to re-resolve the router-direct
# hostnames (IP-Cloud addresses change over time).
:global MikRefreshRouterDirect ""

# Ports the container may reach on the WAN. This is an allowlist, not a filter
# you can forget about: anything the node's transport dials must be listed, or the
# forward chain drops it and the tunnel looks broken with no error.
# The default covers every port Cloudflare's proxy accepts (80/8080/8880, 443/
# 8443, 2052/2053/2082/2083/2086/2087/2095/2096) plus 53 for the container's own
# DNS. A provider on a non-standard port must be added here.
:global MikContainerToWanPorts "443,80,8080,8880,2052,2053,2082,2083,2086,2087,2095,2096,8443,53"

# A second list, because RouterOS accepts at most 15 ports per rule and a
# subscription can easily use more. Empty means "no second rule". Example:
#   "6161,8089,7443,8999,15851,2419,3263,4676"
:global MikExtraWanPorts ""

# Allow the container into the LAN. Leave false unless you know why.
:global MikAllowContainerToLan false
