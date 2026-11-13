# Admin UI helpers. Sourced by the entrypoint and by every CGI.
#
# The panel has no password. It is meant for the LAN, where the only exposure
# is the dst-nat in the router script (src-address-list=mik-private). Anyone on the
# LAN can use the panel; do not expose it anywhere else.
#
# State lives in the persistent root-dir, never in the image:
#   $DATA_DIR/state.json   the active outbound
#   $DATA_DIR/sub.txt      the cached subscription payload
#   $DATA_DIR/lock.d/      the "a test is running" lock

DATA_DIR=${DATA_DIR:-/data}
WEB_ROOT=${WEB_ROOT:-/app/web}
ADMIN_PORT=${ADMIN_PORT:-8080}
ADMIN_LOCK_TTL=${ADMIN_LOCK_TTL:-120}

admin_log() { echo "v2raymik: $*" >&2; }

# start_admin — serve the page, or explain why not and keep running.
start_admin() {
  if [ ! -x "$(command -v httpd 2>/dev/null || true)" ]; then
    admin_log "admin-disabled: busybox httpd not found"
    return 0
  fi
  if [ ! -d "$WEB_ROOT" ]; then
    admin_log "admin-disabled: $WEB_ROOT missing"
    return 0
  fi
  mkdir -p "$DATA_DIR"
  httpd -f -p "$ADMIN_PORT" -h "$WEB_ROOT" &
  ADMIN_PID=$!
  admin_log "admin listening on :${ADMIN_PORT} (reachable only through the router's dst-nat, no password)"
}

# json_escape <string> — escaped contents, without the surrounding quotes.
json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
          -e 's/\r/\\r/g' -e 's/\t/\\t/g' \
    | awk 'BEGIN{ORS=""} {if (NR>1) printf "\\n"; printf "%s", $0}'
}

# gen_of <file> — short fingerprint of the cached subscription.
gen_of() {
  [ -f "$1" ] || { printf ''; return 0; }
  md5sum "$1" 2>/dev/null | cut -d' ' -f1
}

# read_body — POST body from stdin, capped.
read_body() {
  len=${CONTENT_LENGTH:-0}
  case "$len" in ''|*[!0-9]*) len=0 ;; esac
  [ "$len" -gt 8192 ] && len=8192
  dd bs=1 count="$len" 2>/dev/null
}

url_decode() {
  printf '%b' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/+/ /g' -e 's/%/\\x/g')"
}

# form_get <body> <key> — last value wins.
form_get() {
  body=$1
  want=$2
  out=""
  rest=$body
  while [ -n "$rest" ]; do
    pair=${rest%%&*}
    case "$rest" in *"&"*) rest=${rest#*&} ;; *) rest="" ;; esac
    k=${pair%%=*}
    v=${pair#*=}
    [ "$v" = "$pair" ] && v=""
    if [ "$(url_decode "$k")" = "$want" ]; then
      out=$(url_decode "$v")
    fi
  done
  printf '%s' "$out"
}

lock_try() {
  mkdir -p "$DATA_DIR"
  if mkdir "$DATA_DIR/lock.d" 2>/dev/null; then
    printf '%s' "$$" > "$DATA_DIR/lock.d/pid"
    return 0
  fi
  # stale lock: a test that died without cleaning up
  if [ -n "$(find "$DATA_DIR/lock.d" -mmin +$((ADMIN_LOCK_TTL / 60 + 1)) 2>/dev/null)" ]; then
    rm -rf "$DATA_DIR/lock.d"
    mkdir "$DATA_DIR/lock.d" 2>/dev/null && { printf '%s' "$$" > "$DATA_DIR/lock.d/pid"; return 0; }
  fi
  return 1
}

lock_held() { [ -d "$DATA_DIR/lock.d" ]; }

lock_release() { rm -rf "$DATA_DIR/lock.d"; }
