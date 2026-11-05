#!/bin/sh
# Test runner for xray-mikrotik-gateway.
# Every tests/unit/*.t.sh is a standalone POSIX sh script: exit 0 = pass.
set -u

dir=${TESTS_DIR:-/w/tests}
total=0
pass=0
fail=0

for t in "$dir"/unit/*.t.sh; do
  [ -e "$t" ] || continue
  total=$((total + 1))
  name=$(basename "$t")
  if out=$(sh "$t" 2>&1); then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=$((fail + 1))
  fi
done

echo "$total tests, $pass passed, $fail failed"
[ "$fail" -eq 0 ]
