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
- `MikFailOpen`: true / false

## Container log

```
/log print where topics~"container"
```

## Relevant config

```
/ip route print where routing-table=to-world
/ip firewall filter print where comment~"mik"
/container/print
```

## Did you change the port allowlist?

<!-- If your transport uses a port outside 443,80,2052,2053,2082,2083,2086,2087,
     2095,2096,8080,8443,8880,53 it must be added. See docs/security.md. -->

- [ ] the port is in `MikContainerToWanPorts`

Please redact UUIDs, keys, server addresses and the device serial.
