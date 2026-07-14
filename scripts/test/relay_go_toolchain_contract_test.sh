#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
go_log="$tmp_dir/go.log"
mkdir -p "$fake_bin"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '{' \
  '  printf "CALL\n"' \
  '  printf "ENV\t%s\n" "${GOTOOLCHAIN:-}"' \
  '  printf "ARG\t%s\n" "$@"' \
  '  printf "END\n"' \
  '} >>"${FAKE_GO_LOG:?}"' \
  >"$fake_bin/go"
chmod +x "$fake_bin/go"

# A stray inherited machine setting must not move relay builds or tests back to
# the local Go 1.26 toolchain. The fake Go executable makes this contract test
# host-safe and proves the environment received by each recipe.
GOTOOLCHAIN=local \
  PATH="$fake_bin:$PATH" \
  FAKE_GO_LOG="$go_log" \
  make -C "$ROOT_DIR/go-relay-server" \
    build test test-notifications \
    >/dev/null

[ "$(grep -c '^CALL$' "$go_log" || true)" -eq 3 ] ||
  fail 'expected build plus two test Go invocations'
[ "$(grep -c $'^ENV\tgo1.25.0$' "$go_log" || true)" -eq 3 ] ||
  fail 'one or more relay build/test recipes lost GOTOOLCHAIN=go1.25.0'
[ "$(grep -c $'^ARG\tbuild$' "$go_log" || true)" -eq 1 ] ||
  fail 'relay build recipe did not invoke go build exactly once'
[ "$(grep -c $'^ARG\ttest$' "$go_log" || true)" -eq 2 ] ||
  fail 'relay test recipes did not invoke go test exactly twice'
grep -Fxq $'ARG\t-o' "$go_log" ||
  fail 'relay build recipe lost its output flag'
grep -Fxq $'ARG\trelay-server' "$go_log" ||
  fail 'relay build recipe lost its output path'
grep -Fxq $'ARG\t^TestRelayNotificationClosure_' "$go_log" ||
  fail 'notification test recipe lost its focused selector'

printf 'PASS: relay Go toolchain contract\n'
