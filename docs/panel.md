# The LAN admin page

The container serves a small panel on the LAN, on `MikAdminLanPort`
(default 8081). There is no password — anyone on the LAN can use it. It is
reachable only through the `dst-nat` in `v2raymik.rsc`, which requires the
source to be a private (RFC1918) address — no interface list to configure.
There is no WAN path and no login page. If that is
not acceptable for your network, block the port in the forward chain instead.

```
http://<router-lan-ip>:8081/        # MikAdminLanPort
```

## What it does

- **Subscription**: paste a v2ray subscription URL (base64 or plain links) or a
  single link. Parsed locally; nothing leaves the router. Redirects are
  followed (max three, https only; a downgrade to plain http is refused).
- **Test**: each config gets its own short-lived engine with a mixed inbound,
  then a `generate_204` check and a download of a 10–200 MB file (your choice,
default 50 MB). The live tunnel keeps
  running throughout. "Test all" walks the list; "Cancel" stops it.
  The result shows which engine ran (sing-box or Xray).
- **Connect**: the router's traffic moves to that config. The switch is
  verified (TUN up, routes right, 204 through the tunnel) and rolls back
  automatically if the new node does not come up. Expect ~2–3 seconds of
  dropped connections during the switch.

- **Versions**: the top card shows the container version (the repository
  release it was built from), the sing-box version and the Xray version. They
  are written into the image at build time.
- **Check for update**: asks GitHub for the newest release and compares it with
  the container version. It only reads; it changes nothing. If a newer release
  exists, update the container on the router with `/container/repull`
  (or re-import the `.rsc` for that release). The container cannot update
  itself, because it has no RouterOS access.

## One thing the panel refuses to do on its own

It will not open itself to the WAN. The only exposure is the `dst-nat`,
which answers only a private source address.

## Engines per node

The panel picks the engine at parse time and shows it on the row and on the
test result:

- sing-box: vless/vmess/trojan/ss, REALITY,
  hysteria2/hy2/tuic, ws/grpc/httpUpgrade/TCP
- Xray: any of the above with `type=xhttp` or `type=splithttp`, and vless
  `encryption=…`

## State

The active node lives in `/data/state.json` (USB disk, mode 600). The panel's
`state` reply shows the current label, engine, version and tun status. Nothing
in state survives an uninstall, so after uninstall+install pick the node
again.
