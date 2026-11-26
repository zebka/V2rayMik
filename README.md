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

- **RouterOS** marks traffic into the container according to `MikScope`: `all`
  (everything, the 1.3.x default), `lan` (all private LAN clients, recommended
  for a router you manage remotely), `list` (only the IPs in `mik-clients`), or
  `manual` (no rules; you write your own).
- **The container** runs the engine and forwards marked traffic through the node you picked.
- **If the node is down**, marked traffic is dropped, not sent out your ISP (fail-closed for the traffic you marked).
- **The panel** at `http://<router>:8081/` picks the node; no password, LAN only.

`lan` and `list` leave router-originated traffic (Winbox, SSH, WireGuard,
updates) on the main table, so remote management cannot be locked out. Both
redirect LAN port-53 DNS into the tunnel so clients get unpoisoned answers.
See `docs/install.md`, "Choose a scope".

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

On a router you manage remotely, set the scope before the import so management
traffic stays on the main table:

```rsc
:global MikScope "lan"
/import file-name=v2raymik.rsc
```

Use `list` instead to tunnel only selected clients; put their IPs in
`:global MikSrcAddress` and add more later in Winbox under
`/ip firewall address-list`, list `mik-clients`.

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
it by hand. The image is pulled from GitHub Container Registry first; if that
fails, the import falls back to a Docker Hub mirror once, by itself
(`docs/install.md`, "Get the image").

Not sure about your disk name or registry? Build the setup block in the
browser: <https://zebka.github.io/V2rayMik/>. It only writes `:global` lines;
nothing is sent to a server.

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
