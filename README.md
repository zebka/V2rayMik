# mikrotik-xray-gateway

Put a MikroTik RouterOS device's world-bound traffic through **one** Alpine
container running [Xray-core](https://github.com/XTLS/Xray-core) with its native
TUN inbound. No tun2socks, no second container, no geodata files.

RouterOS has no VLESS/REALITY support. This closes that gap without asking you to
give up the router as the place where traffic is split.

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
                     tun0 (198.18.0.1/15, owned by Xray)
                               │
                     Xray outbound → your server:443
```

## Why this shape

- **The TUN belongs to Xray.** RouterOS exposes `/dev/net/tun` to containers, and
  Xray can create and consume a TUN interface itself. That removes tun2socks from
  the path — one process, one image, one less thing to break.
- **Routes are explicit.** `autoSystemRoutingTable` depends on the kernel's
  `ip rule` order, which RouterOS changed in 7.22 and broke TUN gateways. Two
  `/1` routes plus an endpoint `/32` depend on nothing but longest-prefix match.
- **No NAT inside the container, no iptables.** The container shares RouterOS's
  kernel; its netfilter modules are not ours to assume. The router masquerades
  LAN → container, so the container only ever talks to `172.17.0.1`.
- **The split stays on RouterOS.** `iran-ips` decides what is tunnelled. The
  container carries no geo files and no rules, which is what keeps it small.

## Requirements

- RouterOS 7.24.x or newer (validated on **7.25.1**), arm64 or x86 device with the
  **container** package.
- Container mode enabled, which needs **physical access** to the device
  (`/system/device-mode/update container=yes`, then confirm on the device).
- An external disk for `root-dir` and `tmpdir`. Internal flash is too small and
  wears out.
- Clean DNS on the router. If `:resolve twitter.com` returns `10.10.34.x`, fix DNS
  before blaming the tunnel.
- An Xray server you already run. Any outbound Xray understands will do.

## Verified

On a hAP ax³ (arm64, 1 GB) with RouterOS 7.25.1 and USB storage:

- Router-originated **and** LAN traffic leave through the tunnel.
- Exit was confirmed in three countries with three transports (VLESS+REALITY,
  VLESS over WebSocket, plain VLESS), plus a Shadowsocks config that carried TCP
  but not UDP.
- ~13 Mbps single-stream through the tunnel from the router itself; the container
  idles at 10–17 MiB RSS. Details and commands in `docs/benchmarks.md`.

What is *not* verified is written down as such there and in `CHANGELOG.md`.

## Quick start

1. Build or pull the image:

   ```sh
   make image            # or: docker pull ghcr.io/OWNER/mikrotik-xray-gateway
   ```

2. Get the image onto the router — either let the router pull it
   (`remote-image=` in `router/01-container.rsc`) or side-load the tarball
   (`make save`, then upload `dist/*.tar`; see `docs/install-side-load.md`).

3. Put your outbound where the container can read it. Either a full outbound
   object:

   ```
   <disk>/xray-gw/etc/xray/outbound.json
   ```

   or a share link in the container environment:

   ```
   /container/envs/add list=xray-gw key=XRAY_LINK value="vless://…"
   ```

   (or `set` on the existing entry if you already added one)

   Do not set both. The JSON path accepts anything; the link path understands
   `vless://`, `vmess://`, `trojan://` and `ss://`.

   **The port in that link must be in `XrayContainerToWanPorts`** (default:
   every Cloudflare proxy port plus 53). A provider on a non-standard port needs
   one line changed — see "The container's egress allowlist" in
   `docs/security.md` for why it is an allowlist and how to extend it.

4. Import the RouterOS scripts **in one session**, in order:

   ```
   /import file-name=00-vars.rsc
   /import file-name=01-container.rsc
   /import file-name=02-routing.rsc
   /import file-name=03-firewall.rsc
   ```

   Edit `00-vars.rsc` first: WAN interface, LAN subnet, disk.

5. Start the container and watch the log:

   ```
   /container/start [find where name="xray-gw"]
   /log print where topics~"container"
   ```

6. Verify from a LAN client: `curl https://ifconfig.me` should print your
   server's address.

Rollback is `99-uninstall.rsc`. It removes the route first, so traffic leaves the
tunnel before anything else is touched.

## Failure behaviour

`XrayFailOpen` in `00-vars.rsc`:

- `true` (default): a direct route stays at distance 2. The internet keeps
  working when the tunnel dies — **and the real IP leaks silently**.
- `false`: no fallback. Nothing leaks; marked destinations are down while the
  tunnel is down.

Both are shipped on purpose; pick deliberately and read `docs/security.md`.

## Measured performance

Single-stream download through the tunnel, from the router itself: **9.5 MiB in
6 s ≈ 13 Mbps**, on a hAP ax³. The same box ran OpenVPN/TCP at ~14 Mbps, so the
container costs roughly nothing — the path is the limit. Full table, commands and
the not-yet-measured cells are in `docs/benchmarks.md`.

## Roadmap

- A one-page local UI (served by the router) to paste a config, validate it and
  restart the container without Winbox.
- Upload/tests for upload throughput, multi-stream and reboot recovery.
- Optional XHTTP-first examples, since WebSocket is deprecated in Xray.

## Layout

```
docker/           image, entrypoint, link and route helpers
router/           00-vars, 01-container, 02-routing, 03-firewall, 99-uninstall
docs/             architecture, security, troubleshooting, benchmarks, side-load
server/           reference REALITY server config (out of scope)
tests/            unit tests (POSIX sh) and RouterOS lint
```

## Limitations

- Container networking on this class of hardware is CPU-bound; do not expect the
  server's line rate.
- No IPv6 (the reference deployment has it disabled).
- No subscription-URL fetching, no web UI, no per-user accounting.
- The container's root shares RouterOS's kernel. See `docs/security.md` before
  deploying this on a device you do not control.

## License

MIT.
