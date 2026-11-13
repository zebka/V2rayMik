# Admin UI: subscriptions, testing, selecting a config

Status: implemented (0.2.0–0.4.0). Kept as the design record; the current
behaviour is described in the README and `CHANGELOG.md`. As of 1.1.0 the panel
is passwordless (anyone on the LAN), the `iran-ips` split is gone, and `Xray`
means the Xray engine, which runs as a local SOCKS outlet chained under
sing-box rather than owning the TUN.

## 1. Intent

Right now switching exit means editing a RouterOS env var, restarting a container
and hoping. That is fine for the person who built it and hostile to everyone else.

This adds a small local web page served by the router: paste a subscription URL or
a single link, see every config in it tested (204 reachability and download speed)
side by side, click one, and the router's world egress moves to it. The model is
PassWall2's node list, reduced to what one container can honestly do.

Non-goal: per-client / per-device routing, load balancing, failover groups,
rule-based splitting inside the container. The RouterOS `iran-ips` split stays
exactly where it is.

## 2. Where it runs (decided: integrated)

One container, one image. The admin HTTP server is a second process inside the
same container as Xray, started by the same entrypoint.

Why not a separate container: the user wants one thing to deploy and one thing to
look at. The cost is real and is paid explicitly in §7 (the HTTP process shares
the container with the transport, so it must never be able to widen the
container's privileges).

## 3. Process model

```
PID 1: entrypoint (shell supervisor)
 ├── busybox httpd :8080            (serves /app/web, runs /app/cgi/*)
 └── xray run -c /data/config.json  (restarts on HUP)
```

- `state.json` (in the persistent root-dir) is the single source of truth:
  `{ "outbound": {...}, "label": "...", "sub_url": "...", "updated": "ISO" }`.
- On boot: state wins; if there is no state, fall back to `XRAY_OUTBOUND_JSON` /
  `XRAY_LINK` / `XRAY_OUTBOUND_FILE` as today, so an existing install upgrades
  without touching the router.
- The supervisor renders `config.json` from state, starts Xray, and `wait`s.
  A CGI that changes the active config sends `HUP` to PID 1; the trap stops Xray
  and the loop starts it again. No RouterOS call, no container restart, no
  `restart-policy` involved: switching a node is ~2 seconds and the tunnel's
  routes stay untouched.

## 4. Pages and endpoints

`GET /` — the only page. Vanilla HTML/CSS/JS, no framework, no CDN.

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/cgi/login` | POST | password → session cookie |
| `/cgi/state` | GET | current label, exit IP, container health, test-in-progress flag |
| `/cgi/sub` | POST | save a subscription URL or pasted links, return the parsed list |
| `/cgi/test` | POST | test one config by index; returns `{code, ms, mbps, error}` |
| `/cgi/connect` | POST | make one config active, restart Xray, return the new state |

Rules:

- Every response is JSON except `/`.
- The config list is re-parsed on each `/cgi/state` from the cached subscription
  body (stored at `sub.txt`), so no index drift between calls: indices are the
  line numbers of that file.
- Secrets never leave the container: the list exposes `label`, protocol,
  `host:port`, and the test results. No UUID, no key, no full link, not even
  masked — the browser has no use for them.
- Tests are serialised by a lock file. A second concurrent test returns
  `{"busy": true}` instead of stacking CPU work on a 4-core router.

## 5. How a test works

Per config, sequentially:

1. Write `test.json`: a `socks` inbound on `127.0.0.1:10800` + the candidate
   outbound.
2. Add a host route for the candidate's endpoint: `<ip>/32 via <gateway> dev
   <iface>`. **This is essential**: inside the container `0.0.0.0/1` points at
   `tun0`, so without it the test of node B would travel through node A and
   measure the wrong thing.
3. Start `xray run -c test.json`, wait for the port (max 3 s).
4. Reachability: `curl -so /dev/null -w '%{http_code} %{time_total}' --max-time 8
   --socks5-hostname 127.0.0.1:10800 http://connectivitycheck.gstatic.com/generate_204`
   → `204` is a pass.
5. Speed: `curl -so /dev/null -w '%{speed_download}' --max-time 15
   --socks5-hostname 127.0.0.1:10800 "$SPEED_URL"` (default: Cloudflare's 10 MB
   endpoint) → bytes/s → Mbps.
6. Always: kill the test Xray, remove the host route, release the lock.

Timeouts are hard: a dead node costs 8 s, never a hung page.

## 6. Subscription handling

- Fetch with `curl` (direct, unmarked egress) into `sub.txt`.
- If the body is base64 (the common v2ray format), decode it.
- Split on whitespace; keep lines that parse with the existing `links.sh`
  (vless/vmess/trojan/ss). Unparseable lines are reported, not silently dropped.
- A pasted link (no subscription) is supported as a one-entry list.
- Refresh is explicit (a button). No polling, no scheduler.

## 7. The admin plane must survive a dead tunnel

Inside the container `0.0.0.0/1` and `128.0.0.0/1` point at `tun0`; only the
active endpoint has a `/32` bypass. So by default the subscription fetch, the
container's DNS and every test dial would travel through the *currently active*
node — the exact case where the page is needed most.

The supervisor therefore maintains a second set of host routes, "the admin
bypass": `/32 via <gateway> dev <iface>` for

- the subscription host (resolved at fetch time), and
- the two DNS resolvers the container uses.

Effects: a subscription can be refreshed and a dead node replaced while the
active tunnel is down. Cost: those few admin lookups go direct (ISP could poison
them); user DNS is untouched because the router's DNS still travels through the
tunnel to the container. The bypass entries are removed when their config does
not need them, and `99-uninstall.rsc` never sees them (they live inside the
container).

## 8. Ports outside the allowlist

A candidate whose port is not in `XrayContainerToWanPorts` will "test" as dead:
RouterOS' forward chain drops it silently. The UI parses the port, marks such
entries **blocked by the egress allowlist**, refuses to connect to them, and
shows the exact one-line command that adds the port. It does not widen the
allowlist itself — that boundary is the operator's (§ security).

## 9. What "connect" means, and what happens when it fails

`/cgi/connect`:

1. Write `state.json` as `pending` (previous outbound kept aside as `last_good`).
2. Resolve the candidate's endpoint and pin that address into the outbound.
3. `HUP` the supervisor; it renders and starts Xray.
4. Wait up to 12 s for: `tun0` present, `verify_routes` green, and a 204 through
   the TUN. 
5. On success: mark `active`. On failure: restore `last_good`, restart, and
   return the error to the page.

A candidate that was never tested, or tested badly, can still be connected — after
an explicit confirmation dialog. The UI is not the police; it just must not let a
typo silently blackhole the house.

A switch takes ~2–3 s. During that window `tun0` is gone, so packets routed to
the container are dropped, not leaked: the RouterOS world route still points at
`172.17.0.2` and stays active. That is the accepted contract; a pre-warmed second
TUN is out of scope.

## 10. Security

The HTTP process lives next to the transport, so:

- **Only RouterOS decides who can reach it.** The container listens on `:8080`;
  a `dst-nat` on the router forwards one LAN address:port, and the existing
  input/forward rules keep it off the WAN. No `available-from` on WAN, no
  auto-open.
- **Password required**, set with `ADMIN_PASSWORD`. If it is unset the service
  refuses to start and says so in the log — no accidental open panel.
- Session cookie: `HttpOnly`, `SameSite=Strict`, random 32-hex token, server-side
  expiry (2 h), no JWT, no crypto library.
- **CSRF**: every mutating request needs the session's token in a header; the page
  reads it from a meta tag.
- **No shell interpolation from the browser.** CGI receives only integers and
  enums; anything else is rejected. The subscription URL is the one string that
  reaches `curl`, and it is passed as a single argv plus `--proto =http,https`.
- **No arbitrary file reads**: no endpoint takes a path.
- The test lock and a 1-request-per-second ceiling per session.
- The outbound (with UUIDs) lives in `state.json`, mode 600, on the USB disk.
- The page never echoes the subscription URL back; it shows the hostname only.
- If `ADMIN_PASSWORD` is unset, **only the HTTP server stays down**; Xray runs
  normally and the log says `admin-disabled: ADMIN_PASSWORD is not set`. An
  existing install can upgrade without crash-looping.
- `/cgi/test` and `/cgi/connect` must carry the `gen` hash returned by
  `/cgi/state`. Any refresh of `sub.txt` changes it; a stale request gets `409`
  instead of acting on a shifted index.
- `/cgi/sub` is refused while a test holds the lock.

## 11. Testing behaviour

- Per-entry test and an explicit "test all"; both are driven by the browser as a
  sequence of `/cgi/test` calls, so there is no background runner to babysit.
- Closing the tab stops the run. A "cancel" button simply stops issuing requests.
- Selection is per entry; the results table keeps the last result per index until
  the list changes.

## 12. RouterOS changes

- `04-admin.rsc` (new): `dst-nat` LAN → `172.17.0.2:8080`, and a comment-documented
  place in the firewall for the LAN-only restriction. Idempotent, removed by
  `99-uninstall.rsc`.
- The container's egress allowlist already covers 80/443 for the subscription and
  the speed file.
- Nothing else changes: the world route, mangle, MSS and NAT are untouched.

## 13. Image changes

- Base stays `alpine`; add `curl` (SOCKS testing) and keep busybox `httpd`.
- No new daemon beyond `httpd`.
- Image growth budget: +3 MB compressed.

## 14. Verification

- Unit: subscription parsing (base64, mixed, garbage), label extraction, secret
  redaction in `/cgi/state` output, CSRF rejection, bad-index rejection.
- Integration in Docker: two fake endpoints (one reachable, one blackholed) →
  `/cgi/test` returns 204+speed for the first, a bounded timeout for the second,
  and never blocks the main Xray.
- On device: switch between two real configs, confirm the exit IP changes within
  ~3 s and the router's world traffic never drops (ping a public host in a loop).
- Reboot: state survives, the last chosen config comes back.

## 15. Decisions taken after the builder check

1. **Failed switch:** verify, then commit; automatic rollback to `last_good` (§9).
   One bad click cannot take the house down.
2. **Outage window:** ~2–3 s of dropped packets per switch is accepted. It is a
   drop, not a leak, because the world route stays pointed at the container.
3. **Admin plane:** subscription, resolver and test dials get their own `/32`
   bypasses, so the page works even when the active tunnel is dead (§7).
4. **Ports outside the allowlist:** labelled and refused, never auto-widened (§8).
5. **`ADMIN_PASSWORD`:** from the container env; when absent the UI is disabled and
   Xray keeps running — no crash loop (§10).
6. **Index safety:** a `gen` hash guards every mutating call (§10).
7. **`ENDPOINT_IP`:** ignored in state-driven mode; the endpoint address is
   resolved and pinned per config at activation (§9, step 2).
8. **Testing:** on demand, browser-driven, cancelable (§11).

## 16. Left to the builder

- Exact busybox httpd CGI invocation and whether `httpd -h /app/web -f` is enough
  on Alpine 3.22; if not, `lighttpd` is the fallback (and the size budget grows).
- Session storage shape (a directory of token files vs one file).
- How the page renders a config with no label: `protocol host:port` truncated.
- Whether the speed endpoint should be configurable in the UI; default no.
