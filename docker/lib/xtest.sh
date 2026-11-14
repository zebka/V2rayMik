# Testing a candidate config without touching the live tunnel.
#
# Each test runs its own engine (sing-box or xray, whichever the link needs)
# with a SOCKS inbound on localhost. The candidate's endpoint gets a /32
# bypass for the duration, because inside this container the half-default
# routes point at tun0 — without the bypass the test of node B would travel
# through node A and measure the wrong thing.

XTEST_PORT=${XTEST_PORT:-10800}
CHECK_URL=${CHECK_URL:-http://connectivitycheck.gstatic.com/generate_204}
SPEED_BYTES=${SPEED_BYTES:-50000000}
SPEED_URL=${SPEED_URL:-https://speed.cloudflare.com/__down?bytes=$SPEED_BYTES}
# Which country the node exits in. This must be the HTTPS URL: Cloudflare answers
# `http://1.1.1.1/cdn-cgi/trace` with a 301 to HTTPS, and the redirect body has no
# `loc=` line, so a plain-HTTP trace reports nothing while the node is fine.
TRACE_URL=${TRACE_URL:-https://1.1.1.1/cdn-cgi/trace}
# The time limit scales with the size chosen in the panel: a 10 MB test gets
# ~40 s, a 200 MB test up to 230 s. Set SPEED_MAX_TIME to fix it explicitly.
SPEED_MAX_TIME=${SPEED_MAX_TIME:-}
CHECK_MAX_TIME=${CHECK_MAX_TIME:-8}
TRACE_MAX_TIME=${TRACE_MAX_TIME:-6}

# trace_country <trace-body> — the two-letter exit country, or nothing.
trace_country() {
  printf '%s\n' "$1" | sed -n 's/^loc=\([A-Z][A-Z]\)$/\1/p' | head -n 1
}

# xtest_plan <outbound-json> <port> — a full sing-box config with a mixed inbound.
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

# xtest_reason <curl-exit> <http-code> [engine-log] [engine] — one sentence an
# operator can act on. curl's exit status names what broke on the way to the
# node; the engine's last line names what the node itself answered (a REALITY
# key that does not match, a wrong password, a dial timeout). The log is
# optional so the shape can be checked without running anything; the engine
# defaults to sing-box.
xtest_reason() {
  xr_crc=${1:-0}
  xr_code=${2:-0}
  xr_log=${3:-/tmp/xtest.log}
  xr_eng=${4:-sing-box}
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
    printf '%s; %s: %s' "$xr_why" "$xr_eng" "$xr_slog" | tr '|' ' '
  else
    printf '%s' "$xr_why" | tr '|' ' '
  fi
}

# xtest_measure <port> [engine-log] [engine-name] [speed-bytes]
# prints pipe-delimited "code|ms|mbps|country|err".
# country and err are empty on success; err may contain spaces but never a pipe.
xtest_measure() {
  port=$1
  engine_log=${2:-/tmp/xtest.log}
  engine_name=${3:-sing-box}
  bytes=${4:-$SPEED_BYTES}
  # Keep curl's exit status and its own words: a bare `000` in the panel is
  # indistinguishable between a dead node, a poisoned DNS answer and a proxy
  # that refused the tunnel. `-w` still prints "000 <time>" when the check
  # fails, so the output is always one line.
  out=$(curl -s -o /dev/null --max-time "$CHECK_MAX_TIME" \
        --socks5-hostname "127.0.0.1:$port" \
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
    # Cloudflare refuses __down for bytes >= 100000000 (403). Download in
    # chunks of 99,999,000 until the requested size is reached and report the
    # aggregate: bps averaged over every chunk. Time budget is shared across
    # the chunks.
    tmax=${SPEED_MAX_TIME:-$((bytes / 1000000 + 30))}
    [ "$tmax" -gt 240 ] && tmax=240
    [ "$tmax" -lt 30 ] && tmax=30
    total_b=0
    total_ms=0
    budget_ms=$((tmax * 1000))
    remaining=$bytes
    while [ "$remaining" -gt 0 ] && [ "$total_ms" -lt "$budget_ms" ]; do
      chunk=$remaining
      [ "$chunk" -gt 99999000 ] && chunk=99999000
      left_s=$(( (budget_ms - total_ms + 999) / 1000 ))
      out=$(curl -s -o /dev/null --max-time "$left_s" \
            --socks5-hostname "127.0.0.1:$port" \
            -w '%{size_download} %{time_total}' "${SPEED_URL%bytes=*}bytes=$chunk" 2>/dev/null || true)
      cb=${out%% *}
      cs=${out##* }
      case "$cb" in ''|*[!0-9]*) cb=0 ;; esac
      ms=$(awk -v s="${cs:-0}" 'BEGIN { printf "%d", s * 1000 }')
      total_b=$((total_b + cb))
      total_ms=$((total_ms + ms))
      remaining=$((bytes - total_b))
      # An empty or failed chunk ends the loop instead of spinning
      [ "$cb" -gt 0 ] || break
    done
    mbps=$(awk -v b="$total_b" -v t="$total_ms" 'BEGIN { if (t > 0) printf "%.1f", b * 8 / (t / 1000) / 1000000; else print "0.0" }')

    # Where does that node actually exit? Cloudflare's trace answers with
    # `loc=<country>` for the address it sees, queried through the same proxy.
    # `-L` is a seatbelt: if the endpoint ever starts redirecting again, follow it
    # instead of parsing a redirect page as if it were a trace.
    trace=$(curl -sL --max-time "$TRACE_MAX_TIME" --socks5-hostname "127.0.0.1:$port" \
            "$TRACE_URL" 2>/dev/null || true)
    country=$(trace_country "$trace")
  else
    err=$(xtest_reason "$crc" "$code" "$engine_log" "$engine_name")
  fi

  printf '%s|%s|%s|%s|%s\n' "${code:-0}" "${ms:-0}" "${mbps:-0}" "${country:-}" "${err}"
}

# xtest_run <index> [speed-bytes] — prints {"code":204,"ms":123,"mbps":12.3,"engine":...}
# or an error. Assumes the caller holds the lock. Engine is chosen per link.
xtest_run() {
  idx=$1
  bytes=${2:-$SPEED_BYTES}
  link=$(subs_decode "$SUB_FILE" | sed -n "$((idx + 1))p")
  if [ -z "$link" ]; then
    printf '{"code":0,"ms":0,"mbps":0,"error":"no such entry","engine":""}'
    return 0
  fi

  engine=$(engine_of_link "$link")

  if [ "$engine" = "xray" ]; then
    ob=$(link_to_xray_outbound "$link" 2>/dev/null) || {
      printf '{"code":0,"ms":0,"mbps":0,"error":"unsupported link","engine":"xray"}'
      return 0
    }
    ep=$(xray_endpoint_of "$ob" 2>/dev/null) || {
      printf '{"code":0,"ms":0,"mbps":0,"error":"no endpoint","engine":"xray"}'
      return 0
    }
  else
    ob=$(link_to_outbound "$link" 2>/dev/null) || {
      printf '{"code":0,"ms":0,"mbps":0,"error":"unsupported link","engine":"sing-box"}'
      return 0
    }
    ep=$(endpoint_of "$ob" 2>/dev/null) || {
      printf '{"code":0,"ms":0,"mbps":0,"error":"no endpoint","engine":"sing-box"}'
      return 0
    }
  fi

  host=${ep%:*}
  ip=$(resolve_endpoint "$host") || {
    printf '{"code":0,"ms":0,"mbps":0,"error":"resolve failed","engine":"%s"}' "$engine"
    return 0
  }

  # Pin the resolved address into the test outbound. Dialing the hostname would
  # re-resolve inside the engine and could pick a different A record than the
  # /32 bypass below covers — on a CDN endpoint that is a guaranteed timeout.
  if ! is_ipv4 "$host"; then
    if [ "$engine" = "xray" ]; then
      ob=$(xray_pin "$ob" "$ip") || {
        printf '{"code":0,"ms":0,"mbps":0,"error":"bad outbound","engine":"xray"}'
        return 0
      }
    else
      ob=$(printf '%s' "$ob" | jq --arg ip "$ip" '.server = $ip') || {
        printf '{"code":0,"ms":0,"mbps":0,"error":"bad outbound","engine":"sing-box"}'
        return 0
      }
    fi
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

  cfg=/tmp/xtest-$engine.json
  if [ "$engine" = "xray" ]; then
    plan=$(xray_config "$ob" "$XTEST_PORT")
  else
    plan=$(xtest_plan "$ob" "$XTEST_PORT")
  fi
  printf '%s' "$plan" > "$cfg"

  if [ "$engine" = "xray" ]; then
    xray run -c "$cfg" >/tmp/xtest.log 2>&1 &
  else
    sing-box run -c "$cfg" >/tmp/xtest.log 2>&1 &
  fi
  xpid=$!

  cleanup() {
    kill -TERM "$xpid" 2>/dev/null || true
    wait "$xpid" 2>/dev/null || true
    if [ -z "$had_route" ]; then
      ip route del "$ip/32" 2>/dev/null || true
    fi
    rm -f "$cfg"
  }
  # Whatever happens to this process — including a client hang-up killing the
  # CGI — the test engine must not linger and the route must come back.
  trap cleanup EXIT INT TERM

  if ! xtest_wait_port "$XTEST_PORT" "$xpid"; then
    err=$(tail -n 1 /tmp/xtest.log 2>/dev/null | tr -d '\r' \
          | awk '{ gsub(/\033\[[0-9;]*m/, ""); print }' | sed -e 's/.*using outbound\/[^:]*: //' | cut -c1-160 | tr '|' ' ')
    [ -n "$err" ] && err="; engine: $err"
    cleanup
    printf '{"code":0,"ms":0,"mbps":0,"error":"node did not start%s","engine":"%s"}' "$(json_escape "$err")" "$engine"
    return 0
  fi

  result=$(xtest_measure "$XTEST_PORT" /tmp/xtest.log "$engine" "$bytes")
  code=$(printf '%s' "$result" | cut -d'|' -f1)
  ms=$(printf '%s' "$result" | cut -d'|' -f2)
  mbps=$(printf '%s' "$result" | cut -d'|' -f3)
  country=$(printf '%s' "$result" | cut -d'|' -f4)
  err=$(printf '%s' "$result" | cut -d'|' -f5-)

  cleanup
  printf '{"code":%s,"ms":%s,"mbps":%s,"country":"%s","error":"%s","engine":"%s"}' \
    "${code:-0}" "${ms:-0}" "${mbps:-0}" "${country:-}" "$(json_escape "$err")" "$engine"
}
