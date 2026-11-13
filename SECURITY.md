# Security policy

This project puts a container in the routing path of a router, so a bug here can
expose traffic or lock the device out. Reports are welcome and taken seriously.

## What to report privately

Open a private advisory instead of a public issue for anything that is:

- traffic that should be tunnelled leaving directly anyway,
- a way for a LAN or WAN peer to reach the panel or the container's root,
- a command injection or path traversal in the CGI, or
- a secret leaking through logs, or the image.

Use **Security → Report a vulnerability** on
[github.com/zebka/V2rayMik](https://github.com/zebka/V2rayMik/security/advisories/new).

Please include: RouterOS version, image tag, the sequence that triggers it, and
what you expected instead. Do not include a working UUID, private key, or a live
subscription URL.

## What is not a vulnerability

- The admin panel has no password and is reachable from the LAN by design; that
  is the documented 1.1.0 panel, not a bug. If a LAN user switching your exit
  node is not acceptable for you, block the port in the forward chain.
- `v2raymik.rsc` is scoped to `in-interface-list=LAN` for the panel's
  `dst-nat`. If you forward the port to the WAN, that is your change.
- Fail-closed: when the tunnel is down, marked traffic is dropped. That is
  the documented behaviour, not a bug.
- The container's root shares the RouterOS kernel. That is the architecture and
  is documented in `docs/security.md`; it is not a sandbox escape.

## Supported versions

The latest release and `main`. Older tags get no fixes; pin a version only when
you are prepared to move forward.

## Secrets in this repository

None are committed, and none should be: the node config lives in `/data`, and
CI credentials in GitHub secrets. If you believe you found one, treat it as a
vulnerability and report it privately.
