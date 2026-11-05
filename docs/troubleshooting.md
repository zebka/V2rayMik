# Troubleshooting

Symptom → cause → fix. Start with the container log:

```
/container/set [find where name="xray-gw"] logging=yes
/log print where topics~"container"
/container/shell [find where name="xray-gw"]
```

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Container stops immediately, log shows `missing-config` | Neither `XRAY_LINK` nor `/etc/xray/outbound.json` is set | Set one of them in `/container/envs` or drop the file in the root-dir |
| `conflicting-config` | Both were set | Unset one |
| `invalid-outbound` / `invalid-config` | The outbound is a full config, contains `inbounds`, or Xray rejects it | Give one outbound object; run `xray run -test -c` locally to see the real error |
| `unsupported-link: hysteria2` (or similar) | The link path only covers vless/vmess/trojan/ss | Use the JSON outbound path |
| `ipv6-unsupported` | The link's host is an IPv6 literal | Use an IPv4 or a domain; this build has no IPv6 |
| `resolve-failed: host` | DNS inside the container cannot resolve the endpoint | Set `ENDPOINT_IP` to the address |
| Container "running" but nothing is tunnelled | `tun0` never came up, or routes failed | `ip link show tun0` and `ip route` inside the container shell |
| `ip-forward-unavailable` in the log | The kernel refuses `net.ipv4.ip_forward=1` in the namespace | Report the RouterOS version; without it, LAN traffic cannot be forwarded |
| Sites hang on login, small pages work | MSS not clamped | `02-routing.rsc` adds `new-mss=1360`; check it exists and that a fasttrack rule is not bypassing mangle |
| Wrong exit IP from a LAN client | The container subnet got marked, or the LAN client is not in the marked range | `/ip firewall mangle print stats` — the "never mark the container" rule must have counters and sit first |
| Router's own traffic exits direct while LAN is tunnelled | No output mark rule | `02-routing.rsc` adds one only if none exists for the table; check `iran-ips` is not empty |
| DDNS name points at the exit | Router traffic to IP-Cloud went through the tunnel | The installer keeps `cloud.mikrotik.com*` in `router-direct`; verify the list and `/ip cloud force-update` |
| `filesystem not mounted` from `/container` | `tmpdir` or `root-dir` points at a missing disk | Fix `XrayDisk`; `01-container.rsc` recreates `tmpdir` |
| Container restarts in a loop | Xray exits: bad UUID, wrong key, unreachable server | Lower `restart-max-count`, read the log once |
| `:resolve twitter.com` returns `10.10.34.x` | Router DNS is poisoned; the tunnel is not at fault | Point `/ip dns` at a resolver reached through the tunnel, or use DoH |

## Quick health check

```
/container/print where name="xray-gw"           # running, healthy
/ip route print where comment="xray-world"      # active (A flag)
/ip firewall mangle print stats where comment~"xray"   # counters moving
/container/shell [find where name="xray-gw"] cmd="ip route"
/tool fetch url="https://ifconfig.me/ip" output=user    # server IP
```

Inside the container:

```
ip route get 1.1.1.1        # must say dev tun0
ip route get <endpoint-ip>  # must say dev eth0
ip -4 addr show dev tun0    # 198.18.0.1
```

## When you are locked out

`99-uninstall.rsc` removes the route first. If you cannot reach the router at all,
use Winbox over MAC (`/tool mac-server` is usually still enabled) or the serial
console; then remove the `xray-world` route before anything else.
