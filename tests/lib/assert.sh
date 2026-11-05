# Minimal assertions for the POSIX sh test suite.
fail() {
  echo "assertion failed: $*" >&2
  exit 1
}

assert_eq() {
  # assert_eq <actual> <expected> [label]
  [ "$1" = "$2" ] || fail "${3:-value}: expected [$2], got [$1]"
}

assert_match() {
  # assert_match <text> <pattern> [label]
  printf '%s\n' "$1" | grep -q -- "$2" || fail "${3:-text}: no match for [$2] in [$1]"
}

assert_no_match() {
  printf '%s\n' "$1" | grep -q -- "$2" && fail "${3:-text}: unexpected match for [$2] in [$1]"
  return 0
}

assert_exit() {
  # assert_exit <expected-code> <command...>
  code=$1
  shift
  set +e
  "$@" >/dev/null 2>&1
  got=$?
  set -e
  assert_eq "$got" "$code" "exit code of $*"
}
