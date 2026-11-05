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
