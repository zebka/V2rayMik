# Install guide

## Install the RouterOS file

One command on the router downloads the import file and runs it. Nothing to
copy by hand:

```rsc
/tool fetch url="https://raw.githubusercontent.com/zebka/V2rayMik/main/router/v2raymik.rsc" dst-path=v2raymik.rsc; /import file-name=v2raymik.rsc
```

Re-running the same line is the upgrade path: objects are created only when
missing, so an existing install is left running.

To pin a fixed release instead of `main`, point the URL at a tag:

```rsc
/tool fetch url="https://raw.githubusercontent.com/zebka/V2rayMik/v1.3.7/router/v2raymik.rsc" dst-path=v2raymik.rsc; /import file-name=v2raymik.rsc
```

If the router cannot reach GitHub, download `router/v2raymik.rsc` from the
release page, move it onto the router (Winbox **Files**, or `/file`), and:

```rsc
/import file-name=v2raymik.rsc
```

## Get the image

Multi-arch on Docker Hub (use a mirror if `ghcr.io` is unreachable from your network):

```sh
docker pull azebka/v2raymik:latest   # newest release
docker pull azebka/v2raymik:1.2.7    # pin repo + image together
docker pull ghcr.io/zebka/v2raymik:latest
```

`latest` is republished only when a release tag is pushed, so it always equals
the `VERSION` file and the newest release here; `:edge` is the raw `main` build.
In Iran the official registry is often unreachable. Try the official one
first, then a mirror. Set the mirror before the import:

```rsc
:global MikRegistryUrl "https://focker.ir"
/import file-name=v2raymik.rsc
```

Other mirrors that worked in testing: `https://docker.iranserver.com`,
`https://docker.arvancloud.ir` (also needs `:global MikCheckCertificate "no"`,
because the router does not trust its CA). Use the same `MikRegistryUrl` line
only if the default pull fails.

## Disks: name them correctly

The installer picks a disk on its own. The name must be one RouterOS shows.
Check it with `/file print where type=directory`, or in Winbox **Files**:

| Drive | Name on the router |
| --- | --- |
| Internal flash | `flash` |
| USB stick, partitioned | `usb1-part1`, `usb2-part1`, `usb3-part1` |
| USB stick, not partitioned | `usb1`, `usb2`, `usb3` |
| SATA | `sata1`, `sata2` |
| NVMe / M.2 | `nvme1` |
| PCIe | `pcie1`, `pcie2` |
| SD / MMC | `mmc1`, `sd1` |

The installer tries the names in that order and uses the first one found, so a
USB stick plugged in is used before the internal flash. If the wrong disk is
used, pin it once:

```rsc
:global MikDisk "pcie1"
/import file-name=v2raymik.rsc
```

If the name does not exist, the import stops and lists the names that do
exist. Pinning on USB is fragile: the same stick can get a different number
after a reboot, so prefer auto-detect there.

## Side-loading the image

`make save` produces a docker-archive tarball; see `docs/install-side-load.md`.

## The outbound

Two ways to give the container its node. Either a full sing-box outbound object:

```
<disk>/v2raymik/etc/sing-box/outbound.json
```

or a share link in the container environment:

```rsc
/container/envs/add list=v2raymik key=NODE_LINK value="hysteria2://…"
```

(or `set` on the existing entry if you already added one). Do not set both.

### The port in that link

Any port works: since 1.3.0 there is no egress allowlist. The container may
reach any public destination; private ranges stay blocked. If a provider's
port does not connect, it is the endpoint, not the router — see
"The container's egress" in `docs/security.md`.

## Full install on a device that already runs an older release

The 1.2.x file is a superset of the old 00–05 scripts. Re-importing is the
upgrade path; everything is created only when missing. See `CHANGELOG.md` and
`docs/migration.md`.

## Start the container

```rsc
/container/start [find where name="v2raymik"]
/log print where topics~"container"
```

Wait for `*** healthy`. Then open the panel from a LAN device.

## Verify from a client

```sh
curl https://ifconfig.me
```

Should print your server's address, not yours.

## The panel

Open `http://<router-lan-ip>:8081/` from any LAN device — no password, no
login page. Paste a subscription URL (or a single link), press **Test all**,
and on the winning row press **Connect**. See `docs/panel.md`.

## Failure behaviour

Fail-closed: when the tunnel is down, marked traffic is dropped. Nothing
leaks to the ISP. Details in `docs/architecture.md`.

## Rollback / uninstall

```rsc
:global MikMode "uninstall"
/import file-name=v2raymik.rsc
```

Removes everything the project created (container, veth, table, routes,
mangle, filter, nat, mounts). The router is back to its previous state.

## Side-load reference

See `docs/install-side-load.md` for building and uploading a tarball.

## Upgrading to a newer release

```rsc
/tool fetch url="https://raw.githubusercontent.com/zebka/V2rayMik/main/router/v2raymik.rsc" dst-path=v2raymik.rsc; /import file-name=v2raymik.rsc
```

Re-importing is idempotent; existing objects are kept, missing ones are
created. The container keeps running with the same node selected.
