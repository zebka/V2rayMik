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

# Image to pull. Replace OWNER once the repo publishes to GHCR, or point this
# at a tar you side-load (see docs/install-side-load.md).
:global XrayImage "ghcr.io/OWNER/mikrotik-xray-gateway:latest"

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

# Ports the container may reach on the WAN: 443 for TLS/REALITY, 80 for a
# CDN-fronted endpoint, 53 for its own resolver.
:global XrayContainerToWanPorts "443,80,53"

# Allow the container into the LAN. Leave false unless you know why.
:global XrayAllowContainerToLan false
