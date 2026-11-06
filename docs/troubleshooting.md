# Troubleshooting

Symptom → cause → fix. Start with the container log:

```
/container/set [find where name="xray-gw"] logging=yes
/log print where topics~"container"
/container/shell [find where name="xray-gw"]
```

## The one that catches everyone: the port

A transport whose port is not in `XrayContainerToWanPorts` (or, for a one-off port,
`XrayExtraWanPorts`) produces **no error**.
sing-box redials forever, the router logs nothing, and the symptom is "the tunnel is
broken".

```
/log print where topics~"container" and message~"dialing"
```

If you see the same `dialing to tcp:<ip>:<port>` every few seconds and nothing
else, that port is the answer. Add it (see `docs/security.md`) and import
`03-firewall.rsc` again. Remember RouterOS accepts at most 15 ports per rule.

## Symptom table

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Repeated `dialing to …` and nothing else | port missing from the egress allowlist | add it, re-import `03-firewall.rsc` |
| Container stops immediately, `missing-config` | neither `NODE_LINK` nor `/etc/sing-box/outbound.json` is set | set one of them |
| `conflicting-config` | both were set | unset one |
| `invalid-outbound` / `invalid-config` | the outbound is a full config, contains `inbounds`, or sing-box rejects it | give one outbound object; `sing-box check -c` locally shows the real error |
| `unsupported-link: <scheme>` | the link path covers vless/vmess/trojan/ss only | use the JSON outbound path |
| `ipv6-unsupported` | the endpoint host is IPv6 | use IPv4 or a domain; this build has no IPv6 |
| `resolve-failed: <host>` | the container cannot resolve the endpoint | set `ENDPOINT_IP` |
| `ip: can't find device 'eth0'` in older logs | image from before auto-detection | rebuild/repull: the NIC is named after the veth |
| Names fail to resolve, everything else works | the transport does not carry UDP (common with a bare Shadowsocks server) | enable UDP server-side, or run DNS over TCP/HTTPS |
| `:resolve <name>` returns `10.10.34.x` | router DNS is poisoned; the tunnel is fine | fix `/ip dns` or use DoH |
| Small pages work, big downloads stall at 0 | MSS clamp missing on that path | `02-routing.rsc` clamps forward *and* output; check a fasttrack rule is not skipping mangle |
| Router's own traffic exits direct, LAN is tunnelled | no output mark rule | `02-routing.rsc` adds one if none exists; check `iran-ips` is not empty |
| LAN is tunnelled but the router is not | router-originated traffic not masqueraded towards the veth | `03-firewall.rsc` adds `masquerade out-interface=veth-xray` |
| Wrong exit IP from a LAN client | the container subnet got marked | the "never mark the container" rule must sit first and have counters |
| DDNS name points at the exit | router traffic to IP-Cloud went through the tunnel | the installer keeps the `cloud.mikrotik.com*` names in `router-direct`; check it and `/ip cloud force-update` |
| `filesystem not mounted` from `/container` | `tmpdir` or `root-dir` points at a missing disk | fix `sing-boxDisk`; `01-container.rsc` recreates `tmpdir` |
| Container restarts in a loop | xray exits: bad UUID/key, unreachable server | lower `restart-max-count`, read one log entry |
| Router cannot ping `172.17.0.2` | the veth is in a bridge (broken layout on 7.25.1) | keep the address directly on the veth, as the scripts do |

## Quick health check

```
/container/print where name="xray-gw"                    # running, healthy
/ip route print where comment="xray-world"               # active (A flag)
/ip firewall mangle print stats where comment~"xray"     # counters moving
/container/shell [find where name="xray-gw"] cmd="ip route"
/tool fetch url="https://1.1.1.1/cdn-cgi/trace" output=user   # ip=… is the exit
```

Inside the container:

```
ip route get 1.1.1.1        # must say dev tun0
ip route get <endpoint-ip>  # must say via 172.17.0.1 dev veth-xray
ip -4 addr show dev tun0    # 198.18.0.1
```

Two measurements that lie on this setup:

- **`ping` from the router.** sing-box answers ICMP inside the TUN, so replies come
  back in microseconds and never leave the box. Measure latency from a LAN client.
- **A 1 KB page.** It proves the handshake and nothing else; a missing MSS clamp
  only shows up on a download of a few MB.

## When you are locked out

`99-uninstall.rsc` removes the route first. If you cannot reach the router at all,
use Winbox over MAC (`/tool mac-server` is usually still enabled) or the serial
console, then remove the `xray-world` route before anything else.
