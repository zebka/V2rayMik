# Troubleshooting

Symptom → cause → fix. Start with the container log:

```
/container/set [find where name="v2raymik"] logging=yes
/log print where topics~"container"
/container/shell [find where name="v2raymik"]
```

## Repeated dialing and nothing else

```
/log print where topics~"container" and message~"dialing"
```

If you see the same `dialing to tcp:<ip>:<port>` every few seconds and nothing
else, the endpoint is unreachable from your network — since 1.3.0 there is no
port allowlist that could be the cause. The usual suspects: the node is dead,
the port is blocked upstream, DNS resolves wrong (`resolve-failed` below), or
your network filters that destination. Nothing in the router needs editing.

## Symptom table

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Repeated `dialing to …` and nothing else | endpoint unreachable (dead node, upstream block, DNS) | verify the port from another network; there is no allowlist to extend |
| Container stops immediately, `missing-config` | neither `NODE_LINK` nor `/etc/sing-box/outbound.json` is set | set one of them |
| Log says `no node configured yet: open http://<router LAN address>:8081/` | the container is running and waiting for a node | this is not an error: open the panel at `http://<router LAN address>:8081/` and add a subscription or node link |
| `conflicting-config` | both were set | unset one |
| `invalid-outbound` / `invalid-config` | the outbound is a full config, contains `inbounds`, or sing-box rejects it | give one outbound object; `sing-box check -c` locally shows the real error |
| `unsupported-link: <scheme>` | the link covers vless/vmess/trojan/ss/hysteria2/tuic | anything else: use the JSON outbound path |
| `unsupported-transport: xhttp` from the *sing-box* path | the link needs the Xray engine (xhttp/splithttp or vless encryption) | nothing to fix — the engine picker should have used Xray; if you see this, file an issue with the link shape (redacted) |
| `xray-not-ready` in the container log | the xray process died at startup (bad config) | read one line above; usually an outbound Xray rejects, e.g. a vless `encryption` value it does not know |
| `ipv6-unsupported` | the endpoint host is IPv6 | use IPv4 or a domain; this build has no IPv6 |
| `resolve-failed: <host>` | the container cannot resolve the endpoint | set `ENDPOINT_IP` |
| Names fail to resolve, everything else works | the transport does not carry UDP (common with a bare Shadowsocks server) | enable UDP server-side, or run DNS over TCP/HTTPS |
| `:resolve <name>` returns `10.10.34.x` | router DNS is poisoned; the tunnel is fine | fix `/ip dns` or use DoH |
| Small pages work, big downloads or speed tests stall at 0 | the tunnel MTU is 1500, or fasttrack is skipping mangle | the tunnel must be 1400, and fasttrack must take only unmarked connections — see "The container is healthy, big downloads hang" below |
| Router's own traffic exits direct, LAN is tunnelled | no output mark rule | re-import `v2raymik.rsc`; it adds the output mark if none exists |
| LAN is tunnelled but the router is not | router-originated traffic not masqueraded towards the veth | the install adds `masquerade out-interface=veth-mik`; check it exists |
| Tunnel is up, engine logs `accepted`, nothing comes back | the container's own dial is not NAT'd | the install adds `masquerade src-address=$MikSubnet` (`mik: container egress`); check it exists — on routers without a whole-WAN masquerade the transport cannot dial without it |
| Wrong exit IP from a LAN client | the container subnet got marked | the "never mark the container" rule must sit first and have counters |
| DDNS name points at the exit | `/ip cloud` publishes the exit, by design — the tunnel carries everything, including `cloud.mikrotik.com` | if you need the router reachable under that name from outside, move that traffic out by hand, or accept it; there is no exemption anymore |
| `filesystem not mounted` from `/container` | `tmpdir` or `root-dir` points at a missing disk | the import detects the disk (a partitioned stick mounts as `usb2-part1`); the MikDisk validation error lists every mount that exists — pick one of those or unset the global and re-import |
| Container restarts in a loop | the engine exits: bad UUID/key, unreachable server | lower `restart-max-count`, read one log entry |
| Router cannot ping `172.17.0.2` | the veth is in a bridge (broken layout on 7.25.1) | keep the address directly on the veth, as the import does |
| The router is unreachable after import | the tunnel came up and your management path goes through it | see "When you are locked out" |

## Quick health check

```
/container/print where name="v2raymik"                   # running, healthy
/ip route print where routing-table=mik-tunnel           # "mik: tunnel" is active (A flag)
/ip firewall mangle print stats where comment~"mik"      # counters moving
/container/shell [find where name="v2raymik"] cmd="ip route"
/tool fetch url="https://1.1.1.1/cdn-cgi/trace" output=user   # ip=… is the exit
```

Inside the container:

```
ip route get 1.1.1.1        # must say dev tun0
ip route get <endpoint-ip>  # must say via 172.17.0.1 dev veth-mik
ip -4 addr show dev tun0    # 198.18.0.1
```

Two measurements that lie on this setup:

- **`ping` from the router.** the engine answers ICMP inside the TUN, so
  replies come back in microseconds and never leave the box. Measure latency
  from a LAN client.
- **A 1 KB page.** It proves the handshake and nothing else; a missing MSS
  clamp only shows up on a download of a few MB.

## The container is healthy, big downloads hang

Small pages load, a speed test or a large download stalls at zero, and
`/container/print` says `running, healthy`. Look at the MTU first: the tunnel
must be **1400**, not 1500. The transport adds its own header, so a full-size
inner packet no longer fits the WAN MTU and is dropped or fragmented. The MSS
clamp only covers TCP that enters from the LAN; it does not cover UDP inside
the tunnel.

```
/container/shell [find where name="v2raymik"] cmd="grep mtu /etc/sing-box/config.json"
```

If it says 1500, re-import `v2raymik.rsc` (it sets `TUN_MTU` from `MikTunMtu`),
or set `:global MikTunMtu "1400"` before the import.

Then check that fasttrack is not taking connections out of the tunnel:

```
/ip firewall filter print where comment="defconf: fasttrack"
```

The rule must show `connection-mark=no-mark` and
`/ip firewall connection print count-only where connection-mark=mik-conn` must
be above zero while clients are active. Connections opened *before* the import
keep their old route until they close; `/ip firewall connection remove [find]`
clears them.

The healthcheck is not a speed test. It makes one small request to
`http://www.gstatic.com/generate_204`, so a container can be `healthy` and
still too slow for a big download. Measure from a LAN client, not from the
router.

## Remote management or inter-VLAN traffic stopped working

That is the `all` scope: it marks router output too. Switch to a scope that
leaves management and private destinations alone:

```
:global MikScope "lan"
/import file-name=v2raymik.rsc
```

Use `list` to tunnel only chosen clients, or `manual` to write every rule
yourself. All three leave `/ip dns` and `chain=output` untouched. Connections
opened before the switch keep their old route until you clear them with
`/ip firewall connection remove [find]`.

## A client's DNS is still answered by the router

In `lan` and `list`, port-53 queries to the router are redirected into the
tunnel. Check that the client's source is in `mik-private` (or `mik-clients`
for `list`), that both `mik: dns to tunnel` dstnat rules are enabled, and that
no earlier dstnat rule catches port 53 first. Querying an external resolver
directly goes through the generic mark rule instead; DoH/DoT is not redirected.

## The panel is unreachable on a strict firewall

Scopes `all`, `lan` and `list` add `mik: forward to container`, an accept for
`out-interface=veth-mik` above the first forward drop. If your forward chain
drops before that rule, move it up or add your own accept. `manual` mode adds
no filter rules for you.

## When you are locked out

In `all`, the tunnel carries everything, including your management path. If
the tunnel is down, dropped traffic includes the traffic your management tool
needs — and unlike earlier releases there is no fallback to the ISP to save
you. The other scopes avoid this by leaving router output unmarked.

Use Winbox over MAC (`/tool mac-server` is usually still enabled) or the
serial console, then:

```
/ip route remove [find where comment="mik: tunnel"]
```

or uninstall entirely:

```
:global MikMode "uninstall"
/import file-name=v2raymik.rsc
```

The uninstall removes the route first, so marked traffic dies immediately and
the rest of the device is untouched.
