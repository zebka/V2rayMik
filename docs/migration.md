# Moving from 1.0.x to 1.2.x

<!-- old-name-start -->
The 1.2.x series renames and restructures everything: the five import files
became one `router/v2raymik.rsc`, the `iran-ips` split is gone, the panel is
passwordless, and the engine is sing-box (with Xray for the nodes sing-box
cannot speak).

## Steps

1. `:global MikMode "uninstall"`, then import the *new* `router/v2raymik.rsc`.
   Its uninstall also removes the objects the old scripts created (table
   `to-world`, routes `mik-world`/`mik-fallback`, the old MSS rules, the
   `iran-ips` address-list entries in `router-direct`, `MOUNT_MIK_DATA`).
   You do not need the old scripts.
2. Open a new terminal (`MikMode` stays `uninstall` in that one), then
   `/import file-name=v2raymik.rsc` installs the new shape.
3. The old `state.json` is not carried over; pick the node again in the
   panel.

The old `/usb2/xray-gw` and `/usb2/xray-data` directories are not touched.
<!-- old-name-end -->

## What changed

- The image is now **sing-box + Xray**, not sing-box alone.
- The `iran-ips` address-list is gone. The tunnel carries everything.
- `MikFailOpen` / `MikFallbackGw` are gone: when the tunnel is down, traffic
  is dropped (fail-closed).
- The LAN panel has no password — anyone on the LAN can switch the node.
- `MikTable`, `MikRefreshRouterDirect` are gone (table name is fixed:
  `mik-tunnel`).
- The auto-route scheduler and `cgi-bin/health` are gone.
- `ADMIN_PASSWORD` / `MikAdminPassword` are gone; sessions, cookies and the
  login page are gone.
- The `v2raymik.rsc` file installs and uninstalls in one import.

The full list of changes is in `CHANGELOG.md`.
