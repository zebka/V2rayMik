# Architecture

## The path a packet takes

1. A LAN client (or the router) sends to any IPv4 destination other than the
   container subnet.
2. `chain=prerouting` (and `chain=output` for router-originated traffic) mangle
   marks the packet into the `mik-tunnel` routing table. The container's own
   subnet is exempted before any mark rule, so the transport never marks itself.
3. The router looks up `mik-tunnel`, finds `0.0.0.0/0 gateway=172.17.0.2
   distance=1`, and forwards to the veth.
4. `srcnat` masquerades the flow to `172.17.0.1`, the router's address on the
   veth. The container therefore never sees a LAN address.
5. Inside the container, `net.ipv4.ip_forward=1` and two half-default routes send
   the packet to `tun0`.
6. sing-box reads the packet from the TUN, opens (or reuses) a connection to the
   server through its outbound, and writes replies back into the TUN.
7. Replies arrive on `tun0`, the kernel routes them to the on-link `172.17.0.1`,
   and the router un-NATs them back to the client.

There is deliberately no selection of "which destinations go through the
tunnel". Everything goes; that is the whole design. If the tunnel is down,
the route is dead and traffic is dropped.

## Why two `/1` routes instead of a default

`ip route add default dev tun0` competes with the kernel's existing default and
depends on the `ip rule` order. RouterOS 7.22 changed that order
(`1 local`, `2 main`, `3 default`), which silently broke TUN gateways whose
routing lived in a higher-numbered table.

`0.0.0.0/1` and `128.0.0.0/1` together cover the whole IPv4 space, are more
specific than `0.0.0.0/0`, and win on longest-prefix match regardless of rules.
The endpoint `/32` is more specific still, so the transport always leaves
through the physical interface. No `sockopt`, no fwmark, no policy routing.

The `/32` must be `via 172.17.0.1`, not `dev <iface>`: without a gateway it
makes an off-subnet host look on-link, the container ARPs for an address on the
wrong segment, and every dial fails while the route looks correct.

## Why the container needs no iptables

- Return traffic to the LAN is already addressed to `172.17.0.1`, which is
  on-link on the veth inside the container.
- Outbound connections are made by the engines themselves, whose source is the
  container's veth address — no NAT required.
- The server side normally masquerades the tunnel subnet, so inner source
  addresses never need to be routable.

Fewer moving parts, and no dependence on netfilter modules the RouterOS kernel
may not provide.

## Why there is no bridge

MikroTik's documentation builds the container network with a bridge that holds
the veth and the gateway address. On RouterOS 7.25.1 that layout delivered ARP
and nothing else: the router could resolve the container's MAC, `ping 172.17.0.2`
timed out, TCP to the container timed out, and the container's replies never
arrived — while the container itself could reach `172.17.0.1` without trouble.

Putting `172.17.0.1/24` directly on `veth-mik` fixed it immediately. The scripts
therefore create no bridge at all. A leftover bridge from an older install is
removed by the uninstall path only if this project created it.

## The two engines

```
sing-box (owns tun0)
  └── node type            ──┬─ vless/vmess/trojan/ss/hysteria2/tuic, REALITY,
                              │  ws/grpc/httpupgrade          →  sing-box outbound
                              └─  (xhttp|splithttp) or vless encryption=…
                                                                →  SOCKS 127.0.0.1:10810 → xray → node
```

Every outbound sing-box cannot speak is Xray territory, and Xray handles
exactly those. When a node needs Xray, the supervisor also starts `xray run`,
waits for its loopback SOCKS outlet, and renders sing-box with a
`socks → 127.0.0.1:10810` outbound instead of a protocol-native one. The TUN,
the routes and the masquerade are unchanged; the node switch is the same
`state.json`-driven reload in both cases.

UDP through a chained Xray node rides the SOCKS hop; TCP rides it too and is
the case that matters most. hysteria2/tuic stay on sing-box for exactly this
reason.

## Why the endpoint bypass is inside the container

The transport runs in the container, and the container's egress is unmarked by
design. It leaves through the WAN on the main table. The only bypass needed is
`<endpoint>/32 via <gateway> dev <iface>` inside the container, so the engine's
own connection does not enter the TUN.

The router never learns the endpoint address. A resolved endpoint is pinned
into the outbound at every start and at every switch; a CDN-fronted hostname
with several A records is the same as one — the one address in the config is
the one in the bypass. If resolution picks a different record later, set
`ENDPOINT_IP` to pin it.

## Why the endpoint address is pinned into the config

sing-box resolves its outbound address when it dials. Inside this container,
the LAN's DNS goes *through the tunnel* — which cannot come up until the
server is dialable. A hostname outbound is therefore a deadlock waiting to
happen. The supervisor resolves the endpoint once, with the container's own
unmarked egress, and writes the resulting IP into the outbound before the
engine starts. SNI, Host headers and REALITY settings are untouched.

## What we had to get right (measured, not guessed)

Each of these was a real failure on the reference device, and each has a test or a
lint rule in this repo:

| Symptom | Cause |
| --- | --- |
| `ip: can't find device 'eth0'`, tunnel loops | RouterOS names the container's NIC after the veth (`veth-mik`) |
| Every dial fails, route looks right | `/32` installed with `dev` instead of `via <gateway>` |
| Tunnel never comes up with a hostname endpoint | DNS-through-the-tunnel deadlock |
| Marked route "active", packets vanish | gateway reachable only from `main`; needs a connected route inside `mik-tunnel` |
| Everything works, then a 10 MB download stalls at 0 | MSS clamp missing in `chain=output` |
| Router's own traffic dies inside the container | it left with the WAN address as source; masquerade towards the veth fixes it |
| Router could ARP the container but never talk to it | the bridge layout; address on the veth fixes it |

## Process model

```
PID 1: entrypoint (supervisor)
 ├── busybox httpd :8080          (the LAN panel; always on)
 └── sing-box run -c config.json      (restarted on SIGHUP, never the container)
      └── xray run -c config.json    (only while an xray-backed node is active)
```

`/data/state.json` (persistent root-dir) wins over the environment: when the
panel picks a node it writes the outbound there and sends `HUP`; the supervisor
rebuilds `config.json`, starts the right engine(s), waits for the TUN and the
Xray outlet, and verifies the result. The RouterOS routes and the container
itself are untouched, which is why a switch costs ~2–3 s and not a container
restart.

Testing a candidate runs a *second*, short-lived engine (sing-box or xray,
whichever the link needs) with a mixed inbound and a `/32 via <gateway>`
route for its endpoint. Without that route the candidate's dial would enter
the live TUN and the measurement would describe the wrong node.

## Failure behaviour

- `restart-policy=always` handles a crashed process.
- `healthcheck-cmd` (RouterOS 7.23+) checks that `tun0` exists; `stop-on-unhealthy`
  stops a container that is "running" with no tunnel.
- There is no fallback route. When the tunnel is down, marked traffic is
  dropped. The router's own traffic is marked the same, on purpose: a silent
  ISP path on every outage is how the exit country lies.

There is deliberately no `check-gateway=ping` on the tunnel route. On the
reference device the container did not answer ICMP reliably, which silently
deactivated the route and dropped traffic while the tunnel was actually fine.
A route that claims to be active and drops packets is worse than one that
fails loudly.

## Sizing

One supervisor, one TUN, one or two engine processes. The image is bigger
than a sing-box-only build (two engines, ~2×) and idles around 10–30 MiB of
RSS on the reference device. Throughput numbers are in `benchmarks.md`.
