---
name: Bug report
about: Something does not work as documented
title: ""
labels: ""
assignees: ""
---

## What happens

<!-- The symptom. "No internet" is not enough: which traffic, which device. -->

## Expected

## Environment

- RouterOS version (`/system resource print`): 
- Device model and architecture: 
- Image tag: 
- Transport (vless / vmess / trojan / ss / json outbound) and port: 

## Container log

```
/log print where topics~"container"
```

## Relevant config

```
/ip route print where routing-table=mik-tunnel
/ip firewall filter print where comment~"mik"
/container/print
```

## Does the endpoint connect at all?

<!-- Since 1.3.0 there is no port allowlist: every port is allowed. A dead
     dial is an endpoint problem — see docs/troubleshooting.md. -->

- [ ] the same port answers from another network / another client
- [ ] the container log shows `resolve-failed` or a repeated `dialing`

Please redact UUIDs, keys, server addresses and the device serial.
