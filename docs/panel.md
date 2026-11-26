# The LAN admin page

The container serves a small panel on the LAN, on `MikAdminLanPort`
(default 8081). There is no password — anyone on the LAN can use it. It is
reachable only through the `dst-nat` in `v2raymik.rsc`, which requires the
source to be a private (RFC1918) address — no interface list to configure.
There is no WAN path and no login page. If that is
not acceptable for your network, block the port in the forward chain instead.

```
http://<router-lan-ip>:8081/        # MikAdminLanPort
```

## What it does

- **Subscription**: paste a v2ray subscription URL (base64 or plain links) or a
  single link. Parsed locally; nothing leaves the router. Redirects are
  followed (max three, https only; a downgrade to plain http is refused).
- **Test**: each config gets its own short-lived engine with a mixed inbound,
  then a `generate_204` check and a download of a 10, 50 or 99 MB file (your
  choice, default 50 MB). The live tunnel keeps
  running throughout. Each config has its own **Test** button; there is
  no "test all" mode.
  The result shows which engine ran (sing-box or Xray).

## How the speed test works

For every config a separate engine — sing-box or Xray, whichever the link
needs — starts inside the container with a SOCKS inbound on `127.0.0.1:10800`.
The candidate does not touch the live tunnel:

1. **Endpoint resolution.** The node's hostname is resolved through the
   container's resolver. Private and reserved answers (`10.x`, `172.16–31.x`,
   `192.168.x`, `100.64/10` and so on — the classic poisoned-DNS answer) are
   refused, and the public resolvers `1.1.1.1` and `8.8.8.8` are asked as well.
   The resolved address is pinned into the outbound; the engine never
   re-resolves, so a CDN node is tested on the same address the router will
   dial.
2. **Bypass route.** For the duration of the test a `/32` route pins the node
   address to the real egress interface, so the test traffic does not loop
   into the live tunnel. The route is deleted afterwards (unless the live
   config already owned it).
3. **Latency check.** `http://connectivitycheck.gstatic.com/generate_204`
   through the temporary engine. This is the number shown in milliseconds.
4. **Download.** `speed.cloudflare.com/__down?bytes=<N>` through the same
   engine. You pick 10, 50 or 99 MB (default 50). The reported value is the
   effective rate for the whole download (bytes × 8 / seconds), not the
   instantaneous peak, and a small file skews low because the link is still
   ramping up — which is why 99 MB reads higher than 10 MB for the same node.
5. **Exit country.** `1.1.1.1/cdn-cgi/trace` over HTTPS through the same
   engine; the `loc=` line says in which country that node exits.

The time limit scales with the chosen size (1 s per MB plus ~30 s of ramp,
capped at 240 s). Only one test runs at a time; a stale lock is released when
its owner has gone. The 10 MB test uses ~10 MB of traffic, the 99 MB test
~99 MB per measured node.
- **Connect**: the router's traffic moves to that config. The switch is
  verified (TUN up, routes right, 204 through the tunnel) and rolls back
  automatically if the new node does not come up. Expect ~2–3 seconds of
  dropped connections during the switch.

- **Versions**: the top card shows the container version (the repository
  release it was built from), the sing-box version and the Xray version. They
  are written into the image at build time.
- **Check for update**: asks GitHub for the newest release and compares it with
  the container version. It only reads; it changes nothing. If a newer release
  exists, the panel shows two commands to run on the router: first
  `/container set ... remote-image=ghcr.io/zebka/v2raymik:<version>` (use
  `azebka/v2raymik:<version>` on the Docker Hub mirror), then
  `/container/repull ...`. A bare `/container/repull` keeps the old
  `remote-image` and can restore the previous release. Re-importing the `.rsc`
  for that release is the other option. The container cannot update itself,
  because it has no RouterOS access.

## One thing the panel refuses to do on its own

It will not open itself to the WAN. The only exposure is the `dst-nat`,
which answers only a private source address.

## Engines per node

The panel picks the engine at parse time and shows it on the row and on the
test result:

- sing-box: vless/vmess/trojan/ss, REALITY,
  hysteria2/hy2/tuic, ws/grpc/httpUpgrade/TCP
- Xray: any of the above with `type=xhttp` or `type=splithttp`, and vless
  `encryption=…`

## State

The active node lives in `/data/state.json` (USB disk, mode 600). The panel's
`state` reply shows the current label, engine, version and tun status. Nothing
in state survives an uninstall, so after uninstall+install pick the node
again.
