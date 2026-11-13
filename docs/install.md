# Install guide

## Get the image

Multi-arch on Docker Hub (use a mirror if `ghcr.io` is unreachable from your network):

```sh
docker pull azebka/v2raymik:latest   # newest release
docker pull azebka/v2raymik:1.2.7    # pin repo + image together
docker pull ghcr.io/zebka/v2raymik:latest
```

`latest` is republished only when a release tag is pushed, so it always equals
the `VERSION` file and the newest release here; `:edge` is the raw `main` build.
In Iran a mirror works better, for example:

```rsc
:global MikRegistryUrl "https://docker.iranserver.com"
/import file-name=v2raymik.rsc
```

If your mirror's CA is not trusted by the router (`docker.arvancloud.ir` on
7.25.1), also `:global MikCheckCertificate "no"`.

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

### The egress allowlist

The port in that link must be in `MikContainerToWanPorts` (default: every
Cloudflare proxy port plus 53, TCP and UDP). A provider on a non-standard port
needs one line — see "The container's egress allowlist" in `docs/security.md`.
Hysteria2/TUIC are UDP, so their port has to be there as well.

Extra ports go in `MikExtraWanPorts`:

```rsc
:global MikExtraWanPorts "6161,22001"
/import file-name=v2raymik.rsc
```

Re-importing rebuilds both allowlist rules, so a port added there survives an
upgrade. A port added by hand in `/ip firewall filter` does not.

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
/import file-name=v2raymik.rsc
```

Re-importing is idempotent; existing objects are kept, missing ones are
created. The container keeps running with the same node selected.
