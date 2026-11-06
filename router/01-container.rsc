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
# The address goes on the veth itself, with no bridge in between. Measured on
# RouterOS 7.25.1: with the veth in a bridge, the router could ARP the container
# but never delivered a packet to it (ping and TCP both timed out while the
# container answered its own gateway). Direct on the veth, it works.
:if ([:len [/interface veth find where name=$XrayVeth]] = 0) do={
  /interface veth add name=$XrayVeth address=($XrayContainerIp . "/24") \
    gateway=$XrayGatewayIp comment="xray gateway"
}

:if ([:len [/ip address find where interface=$XrayVeth and address=($XrayGatewayIp . "/24")]] = 0) do={
  /ip address add address=($XrayGatewayIp . "/24") interface=$XrayVeth comment="xray gateway"
}

# --- container environment ---------------------------------------------------
# The outbound lives in the container's root-dir, so it survives a re-pull:
#   <disk>/xray-gw/etc/xray/outbound.json
# Set XRAY_LINK here instead if you prefer a share link (do not set both).
# Each entry is added only when missing, so re-importing never resets a value
# the admin page has since changed.
:if ([:len [/container envs find where list=$XrayContainerName and key="XRAY_OUTBOUND_FILE"]] = 0) do={
  /container envs add list=$XrayContainerName key=XRAY_OUTBOUND_FILE \
    value="/etc/xray/outbound.json"
}

:if ([:len [/container envs find where list=$XrayContainerName and key="ADMIN_PASSWORD"]] = 0) do={
  /container envs add list=$XrayContainerName key=ADMIN_PASSWORD value=$XrayAdminPassword
}

# The UI marks configs whose port is outside this list as blocked, so it must
# match the firewall allowlist exactly — both rules.
:if ([:len [/container envs find where list=$XrayContainerName and key="ALLOWED_PORTS"]] = 0) do={
  :local allowed $XrayContainerToWanPorts
  :if ([:len $XrayExtraWanPorts] > 0) do={
    :set allowed ($allowed . "," . $XrayExtraWanPorts)
  }
  /container envs add list=$XrayContainerName key=ALLOWED_PORTS value=$allowed
} else={
  :local allowed $XrayContainerToWanPorts
  :if ([:len $XrayExtraWanPorts] > 0) do={
    :set allowed ($allowed . "," . $XrayExtraWanPorts)
  }
  /container envs set [find where list=$XrayContainerName and key="ALLOWED_PORTS"] value=$allowed
}

# --- container ---------------------------------------------------------------
# Adding the container starts the image pull; it is not started automatically.
# Two paths: pull from a registry (XrayImage) or side-load a docker-archive tar
# already uploaded to the disk (XrayImageFile). The file path wins when set.
:if ([:len $XrayImageFile] > 0) do={
  :if ([:len [/container find where name=$XrayContainerName]] = 0) do={
    /container add name=$XrayContainerName file=$XrayImageFile interface=$XrayVeth \
      root-dir=($XrayDisk . "/" . $XrayContainerName) dns=1.1.1.1 \
      envlist=$XrayContainerName start-on-boot=yes restart-policy=always \
      memory-high=100663296 logging=yes
  }
} else={
  :if ([:len [/container find where name=$XrayContainerName]] = 0) do={
    /container add name=$XrayContainerName remote-image=$XrayImage interface=$XrayVeth \
      root-dir=($XrayDisk . "/" . $XrayContainerName) dns=1.1.1.1 \
      envlist=$XrayContainerName start-on-boot=yes restart-policy=always \
      memory-high=100663296 logging=yes
  }
}

:log info "01-container: objects ready; wait for /container/print status=stopped, then run 02-routing.rsc"
