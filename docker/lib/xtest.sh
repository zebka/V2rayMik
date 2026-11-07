# Testing a candidate config without touching the live tunnel.
#
# Each test runs its own sing-box with a SOCKS inbound on localhost. The candidate's
# endpoint gets a /32 bypass for the duration, because inside this container the
# half-default routes point at tun0 — without the bypass the test of node B would
# travel through node A and measure the wrong thing.

XTEST_PORT=${XTEST_PORT:-10800}
CHECK_URL=${CHECK_URL:-http://connectivitycheck.gstatic.com/generate_204}
SPEED_URL=${SPEED_URL:-https://speed.cloudflare.com/__down?bytes=10000000}
# Which country the node exits in. This must be the HTTPS URL: Cloudflare answers
# `http://1.1.1.1/cdn-cgi/trace` with a 301 to HTTPS, and the redirect body has no
# `loc=` line, so a plain-HTTP trace reports nothing while the node is fine.
TRACE_URL=${TRACE_URL:-https://1.1.1.1/cdn-cgi/trace}
SPEED_MAX_TIME=${SPEED_MAX_TIME:-15}
CHECK_MAX_TIME=${CHECK_MAX_TIME:-8}
TRACE_MAX_TIME=${TRACE_MAX_TIME:-6}

# trace_country <trace-body> — the two-letter exit country, or nothing.
trace_country() {
  printf '%s\n' "$1" | sed -n 's/^loc=\([A-Z][A-Z]\)$/\1/p' | head -n 1
}

# xtest_plan <outbound-json> <port> — a full config with a mixed inbound.
xtest_plan() {
  printf '%s' "$1" \
    | jq -c --argjson port "$2" --arg listen "127.0.0.1" \
      '{log:{level:"warn", timestamp:false},
        inbounds:[{type:"mixed", tag:"test-in", listen:$listen, listen_port:$port}],
        outbounds:[(. + {tag:"proxy"})],
        route:{final:"proxy"}}'
}

# xtest_wait_port <port> <pid> — up to 3 s.
xtest_wait_port() {
  port=$1
  pid=$2
  i=0
  while [ "$i" -lt 30 ]; do
    nc -z 127.0.0.1 "$port" 2>/dev/null && return 0
    kill -0 "$pid" 2>/dev/null || return 1
    i=$((i + 1))
    sleep 0.1
  done
  return 1
}

# xtest_reason <curl-exit> <http-code> [engine-log] — one sentence an operator
# can act on. curl's exit status names what broke on the way to the node; the
# engine's last line names what the node itself answered (a REALITY key that does
# not match, a wrong password, a dial timeout). The log is optional so the shape
# can be checked without running anything.
xtest_reason() {
  xr_crc=${1:-0}
  xr_code=${2:-0}
  xr_log=${3:-/tmp/xtest.log}
  case "$xr_crc" in
    0)   xr_why="the check answered http $xr_code" ;;
    5|6) xr_why="cannot resolve the check host" ;;
    7)   xr_why="connection refused" ;;
    28)  xr_why="timed out after ${CHECK_MAX_TIME:-8}s" ;;
    35)  xr_why="tls handshake failed" ;;
    52)  xr_why="empty reply" ;;
    56)  xr_why="connection reset" ;;
    97)  xr_why="the proxy could not open the connection" ;;
    *)   xr_why="curl exit $xr_crc" ;;
  esac
  [ "$xr_code" = "0" ] || [ "$xr_crc" = "0" ] || xr_why="$xr_why (http $xr_code)"
  # sing-box writes colour even into a file; drop the escapes, then the
  # "connection: ... using outbound/vless[proxy]:" preamble, which never differs
  # and only pushes the reason out of the visible part.
  xr_slog=$(tail -n 1 "$xr_log" 2>/dev/null | tr -d '\r' \
            | awk '{ gsub(/\033\[[0-9;]*m/, ""); print }' \
            | sed -e 's/.*using outbound\/[^:]*: //' | cut -c1-160)
  if [ -n "$xr_slog" ]; then
    printf '%s; sing-box: %s' "$xr_why" "$xr_slog"
  else
    printf '%s' "$xr_why"
  fi
}

# xtest_run <index> — prints {"code":204,"ms":123,"mbps":12.3} or an error.
# Assumes the caller holds the lock and is inside /data.
xtest_run() {
  idx=$1
  link=$(subs_decode "$SUB_FILE" | sed -n "$((idx + 1))p")
  if [ -z "$link" ]; then
    printf '{"code":0,"ms":0,"mbps":0,"error":"no such entry"}'
    return 0
  fi

  ob=$(link_to_outbound "$link" 2>/dev/null) || {
    printf '{"code":0,"ms":0,"mbps":0,"error":"unsupported link"}'
    return 0
  }

  ep=$(endpoint_of "$ob" 2>/dev/null) || {
    printf '{"code":0,"ms":0,"mbps":0,"error":"no endpoint"}'
    return 0
  }
  host=${ep%:*}
  ip=$(resolve_endpoint "$host") || {
    printf '{"code":0,"ms":0,"mbps":0,"error":"resolve failed"}'
    return 0
  }

  # Pin the resolved address into the test outbound. Dialing the hostname would
  # re-resolve inside the engine and could pick a different A record than the
  # /32 bypass below covers — on a CDN endpoint that is a guaranteed timeout.
  if ! is_ipv4 "$host"; then
    ob=$(printf '%s' "$ob" | jq --arg ip "$ip" '.server = $ip') || {
      printf '{"code":0,"ms":0,"mbps":0,"error":"bad outbound"}'
      return 0
    }
  fi

  eth=$(detect_egress)
  gw=$(detect_gateway)
  # If this address already has a bypass, it belongs to the live config: do not
  # delete it after the test, or the tunnel that is carrying traffic loses its
  # own route and starts looping into itself.
  had_route=$(ip route show "$ip/32" 2>/dev/null || true)
  if [ -n "$gw" ]; then
    ip route replace "$ip/32" via "$gw" dev "$eth" 2>/dev/null || true
  else
    ip route replace "$ip/32" dev "$eth" 2>/dev/null || true
  fi

  cfg=/tmp/xtest.json
  plan=$(xtest_plan "$ob" "$XTEST_PORT")
  printf '%s' "$plan" > "$cfg"

  sing-box run -c "$cfg" >/tmp/xtest.log 2>&1 &
  xpid=$!

  cleanup() {
    kill -TERM "$xpid" 2>/dev/null || true
    wait "$xpid" 2>/dev/null || true
    if [ -z "$had_route" ]; then
      ip route del "$ip/32" 2>/dev/null || true
    fi
    rm -f "$cfg"
  }

  if ! xtest_wait_port "$XTEST_PORT" "$xpid"; then
    cleanup
    printf '{"code":0,"ms":0,"mbps":0,"error":"node did not start"}'
    return 0
  fi

  # Keep curl's exit status and its own words: a bare `000` in the panel is
  # indistinguishable between a dead node, a poisoned DNS answer and a proxy that
  # refused the tunnel. `-w` still prints "000 <time>" when the check fails, so
  # the output is always one line; the `|| echo` this replaced produced two for
  # some failures and every field ended up 0 / empty.
  out=$(curl -s -o /dev/null --max-time "$CHECK_MAX_TIME" \
        --socks5-hostname "127.0.0.1:$XTEST_PORT" \
        -w '%{http_code} %{time_total}' "$CHECK_URL" 2>/tmp/xtest.curl)
  crc=$?
  code=${out%% *}
  secs=${out##* }
  [ -n "$out" ] || { code=0; secs=0; }
  # expr exits 1 when the result is 0; keep the value, drop the status
  code=$(expr "${code:-0}" + 0 2>/dev/null || true)
  [ -n "$code" ] && [ "$code" -eq "$code" ] 2>/dev/null || code=0
  ms=$(awk -v s="${secs:-0}" 'BEGIN { printf "%d", s * 1000 }')

  mbps=0
  country=""
  err=""
  if [ "$code" = "204" ]; then
    bps=$(curl -s -o /dev/null --max-time "$SPEED_MAX_TIME" \
          --socks5-hostname "127.0.0.1:$XTEST_PORT" \
          -w '%{speed_download}' "$SPEED_URL" 2>/dev/null || true)
    mbps=$(awk -v b="${bps:-0}" 'BEGIN { printf "%.1f", b * 8 / 1000000 }')

    # Where does that node actually exit? Cloudflare's trace answers with
    # `loc=<country>` for the address it sees, queried through the same proxy.
    # `-L` is a seatbelt: if the endpoint ever starts redirecting again, follow it
    # instead of parsing a redirect page as if it were a trace.
    trace=$(curl -sL --max-time "$TRACE_MAX_TIME" --socks5-hostname "127.0.0.1:$XTEST_PORT" \
            "$TRACE_URL" 2>/dev/null || true)
    country=$(trace_country "$trace")
  else
    err=$(xtest_reason "$crc" "$code" /tmp/xtest.log)
  fi

  cleanup
  printf '{"code":%s,"ms":%s,"mbps":%s,"country":"%s","error":"%s"}' \
    "${code:-0}" "${ms:-0}" "${mbps:-0}" "${country:-}" "$(json_escape "${err:-}")"
}
