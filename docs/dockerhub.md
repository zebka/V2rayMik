# mikrotik-xray-gateway

A MikroTik **RouterOS** egress gateway in **one** Alpine container: sing-box with
its native TUN inbound, driven by a small LAN admin page. It is built for routers,
not for laptops — the router keeps its Iran/world split, and this image only
carries the world half. (The name is historic: the engine was Xray until 0.4.x.)

- **One container, one process to trust.** No tun2socks, no second container, no
  geodata files, no iptables inside the container. Image: ~40 MB, idle ~10–17 MiB
  RSS on a hAP ax³.
- **Real TUN inside the container.** sing-box creates `tun0`; RouterOS routes
  `0.0.0.0/0` in a dedicated table to the container. The endpoint is pinned with
  a `/32`, so the transport never routes into itself.
- **A LAN panel** on `:8081` (through the router): paste a subscription URL,
  test each node (real delay, exit country, Mbps), then **Connect** — the router's
  world route follows.
- **Automatic fallback to the ISP.** If the selected node dies, world traffic
  returns to the router's own address (your own country) instead of silently
  failing over to another VPN with a different exit country.

Platforms: `linux/amd64`, `linux/arm64`. Runs on RouterOS 7.24+ devices with the
`container` package (validated on 7.25.1, hAP ax³).

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | the newest released version, and only that |
| `0.5.1`, `0.5.0`, `0.4.1`, … | released versions, immutable, equal to the source tag |
| `edge` | the current `main` build, for testing only |
| `1.14.4` | the sing-box release bundled in the image |

## RouterOS quick start

The container is only half of the setup; the routing, firewall and admin NAT live
in the repository's RouterOS scripts.

1. Import the scripts from
   [the repository](https://github.com/zebka/mikrotik-xray-gateway/tree/main/router)
   in one session (`00-vars.rsc` … `05-auto-route.rsc`), after editing
   `00-vars.rsc` for your WAN interface, LAN subnet and disk.
2. Point the container at this image:

   ```
   /container/set [find where name="xray-gw"] remote-image=azebka/mikrotik-xray-gateway:0.5.1
   ```

   Pin a version so the image and the router scripts are a known pair, or use
   `:latest`, which only ever moves to a new release. `:edge` is the raw `main`
   build. The panel shows the running version under **Status → image**.

   If `docker.io` is not reachable from your network, set a mirror and
   `check-certificate=no` as described in the repository README (Iran: use
   `registry-url=https://docker.iranserver.com`).
3. Start it, then open the panel from a LAN device on
   `http://<router-lan-ip>:8081/`.

Full guide, architecture, security notes and the uninstall script:
**[github.com/zebka/mikrotik-xray-gateway](https://github.com/zebka/mikrotik-xray-gateway)**
(Persian: [README.fa.md](https://github.com/zebka/mikrotik-xray-gateway/blob/main/README.fa.md)).

## Environment

Everything is optional; a subscription entered in the panel is stored in `/data`
and wins over the environment.

| Variable | Default | Purpose |
| --- | --- | --- |
| `NODE_LINK` | — | one share link (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, `tuic://`) |
| `NODE_OUTBOUND_FILE` | — | path to a full sing-box outbound JSON |
| `NODE_OUTBOUND_JSON` | — | the same JSON inline |
| `ADMIN_PASSWORD` | — | panel password; empty disables the panel |
| `ALLOWED_PORTS` | all | transport ports the panel may use |
| `TUN_NAME` / `TUN_ADDR` | `tun0` / `198.18.0.1` | the TUN sing-box creates |
| `DATA_DIR` | `/data` | mount this; it holds the chosen node and the session DB |
| `SINGBOX_LOG_LEVEL` | `warn` | sing-box log level inside the container log |
| `CHECK_URL` | Google `generate_204` | what the panel and the health probe test |

## Health endpoint

`GET /cgi-bin/health` is unauthenticated and answers plain text:

```
selected=1 up=1 live=1
```

- `selected` — a node was chosen in the panel
- `up` — the tunnel started and `tun0` exists
- `live` — a `204` actually came back through the tunnel (cached 20 s)

That is all a router needs to decide whether to keep its world route pointed at
the container. It carries no secrets and no labels.

## Notes

- MIT licensed.
- Not a hosting service and not a proxy provider: you need your own server.
- The container shares the RouterOS kernel. Read
  [docs/security.md](https://github.com/zebka/mikrotik-xray-gateway/blob/main/docs/security.md)
  before deploying it on a device you do not own.
- The image is also published to GHCR as
  `ghcr.io/zebka/mikrotik-xray-gateway` for networks where Docker Hub is
  unreachable.
