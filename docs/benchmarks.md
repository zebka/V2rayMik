# Benchmarks

All numbers come from the reference device. Anything marked **TBD** has not been
measured and must not be quoted as a result.

## Reference device

| Item | Value |
| --- | --- |
| Device | MikroTik hAP ax³ (C53UiG+5HPaxD2HPaxD), arm64 |
| RouterOS | 7.24.2 |
| RAM | 1 GB |
| Storage | USB 2.0 SATA enclosure, ext4, 233 GB |
| Uplink | DHCP behind a modem (double NAT) |
| Exit | Xray over TCP 443 to a VPS outside the country |
| Split | `iran-ips` on RouterOS, `to-world` table |

## Footprint

| Metric | Value |
| --- | --- |
| Image, compressed | 17.5 MB (amd64 build; arm64 measured in Task 12) |
| Image, uncompressed layers | 64.6 MB (amd64 build) |
| Container RSS at idle | TBD |
| Boot to first tunnelled packet | TBD |

## Throughput

Measured with `iperf3` against the exit server, once per direction, single-stream
and four-stream. Record the CPU percentage during the run
(`/system resource print`).

| Test | Result |
| --- | --- |
| Download, 1 stream | TBD |
| Download, 4 streams | TBD |
| Upload, 1 stream | TBD |
| Upload, 4 streams | TBD |
| CPU during download | TBD |

Context, so the numbers are not read in isolation: the same reference line
previously ran OpenVPN/TCP at ~14 Mbps down / ~15.8 Mbps up, while the server
itself could do ~350/330 Mbps. Container networking on this hardware is
CPU-bound; published reports for other container-based designs range from
~25 Mbps (original tun2socks) to ~65 Mbps (hev-socks5-tunnel). The single-process
TUN design has no published figure, which is exactly why this table exists.

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
