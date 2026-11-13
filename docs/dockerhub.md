# V2rayMik

**sing-box + Xray** gateway for MikroTik RouterOS.

A MikroTik **RouterOS** egress gateway in **one** Alpine container: sing-box
with its native TUN, and Xray as a local outlet for the link families sing-box
cannot speak (xhttp/splithttp, vless `encryption=…`). It is built for routers,
not for laptops — but since 1.2.0 the router no longer splits traffic by
destination: everything not on the container subnet rides the tunnel, and there
is no fallback to the ISP.

- **One container, two engines.** No tun2socks, no second container, no geodata
  files, no iptables inside the container. Both engines are sha256-verified at
  build time.
- **Real TUN inside the container.** sing-box creates `tun0`; RouterOS routes
  `0.0.0.0/0` in a dedicated table to the container. The endpoint is pinned
  with a `/32`, so the transport never routes into itself.
- **A passwordless LAN panel** on `:8081` (through the router's dst-nat): paste
  a subscription URL, test each node (real delay, exit country, Mbps), then
  **Connect** — the router's traffic follows. Anyone on the LAN can use it.
- **Fail-closed.** When the tunnel is down, traffic is dropped. There is no
  ISP fallback, by design.

Platforms: `linux/amd64`, `linux/arm64`. Runs on RouterOS 7.24+ devices with the
`container` package (validated on 7.25.1, hAP ax³).

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | the newest released version, and only that |
| `1.2.0`, `1.1.2`, `1.1.1`, `1.1.0`, `1.0.1`, … | released versions, immutable, equal to the source tag |
| `edge` | the current `main` build, for testing only |
| `1.14.4` | the sing-box release bundled in the image |

## RouterOS quick start

The container is only half of the setup; routing, firewall and the admin NAT
live in **one** file in the repository.

1. Import it:

   ```
   /import file-name=v2raymik.rsc
   ```

   It creates everything (veth, mounts, container, table `mik-tunnel`, mangle,
   firewall, dst-nat). Re-importing is how upgrades work; defaults can be
   overridden in the same session before the import (`MikWan`, `MikDisk`,
   `MikImage`, `MikRegistryUrl`, …).
2. Point the container at this image:

   ```
   :global MikImage "azebka/v2raymik:1.2.0"
   /import file-name=v2raymik.rsc
   ```

   Pin a version so the image and the router scripts are a known pair, or use
   `:latest`, which only ever moves to a new release. `:edge` is the raw `main`
   build. The panel shows the running version under **Status → image**.

   If `docker.io` is not reachable from your network, set a mirror and
   `MikCheckCertificate "no"` as described in the repository README (Iran: use
   `MikRegistryUrl "https://docker.iranserver.com"`).
3. Start it, then open the panel from a LAN device on
   `http://<router-lan-ip>:8081/`.

Full guide, architecture, security notes and the uninstall:
**[github.com/zebka/V2rayMik](https://github.com/zebka/V2rayMik)**
(Persian: [README.fa.md](https://github.com/zebka/V2rayMik/blob/main/README.fa.md)).

## Environment

Everything is optional; a subscription entered in the panel is stored in `/data`
and wins over the environment.

| Variable | Default | Purpose |
| --- | --- | --- |
| `NODE_LINK` | — | one share link (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, `tuic://`) |
| `NODE_OUTBOUND_FILE` | — | path to a full sing-box outbound JSON |
| `NODE_OUTBOUND_JSON` | — | the same JSON inline |
| `ALLOWED_PORTS` | all | transport ports the panel may use |
| `TUN_NAME` / `TUN_ADDR` | `tun0` / `198.18.0.1` | the TUN sing-box creates |
| `DATA_DIR` | `/data` | mount this; it holds the chosen node |
| `SINGBOX_LOG_LEVEL` | `warn` | sing-box log level inside the container log |
| `CHECK_URL` | Google `generate_204` | what the panel tests |

## Notes

- MIT licensed.
- Not a hosting service and not a proxy provider: you need your own server.
- The container shares the RouterOS kernel. Read
  [docs/security.md](https://github.com/zebka/V2rayMik/blob/main/docs/security.md)
  before deploying it on a device you do not own.
- The image is also published to GHCR as
  `ghcr.io/zebka/v2raymik` for networks where Docker Hub is
  unreachable.
