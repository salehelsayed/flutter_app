#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

group_block="$tmp_dir/group-tests.block"
declaration_count="$(grep -Fxc 'readonly GROUP_TESTS=(' scripts/run_test_gates.sh || true)"
[ "$declaration_count" -eq 1 ] ||
  fail "expected one exact readonly GROUP_TESTS declaration, found $declaration_count"
awk '
  $0 == "readonly GROUP_TESTS=(" {
    if (found++) exit 91
    inside = 1
  }
  inside { print }
  inside && $0 == ")" { closed = 1; exit }
  END {
    if (found != 1 || closed != 1) exit 92
  }
' scripts/run_test_gates.sh >"$group_block" ||
  fail 'could not parse the exact readonly GROUP_TESTS array'

expected="$tmp_dir/expected.paths"
{
  rg -l --glob '*_test.dart' 'P269' test
  printf '%s\n' \
    'test/features/groups/presentation/contact_picker_wired_test.dart'
} | LC_ALL=C sort -u >"$expected"

[ -s "$expected" ] || fail 'P269 Dart test discovery returned no files'

while IFS= read -r required_path; do
  [ -n "$required_path" ] || continue
  count="$(awk -v required_path="$required_path" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "\"" required_path "\"") count++
    }
    END { print count + 0 }
  ' "$group_block")"
  [ "$count" -eq 1 ] ||
    fail "$required_path must occur exactly once inside GROUP_TESTS; found $count"
done <"$expected"

# Prove that a later array cannot satisfy membership: the parser has stopped at
# GROUP_TESTS' own closing parenthesis and therefore contains no declaration or
# entry from OPTIONAL_MANUAL_TESTS.
if rg -q '^readonly OPTIONAL_MANUAL_TESTS=\(' "$group_block"; then
  fail 'GROUP_TESTS parser leaked into OPTIONAL_MANUAL_TESTS'
fi

printf 'PASS: every P269 Dart test and contact-picker extension occurs once in GROUP_TESTS\n'
