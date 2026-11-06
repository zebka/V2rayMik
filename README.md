# mikrotik-xray-gateway

[![build](https://github.com/zebka/mikrotik-xray-gateway/actions/workflows/build.yml/badge.svg)](https://github.com/zebka/mikrotik-xray-gateway/actions/workflows/build.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/azebka/mikrotik-xray-gateway)](https://hub.docker.com/r/azebka/mikrotik-xray-gateway)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![فارسی](https://img.shields.io/badge/readme-%D9%81%D8%A7%D8%B1%D8%B3%DB%8C-0a7)](README.fa.md)

Put a MikroTik RouterOS device's world-bound traffic through **one** Alpine
container running [sing-box](https://github.com/SagerNet/sing-box) with its native
TUN inbound. No tun2socks, no second container, no geodata files.

> The repository keeps its historic name; since **0.5.0 the engine is sing-box**
> (it was Xray until 0.4.x). That is what lets the same gateway carry
> **hysteria2**, tuic, vless/REALITY, vmess, trojan and shadowsocks nodes — the
> config format the panel already receives from providers.

RouterOS has no VLESS/REALITY/hysteria2 support. This closes that gap without
asking you to give up the router as the place where traffic is split. It also
serves a small LAN page for subscriptions and node switching, so you do not need
Winbox to change the exit.

```
LAN clients ─┐
             ├─ mangle: mark !iran-ips → to-world
router own ──┘                 │
                     /ip route in to-world: gw 172.17.0.2 (distance 1)
                               │
                     veth-xray (172.17.0.2 ⇄ 172.17.0.1, no bridge)
                               │
                     container eth0 172.17.0.2
                     ip_forward=1, routes: 0/1 + 128/1 → tun0, <endpoint>/32 → eth0
                               │
                     tun0 (198.18.0.1/15, owned by sing-box)
                               │
                     sing-box outbound → your server (tcp or udp, per node)
```

## Why this shape

- **The TUN belongs to the engine.** RouterOS exposes `/dev/net/tun` to containers,
  and sing-box creates and consumes a TUN interface itself. That removes tun2socks
  from the path — one process, one image, one less thing to break.
- **Routes are explicit.** `auto_route` is off: the container sets two `/1` routes
  and an endpoint `/32` itself, so the split depends on longest-prefix match and
  nothing else — not on `ip rule` ordering that RouterOS changed in 7.22.
- **No NAT inside the container, no iptables.** The container shares RouterOS's
  kernel; its netfilter modules are not ours to assume. The router masquerades
  LAN → container, so the container only ever talks to `172.17.0.1`.
- **The split stays on RouterOS.** `iran-ips` decides what is tunnelled. The
  container carries no geo files and no rules, which is what keeps it small.

## Supported node types

| Link scheme | Notes |
| --- | --- |
| `vless://` | including REALITY and `xtls-rprx-vision` |
| `vmess://` | |
| `trojan://` | TLS and WebSocket/gRPC |
| `ss://` | |
| `hysteria2://`, `hy2://` | QUIC/UDP; obfs (salamander) and `pinSHA256` are honoured |
| `tuic://` | |

Transports: TCP, WebSocket, gRPC and HTTPUpgrade. **xhttp/splithttp is not
supported** — sing-box has no such transport, and the panel says so instead of
silently failing.

Hysteria2 and TUIC are UDP. Their port has to be in the router's container
allowlist, otherwise the panel shows `port blocked`.

## Requirements

- RouterOS 7.24.x or newer (validated on **7.25.1**), arm64 or x86 device with the
  **container** package.
- Container mode enabled, which needs **physical access** to the device
  (`/system/device-mode/update container=yes`, then confirm on the device).
- An external disk for `root-dir` and `tmpdir`. Internal flash is too small and
  wears out.
- Clean DNS on the router. If `:resolve twitter.com` returns `10.10.34.x`, fix DNS
  before blaming the tunnel.
- An Xray/sing-box server you already run (vless, vmess, trojan, ss, hysteria2
  or tuic). Any node your provider gives you as a share link is fine.

## Verified

On a hAP ax³ (arm64, 1 GB) with RouterOS 7.25.1 and USB storage:

- Router-originated **and** LAN traffic leave through the tunnel.
- Exit was confirmed in three countries with three transports (VLESS+REALITY,
  VLESS over WebSocket, plain VLESS), plus a Shadowsocks config that carried TCP
  but not UDP.
- A **hysteria2** node (QUIC/UDP, obfs=salamander, pinned certificate) moved
  10 MB in 3.2 s through the same container: ≈25 Mbps, exit `loc=US`.
- The panel loads a subscription, tests each node (real delay, exit country,
  Mbps) and switches the world route in ~3 seconds.
- With the selected node stopped, the scheduler moved world traffic back to the
  ISP in under 30 seconds (`loc=IR`, the router's own address) and returned to
  the node when it came back — with the OpenVPN route never enabled.
- The container idles at 10–22 MiB RSS. Details and commands in
  `docs/benchmarks.md`.

What is *not* verified is written down as such there and in `CHANGELOG.md`.

## Quick start

0. **Get the image.** Multi-arch on Docker Hub (use this through a mirror if
   `ghcr.io` is unreachable from your network):

   ```
   docker pull azebka/mikrotik-xray-gateway:latest   # newest release
   docker pull azebka/mikrotik-xray-gateway:0.4.2    # pin repo + image together
   docker pull ghcr.io/zebka/mikrotik-xray-gateway:latest
   ```

   `latest` is republished only when a release tag is pushed, so it always equals
   the `VERSION` file and the newest release here; `:edge` is the raw `main`
   build. The panel shows the running version under **Status → image**.

   On RouterOS, `01-container.rsc` sets `remote-image=`; in Iran a mirror works
   better, for example:

   ```
   /container/config/set registry-url=https://docker.iranserver.com check-certificate=no
   ```

   `make image` builds it locally instead, and `make save` produces a tarball for
   side-loading (`docs/install-side-load.md`).

1. Get the image onto the router — either let the router pull it
   (`remote-image=` in `router/01-container.rsc`) or side-load the tarball
   (`make save`, then upload `dist/*.tar`; see `docs/install-side-load.md`).

2. Put your outbound where the container can read it. Either a full sing-box
   outbound object:

   ```
   <disk>/xray-gw/etc/sing-box/outbound.json
   ```

   or a share link in the container environment:

   ```
   /container/envs/add list=xray-gw key=NODE_LINK value="hysteria2://…"
   ```

   (or `set` on the existing entry if you already added one)

   Do not set both. The JSON path accepts any sing-box outbound; the link path
   understands `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`
   (`hy2://`) and `tuic://`.

   **The port in that link must be in `XrayContainerToWanPorts`** (default:
   every Cloudflare proxy port plus 53; the rule covers TCP and UDP). A provider
   on a non-standard port needs one line changed — see "The container's egress
   allowlist" in `docs/security.md` for why it is an allowlist and how to extend
   it. Hysteria2/TUIC are UDP, so their port has to be there as well.

3. Import the RouterOS scripts **in one session**, in order:

   ```
   /import file-name=00-vars.rsc
   /import file-name=01-container.rsc
   /import file-name=02-routing.rsc
   /import file-name=03-firewall.rsc
   /import file-name=04-admin.rsc
   /import file-name=05-auto-route.rsc
   ```

   Edit `00-vars.rsc` first: WAN interface, LAN subnet, disk, and
   `XrayAdminPassword` if you want the LAN page.

   `05-auto-route.rsc` is optional but recommended: it is what makes the router
   follow the node you pick in the panel, and it is the only thing that should
   toggle the world route afterwards.

4. Start the container and watch the log:

   ```
   /container/start [find where name="xray-gw"]
   /log print where topics~"container"
   ```

5. Verify from a LAN client: `curl https://ifconfig.me` should print your
   server's address.

6. Optional, the panel: open `http://<router-lan-ip>:8081/` from a LAN device,
   sign in with `XrayAdminPassword`, paste a subscription URL (or a single
   link), press **Test all**, then **Connect** on the node you want. See
   "Admin page" below.

Rollback is `99-uninstall.rsc`. It removes the route first, so traffic leaves the
tunnel before anything else is touched.

## Failure behaviour

`XrayFailOpen` in `00-vars.rsc`:

- `true` (default): a direct route stays at distance 2, through the **ISP's own
  gateway**. When the tunnel dies, world traffic goes back out of the router's
  real address: the internet keeps working, in the country the router is in —
  and that is visible to every destination.
- `false`: no fallback. Nothing leaks; marked destinations are down while the
  tunnel is down.

Both are shipped on purpose; pick deliberately and read `docs/security.md`.

A fallback is deliberately **never another tunnel**. Pointing it at OpenVPN or
WireGuard looks safer but hides a dead node and quietly changes the exit
country, which is exactly the thing you are paying for.

### Follow the panel automatically

`router/05-auto-route.rsc` adds a 30-second scheduler that asks the container's
public `cgi-bin/health` endpoint (`selected=`, `up=`, `live=`). Only when all
three are `1` does it keep `xray-world` enabled; otherwise it disables it and
enables the route to the ISP gateway, disabling every other default route in the
table (OpenVPN, WireGuard) on the way. The script owns the routing table while it
runs: to use another tunnel as the exit, disable the scheduler and enable the
route by hand.

The ISP gateway is read from the main table on every run, so a DHCP or PPPoE
change needs no edit.


## Admin page

The same container serves a small panel on the LAN: subscriptions, per-config
testing, and switching the active node.

```
http://<router-lan-ip>:8081/        # XrayAdminLanPort
```

- **Subscription**: paste a v2ray subscription URL (base64 or plain links) or a
  single link. Parsed locally; nothing leaves the router.
- **Test**: each config gets its own short-lived sing-box with a mixed inbound,
  then a `generate_204` check and a 10 MB download. The live tunnel keeps running
  throughout. "Test all" walks the list; "Cancel" stops it.
- **Connect**: the router's world traffic moves to that config. The switch is
  verified (TUN up, routes right, 204 through the tunnel) and rolls back
  automatically if the new node does not come up. Expect ~2–3 seconds of dropped
  connections during the switch; nothing leaks, because the world route keeps
  pointing at the container.

Two things the panel refuses to do on its own, by design:

- It will not connect a config whose port is outside the egress allowlist. Those
  rows say `port blocked` — add the port first (see `docs/security.md`).
- It will not open itself to the WAN. The only exposure is the LAN `dst-nat` in
  `router/04-admin.rsc`, and the panel is disabled while `XrayAdminPassword` is
  empty.

## Measured performance

Two different measurements, both from the router itself, both small samples on
consumer links — read them as orders of magnitude, not as a spec:

| Test | Result |
| --- | --- |
| `tool fetch` of 9.5 MiB, single stream (early build, TR node) | **≈ 13 Mbps** |
| The panel's own 10 MB test, three nodes on the same box | **30–38 Mbps** |
| A hysteria2 node, 10 MB through the panel's method | **≈ 25 Mbps** |
| OpenVPN/TCP on the same box, for comparison (`iperf3`) | ~14 Mbps down / ~15.8 Mbps up |

The container is not the limit here: the same hardware carried OpenVPN at 14, Xray
at 30–38 and hysteria2 at 25 over different paths. Full table, commands and the
not-yet-measured cells are in `docs/benchmarks.md`.

## Roadmap

- Upload throughput, multi-stream and reboot-recovery tests.
- Consume a provider's sing-box JSON subscription (`?format=json`) directly.
- Per-node "last worked at" memory, so the panel can rank nodes by history.

## Layout

```
docker/           image, entrypoint, link and route helpers, admin CGI
router/           00-vars, 01-container, 02-routing, 03-firewall, 04-admin,
                  05-auto-route, 99-uninstall
docs/             architecture, security, troubleshooting, benchmarks, side-load,
                  dockerhub (the Docker Hub page), design/ (the admin UI record)
server/           reference REALITY server config (out of scope)
tests/            unit tests (POSIX sh) and RouterOS lint
```

## Limitations

- Container networking on this class of hardware is CPU-bound; do not expect the
  server's line rate.
- No IPv6 (the reference deployment has it disabled).
- xhttp/splithttp links are rejected: sing-box has no such transport. If your
  provider only offers xhttp, this image is not for that node.
- One router, one active node. No per-user accounting and no multi-tenant panel.
- The container's root shares RouterOS's kernel. See `docs/security.md` before
  deploying this on a device you do not control.

## Getting help

- Read `docs/troubleshooting.md` first; it starts with the three commands that
  answer most questions.
- Open an issue with the output of:
  `/container/print`, `/log print where topics~"container"` (last 50 lines),
  `/ip route print where routing-table=to-world`, and the panel's `state` reply.
- Never paste a working config, a subscription URL, or the panel password into an
  issue.
- Anything that looks like a security problem goes to `SECURITY.md` (private
  advisory), not to a public issue.

## License

MIT.
