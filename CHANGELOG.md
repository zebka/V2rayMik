# Changelog

## 0.1.0 — 2026-11-06

First release. A single Alpine container running Xray-core with its native TUN
inbound, used as the next hop for a RouterOS policy route.

### Included

- `docker/`: image (Alpine + pinned Xray 26.10.31), entrypoint, share-link
  parsing (vless/vmess/trojan/ss), route planning, endpoint pinning.
- `router/`: four importable scripts and an uninstall, idempotent, with a vars
  header.
- Tests: POSIX sh unit tests for link parsing, config rendering and routing, plus
  a RouterOS lint that enforces the invariants this design depends on.
- Docs: architecture, security (including the egress allowlist), troubleshooting,
  side-loading, benchmarks, Persian README.

### Verified on

MikroTik hAP ax³, RouterOS 7.25.1, arm64, USB storage. Router and LAN traffic
leave through the tunnel (exit in TR/DE/FI tested), ~13 Mbps single stream from
the router, 10–17 MiB container RSS.

### Things this release encodes, learned on real hardware

- The container's NIC is named after the veth, not `eth0`.
- A `/32` bypass needs `via <gateway>`, not `dev <iface>`.
- A hostname outbound deadlocks against DNS-through-the-tunnel; the address is
  pinned at start.
- A custom routing table needs a connected route for the gateway inside it.
- The router's own traffic must be masqueraded towards the veth, or it is dropped
  inside the container.
- Router-originated traffic needs its own MSS clamp in `chain=output`.
- A bridge between the router and the veth delivered ARP only on 7.25.1; the
  address lives on the veth.
- `check-gateway=ping` on the world route is unreliable here and is not used.
- RouterOS accepts at most 15 ports in one `dst-port` list.

### Known limitations

- No IPv6.
- No subscription-URL fetching, no UI, no per-user accounting.
- Multi-address (CDN) endpoints need `ENDPOINT_IP`.
- A container shares the router's kernel; see `docs/security.md`.
