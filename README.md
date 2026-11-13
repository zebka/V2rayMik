# V2rayMik

**sing-box** and **Xray** gateway for MikroTik RouterOS. One container, one
import file, no rules to memorize.

[![build](https://github.com/zebka/V2rayMik/actions/workflows/build.yml/badge.svg)](https://github.com/zebka/V2rayMik/actions/workflows/build.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/azebka/v2raymik)](https://hub.docker.com/r/azebka/v2raymik)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![فارسی](https://img.shields.io/badge/readme-%D9%81%D8%A7%D8%B1%D8%B3%DB%8C-0a7)](README.fa.md)

Put a MikroTik RouterOS device's traffic through **one** Alpine container
running the proxy engines it needs. No tun2socks, no second container, no
geo files.

> Since **1.2.0** the image carries **Xray** as well as **sing-box**, the
> split by geography is gone, and the whole router-side setup is one import
> file with install and uninstall in it. Versions before 1.2.0 used five
> import files, an `iran-ips` split and a password on the panel; see
> `CHANGELOG.md` for what changed and how to move.

RouterOS has no VLESS/REALITY/hysteria2 support. This closes that gap without
asking you to give up the router as the place where traffic is routed. It
also serves a small LAN page for subscriptions and node switching.

```
LAN clients ─┐
             ├─ everything IPv4 except the container subnet → tunnel
router own ──┘
                     /ip route in mik-tunnel: 0.0.0.0/0 → 172.17.0.2 (distance 1)
                                │
                     veth-mik (172.17.0.2 ⇄ 172.17.0.1, no bridge)
                                │
                     container eth0 172.17.0.2
                     ip_forward=1, routes: 0/1 + 128/1 → tun0, <endpoint>/32 → eth0
                                │
                     tun0 (198.18.0.1/15, owned by sing-box)
                                │
                     sing-box outbound ──┬─ direct to the node (sing-box nodes)
                                         └─ SOCKS 127.0.0.1:10810 → xray → the node
```

## Why this shape

- **The TUN belongs to sing-box.** RouterOS exposes `/dev/net/tun` to
  containers, and sing-box creates and consumes a TUN interface itself. That
  removes tun2socks from the path — one process, one image, one less thing to
  break.
- **Routes are explicit.** The container sets two `/1` routes and an endpoint
  `/32` itself, so the split depends on longest-prefix match and nothing else.
- **No NAT inside the container, no iptables.** The container shares RouterOS's
  kernel; its netfilter modules are not ours to assume. The router masquerades
  LAN → container, so the container only ever talks to `172.17.0.1`.
- **Everything not local goes through the tunnel.** There is no address-list
  deciding what "world" means, nothing to keep stocked, nothing to rot. When
  the tunnel is down, traffic is dropped — fail-closed, no ISP fallback.

## Engines: sing-box and Xray, per node

The image carries both. The engine is chosen per node at parse time; you never
pick it by hand.

| Node type | Engine |
| --- | --- |
| `vless://` (REALITY, vision flow, ws/grpc/httpupgrade/tcp) | sing-box |
| `vmess://`, `trojan://`, `ss://` | sing-box |
| `hysteria2://`, `hy2://`, `tuic://` | sing-box |
| Any of the above with `type=xhttp` or `type=splithttp` | **Xray** |
| `vless://…encryption=…` (post-quantum vless) | **Xray** |

Under the hood, an Xray node runs xray as a local SOCKS5 outlet on
`127.0.0.1:10810`, and sing-box (which owns the TUN) chains to it. Both
engines are up only for the node being used; switching a node switches the
engine with it. UDP through an Xray-chained node is best effort (the SOCKS
hop carries it); TCP is unaffected.

Transports either engine understands: TCP, WebSocket, gRPC and HTTPUpgrade.
The panel shows which engine ran a test or the active connection.

Hysteria2 and TUIC are UDP, and providers usually pick a port of their own.
Add that port to `MikExtraWanPorts` before importing:

```
:global MikExtraWanPorts "22001,8443"
```

The scripts then keep an extra accept rule for it, and the panel unblocks
those rows. Without it the node's handshake leaves the router and never comes
back, and the panel reports `port blocked`.

A hysteria2 link that carries both `insecure=1` and `pinSHA256` is parsed with
the pin dropped: `insecure` is the provider's own statement that verification
is off, and pins in these links go stale after a certificate rotation. A link
with a pin and no `insecure` keeps the pin — and a pin that cannot be decoded
now fails the link instead of vanishing silently.

## Requirements

- RouterOS 7.24.x or newer (validated on **7.25.1**), arm64 or x86 device with
  the **container** package.
- Container mode enabled, which needs **physical access** to the device
  (`/system/device-mode/update container=yes`, then confirm on the device).
- An external disk for `root-dir` and `tmpdir`. Internal flash is too small
  and wears out.
- Clean DNS on the router. If `:resolve twitter.com` returns `10.10.34.x`, fix
  DNS before blaming the tunnel.
- A server you already run (vless, vmess, trojan, ss, hysteria2 or tuic). Any
  node your provider gives you as a share link is fine.

## Verified

Measured on a hAP ax³ (arm64, 1 GB) with RouterOS 7.25.1, USB storage and the
1.0.x (five-file, split) build. Everything below is that build; the 1.2.0
full-tunnel rework has not had a hardware run yet, and the Xray path has not
been used with a live node:

- Router-originated **and** LAN traffic leave through the tunnel.
- Exit was confirmed in three countries with three transports (VLESS+REALITY,
  VLESS over WebSocket, plain VLESS), plus a Shadowsocks config that carried
  TCP but not UDP.
- A **hysteria2** node (QUIC/UDP, obfs=salamander, pinned certificate) moved
  10 MB in 3.2 s through the container: ≈25 Mbps, exit `loc=US`.
- The panel loads a subscription, tests each node (real delay, exit country,
  Mbps) and switches the world route in ~3 seconds.
- With the selected node stopped, marked traffic stopped instead of going
  direct (fail-closed).
- The container idles at 10–22 MiB RSS. Details and commands in
  `docs/benchmarks.md`.

What is not verified is written down as such there and in `CHANGELOG.md`.

## Quick start

0. **Get the image.** Multi-arch on Docker Hub (use this through a mirror if
   `ghcr.io` is unreachable from your network):

   ```
   docker pull azebka/v2raymik:latest   # newest release
   docker pull azebka/v2raymik:1.2.0    # pin repo + image together
   docker pull ghcr.io/zebka/v2raymik:latest
   ```

   `latest` is republished only when a release tag is pushed, so it always
   equals the `VERSION` file and the newest release here; `:edge` is the raw
   `main` build. On RouterOS, the import sets `remote-image=`; in Iran a
   mirror works better, for example:

   ```
   :global MikRegistryUrl "https://docker.iranserver.com"
   /import file-name=v2raymik.rsc
   ```

   (if your mirror's CA is not trusted by the router — `docker.arvancloud.ir`
   on 7.25.1 is the known case — also `:global MikCheckCertificate "no"`).
   `make image` builds it locally instead, and `make save`
   produces a tarball for side-loading (`docs/install-side-load.md`).

1. Get the image onto the router — either let the router pull it, or
   side-load the tarball (`make save`, then upload `dist/*.tar`).

2. Put your outbound where the container can read it. Either a full sing-box
   outbound object:

   ```
   <disk>/v2raymik/etc/sing-box/outbound.json
   ```

   or a share link in the container environment:

   ```
   /container/envs/add list=v2raymik key=NODE_LINK value="hysteria2://…"
   ```

   (or `set` on the existing entry if you already added one). Do not set both;
   the JSON path accepts any sing-box outbound, and nodes that need Xray are
   chosen from links.

   **The port in that link must be in `MikContainerToWanPorts`** (default:
   every Cloudflare proxy port plus 53; the rule covers TCP and UDP). A
   provider on a non-standard port needs one line — see "The container's
   egress allowlist" in `docs/security.md`. Hysteria2/TUIC are UDP, so their
   port has to be there as well.

3. One import:

   ```
   /import file-name=v2raymik.rsc
   ```

   It creates everything (veth, mounts, container, table `mik-tunnel`, mangle
   rules, firewall, dst-nat) and re-importing it is how upgrades work.
   Defaults live in the same file, at the top; override any of them in the
   same terminal session before the import (`MikWan`, `MikDisk`, `MikImage`,
   …).

4. Start the container and watch the log:

   ```
   /container/start [find where name="v2raymik"]
   /log print where topics~"container"
   ```

5. Verify from a LAN client: `curl https://ifconfig.me` should print your
   server's address.

6. Optional, the panel: open `http://<router-lan-ip>:8081/` from a LAN device —
   no password. Paste a subscription URL (or a single link), press **Test
   all**, then **Connect** on the node you want. See "Admin page" below.

Rollback is the same file: `:global MikMode "uninstall"`, import, done.

<!-- old-name-start -->
## Moving from ≤ 1.0.x (mikrotik-xray-gateway)

1.2.0 removes the five-file layout, the split, the password and the
auto-route scheduler. To move:

1. `:global MikMode "uninstall"` then `/import file-name=` the *new*
   `router/v2raymik.rsc` — its uninstall also cleans the 1.x leftovers
   (table `to-world`, `mik-world`/`mik-fallback` routes, the old MSS rules,
   `MOUNT_MIK_DATA`). You do not need the old scripts.
2. Open a new terminal (`MikMode` stays `uninstall` in this one), then
   `/import file-name=v2raymik.rsc` installs the new shape.
3. `state.json` is not carried over; pick the node in the panel once.

The old `/usb2/xray-gw` and `/usb2/xray-data` directories are not touched.
<!-- old-name-end -->

## Failure behaviour

Fail-closed. The table `mik-tunnel` carries everything, with one route, at
distance 1, via the container. When the tunnel is down the route is still
there but the gateway answers nothing — traffic is dropped, and nothing
leaks to the ISP. There is no fallback at all since 1.2.0 (earlier releases
could fall back to the ISP; that behaved like a silent ISP leak on every
outage, so it was removed).

If that trade-off is not yours, do not deploy this release.

## Admin page

The same container serves a small panel on the LAN: subscriptions, per-config
testing, and switching the active node. **There is no password** — anyone on
the LAN can use it. It is reachable only through the `dst-nat` in
`MikAdminLanPort`, scoped to the LAN interface list; there is no WAN path and
no login page. If that is not acceptable for your network, block the port in
the forward chain instead.

```
http://<router-lan-ip>:8081/        # MikAdminLanPort
```

- **Subscription**: paste a v2ray subscription URL (base64 or plain links) or a
  single link. Parsed locally; nothing leaves the router. Redirects are followed
  (max three, and only to `https://`; a downgrade to plain http is refused).
- **Test**: each config gets its own short-lived engine with a mixed inbound,
  then a `generate_204` check and a 10 MB download. The live tunnel keeps
  running throughout. "Test all" walks the list; "Cancel" stops it.
  The result shows which engine ran (sing-box or xray).
- **Connect**: the router's traffic moves to that config. The switch is
  verified (TUN up, routes right, 204 through the tunnel) and rolls back
  automatically if the new node does not come up. Expect ~2–3 seconds of
  dropped connections during the switch.

Two things the panel refuses to do on its own, by design:

- It will not connect a config whose port is outside the egress allowlist. Those
  rows say `port blocked` — add the port first (see `docs/security.md`).
- It will not open itself to the WAN. The only exposure is the LAN `dst-nat`.

## Measured performance

From the router itself, small samples on consumer links — orders of magnitude,
not spec. All measured on the 1.0.x split build; the full-tunnel build should
be equal but has not been measured yet:

| Test | Result |
| --- | --- |
| `tool fetch` of 9.5 MiB, single stream (early build) | **≈ 13 Mbps** |
| The panel's own 10 MB test, three nodes on the same box | **30–38 Mbps** |
| A hysteria2 node, 10 MB through the panel's method | **≈ 25 Mbps** |
| OpenVPN/TCP on the same box, for comparison (`iperf3`) | ~14 Mbps down / ~15.8 Mbps up |

The container is not the limit here. Full table, commands and the not-yet-
measured cells are in `docs/benchmarks.md`.

## Roadmap

- Upload throughput, multi-stream and reboot-recovery tests on the full-tunnel
  build.
- Live runs of Xray nodes on hardware.
- Consume a provider's sing-box JSON subscription (`?format=json`) directly.
- Per-node "last worked at" memory, so the panel can rank nodes by history.

## Layout

```
docker/           image, entrypoint (both engines), link/xray/route helpers,
                  admin CGI, panel (index.html + app.js)
router/           v2raymik.rsc — the whole router side, install and uninstall
docs/             architecture, security, troubleshooting, benchmarks,
                  side-load, dockerhub, design/ (the admin UI record)
server/           reference REALITY server config (out of scope)
tests/            unit tests (POSIX sh) and the static lint
```

## Limitations

- Container networking on this class of hardware is CPU-bound; do not expect
  the server's line rate.
- No IPv6 (the reference deployment has it disabled).
- Both engines together cost ~2× the image size and disk of one; that is the
  price of covering the whole link space.
- UDP through an Xray-chained node travels via the SOCKS hop (best effort);
  hysteria2/tuic are the better choice when the provider lets you pick.
- One router, one active node. No per-user accounting and no multi-tenant
  panel.
- The container's root shares RouterOS's kernel. See `docs/security.md`
  before deploying this on a device you do not control.

## Getting help

- Read `docs/troubleshooting.md` first; it starts with the three commands
  that answer most questions.
- Open an issue with the output of:
  `/container/print`, `/log print where topics~"container"` (last 50 lines),
  `/ip route print where routing-table=mik-tunnel`, and the panel's `state` reply.
- Never paste a working config, a subscription URL, or any other secret into
  an issue.
- Anything that looks like a security problem goes to `SECURITY.md` (private
  advisory), not to a public issue.

## License

MIT.
