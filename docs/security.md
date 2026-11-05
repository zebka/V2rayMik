# Security

Read this before deploying on a device that is not yours alone.

## A container on RouterOS is not a sandbox

MikroTik's own documentation says it plainly: once container mode is enabled,
containers can be added remotely; a compromised RouterOS means containers are a
way to run arbitrary software on the router; and a determined expert can escape
the container to a root shell. An image is code running with your router's
kernel, next to your firewall.

What this project does about it:

- The container subnet is **default deny** in the forward chain. It may reach the
  WAN on `tcp/443`, `tcp/80` and `udp/443,53` (its transport) and nothing else.
  It may not reach the LAN unless you explicitly opt in.
- The container gets no WAN-exposed ports. Nothing is forwarded to it.
- No secrets live in the repository or the image, and the outbound file is the
  operator's own file on the operator's own disk.
- The image is built from `alpine` + the official Xray release, with a pinned
  version. No `curl | sh` at runtime, no third-party binaries.

What it cannot do: protect you from a malicious image, a compromised registry, or
a RouterOS vulnerability. Pin the version you audited.

## The container's egress allowlist

The container subnet is **default-deny**. Three rules in `03-firewall.rsc` decide
everything it can reach:

| Rule | Effect |
| --- | --- |
| accept `172.17.0.0/24 → WAN` on `XrayContainerToWanPorts` (tcp) | the transport's TCP ports |
| accept `172.17.0.0/24 → WAN` on `XrayContainerToWanPorts` (udp) | UDP transports, DNS |
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

A container on RouterOS is not a sandbox: it shares the router's kernel, and
MikroTik's own documentation warns that a container compromise can become a
RouterOS compromise. If the image or the registry is ever compromised, the
blast radius is decided by these rules, not by the image's good behaviour. An
open egress turns a compromised image into a usable proxy or scanner on a
residential IP; a three-port allowlist turns it into a broken container.

This is least privilege, applied to the one network path the container owns.

### The default list

`XrayContainerToWanPorts` defaults to:

```
443,80,8080,8880,2052,2053,2082,2083,2086,2087,2095,2096,8443,53
```

That is every port Cloudflare's proxy accepts, plus 53 for the container's own
resolver. It covers REALITY/TLS on 443, XHTTP behind a CDN, and WebSocket on the
CDN's alternative ports — the configurations most people actually run.

### If your provider uses another port

Add it. Find the port in the link (`@host:PORT`) or in the container log:

```
/log print where topics~"container" and message~"dialing"
```

you will see `dialing to tcp:<ip>:<port>`. Then either edit
`XrayContainerToWanPorts` in `00-vars.rsc` and re-import `03-firewall.rsc`, or
patch the live rule:

```
/ip firewall filter set [find where comment="xray: container tcp transport"] \
  dst-port=443,80,2052,2053,2082,2083,2086,2087,2095,2096,8443,8080,8880,53,3001
/ip firewall filter set [find where comment="xray: container udp transport"] \
  dst-port=443,80,2052,2053,2082,2083,2086,2087,2095,2096,8443,8080,8880,53,3001
```

`03-firewall.rsc` re-applies the variable on every import, so the script and the
device stay in step.

RouterOS accepts at most **15 ports in one `dst-port` list**. The default list has
14, which leaves room for exactly one exception. If you need more, add a second
pair of accept rules (for example one for the CDN ports and one per provider)
rather than trimming the first list.

A tunnel whose port is missing does not fail loudly: Xray keeps redialling, the
router logs nothing, and the symptom is "the internet is slow / half broken".
That is why the port list is documented here rather than left implicit.

## What fail-open leaks

With `XrayFailOpen=true`, a dead tunnel means marked traffic silently takes the
direct route. Your real address becomes visible to every destination that
believed it was talking to the server. If that matters more than staying online,
set it to `false`: marked traffic then blackholes while the tunnel is down.

This is not a bug in either mode; it is the trade-off, and it is why the flag
exists instead of a default baked into the scripts.

## What the server sees

The router masquerades LAN → container, so the server sees the router, not
individual clients. Per-client attribution stops at the router. If you need it,
that is a deliberate change in `03-firewall.rsc`, not a setting.

## Credentials

- The share link or outbound JSON contains your server address and UUID/password.
  It lives in the container's root-dir on the USB disk, readable through SMB if
  you share that disk. Treat the disk as sensitive.
- Do not commit an outbound file. The repo's `.gitignore` covers tarballs and
  scratch, not your files; keep them off the repo path entirely.

## Reporting

Open an issue with the RouterOS version, the container log, and what you expected
to happen. Do not paste UUIDs, server addresses or keys.
