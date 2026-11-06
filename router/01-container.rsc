# 01-container.rsc — veth, container bridge, storage and the container entry.
#
# Import 00-vars.rsc first, in the same terminal session:
#   /import file-name=00-vars.rsc
#   /import file-name=01-container.rsc
#
# Safe to import twice: every object is created only when it is missing.

# RouterOS scopes globals per script: a global must be declared in the same file
# that reads it, or `$MikVeth` is simply "nothing" even after 00-vars.rsc ran.
:global MikVeth
:global MikDisk
:global MikContainerIp
:global MikGatewayIp
:global MikContainerName
:global MikImage
:global MikImageFile
:global MikCheckCertificate
:global MikAdminPassword
:global MikContainerToWanPorts
:global MikExtraWanPorts

:if ([:typeof $MikVeth] = "nothing") do={
  :error "import 00-vars.rsc first in this session"
}

# --- storage -----------------------------------------------------------------
# Pull/extract needs a live tmpdir on the external disk. On this device the old
# tmpdir pointed at a removed USB stick, which is why containers failed for weeks.
:if ([:len [/file find where name=($MikDisk . "/tmp")]] = 0) do={
  /file add name=($MikDisk . "/tmp") type=directory
}
/container/config/set tmpdir=($MikDisk . "/tmp") registry-url="https://registry-1.docker.io"

# The panel's state (subscription, chosen node, sessions) lives outside the
# container's root-dir, because `/container/repull` wipes that directory on every
# update. This mount is what makes an upgrade keep the selected node.
:if ([:len [/file find where name=($MikDisk . "/v2raymik-data")]] = 0) do={
  /file add name=($MikDisk . "/v2raymik-data") type=directory
}
:if ([:len [/container/mounts find where list="MOUNT_MIK_DATA"]] = 0) do={
  /container/mounts add list=MOUNT_MIK_DATA src=($MikDisk . "/v2raymik-data") dst=/data
}

# --- veth --------------------------------------------------------------------
# The address goes on the veth itself, with no bridge in between. Measured on
# RouterOS 7.25.1: with the veth in a bridge, the router could ARP the container
# but never delivered a packet to it (ping and TCP both timed out while the
# container answered its own gateway). Direct on the veth, it works.
:if ([:len [/interface veth find where name=$MikVeth]] = 0) do={
  /interface veth add name=$MikVeth address=($MikContainerIp . "/24") \
    gateway=$MikGatewayIp comment="mik gateway"
}

:if ([:len [/ip address find where interface=$MikVeth and address=($MikGatewayIp . "/24")]] = 0) do={
  /ip address add address=($MikGatewayIp . "/24") interface=$MikVeth comment="mik gateway"
}

# --- container environment ---------------------------------------------------
# The outbound lives in the container's root-dir, so it survives a re-pull:
#   <disk>/v2raymik/etc/sing-box/outbound.json
# Set NODE_LINK here instead if you prefer a share link (do not set both).
# Each entry is added only when missing, so re-importing never resets a value
# the admin page has since changed.
:if ([:len [/container envs find where list=$MikContainerName and key="NODE_OUTBOUND_FILE"]] = 0) do={
  /container envs add list=$MikContainerName key=NODE_OUTBOUND_FILE \
    value="/etc/sing-box/outbound.json"
}

:if ([:len [/container envs find where list=$MikContainerName and key="ADMIN_PASSWORD"]] = 0) do={
  /container envs add list=$MikContainerName key=ADMIN_PASSWORD value=$MikAdminPassword
}

# The UI marks configs whose port is outside this list as blocked, so it must
# match the firewall allowlist exactly — both rules.
:if ([:len [/container envs find where list=$MikContainerName and key="ALLOWED_PORTS"]] = 0) do={
  :local allowed $MikContainerToWanPorts
  :if ([:len $MikExtraWanPorts] > 0) do={
    :set allowed ($allowed . "," . $MikExtraWanPorts)
  }
  /container envs add list=$MikContainerName key=ALLOWED_PORTS value=$allowed
} else={
  :local allowed $MikContainerToWanPorts
  :if ([:len $MikExtraWanPorts] > 0) do={
    :set allowed ($allowed . "," . $MikExtraWanPorts)
  }
  /container envs set [find where list=$MikContainerName and key="ALLOWED_PORTS"] value=$allowed
}

# --- container ---------------------------------------------------------------
# Adding the container starts the image pull; it is not started automatically.
# Two paths: pull from a registry (MikImage) or side-load a docker-archive tar
# already uploaded to the disk (MikImageFile). The file path wins when set.
:if ([:len $MikImageFile] > 0) do={
  :if ([:len [/container find where name=$MikContainerName]] = 0) do={
    /container add name=$MikContainerName file=$MikImageFile interface=$MikVeth \
      root-dir=($MikDisk . "/" . $MikContainerName) dns=1.1.1.1 \
      envlist=$MikContainerName start-on-boot=yes restart-policy=always \
      check-certificate=$MikCheckCertificate mountlists=MOUNT_MIK_DATA \
      memory-high=100663296 logging=yes
  }
} else={
  :if ([:len [/container find where name=$MikContainerName]] = 0) do={
    /container add name=$MikContainerName remote-image=$MikImage interface=$MikVeth \
      root-dir=($MikDisk . "/" . $MikContainerName) dns=1.1.1.1 \
      envlist=$MikContainerName start-on-boot=yes restart-policy=always \
      check-certificate=$MikCheckCertificate mountlists=MOUNT_MIK_DATA \
      memory-high=100663296 logging=yes
  }
}

:log info "01-container: objects ready; wait for /container/print status=stopped, then run 02-routing.rsc"
