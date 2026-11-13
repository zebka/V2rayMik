# Security

Read this before deploying on a device that is not yours alone.

## A container on RouterOS is not a sandbox

MikroTik's own documentation says it plainly: once container mode is enabled,
containers can be added remotely; a compromised RouterOS means containers are a
way to run arbitrary software on the router; and a determined expert can escape
the container to a root shell. An image is code running with your router's
kernel, next to your firewall.

What this project does about it:

- The container subnet is **default deny** in the forward chain: it may
  reach any public destination (its transport is the product's whole job)
  and no private range — RFC1918, loopback and link-local are refused by
  the fixed `mik-private` list. It may reach the LAN only with the explicit
  `MikAllowContainerToLan` opt-in.
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

- **One door, from private space only.** The container listens on `:8080`; the
  only exposure is the `dst-nat` in `router/v2raymik.rsc`, which requires the
  source to be in the fixed `mik-private` address list (RFC1918 + link-local).
  That list needs no interface names and no per-router guessing: a source that
  is not private is refused. There is no WAN rule to forget to remove, and no
  login page to brute-force.
- **No secrets in responses.** The list carries label, protocol, host and
  port — never a UUID, key or full link. The active outbound lives in
  `/data/state.json` (mode 600) on the USB disk.
- **No shell from the browser.** CGI parameters are integers and enums; the
  subscription URL is the single free-form string and it goes to `curl` with
  `--proto '=http,https'` (redirects max three, https only — plain http is
  refused), a two-megabyte cap, a plain browser User-Agent (a `v2ray`-flavoured
  one is silently dropped by some provider edges), and a host that looks
  private/loopback/link-local is refused.
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

## The container's egress

Since 1.3.0 the container's egress is filtered by **destination class, not by
port**. Two rules decide everything it can reach:

| Rule | Effect |
| --- | --- |
| accept `172.17.0.0/24 → !mik-private` | any public destination, any port |
| **drop** `172.17.0.0/24 → anything` | private space (RFC1918, loopback, link-local) |

The `mik-private` list is fixed and typed into the script once — there is no
`MikLanSubnet` to guess wrong, and it covers every private range rather than
your one LAN. With `:global MikAllowContainerToLan true` the accept becomes
unconditional and the drop rule is removed: the container can then reach the
LAN too, which is an explicit opt-in.

### Why the port allowlist is gone

It was removed in 1.3.0, and the reasons are worth keeping on record:

- **The ports are not knowable in advance.** A node's port belongs to whoever
  runs the node. Providers use 22001, 8443, 30000-something — anything. An
  allowlist that must be edited before every new provider is a list that is
  always wrong, and it fails silently: the engine redials forever, the router
  logs nothing, and the symptom is "the internet is slow / half broken".
- **It solved the wrong problem.** The panel marked non-allowlisted rows
  `port blocked` and refused to connect them — a guard against a config the
  operator chose to import. The operator is the trust boundary here.
- **Ports do not contain the private networks.** What an open egress actually
  endangers is the LAN and router-adjacent space, and that is what
  `mik-private` denies — the boundary the old allowlist only approximated.

### What the trade-off costs

A container on RouterOS is not a sandbox: it shares the router's kernel. If
the image or the registry is ever compromised, the blast radius is decided by
these two rules. Since 1.3.0 a compromised image **can reach the internet on
any port** from your IP — it cannot reach the LAN, the router's private
address space, or the panel's data, but it can talk outward. On a product
whose whole job is reaching arbitrary ports on arbitrary servers, filtering
outbound ports meant filtering the product itself.

If you run this on a hostile network and want the old behaviour back, it is
your file: the two rules above are ordinary firewall entries — tighten them
by hand after the import.

### If a provider's port does not connect

It is no longer the allowlist. Check the usual suspects in the container log:

```
/log print where topics~"container" and message~"dialing"
```

Repeated `dialing to tcp:<ip>:<port>` with no answer means the endpoint is
unreachable from your network (blocking, DNS, a dead node) — not a port the
router refuses.

## Failure behaviour (no fallback)

Since 1.2.0 there is no secondary route: when the tunnel is down, marked
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
