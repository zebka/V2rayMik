# Changelog
## 1.3.5 - 2026-11-14

### Fixed

- **Disks are detected by their real file type.** RouterOS lists a whole
  drive such as `pcie1` or `usb2` with type `disk`, not `directory`, so the
  auto-detect never matched it and fell back to `flash`. Both types are now
  accepted, in the detect, the explicit `MikDisk` check and the error's list
  of existing mounts.

## 1.3.4 - 2026-11-14

### Fixed

- **A PCIe or NVMe disk is detected.** Auto-detect did not know `pcie1` (and
  `pcie2`), so on a router with an M.2/PCIe disk the container, its data and
  the image landed on the small internal flash. `pcie1`/`pcie2` are now
  candidates, ahead of flash.

## 1.3.3 - 2026-11-14

### Fixed

- **Uninstall no longer aborts on a container that is still stopping.** The
  1.3.2 wait checked the container's state once and then removed it anyway.
  Uninstall now retries the removal for up to 40 seconds and stops with a
  clear message if the container never goes away.

## 1.3.2 - 2026-11-14

Reinstall works straight after an uninstall, in the same terminal.

### Fixed

- **Uninstall then install no longer fails.** `:global MikMode "uninstall"`
  stayed set in the terminal, so the next import ran the uninstall again and
  never installed. The uninstall now resets `MikMode` to `install` when it
  finishes.
- **Uninstall waits for the container to stop** before removing it. A fixed
  3-second delay was not enough, and `/container remove` refused a container
  that was still running.

## 1.3.1 - 2026-11-14

Disk detection works on partitioned USB storage and fails with the names
that are actually there.

### Fixed

- **A partitioned USB stick is now detected.** RouterOS mounts a formatted,
  partitioned drive as `usb2-part1`, not `usb2` — the auto-detect only
  matched the bare name and fell back to the small internal flash, and an
  explicit `MikDisk "usb2"` stopped the import with "does not exist" on a
  router where the stick was sitting right there. The detect now tries
  `<disk>` and `<disk>-part1` per candidate (usb1–3, sata1/2, nvme1, mmc1,
  sd1, nand1, flash, data).
- The MikDisk validation error lists the mounts that exist on the router
  (`existing mounts: usb2-part1 flash ...`), so the right name is visible
  without guessing.
- Prefer auto-detect over pinning `MikDisk` on USB storage: on some hardware
  the same stick enumerates as usb1 after a reboot and a pinned name breaks
  the next import.

## 1.3.0 - 2026-11-13

Zero-config: the import no longer names one of your interfaces, disks or
subnets, and the egress port allowlist is gone.

### Changed

- **`MikWan`, `MikLanSubnet`, `MikContainerToWanPorts`, `MikExtraWanPorts`
  are removed.** Nothing in the file needs per-router editing anymore; a
  fresh import runs unmodified on any device.
- **`MikDisk` is detected** (first existing of usb1–3, sata1/2, mmc1, sd1,
  nand1, flash, data). Setting it by hand still works and now fails with a
  clear error when the disk does not exist — `/file add name="nodisk/x"`
  silently creates junk on 7.25.1, so a silent default was worse than none.
- **The LAN is the fixed `mik-private` address list** (127/8, 10/8,
  172.16/12, 192.168/16, 169.254/16) instead of a guessed `MikLanSubnet`:
  - the "mik: router to LAN" mangle matches `dst-address-list=mik-private`,
    so the router stays reachable from every private range, not from one
    guessed subnet (on 1.2.7 the printed rule had a stale subnet);
  - the panel's `dst-nat` requires `src-address-list=mik-private` instead of
    `in-interface-list=LAN` — no interface list to have wrong or empty;
  - the container's egress is denied into private space by
    `dst-address-list=!mik-private`.
- **The container's egress is no longer filtered by port.** The accept pair
  (tcp/udp × `MikContainerToWanPorts`/`MikExtraWanPorts`) is replaced by one
  accept to any non-private destination and the existing default deny.
  Ports belong to whoever runs the node and are never knowable in advance;
  the old list failed silently (the engine redialed forever, nothing logged)
  and marked real configs `port blocked` in the panel. The trade — a
  compromised image can now reach the internet on any port, but never the
  LAN — is written down in `docs/security.md`.
- `MikAllowContainerToLan=true` now widens that single accept to everything
  and removes the deny rule, instead of adding a separate LAN rule.
- **Panel:** `ALLOWED_PORTS` is gone from the image and removed from the
  container env on re-import; rows no longer show `port blocked` and Test /
  Connect are enabled for every parseable entry.
- **A fresh install now starts the container.** After the image pull finishes,
  RouterOS leaves the just-added container `stopped` forever (7.25.1) — the
  import now waits for the pull and starts it, so a first install needs no
  manual `/container start`.
- **The container's egress is NAT'd by the project itself.** The tunnel's
  transport dial left with the container's address as source and only worked
  on routers whose whole-WAN masquerade happened to cover it; one explicit
  `src-address=$MikSubnet` masquerade (`mik: container egress`) now ships
  with the install, so the tunnel comes up on a bare firewall too.

### Upgrade

Re-import `v2raymik.rsc`: the ≤1.2.x port rules, the LAN-scoped dst-nat and
the old `ALLOWED_PORTS` env are removed by comment/key, and the new rules are
added in their place. `/container/repull` picks up the new image.

## 1.2.7 - 2026-11-13

### Fixed

- **The router was unreachable from its own LAN.** With the tunnel
  installed, the router's own replies to any LAN address were routed
  into the tunnel (as "!local" traffic), so the router never answered
  ARP-adjacent ports: SSH, Winbox, ping, DNS, anything.
  A "mik: router to LAN" accept now exempts the router's traffic to
  MikLanSubnet in the output chain before any marking.

## 1.2.6 - 2026-11-13

### Fixed

- **Uninstall did not remove the "mik: container replies (established)"
  rule** added in 1.2.4 for the panel return path on stripped-down
  configs. The uninstall filter list now includes it, so an uninstall
  leaves no project rules behind.

## 1.2.5 - 2026-11-13

### Fixed

- **Uninstall failed on a freshly-installed router.** RouterOS 7
  injects the veth's connected route into every fib table, so a
  blanket "remove every route in the table" hit a dynamic route
  owned by the system and the uninstall stopped before touching
  anything else. Routes are now removed by comment (only the ones
  this project creates), and the fib tables are removed last, after
  the veth is gone.

## 1.2.4 - 2026-11-13

### Fixed

- **The panel is unreachable on stripped-down RouterOS configs.** A LAN
  client reaches the container through the dst-nat fine, but the
  container's replies (SYN-ACK, then the rest) were dropped by
  "mik: container default deny" on any device whose forward chain had
  no stock "accept established" rule (CHR and custom exports).
  The script now inserts an explicit established/related/untracked
  accept for the container side itself, so the reply path works
  regardless of the stock rules.

## 1.2.3 - 2026-11-13

### Fixed

- **`is_json` only accepted an argument but was piped one instead**: with
  `set -u`, calling it on stdin printed "1: parameter not set" and every
  Xray outbound looked invalid. It now accepts either an argument or stdin.

### History

- 1.2.0: test fixture had one brace too many; CI stopped the release.
- 1.2.1: fixture fixed; the Xray render was empty (`jq` without `-n` runs
  zero times with no input documents); CI stopped the release again.
- 1.2.2: `-n` fixed and the release kept failing in the Xray section on
  `is_json`, the bug above. The release has still never shipped an image.

## 1.2.2 - 2026-11-13

### Fixed

- **`xray_config` rendered an empty plan, and the Xray end of the CI
  therefore always failed at "xray plan has no socks inbound".** `jq`
  without `-n` runs the filter once per input document, and there is no
  input document - the outbound arrives on stdin only for the
  validation step, not for the render. The render now uses `-n` like
  `render_config` already did, and xray-backed nodes boot.

### History

- 1.2.0 failed to ship: its Xray test fixture had one brace too many.
- 1.2.1 fixed the fixture, but the Xray render produced an empty plan
  for the reason above; CI refused the release again, so no broken image
  was ever published. Both failures were CI doing its job.

## 1.2.1 - 2026-11-13

### Fixed

- **The 1.2.0 CI refused to ship the release**, correctly. The Xray side
  rendered its config with a bare `jq -c` filter that produced no output on
  error and no diagnostics when the outbound was not JSON at all. The config
  now renders the same way the sing-box side does (outbound validated with
  `jq -e`, rendered via `--slurpfile`), so a broken Xray outbound fails with
  an error instead of an empty file.
- **The Xray unit-test fixture had one brace too many**, which is what the
  failing test actually pointed at. Balanced.

## 1.2.0 - 2026-11-13

Everything in this release went in one direction: fewer moving parts, one
file on the router, one door on the LAN — and two engines so no config range
is out of reach. If you upgrade from 1.0.x, read the migration note at the
bottom before importing.

This release also merges the parallel 1.1.x line (1.1.0–1.1.2), published
while this rework was in flight: those fixes are carried over, and the
1.1.0 Stop button is deliberately not. 1.2.0 is fail-closed with no fallback
at all - the split and the auto-route that powered Stop are gone.

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
- **The subscription fetch is hardened end to end**: a cap of 2 MB, HTTPS-only
  redirects (max 3, downgrades refused), private hosts refused, and a plain
  browser User-Agent — a "v2ray" one is dropped silently by some provider
  edges and DPI. A failed fetch names its own error instead of a bare
  "could not fetch".

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

### Merged from the 1.1.x line

- Everything from 1.1.2, 1.1.1 and 1.1.0 is in this release; 1.2.0 supersedes
  that line: the fetch sends a plain browser User-Agent (a v2ray-flavoured one
  is dropped by provider edges and DPI with zero bytes back), a failed test
  names curl exit and the engine last line, a failed import no longer wipes a
  cached list, and a sing-box JSON profile link is named instead of called
  broken.
- The 1.1.0 Stop button (bypass.flag, the health bypass=1 field, the
  scheduler, the ISP fallback route) is not carried over. It was a deliberate
  use-the-ISP-now switch; 1.2.0 made the opposite decision: no fallback
  exists anywhere in the design, only fail-closed drop. If that switch
  matters, it is a separate feature to debate.

## 1.1.2 — 2026-11-07

### Fixed

- **A subscription no longer hangs because of our own name.** The fetch sent
  `User-Agent: v2raymik-admin`. Measured against a real provider panel: no UA,
  `curl/x` and `clash/x` answer `200` in ~0.4 s, while `v2raymik-admin`,
  `v2raymik` and `v2rayNG/1.8.5` get **no answer at all** until the timeout —
  a User-Agent containing `v2ray` is dropped silently, by DPI or by the
  provider's edge. The panel now sends a plain browser User-Agent. Before this,
  the operator saw "the subscription does not import at all" while pasting one
  of its nodes by hand worked, which points away from the fetch.
- **A sing-box JSON profile is named instead of being called broken.** Some
  panels hand out a sing-box profile at the subscription URL. It is a valid
  subscription that this panel cannot eat (it wants links), so the message now
  says exactly that: `that link is a sing-box JSON profile, not a list of links;
  pick the v2ray/links subscription in the provider panel`. An unrecognised
  payload reports its byte size and line count, and an HTML answer is still
  named as a block or login page.

## 1.1.1 — 2026-11-07

### Fixed

- **A failed test now says why.** The panel used to answer a bare
  `{"code":0,"ms":0,"mbps":0,"country":"","error":""}` for every kind of failure —
  a dead endpoint, a refused port, a poisoned DNS answer and a node whose REALITY
  key no longer matches all looked identical, and the web page printed
  `unreachable`. `xtest` now keeps curl's exit status, reports the real elapsed
  time instead of `0` for fast failures, and appends the engine's last line with
  its terminal colour and the `using outbound/...` preamble stripped. What the
  operator sees is one sentence: `timed out after 8s`, `connection refused`,
  `the proxy could not open the connection; sing-box: reality verification
  failed`, `the check answered http 403`.
- **A failed import no longer wipes the working list.** `sub` replaced
  `/data/sub.txt` first and parsed afterwards, so a provider that answered with a
  login page or an empty payload left the panel with zero configs and nothing to
  test. The payload is now parsed in `sub.tmp`, and only a payload with at least
  one usable link replaces the cached list.
- **The subscription fetch names its own failure.** `-f` collapsed an HTTP 403, a
  bad certificate and a poisoned DNS answer into `could not fetch the
  subscription`. The fetch now reports the HTTP status (`the subscription
  answered HTTP 403`), curl's exit code and first line (`could not fetch: curl 6
  Could not resolve host: ...`), and recognises an HTML page (`the subscription
  returned a web page, not configs`), which is what a block page or an expired
  login looks like.

No behaviour changed for a config that tests fine: the check URL, the speed
measurement and the exit-country lookup are the same.

## 1.1.0 — 2026-11-07

### Added

- **Stop, from the panel.** A Stop button makes the router send traffic out
  through the ISP *on purpose*: the container writes `/data/bypass.flag` and
  `health` then answers `selected=0`, so the router's scheduler takes the branch
  it already takes for a dead node. `sing-box` is **not** killed and `tun0` stays
  up, so the container's healthcheck and `restart-policy=always` never fire —
  a deliberate stop must not look like a crash, or `stop-on-unhealthy` would
  restart exactly what was stopped. Start removes the flag and traffic returns to
  the node still recorded in `state.json`; connecting a config clears the flag
  too. The flag lives on the disk, so a stop survives a reboot.
  New endpoint: `POST /cgi-bin/power` with `state=stop|start`.
- `health` answers a fourth field, `bypass=0|1`. The router's scheduler ignores
  it (it reads `selected=`, `up=`, `live=`), so an old scheduler keeps working
  against a new image; it is there so a raw fetch says *why* a node that is up is
  not selected.

### Changed

- **The world route now follows the panel in ~10 seconds, both ways.** The
  scheduler ticks every **10 s** instead of 30 s, and **one** sample decides in
  each direction instead of three good samples before returning to the tunnel.
  This removes the damping on purpose: returning took 60–90 s, longer than a page
  load waits, and the cost of a node that wobbles is two route flips rather than a
  minute on the ISP.
- `live.cache` in `health` is valid for **5 s** instead of 20 s, so a 10 s poll
  always gets a fresh probe; the probe timeout dropped from 4 s to 3 s so the
  whole answer fits inside the router's 4 s fetch.
- `health` counts the Stop flag as "not selected". Both a stopped tunnel and a
  dead node fall back to the ISP, which is the same thing the router has to do in
  either case.

### Fixed

- **The panel says what the router is actually doing.** The world-route line was
  hard-wired to "tunnel" unless Stop was pressed, so a router with no node chosen
  or with `tun0` down claimed a tunnel that was not there. It now reads
  "ISP, no node chosen", "ISP, tunnel down", "tunnel" or
  "ISP, stopped on purpose", and the Stop button is disabled while there is
  nothing to stop.
- The "testing…" pill was visible all the time: `.pill` sets
  `display:inline-block`, which beats the browser's own `[hidden]` rule.
- The page paints its own `Canvas` background instead of relying on the browser's
  default, so it stays readable in a webview that makes the page transparent.

### Upgrading

`05-auto-route.rsc` only creates what is missing, so an existing install keeps its
30 s scheduler and its 3-sample return — and prints a warning saying so on import.
On a router that already runs it:

```
/system script remove [find where name="mik-auto-route"]
/system scheduler remove [find where name="mik-auto-route"]
/import file-name=05-auto-route.rsc
```

The image has to move too: Stop is a container change, and with a 1.0.x image the
panel has no Stop button at all. With the new image and an old router script, Stop
works but Start takes the old 60–90 s to come back.

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
