# Benchmarks

> **Read this first.** Every number below was measured on the 1.0.x build —
> the five-file layout with the `iran-ips` split, sing-box only. Since 1.2.0
> the gateway is full-tunnel, carries **two engines**, and has no ISP
> fallback; nothing here transfers automatically. The image is bigger (both
> cores) and likely uses more RSS. Re-measure on your own hardware before
> quoting any of this. The Xray engine path has no hardware run behind it at
> all.

All numbers come from the reference device. Anything marked **TBD** has not been
measured and must not be quoted as a result.

## Reference device

| Item | Value |
| --- | --- |
| Device | MikroTik hAP ax³ (C53UiG+5HPaxD2HPaxD), arm64 |
| RouterOS | 7.25.1 |
| RAM | 1 GB |
| Storage | USB 2.0 SATA enclosure, ext4, 233 GB |
| Uplink | DHCP behind a modem (double NAT) |
| Exit | Xray over TCP (REALITY 8999, WebSocket 2087 via CDN, plain VLESS 8089/3010 all tested) |
| Split | `iran-ips` on RouterOS, `to-world` table |

## Footprint

| Metric | Value |
| --- | --- |
| Image, compressed | 17.5 MB (amd64 build; arm64 measured in Task 12) |
| Image, uncompressed layers | 64.6 MB (amd64 build) |
| Container RSS at idle | 10–17 MiB fresh, 21.3 MiB after a day of traffic |
| Container size on disk (root-dir) | ~46 MiB |
| Boot to first tunnelled packet | TBD |

## Throughput

Measured with `iperf3` against the exit server, once per direction, single-stream
and four-stream. Record the CPU percentage during the run
(`/system resource print`).

| Test | Result |
| --- | --- |
| Download, 1 stream, from the router (`tool fetch`, 9.5 MiB) | **≈ 13 Mbps** |
| Download, 10 MB through the panel's own test (three nodes, TR) | **30–38 Mbps** |
| Download, 4 streams | TBD |
| Upload, 1 stream | TBD |
| Upload, 4 streams | TBD |
| CPU during download | TBD |

The first figure is a `tool fetch` of a 10 MB file through the tunnel, from the
router itself, on 7.25.1, on one early node. The second is the panel's speed test
on three later nodes (`/cgi-bin/test`: a short-lived Xray, a `generate_204`, then
a 10 MB download), which is a different method and a different path — treat both
as order-of-magnitude results, not as a spec. The container eats roughly none of
the link: the path is the limit.

### Reference: OpenVPN/TCP on the same box

Before Xray, the same device ran OpenVPN over **TCP 9443** to a Turkish server
(the ISP drops outbound UDP, so WireGuard and L2TP never connected):

| Test | Result |
| --- | --- |
| Download, `iperf3`, 1 stream | ~14 Mbps |
| Upload, `iperf3`, 1 stream | ~15.8 Mbps |
| Exit | `loc=TR`, verified with `cdn-cgi/trace` |

So 13–14 Mbps was the ceiling of that path at the time; the later Xray nodes
reached 30–38 on better paths. Upload and four-stream numbers are still to be
taken on either setup.

## Latency

| Test | Result |
| --- | --- |
| ICMP 8.8.8.8 through the tunnel | TBD |
| ICMP 1.1.1.1 through the tunnel | TBD |
| RTT to the exit server, direct | TBD |

## How to reproduce

```
# on the server
iperf3 -s

# through the tunnel, from a client behind the router
iperf3 -c <server> -P 1 -t 20
iperf3 -c <server> -P 4 -t 20
iperf3 -c <server> -P 1 -t 20 -R
```

Note the RouterOS version and the image tag with every run; a RouterOS change can
move these numbers more than the image can.
