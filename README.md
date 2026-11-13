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

1. Import the file once on the router:

   ```
   /import file-name=v2raymik.rsc
   ```

   It creates the veth, the mounts, the container, the routing table, the
   firewall and the LAN dst-nat. Re-importing is the upgrade path.

2. Start the container and wait for it to come up:

   ```
   /container/start [find where name="v2raymik"]
   ```

3. Open `http://<router>:8081/` on a LAN device — no password. Paste a
   subscription URL, press **Test**, and on the winning row press
   **Connect**. That's it: the router and every LAN client behind it now
   exit through the node you picked.

To uninstall, `:global MikMode "uninstall"` and import again. See
`docs/install.md` for the full guide, the Iran mirror, and rollback.

## Requirements

- RouterOS 7.24+ with the **container** package (validated on 7.25.1)
- Container mode enabled — needs **physical access** to the device once
- An external disk for the container's root-dir
- A proxy server you already run (vless, vmess, trojan, ss, hysteria2, tuic)

## Documentation

- `docs/install.md` — install, upgrade, side-loading, mirrors, rollback
- `docs/architecture.md` — packet flow, engines, the two `/1` routes
- `docs/panel.md` — the LAN admin page: subscriptions, testing, switching
- `docs/security.md` — egress allowlist, what fail-closed means, credentials
- `docs/troubleshooting.md` — common failures and their fixes
- `docs/benchmarks.md` — measured throughput on the reference device
- `docs/migration.md` — moving from 1.0.x
- `docs/dockerhub.md` — the Docker Hub page
- `docs/design/admin-ui.md` — design record of the panel

## License

MIT.
