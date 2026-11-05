# 01-container.rsc — veth, container bridge, storage and the container entry.
#
# Import 00-vars.rsc first, in the same terminal session:
#   /import file-name=00-vars.rsc
#   /import file-name=01-container.rsc
#
# Safe to import twice: every object is created only when it is missing.

:if ([:typeof $XrayVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

# --- storage -----------------------------------------------------------------
# Pull/extract needs a live tmpdir on the external disk. On this device the old
# tmpdir pointed at a removed USB stick, which is why containers failed for weeks.
:if ([:len [/file find where name=($XrayDisk . "/tmp")]] = 0) do={
  /file add name=($XrayDisk . "/tmp") type=directory
}
/container/config/set tmpdir=($XrayDisk . "/tmp") registry-url="https://registry-1.docker.io"

# --- veth --------------------------------------------------------------------
:if ([:len [/interface veth find where name=$XrayVeth]] = 0) do={
  /interface veth add name=$XrayVeth address=($XrayContainerIp . "/24") \
    gateway=$XrayGatewayIp comment="xray gateway"
}

# --- container bridge (L3 next hop; never added to the LAN bridge) ------------
:if ([:len [/interface bridge find where name=$XrayBridge]] = 0) do={
  /interface bridge add name=$XrayBridge comment="container network"
}

:if ([:len [/interface bridge port find where bridge=$XrayBridge and interface=$XrayVeth]] = 0) do={
  /interface bridge port add bridge=$XrayBridge interface=$XrayVeth
}

:if ([:len [/ip address find where interface=$XrayBridge and address=($XrayGatewayIp . "/24")]] = 0) do={
  /ip address add address=($XrayGatewayIp . "/24") interface=$XrayBridge comment="xray gateway"
}

# --- container environment ---------------------------------------------------
# The outbound lives in the container's root-dir, so it survives a re-pull:
#   <disk>/xray-gw/etc/xray/outbound.json
# Set XRAY_LINK here instead if you prefer a share link (do not set both).
:if ([:len [/container envs find where list=$XrayContainerName]] = 0) do={
  /container envs add list=$XrayContainerName key=XRAY_OUTBOUND_FILE \
    value="/etc/xray/outbound.json"
}

# --- container ---------------------------------------------------------------
# Adding the container starts the image pull; it is not started automatically.
:if ([:len [/container find where name=$XrayContainerName]] = 0) do={
  /container add name=$XrayContainerName remote-image=$XrayImage interface=$XrayVeth \
    root-dir=($XrayDisk . "/" . $XrayContainerName) dns=1.1.1.1 \
    envlist=$XrayContainerName start-on-boot=yes restart-policy=always \
    memory-high=100663296 logging=yes
}

:log info "01-container: objects ready; wait for /container/print status=stopped, then run 02-routing.rsc"
