# Architecture

## The path a packet takes

1. A LAN client sends to a destination that is not in `iran-ips` and not local.
2. `chain=prerouting` mangle marks the connection `to-world`. The container's own
   subnet is exempted before any mark rule, so the transport never marks itself.
3. The router looks up `to-world`, finds `0.0.0.0/0 gateway=172.17.0.2 distance=1`,
   and forwards to the veth.
4. `srcnat` masquerades the flow to `172.17.0.1` (the router's address on the
   container bridge). The container therefore never sees a LAN address.
5. Inside the container, `net.ipv4.ip_forward=1` and two half-default routes send
   the packet to `tun0`.
6. Xray reads the packet from the TUN, opens (or reuses) a connection to the
   server through its outbound, and writes replies back into the TUN.
7. Replies arrive on `tun0`, the kernel routes them to the on-link `172.17.0.1`,
   and the router un-NATs them back to the client.

## Why two `/1` routes instead of a default

`ip route add default dev tun0` competes with the kernel's existing default and
depends on the `ip rule` order. RouterOS 7.22 changed that order
(`1 local`, `2 main`, `3 default`), which silently broke TUN gateways whose
routing lived in a higher-numbered table.

`0.0.0.0/1` and `128.0.0.0/1` together cover the whole IPv4 space, are more
specific than `0.0.0.0/0`, and win on longest-prefix match regardless of rules.
The endpoint `/32` is more specific still, so the transport always leaves through
`eth0`. No `sockopt`, no fwmark, no policy routing.

## Why the container needs no iptables

- Return traffic to the LAN is already addressed to `172.17.0.1`, which is
  on-link on `eth0` inside the container.
- Outbound connections are made by Xray itself, whose source is the container's
  `eth0` address — no NAT required.
- The server side normally masquerades the tunnel subnet, so inner source
  addresses never need to be routable.

Fewer moving parts, and no dependence on netfilter modules the RouterOS kernel
may not provide.

## Why the endpoint bypass is inside the container

The transport runs in the container, and the container's egress is unmarked by
design. It leaves through the WAN on the main table. The only bypass needed is
`<endpoint>/32 dev eth0` inside the container, so Xray's own connection does not
enter the TUN.

The router never learns the endpoint address. There is no address list to keep in
sync. A hostname with **one** A record keeps working: the entrypoint re-resolves
every five minutes and swaps the `/32` without restarting Xray.

A hostname with several A records (typical for a CDN in front of the server) is
**not** safe that way: Xray may dial an address the bypass does not know, and that
packet would enter the tunnel that carries it. Set `ENDPOINT_IP` to pin the
address; the re-resolve loop then does nothing.

## Health and failover

- `restart-policy=always` handles a crashed process.
- `healthcheck-cmd` (RouterOS 7.23+) checks that `tun0` exists; `stop-on-unhealthy`
  stops a container that is "running" with no tunnel.
- `check-gateway=ping` on the world route deactivates it when `172.17.0.2` stops
  answering — which is what a stopped container is.
- Fail-open adds a distance-2 route to the WAN, so a deactivated world route leaves
  the internet reachable. Fail-closed does not: a missing next hop drops marked
  traffic.

The chain that matters: Xray's `tun0` disappears → the healthcheck stops the
container → the veth stops answering → the world route goes inactive → fallback (or
blackhole, in fail-closed).

## Sizing

One `xray` process, one TUN, two containers' worth of nothing. The image is
~17.5 MB compressed on amd64 and the container idles at a few tens of MB of RSS.
Numbers measured on the reference device are in `benchmarks.md`.
