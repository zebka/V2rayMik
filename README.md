# V2rayMik

**sing-box** and **Xray** gateway for MikroTik RouterOS. One import file,
one container, no rules to memorize.

[![build](https://github.com/zebka/V2rayMik/actions/workflows/build.yml/badge.svg)](https://github.com/zebka/V2rayMik/actions/workflows/build.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/azebka/v2raymik)](https://hub.docker.com/r/azebka/v2raymik)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![فارسی](https://img.shields.io/badge/readme-%D9%81%D8%A7%D8%B1%D8%B3%DB%8C-0a7)](README.fa.md)

V2rayMik puts your router's world-bound traffic through a single Alpine
container with Xray and sing-box inside. No tun2socks, no second container,
no geodata files. And a small LAN page to load subscriptions and pick a
node — no Winbox needed to switch servers.

```
LAN device ──► RouterOS ──► veth ──► container (Xray / sing-box) ──► your node ──► Internet
                  │                        │
                  │                        └─ TUN: all traffic leaves through the node
                  └─ marks world traffic ──► tunnel table
                     (LAN and private ranges stay direct)
```

- **RouterOS** marks every non-LAN packet and sends it to the container.
- **The container** runs the engine and forwards everything through the node you picked.
- **If the node is down**, marked traffic is dropped, not sent out your ISP (fail-closed).
- **The panel** at `http://<router>:8081/` picks the node; no password, LAN only.

## Supported nodes

| Node type | Engine |
| --- | --- |
| `vless://`, `vmess://`, `trojan://`, `ss://` | sing-box |
| `hysteria2://`, `hy2://`, `tuic://` | sing-box |
| `type=xhttp` / `splithttp` | **Xray** |
| `vless://…encryption=…` | **Xray** |

The image carries both engines; the right one is picked per node automatically.
Transports: TCP, WS, gRPC, HTTPUpgrade.

## Install

One line on the router downloads the import file and runs it. Nothing to copy:

```
/tool fetch url="https://raw.githubusercontent.com/zebka/V2rayMik/main/router/v2raymik.rsc" dst-path=v2raymik.rsc; /import file-name=v2raymik.rsc
```

That creates the veth, the mounts, the container, the routing table, the
firewall and the LAN dst-nat. Running the same line again is the upgrade path.
The container starts by itself once its image is ready.

**Disk names.** The container's image and data go on a disk. The installer
looks for these, in this order, and uses the first one it finds:
`usb1`, `usb2`, `usb3`, `sata1`, `sata2`, `nvme1`, `pcie1`, `pcie2`, `mmc1`,
`sd1`, `nand1`, `flash`, `data`. A partitioned drive is found as
`<name>-part1` (for example `usb2-part1`). Check your name with
`/file print where type=directory` or in Winbox **Files**. If a USB stick is
plugged in, it is used before the internal flash. Details and how to pin a
disk are in `docs/install.md`.

Open `http://<router>:8081/` on a LAN device — no password. Paste a
subscription URL, press **Test**, and on the winning row press **Connect**.
That's it: the router and every LAN client behind it now exit through the
node you picked.

To uninstall:

```
:global MikMode "uninstall"; /import file-name=v2raymik.rsc
```

If the router cannot reach GitHub, download `router/v2raymik.rsc` and import
it by hand. The image is pulled from Docker Hub; if that is blocked, set a
mirror first (`docs/install.md`, "Get the image").

See `docs/install.md` for the full guide, the Iran mirror and rollback.

## Requirements

- RouterOS 7.24+ with the **container** package (validated on 7.25.1)
- Container mode enabled — needs **physical access** to the device once
- An external disk for the container's root-dir
- A proxy server you already run (vless, vmess, trojan, ss, hysteria2, tuic)

## Documentation

- `docs/install.md` — install, upgrade, side-loading, mirrors, rollback
- `docs/architecture.md` — packet flow, engines, the two `/1` routes
- `docs/panel.md` — the LAN admin page: subscriptions, testing, switching
- `docs/security.md` — container egress boundaries, what fail-closed means, credentials
- `docs/troubleshooting.md` — common failures and their fixes
- `docs/benchmarks.md` — measured throughput on the reference device
- `docs/migration.md` — moving from 1.0.x
- `docs/dockerhub.md` — the Docker Hub page
- `docs/design/admin-ui.md` — design record of the panel

## License

MIT.
