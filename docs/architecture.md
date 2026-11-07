# Architecture

## The path a packet takes

1. A LAN client sends to a destination that is not in `iran-ips` and not local.
2. `chain=prerouting` mangle marks the connection `to-world`. The container's own
   subnet is exempted before any mark rule, so the transport never marks itself.
3. The router looks up `to-world`, finds `0.0.0.0/0 gateway=172.17.0.2 distance=1`,
   and forwards to the veth.
4. `srcnat` masquerades the flow to `172.17.0.1`, the router's address on the
   veth. The container therefore never sees a LAN address.
5. Inside the container, `net.ipv4.ip_forward=1` and two half-default routes send
   the packet to `tun0`.
6. sing-box reads the packet from the TUN, opens (or reuses) a connection to the
   server through its outbound, and writes replies back into the TUN.
7. Replies arrive on `tun0`, the kernel routes them to the on-link `172.17.0.1`,
   and the router un-NATs them back to the client.

The router's **own** traffic takes the same path: an `output`-chain mark puts it in
`to-world`, and the same masquerade applies to it. That last part is not optional —
see "What we had to get right" below.

## Why two `/1` routes instead of a default

`ip route add default dev tun0` competes with the kernel's existing default and
depends on the `ip rule` order. RouterOS 7.22 changed that order
(`1 local`, `2 main`, `3 default`), which silently broke TUN gateways whose
routing lived in a higher-numbered table.

`0.0.0.0/1` and `128.0.0.0/1` together cover the whole IPv4 space, are more
specific than `0.0.0.0/0`, and win on longest-prefix match regardless of rules.
The endpoint `/32` is more specific still, so the transport always leaves through
the physical interface. No `sockopt`, no fwmark, no policy routing.

The `/32` must be `via 172.17.0.1`, not `dev <iface>`: without a gateway it makes
an off-subnet host look on-link, the container ARPs for an address on the wrong
segment, and every dial fails while the route looks correct.

## Why the container needs no iptables

- Return traffic to the LAN is already addressed to `172.17.0.1`, which is
  on-link on the veth inside the container.
- Outbound connections are made by sing-box itself, whose source is the container's
  veth address — no NAT required.
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
removed by `99-uninstall.rsc` only if this project created it.

## Why the endpoint bypass is inside the container

The transport runs in the container, and the container's egress is unmarked by
design. It leaves through the WAN on the main table. The only bypass needed is
`<endpoint>/32 via <gateway> dev <iface>` inside the container, so sing-box's own
connection does not enter the TUN.

The router never learns the endpoint address. There is no address list to keep in
sync. A hostname with **one** A record keeps working: the entrypoint re-resolves
every five minutes and swaps the `/32` without restarting sing-box.

A hostname with several A records (typical for a CDN in front of the server) is
**not** safe that way: sing-box may dial an address the bypass does not know, and that
packet would enter the tunnel that carries it. Set `ENDPOINT_IP` to pin the
address; the re-resolve loop then does nothing.

## Why the endpoint address is pinned into the config

sing-box resolves its outbound address when it dials. Inside this container, DNS goes
*through the tunnel* — which cannot come up until the server is dialable. A
hostname outbound is therefore a deadlock: dial needs DNS, DNS needs the dial.

The entrypoint resolves the endpoint once, with the container's own unmarked
egress, and writes the resulting IP into the outbound before sing-box starts. SNI,
Host headers and REALITY settings are untouched.

## What we had to get right (measured, not guessed)

Each of these was a real failure on the reference device, and each has a test or a
lint rule in this repo:

| Symptom | Cause |
| --- | --- |
| `ip: can't find device 'eth0'`, tunnel loops | RouterOS names the container's NIC after the veth (`veth-mik`) |
| Every dial fails, route looks right | `/32` installed with `dev` instead of `via <gateway>` |
| Tunnel never comes up with a hostname endpoint | DNS-through-the-tunnel deadlock |
| Marked route "active", packets vanish | gateway reachable only from `main`; needs a connected route inside `to-world` |
| Everything works, then a 10 MB download stalls at 0 | MSS clamp missing in `chain=output` |
| Router's own traffic dies inside the container | it left with the WAN address as source; masquerade towards the veth fixes it |
| Router could ARP the container but never talk to it | the bridge layout; address on the veth fixes it |

## Process model

```
PID 1: entrypoint (supervisor)
 ├── busybox httpd :8080          (the LAN panel; off without ADMIN_PASSWORD)
 └── sing-box run -c config.json      (restarted on SIGHUP, never the container)
```

`/data/state.json` (persistent root-dir) wins over the environment: when the panel
picks a node it writes the outbound there and sends `HUP`; the supervisor rebuilds
`config.json`, restarts sing-box, and verifies the result. The RouterOS routes and the
container itself are untouched, which is why a switch costs ~2–3 s and not a
container restart.

Testing a candidate runs a *second*, short-lived sing-box with a mixed inbound and a
`/32 via <gateway>` route for its endpoint. Without that route the candidate's
dial would enter the live TUN and the measurement would describe the wrong node.

## Health and failover

- `restart-policy=always` handles a crashed process.
- `healthcheck-cmd` (RouterOS 7.23+) checks that `tun0` exists; `stop-on-unhealthy`
  stops a container that is "running" with no tunnel.
- Fail-open adds a distance-2 route through the ISP gateway, so a stopped
  container leaves the internet reachable from the router's own address.
  Fail-closed does not: a missing next hop drops marked traffic. The fallback is
  the ISP, never another tunnel, so a dead node cannot hide behind a VPN that
  changes the exit country.
- `05-auto-route.rsc` is the only thing that should toggle those routes. It keeps
  `mik-world` enabled only while the panel reports a selected, up and live node,
  and otherwise enables the ISP route and disables every other default route in
  the table. One sample decides, each way: the tick is 10 s, so a node that dies
  and a node that returns are both handled within about ten seconds.

## Stop

The panel's Stop button is not a process control. It writes `/data/bypass.flag`;
`health` then answers `selected=0 bypass=1`, and the scheduler takes the same
branch it takes for a dead node: world traffic leaves through the ISP, which is
what was asked for. `sing-box` is left running and `tun0` stays up, so the
container's `healthcheck-cmd` stays green and `restart-policy=always` never fires —
killing the engine would have made "stopped on purpose" indistinguishable from
"crashed", and `stop-on-unhealthy` would restart exactly what the operator
stopped. Start removes the flag; the node in `state.json` was never touched, so
the tunnel returns on the same node in one tick. The flag lives on the disk, so a
stop survives a reboot.

There is deliberately no `check-gateway=ping` on the world route. On the reference
device the container did not answer ICMP reliably, which silently deactivated the
route and sent everything down the fallback while the tunnel was actually fine. A
route that claims to be active and drops packets is worse than one that fails
loudly.

## Sizing

One `sing-box` process, one TUN, nothing else. The image is ~30 MB compressed and the
container idled at 10–17 MiB of RSS on the reference device. Throughput numbers are
in `benchmarks.md`.
