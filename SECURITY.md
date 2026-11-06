# Security policy

This project puts a container in the routing path of a router, so a bug here can
expose traffic or lock the device out. Reports are welcome and taken seriously.

## What to report privately

Open a private advisory instead of a public issue for anything that is:

- a bypass of the split (traffic that should be tunnelled leaving directly),
- an authentication or session flaw in the admin CGI (`docker/web/cgi-bin/*`),
- a way for a LAN or WAN peer to reach the panel or the container's root,
- a command injection or path traversal in the CGI, or
- a secret leaking through logs, the health endpoint, or the image.

Use **Security → Report a vulnerability** on
[github.com/zebka/mikrotik-xray-gateway](https://github.com/zebka/mikrotik-xray-gateway/security/advisories/new).

Please include: RouterOS version, image tag, the sequence that triggers it, and
what you expected instead. Do not include a working UUID, private key, or a live
subscription URL.

## What is not a vulnerability

- The admin panel is reachable from the LAN by design. It is not exposed to the
  WAN; if you add your own port forward to it, that is your change.
- `XrayFailOpen: true` lets world traffic leave from the router's real address
  when the tunnel is down. That is the documented fail-open mode, not a bug. Use
  `false` if a leak matters more than an outage.
- The container's root shares the RouterOS kernel. That is the architecture and
  is documented in `docs/security.md`; it is not a sandbox escape.
- The health endpoint is unauthenticated by design. It answers three booleans and
  nothing else.

## Supported versions

The latest release and `main`. Older tags get no fixes; pin a version only when
you are prepared to move forward.

## Secrets in this repository

None are committed, and none should be: the panel password lives in the
RouterOS container environment, the node config in `/data`, and CI credentials in
GitHub secrets. If you believe you found one, treat it as a vulnerability and
report it privately.
