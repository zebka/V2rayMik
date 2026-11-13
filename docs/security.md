# Security

Read this before deploying on a device that is not yours alone.

## A container on RouterOS is not a sandbox

MikroTik's own documentation says it plainly: once container mode is enabled,
containers can be added remotely; a compromised RouterOS means containers are a
way to run arbitrary software on the router; and a determined expert can escape
the container to a root shell. An image is code running with your router's
kernel, next to your firewall.

What this project does about it:

- The container subnet is **default deny** in the forward chain. It may reach
  the WAN on the transport ports (default: the Cloudflare proxy ports plus 53,
  TCP and UDP) and nothing else. It may not reach the LAN unless you
  explicitly opt in.
- The container gets no WAN-exposed ports. Nothing is forwarded to it.
- No secrets live in the repository or the image, and the outbound file is the
  operator's own file on the operator's own disk.
- The image is built from a digest-pinned `alpine` + the official sing-box and
  Xray releases, **downloaded with sha256 verification** against the digests
  GitHub publishes for each asset. No `curl | sh` at runtime, no third-party
  binaries.

What it cannot do: protect you from a malicious image, a compromised registry,
or a RouterOS vulnerability. Pin the version you audited.

## The admin page (passwordless, by design)

The panel has **no password**. Anyone who can reach it can load a
subscription, test every node, and switch what the router's traffic uses. That
is the trade you accept by choosing a single-file, no-login panel; it is
documented here because it is a real reduction in protection compared to a
login screen.

What keeps that bounded to your LAN:

- **One door, on the LAN.** The container listens on `:8080`; the only
  exposure is the `dst-nat` in `router/v2raymik.rsc`, which is scoped to
  `in-interface-list=LAN`. There is no WAN rule to forget to remove, and no
  login page to brute-force.
- **No secrets in responses.** The list carries label, protocol, host and
  port — never a UUID, key or full link. The active outbound lives in
  `/data/state.json` (mode 600) on the USB disk.
- **No shell from the browser.** CGI parameters are integers and enums; the
  subscription URL is the single free-form string and it goes to `curl` with
  `--proto '=http,https'`, **redirects are never followed**, a two-megabyte
  cap, and a host that looks private/loopback/link-local is refused.
- **One test at a time**, guarded by a lock directory with a 2-minute stale
  timeout, so a dead tab cannot pin the CPU.
- **Failed switch → rollback.** State is written tentatively; if the new node
  does not come up in time, the previous outbound is restored (or, on a
  first switch, the state is dropped and the environment config returns).
- **The `gen` hash** of the current config list is required for Test and
  Connect, so a stale tab cannot act on a shifted index.

What it does *not* protect against: anyone on your LAN, and the container
image itself. If a LAN user switching your exit node is not acceptable, block
`tcp/8081` in the forward chain — the panel disappears entirely and the
container keeps working.

Do not expose the port beyond the LAN. There is no TLS and no credential in
front of it.

## The container's egress allowlist

The container subnet is **default-deny**. Three rules in the router script
decide everything it can reach:

| Rule | Effect |
| --- | --- |
| accept `172.17.0.0/24 → WAN` on `MikContainerToWanPorts` (tcp) | the transport's TCP ports |
| accept `172.17.0.0/24 → WAN` on `MikContainerToWanPorts` (udp) | UDP transports, DNS |
| **drop** `172.17.0.0/24 → anything` | everything else |

### Why ports and not "allow the server's IP"

- **The endpoint is not stable.** CDN-fronted and rotating endpoints resolve to
  different addresses, so an address-based rule silently rots while the config
  still looks right. Ports do not rot the same way.
- **Ports are a coarse but honest boundary.** The container needs exactly one
  outbound service: its transport. Everything else it might do — scanning the
  LAN, reaching a C2, joining a botnet, being used as an open relay — is
  outbound traffic, and outbound traffic is what this rule removes.

### Why not allow every port

A container on RouterOS is not a sandbox: it shares the router's kernel. If the
image or the registry is ever compromised, the blast radius is decided by these
rules, not by the image's good behaviour. An open egress turns a compromised
image into a usable proxy or scanner on a residential IP; a three-port
allowlist turns it into a broken container.

This is least privilege, applied to the one network path the container owns.

### The default list

`MikContainerToWanPorts` defaults to:

```
443,80,8080,8880,2052,2053,2082,2083,2086,2087,2095,2096,8443,53
```

That is every port Cloudflare's proxy accepts, plus 53 for the container's
own resolver. It covers REALITY/TLS on 443, xhttp behind a CDN, and WebSocket
on the CDN's alternative ports — the configurations most people actually run.

### If your provider uses another port

Find the port in the link (`@host:PORT`) or in the container log:

```
/log print where topics~"container" and message~"dialing"
```

then set `MikExtraWanPorts` in your copy of the import variables and
re-import `v2raymik.rsc`; the script adds the accept pair *and* appends the
ports to the container's `ALLOWED_PORTS`. That second list is not decoration —
the admin page compares each entry's port against it and marks non-allowlisted
rows `port blocked`. RouterOS accepts at most **15 ports in one `dst-port`
list**; the default list has 14, which is what the `(extra)` pair exists for.

A tunnel whose port is missing does not fail loudly: the engine keeps
redialling, the router logs nothing, and the symptom is "the internet is slow
/ half broken". That is why the port list is documented here rather than left
implicit.

## Failure behaviour (no fallback)

Since 1.1.0 there is no secondary route: when the tunnel is down, marked
traffic is dropped. Earlier releases could be configured to fall back to the
ISP in that moment; that leaked the router's real address on every outage,
and the trade-off was removed. If you need "internet regardless of who sees
us", that is a different product decision — make it deliberately, with your
own route, not with a hidden default.

The container itself is not tunnelled: the router's masquerade keeps the
container subnet direct to the WAN, which is what keeps its own DNS, image
pulls and subscription fetches independent of the tunnel state.

## What the server sees

The router masquerades LAN → container, so the server sees the router, not
individual clients. Per-client attribution stops at the router. If you need it,
that is a deliberate change in the router script, not a setting.

## Credentials

- The share link or outbound JSON contains your server address and UUID/password.
  It lives in the container's root-dir on the USB disk, readable through SMB if
  you share that disk. Treat the disk as sensitive.
- Do not commit an outbound file. The repo's `.gitignore` covers tarballs and
  scratch, not your files; keep them off the repo path entirely.
- The panel shows no credential. The URL you paste is stored at
  `/data/sub.txt` (mode 600) on the USB disk.

## Reporting

Open an issue with the RouterOS version, the container log, and what you
expected to happen. Do not paste UUIDs, server addresses or keys.
