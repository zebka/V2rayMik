# Reference server: VLESS + REALITY

Out of scope for this project — there are better maintained installers — but here
is the minimum shape the client expects, so you can check compatibility.

## Server side (Xray-core, any Linux)

```json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "GENERATE-A-UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "www.microsoft.com:443",
        "xver": 0,
        "serverNames": ["www.microsoft.com"],
        "privateKey": "GENERATE-WITH: xray x25519",
        "shortIds": ["0123456789abcdef"]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
```

Generate the pair with `xray x25519`: the **private** key stays on the server, the
**public** key goes into the client's `pbk`.

## Firewall

Open `tcp/443` only. REALITY speaks TLS 1.3 to a real site; there is no
certificate to install and no domain to point at the server.

Do not run another TLS service on the same port.

## Client link

```
vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=0123456789abcdef&type=tcp#name
```

That link is exactly what `XRAY_LINK` accepts. If you prefer the JSON path, any
outbound object Xray understands works, including VMess, Trojan, Shadowsocks,
WebSocket, gRPC and XHTTP.

## Server-side NAT

If the server has no route back to the tunnel's inner addresses, masquerade the
Xray interface. With this project's router-side masquerade the inner source is the
router itself, so a simple MASQUERADE on the server's egress is enough.
