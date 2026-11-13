# Changelog

## 1.1.0 - 2026-11-13

Everything in this release went in one direction: fewer moving parts, one
file on the router, one door on the LAN — and two engines so no config range
is out of reach. If you upgrade from 1.0.x, read the migration note at the
bottom before importing.

### Breaking

- **The Iran/foreign split is gone.** No `iran-ips`, no address lists, no
  per-destination exceptions, no `router-direct` entries. Every IPv4
  destination except the container subnet is carried by the tunnel.
  Router-originated traffic included. The consequences are documented in
  `docs/troubleshooting.md` (MikroTik DDNS will publish the exit address now)
  and `docs/security.md`.
- **There is no fallback route, at all.** `MikFailOpen` and `MikFallbackGw`
  are gone. When the tunnel is down, marked traffic is dropped. This was a
  deliberate choice for this release: a silent fall-back to the ISP leaked
  the real address on every outage.
- **The five `.rsc` files became one.** `router/00-vars.rsc` …
  `router/05-auto-route.rsc`, `router/90-migrate-from-xray.rsc` and
  `router/99-uninstall.rsc` were replaced by `router/v2raymik.rsc`:
  `/import file-name=v2raymik.rsc` installs and upgrades,
  `:global MikMode "uninstall"` + the same import removes everything the
  project creates (including the legacy 1.x leftovers the old uninstall left
  behind: the `MSS clamp back` and `MSS clamp (router output)` rules, the
  extra transport pair, the `mik-tunnel`/`to-world` tables, `MOUNT_MIK_DATA`).
- **`MikTable`, `MikRefreshRouterDirect` are gone** (one table, fixed name
  `mik-tunnel`; nothing left to re-resolve).
- **The auto-route scheduler is gone.** `mik-auto-route` and its
  `/tool fetch` of `cgi-bin/health` are removed; `cgi-bin/health` and the
  `/ip route` toggling it did are gone with them. The route in `mik-tunnel`
  stays enabled; traffic drops while the tunnel is down.
- **The panel is passwordless.** `MikAdminPassword`, `ADMIN_PASSWORD`,
  sessions, cookies and the login page are all removed. Anyone on the LAN
  can load a subscription and switch the node; the only exposure is the same
  LAN `dst-nat` as before. If that is not acceptable, block the port on the
  bridge instead of asking for a password back — the panel is honest about
  what it is now.

### Added

- **Both engines, per node, automatically.** The image now carries sing-box
  1.14.4 and Xray v26.11.9, both downloaded with sha256 verification against
  the GitHub-reported digests (the base image is pinned by digest too).
  - **sing-box** (default): hysteria2, tuic, vless/vmess/trojan/ss, REALITY,
    ws/grpc/httpupgrade.
  - **Xray**, picked automatically for: `type=xhttp|splithttp` and vless
    `encryption=…` links. sing-box cannot speak those; Xray can.
  - For an Xray node, xray runs as a local SOCKS5 outlet on 127.0.0.1 and
    sing-box — which owns the TUN — chains to it. One TUN, both engines, no
    second container, no second route set.
  - The panel shows which engine a test or the active connection used, and
    `state.json`/`status.json` record it.
- **`MikroTik DDNS no longer silently breaks.** With nothing kept direct,
  `/ip cloud` publishes the tunnel exit; this is now documented instead of
  being handled by a special case.

### Fixed

- **`01-container.rsc` reopening used to clobber `registry-url`** back to
  `docker.io` on every re-import, silently undoing the Iranian mirror the
  docs recommend. The registry URL is a variable (`MikRegistryUrl`) now.
- **`99-uninstall.rsc` left firewall rules and a routing table behind.**
  The MSS clamp rules and the connected-route row survived every uninstall;
  the new single file removes every object it and the old scripts created.
- **`connect` could read a stale `status.json`** from the node it was just
  replacing and roll back a healthy switch. It waits for a status written
  after its own reload now.
- **Failing to decode a hysteria2 `pinSHA256` no longer drops the pin
  silently**; it says so and fails the link instead.
- **`hex_to_b64` reported success on failure** when `xxd` was missing.
- **`urldecode` turned a literal backslash into an escape**, mangling
  passwords that contained one.
- **`TUN_MTU` with a non-numeric value made the container crash-loop**; it
  falls back to 1500.
- **The test harness leaked a sing-box and a `/32` bypass** if it was killed
  mid-test; cleanup is now wired to EXIT/INT/TERM.
- **Dead code removed** (`reapply_endpoint_route`, never called).
- **The subscription fetch no longer follows redirects and caps at 2 MB**,
  and refuses hosts that look private — the panel is reachable by anyone on
  the LAN, so its one free-form URL is now a narrow one.

### Changed

- **`index.html` no longer inlines its script**; the panel is served with a
  `Content-Security-Policy` (`default-src 'self'`).
- **CI pins every action by SHA**, and builds verify both engines run.

### Not yet verified

- The Xray path (xhttp/splithttp links, vless `encryption=…`) has no
  live-device run behind it yet; the sing-box path is unchanged. Xray nodes
  are tested by the same `xtest` harness, but treat them as experimental
  until you measure them yourself.
- The full-tunnel design has not been measured on hardware yet; the split
  design's benchmarks (docs/benchmarks.md) do not transfer automatically.

### Migration from 1.0.x

1. Import the new file in uninstall mode to remove the old install:
   `:global MikMode "uninstall"` then `/import file-name=v2raymik.rsc`.
   (The old `99-uninstall.rsc` is not needed and leaving it out is fine.)
2. Open a new terminal, `:global MikMode` is gone, and
   `/import file-name=v2raymik.rsc` installs the new shape.
3. `state.json` is not carried over; pick the node in the panel once.

## 1.0.1 — 2026-11-06

### Fixed

- **`01-container.rsc`, `02-routing.rsc` and `03-firewall.rsc` import again.**
  The three files shipped with a UTF-8 byte-order mark in front of the first
  `#`. RouterOS reads the first line of an imported file as a command, so
  `/import` answered `Script Error: expected command name (line 1 column 1)` and
  skipped the whole file — while the next line of the operator's paste still
  printed, so a fresh install stalled at `01-container.rsc` with nothing in the
  log to say why. The BOMs are gone, and `tests/lint-rsc.sh` now fails on a BOM
  in any router script or test script, because editors add one silently.
- **`05-auto-route.rsc` no longer raises an argument error when the world route
  is missing.** The "no `mik-world` route" branch ended in a bare `:return`,
  which on 7.25 fails with `missing value(s) of argument(s) value (:return)`:
  the closing brace is read as the missing argument. It returns an explicit value
  now. Only reachable in a half-finished install, but it wrote a script error to
  the log on every 30-second run.
- **`90-migrate-from-xray.rsc` prints a LAN subnet with its prefix.**
  `/ip address get <id> network` returns `192.168.88.0` on 7.25 — no `/24` — and
  the migration took that at face value: the printed `MikLanSubnet` had no
  prefix, and because the string was not empty the "guessed, check it" warning
  never appeared. The length is read from the address itself now, a value
  without a prefix counts as not found, and `MikFailOpen` is guessed as `true`
  (the shipped default) instead of `false`, since a hand-built install has no
  route commented `xray-fallback`.
- **`02-routing.rsc` stops warning about the route it created itself.** The
  competing-distance-1 check looked at every row in the table, so on the second
  import it found `mik: connected to container` — the row `02-routing.rsc`
  creates so the gateway is reachable — and logged "disable it or the exit is
  per-connection random". It only considers `0.0.0.0/0` now.

## 1.0.0 — 2026-11-06

### Changed

- **The project is V2rayMik.** The repository is `zebka/V2rayMik`, the image is
  `azebka/v2raymik` (also `ghcr.io/zebka/v2raymik`), the container is
  `v2raymik`, the router globals are `Mik*`, object comments start with `mik: `,
  and the persistent data lives in `/usb2/v2raymik-data`. The name matches what
  the project has been since 0.5.0 — a sing-box gateway — instead of the Xray
  name it shipped under until 0.4.x.
- **An existing install moves over with one import.**
  `router/90-migrate-from-xray.rsc` reads every value from the device, stops and
  removes the old container, removes the old veth and its `172.17.0.1/24`
  address, the old mount, env list, firewall rules, routes and scheduler, copies
  `sub.txt` to the new data directory, and prints the `:global Mik*` block to
  paste into `00-vars.rsc`. Running it twice prints "nothing to migrate" and
  changes nothing. The old root-dir and data directory are left in place as the
  rollback path. Both READMEs carry the same section.

### Breaking

- **The deprecated `XRAY_LINK`, `XRAY_OUTBOUND_JSON`, `XRAY_OUTBOUND_FILE` and
  `XRAY_LOG_LEVEL` environment names are no longer read.** They have been
  aliases since 0.5.0; `NODE_LINK`, `NODE_OUTBOUND_JSON`, `NODE_OUTBOUND_FILE`
  and `SINGBOX_LOG_LEVEL` are the names, and a set that only carries the old
  ones now falls back to the default instead of being picked up.
- **Anything that matches our object comments has to match `mik: `.** The
  firewall, mangle and route comments changed from `xray: ` to `mik: `, and the
  objects themselves are recreated under their new names.

### Fixed

- **`99-uninstall.rsc` removes the container again.** The section header comment
  and the section's `:if` had been merged onto one line, so the entire
  container-removal block was part of the comment: uninstall removed the routes
  and the firewall rules and then left the container and its plumbing behind.
- **`01-container.rsc` points the outbound file at the documented path.** The
  `NODE_OUTBOUND_FILE` entry was created with `/etc/xray/outbound.json` while
  everything else — the entrypoint's own default, the READMEs, the data
  directory the mount creates — uses `/etc/sing-box/outbound.json`. A JSON-file
  install therefore found nothing at the path it was told about. The env name is
  also `NODE_OUTBOUND_FILE` now, matching the other three.

### Docs

- Both READMEs, the Docker Hub page and every live doc use the new names; the
  build pipeline, the `Makefile` default and the published tags follow. History
  (older changelog entries, benchmark numbers, the server-side reference) keeps
  the names it was written with, and the migration section is the only place
  that still spells the old ones out.

## 0.5.1 — 2026-11-06

### Fixed

- **The panel shows the node's exit country again.** The per-node test asked
  Cloudflare for the trace over plain HTTP, and `http://1.1.1.1/cdn-cgi/trace`
  answers `301 Moved Permanently`; the redirect page contains no `loc=` line, so
  the country came back empty while the delay and the 10 MB speed were measured
  correctly. The trace is now fetched over HTTPS, follows a redirect if one
  appears, and is parsed by one small function that has its own test — a
  non-trace answer can no longer turn into a bogus country.

### Docs

- The egress allowlist section named a variable that does not exist
  (`sing-boxContainerToWanPorts`); it is `XrayContainerToWanPorts`, and
  `XrayExtraWanPorts` is the one for a single provider port.
- Documented what a hysteria2 or TUIC node actually needs: its UDP port in
  `XrayExtraWanPorts`, which feeds both the firewall rule and the container's
  `ALLOWED_PORTS` — the list the admin page compares against before it enables Test
  and Connect.

## 0.5.0 — 2026-11-06

### Changed

- **The engine is sing-box, not Xray.** One config format covers vless, vmess,
  trojan, shadowsocks, **hysteria2** and tuic, and sing-box owns the TUN itself —
  so the container still has one process in the tunnel path and RouterOS still
  owns every route. The repository and image keep their historic name.
- **Hysteria2 / TUIC nodes work**, including the `obfs=salamander` and
  `pinSHA256` options that Iranian providers hand out. The panel tests and
  connects them like any other node. Verified on the reference router: a hysteria2
  node carried a 10 MB download in 3.2 s (≈25 Mbps) while the Xray-shaped nodes
  were still in the list.
- **A stale `pinSHA256` can no longer kill a node.** When a link also says
  `insecure=1`, the provider is telling clients not to verify, so the pin is
  dropped instead of enforced. Measured on a live node: the pin named a key the
  server never presented, sing-box refused the handshake
  (`unrecognized remote public key`), while the same link was fine in the
  hysteria2 client — which honours `insecure` over the pin.
- Environment names are now engine-neutral: `NODE_LINK`, `NODE_OUTBOUND_FILE`,
  `NODE_OUTBOUND_JSON`, `SINGBOX_LOG_LEVEL`. The old `XRAY_*` names still work.
- xhttp/splithttp links are **rejected with a named error**: sing-box has no such
  transport. WebSocket, gRPC and HTTPUpgrade are supported.
- `docs/` and both READMEs were rewritten around sing-box; `docs/dockerhub.md`
  follows.

### Notes

- A hysteria2/TUIC node is UDP: its port must be in the RouterOS container
  allowlist (`XrayContainerToWanPorts`/`XrayExtraWanPorts`, which kept their names
  for compatibility). The panel marks nodes whose port is missing as
  `port blocked`.
- The image grows to ~30 MB compressed because sing-box is a bigger binary.

## 0.4.2 — 2026-11-06

### Changed

- **The image and the repository now carry the same version, enforced.** A
  `VERSION` file is the single source of truth; CI refuses to build a `v*` tag
  that disagrees with it and refuses a `VERSION` with no `CHANGELOG` section.
  The value is written to `/app/VERSION` in the image and shown in the panel
  under **Status → image**.
- **`latest` now means "newest release"**, not "whatever is on `main`". Main
  builds publish `:edge`; only tag builds publish `:latest`, so the image you
  pull and the source tag are always the same code. `make check-version` runs the
  same check locally.

## 0.4.1 — 2026-11-06

### Changed

- The Docker Hub page is now generated from `docs/dockerhub.md` by CI on every
  release, so the two never drift.
- Every tag creates a GitHub release automatically.
- README (both languages) rewritten for people who are not the author: pinned
  image tags and the Iranian mirror, the optional `05-auto-route.rsc` step, the
  panel, the ISP fallback, honest performance numbers with their methods, and a
  "getting help" section.

### Fixed

- Removed a stray browser session file (`cookies.txt`) that had been committed by
  accident, and added it to `.gitignore`.
- Internal planning notes moved out of the published tree; the admin UI design
  record now lives in `docs/design/admin-ui.md`.

## 0.4.0 — 2026-11-06

### Changed

- **The fallback is the ISP, not another tunnel.** When the panel's node is not
  live, `05-auto-route.rsc` enables the default route through the ISP gateway
  (traffic leaves from the router's own address, in its own country) and keeps
  every other default route in the table — OpenVPN, WireGuard — disabled. A VPN
  fallback hid a dead node and silently changed the exit country.
- `02-routing.rsc` only adds `xray-fallback` when nothing else in the table
  already points at the ISP gateway, instead of skipping it whenever any
  distance-2 route exists.

## 0.3.3 — 2026-11-06

### Fixed

- Every imported `.rsc` file now declares the globals it reads. RouterOS scopes
  globals per script, so `01`…`99` saw `nothing` and refused to run when imported
  one file at a time, even after `00-vars.rsc`. `tests/lint-rsc.sh` enforces it.

## 0.3.2 — 2026-11-06

### Fixed

- An empty RouterOS array is `[:toarray ""]`, not `{}`; the auto-route script
  failed to import because of it.

## 0.3.1 — 2026-11-06

### Fixed

- `05-auto-route.rsc`: `/tool fetch` needs the `ftp` policy, otherwise the
  scheduler polls the health endpoint and silently gets nothing.
- The fallback route is found by shape (every other default route in the table)
  instead of by this project's device-specific comment.

## 0.3.0 — 2026-11-06

### Fixed

- **Connect now works.** `_common` never defined `STATUS_FILE`, so `connect`'s
  wait loop tested an empty path and rolled back every successful switch after
  12 s — even on a node that was up and passing traffic. The default is now set
  next to `state.json`, the wait is 20 s, and the 204 probe gets a second try.

## 0.2.9 — 2026-11-06

### Fixed

- `cgi-bin/health` and `cgi-bin/connect` landed in the image with a UTF-8 BOM,
  so busybox httpd could not exec them and `/cgi-bin/health` answered 404. Both
  files are stripped, and `tests/unit/cgi-headers.t.sh` now fails the build if any
  CGI script loses its shebang to a BOM or gains CRLF line endings.

## 0.2.8 — 2026-11-06

### Fixed

- Admin egress is now an `ip rule from <container-ip> lookup 100` with a default
  route in table 100, instead of a `/32` bypass per resolver. The `/32` also
  captured packets forwarded from the router, which bounced back out of the veth
  and looped: every test of `1.1.1.1` timed out.

## 0.2.7 — 2026-11-06

### Fixed

- Testing the config that is already active no longer deletes its endpoint
  `/32` bypass at the end of the test. Losing that bypass made the live tunnel
  route its own server address into itself, so every request looped.

## 0.2.6 — 2026-11-06

### Added

- `cgi-bin/health`: an unauthenticated plain-text endpoint (`selected=`, `up=`,
  `live=`) so RouterOS can follow the panel's choice without credentials.
- `router/05-auto-route.rsc`: a 30-second scheduler that moves the world route to
  Xray only while the panel reports a selected, up and live node, and back to the
  OpenVPN route otherwise. This is what makes "Connect" actually move traffic.

### Changed

- The panel's first column is **real delay** (✓ ms / ✗ timeout) and a **country**
  column shows the exit country reported by Cloudflare's trace through that node.

## 0.2.5 — 2026-11-06

Connect works again: `verify_routes` probed `1.1.1.1`, which the admin plane
deliberately bypasses, so every restart looked broken and rolled back. It now
probes a neutral address. Tests also report the exit country.

## 0.2.4 — 2026-11-06

### Added

- The image is published to Docker Hub as well as GHCR (CI runs both when the
  `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` secrets are set), so it can be pulled
  through an Iranian Docker Hub mirror.
- `XrayCheckCertificate` in `00-vars.rsc`, because `docker.arvancloud.ir` needs
  `check-certificate=no` on RouterOS.
- `docs/install-side-load.md` documents the mirror route and which mirrors were
  actually tested.

### Verified

`azebka/mikrotik-xray-gateway:latest` pulls on a hAP ax³ from
`docker.arvancloud.ir` (`arch=arm64`, ~90 s), container starts, panel answers.

## 0.2.2 — unreleased

CI fix: Docker Hub secrets are mapped to `env` (GitHub does not allow `secrets`
in `if:`).

## 0.2.1 — 2026-11-06

Fixes found by running a real subscription through the panel:

- Config indices are the raw payload line numbers; one unparseable link no longer
  shifts every row onto the wrong node.
- The test pins the resolved endpoint address, so a CDN endpoint cannot rotate to
  an address the `/32` bypass does not cover.
- `xhttp` (path/host/mode/extra) and `alpn` are parsed instead of dropped.
- Placeholder rows that point at `127.0.0.1` are filtered out of the list.
- `XrayExtraWanPorts`: a second allowlist rule, because RouterOS caps one
  `dst-port` list at 15 entries and a subscription easily uses more.

## 0.2.0 — 2026-11-06

### Added

- A LAN-only admin page inside the same container: subscription import, per-config
  testing (204 + 10 MB download through a temporary SOCKS instance), and verified
  node switching with automatic rollback.
- `docker/lib/{admin,subs,xtest}.sh`: sessions, subscription decoding, the test
  harness.
- `router/04-admin.rsc`: the `dst-nat` that exposes the panel to the LAN only.
- `ADMIN_PASSWORD`, `ALLOWED_PORTS`, `XrayAdminPort` and `XrayAdminLanPort`.

### Changed

- The entrypoint is now a supervisor: state first, environment second, and a
  `SIGHUP` restarts only the Xray child.
- `01-container.rsc` adds missing env entries one by one instead of only when the
  env list is empty, so upgrades do not reset values the panel has changed.
- Image grows by ~2 MB (curl, busybox-extras httpd, the web root).

### Notes

- Switching nodes costs ~2–3 s of dropped connections. Nothing leaks: the world
  route keeps pointing at the container.
- Configs whose port is outside the allowlist are marked `port blocked` and
  cannot be connected from the panel.

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
