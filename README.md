# V2rayMik

**sing-box** and **Xray** gateway for MikroTik RouterOS. One container, one LAN panel, and no Winbox needed to switch nodes.

[![build](https://github.com/zebka/V2rayMik/actions/workflows/build.yml/badge.svg)](https://github.com/zebka/V2rayMik/actions/workflows/build.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/azebka/v2raymik)](https://hub.docker.com/r/azebka/v2raymik)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![فارسی](https://img.shields.io/badge/readme-%D9%81%D8%A7%D8%B1%D8%B3%DB%8C-0a7)](README.fa.md)

```
LAN device ──► RouterOS ──► veth ──► container (Xray / sing-box) ──► your node ──► Internet
                   └─ selected traffic ──► mik-tunnel table (fail-closed)
```

## Quick Install

**Start with the Setup Generator: <https://zebka.github.io/V2rayMik/>**

1. Open the generator, choose a scope (`lan`, `list`, `all`, or `manual`) and your disk/registry options.
2. Copy the generated commands into the RouterOS Terminal and run the import.
3. Open `http://<router>:8081/` on a LAN device, paste a subscription or link, press **Test**, then **Connect**.

The generator only writes `:global` lines, nothing is sent to a server. Re-running the import is the upgrade path.

Requires RouterOS 7.24+ with the **container** package, an external disk, and a node you already run.

## Scope

| Scope | Tunneled traffic | Router management |
| --- | --- | --- |
| `lan` (recommended) | all private LAN clients, with DNS redirected into the tunnel | stays on the main table |
| `list` | only the IPs in `mik-clients` (editable live in Winbox) | stays on the main table |
| `all` | LAN and router output, the 1.3.x default | tunneled |
| `manual` | nothing automatically, you write your own rules | untouched |

## Docs

- [Install, upgrade, mirrors, rollback](docs/install.md)
- [LAN panel: subscriptions, testing, switching](docs/panel.md)
- [Packet flow and engines](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

MIT.
