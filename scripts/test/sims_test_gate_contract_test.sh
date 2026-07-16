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

fake_bin="$tmp_dir/bin"
dart_log="$tmp_dir/dart.log"
flutter_log="$tmp_dir/flutter.log"
mkdir -p "$fake_bin"
touch "$dart_log" "$flutter_log"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  'printf "CALL\n" >>"${FAKE_DART_LOG:?}"' \
  'printf "ARG\t%s\n" "$@" >>"${FAKE_DART_LOG:?}"' \
  'exit "${FAKE_DART_STATUS:-0}"' \
  >"$fake_bin/dart"
chmod +x "$fake_bin/dart"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  'printf "CALL\n" >>"${FAKE_FLUTTER_LOG:?}"' \
  'printf "ARG\t%s\n" "$@" >>"${FAKE_FLUTTER_LOG:?}"' \
  'exit "${FAKE_FLUTTER_STATUS:-0}"' \
  >"$fake_bin/flutter"
chmod +x "$fake_bin/flutter"

export PATH="$fake_bin:$PATH"
export FAKE_DART_LOG="$dart_log"
export FAKE_FLUTTER_LOG="$flutter_log"

# RED/GREEN 1: the public gate forwards the selected mode and every remaining
# argument to the typed Dart orchestrator without rewriting them.
./scripts/run_test_gates.sh sims smoke --list --only android.voice.capture \
  >"$tmp_dir/sims-smoke.stdout"
actual_args="$(awk -F '\t' '$1 == "ARG" { print $2 }' "$dart_log")"
expected_args="$(
  printf '%s\n' \
    tool/sims/sims.dart \
    smoke \
    --list \
    --only \
    android.voice.capture
)"
[ "$actual_args" = "$expected_args" ] ||
  fail 'sims smoke did not delegate the exact mode/argument vector'

# Omitting the mode is the release-safe shorthand for the major-update gate.
: >"$dart_log"
./scripts/run_test_gates.sh sims --list >"$tmp_dir/sims-default.stdout"
default_args="$(awk -F '\t' '$1 == "ARG" { print $2 }' "$dart_log")"
[ "$default_args" = "$(printf '%s\n' tool/sims/sims.dart major --list)" ] ||
  fail 'sims without an explicit mode did not default to major'

# The wrapper must preserve the orchestrator's exit status.
: >"$dart_log"
set +e
FAKE_DART_STATUS=23 ./scripts/run_test_gates.sh sims full \
  >"$tmp_dir/sims-failure.stdout" 2>"$tmp_dir/sims-failure.stderr"
sims_failure_status=$?
set -e
[ "$sims_failure_status" -eq 23 ] ||
  fail "sims delegated failure returned $sims_failure_status instead of 23"

# A non-option first argument is a mode selector, so reject misspellings before
# Dart is started. Options remain valid with the implicit major mode above.
: >"$dart_log"
set +e
./scripts/run_test_gates.sh sims bogus \
  >"$tmp_dir/sims-invalid.stdout" 2>"$tmp_dir/sims-invalid.stderr"
sims_invalid_status=$?
set -e
[ "$sims_invalid_status" -eq 2 ] ||
  fail "invalid sims mode returned $sims_invalid_status instead of 2"
grep -Fq 'Invalid sims mode: bogus' "$tmp_dir/sims-invalid.stderr" ||
  fail 'invalid sims mode did not report the rejected value'
[ ! -s "$dart_log" ] || fail 'invalid sims mode unexpectedly invoked Dart'

# RED/GREEN 2: contract registration is convention-based and deterministic.
# Every top-level scripts/test/*_test.sh file, including this one, must appear
# once in lexical order without maintaining another hand-written registry.
contract_list="$(./scripts/run_test_gates.sh sims-contracts --list)"
actual_contracts="$(
  printf '%s\n' "$contract_list" |
    sed -n 's/^  *[0-9][0-9]*\. bash \(scripts\/test\/.*_test\.sh\)$/\1/p'
)"
expected_contracts="$(
  find scripts/test -maxdepth 1 -type f -name '*_test.sh' -print |
    LC_ALL=C sort
)"
[ -n "$actual_contracts" ] || fail 'sims-contracts --list was empty'
[ "$actual_contracts" = "$expected_contracts" ] ||
  fail 'sims-contracts --list did not exactly match sorted shell discovery'

# RED/GREEN 3: default execution is fail-fast with the original status;
# diagnostic continuation attempts every contract and returns one aggregate red.
fixture_dir="$tmp_dir/contracts"
fixture_log="$tmp_dir/contracts.log"
mkdir -p "$fixture_dir"

write_fixture() {
  local name="$1"
  local status="$2"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -u' \
    'printf "%s\n" "$(basename "$0")" >>"${SIMS_FIXTURE_LOG:?}"' \
    "exit $status" \
    >"$fixture_dir/$name"
  chmod +x "$fixture_dir/$name"
}

# Create out of order so the execution log proves lexical sorting.
write_fixture 03_after_test.sh 0
write_fixture 01_before_test.sh 0
write_fixture 02_failure_test.sh 7
export SIMS_FIXTURE_LOG="$fixture_log"

: >"$fixture_log"
set +e
SIMS_CONTRACTS_DIR="$fixture_dir" ./scripts/run_test_gates.sh sims-contracts \
  >"$tmp_dir/contracts-fast.stdout" 2>"$tmp_dir/contracts-fast.stderr"
contracts_fast_status=$?
set -e
[ "$contracts_fast_status" -eq 7 ] ||
  fail "fail-fast contracts returned $contracts_fast_status instead of 7"
[ "$(sed -n '1,2p' "$fixture_log")" = "$(printf '%s\n' 01_before_test.sh 02_failure_test.sh)" ] ||
  fail 'fail-fast contracts did not stop at the first sorted failure'
[ "$(wc -l <"$fixture_log" | tr -d ' ')" -eq 2 ] ||
  fail 'fail-fast contracts executed a row after the failure'

: >"$fixture_log"
set +e
SIMS_CONTRACTS_DIR="$fixture_dir" ./scripts/run_test_gates.sh \
  sims-contracts --continue-on-failure \
  >"$tmp_dir/contracts-continue.stdout" \
  2>"$tmp_dir/contracts-continue.stderr"
contracts_continue_status=$?
set -e
[ "$contracts_continue_status" -eq 1 ] ||
  fail "continued contracts returned $contracts_continue_status instead of 1"
[ "$(cat "$fixture_log")" = "$(printf '%s\n' 01_before_test.sh 02_failure_test.sh 03_after_test.sh)" ] ||
  fail 'continued contracts did not execute every row in sorted order'
grep -Fq 'Sims shell contracts failed (1):' \
  "$tmp_dir/contracts-continue.stderr" ||
  fail 'continued contracts omitted the aggregate failure header'
grep -Fq '02_failure_test.sh exited with 7' \
  "$tmp_dir/contracts-continue.stderr" ||
  fail 'continued contracts omitted the failing path and original status'

# RED/GREEN 4: the documented mutation matrix is a real lane. It first runs
# the process-shim contracts above, then the typed causal host contracts that
# cover scheduler/resource, cache, checkpoint, verdict, and device-loss seams.
mutation_dir="$tmp_dir/mutation-contracts"
mkdir -p "$mutation_dir"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "PASS: injected command-family failures were rejected\n"' \
  >"$mutation_dir/command_family_mutation_test.sh"
chmod +x "$mutation_dir/command_family_mutation_test.sh"

: >"$flutter_log"
SIMS_CONTRACTS_DIR="$mutation_dir" ./scripts/run_test_gates.sh \
  sims-contracts --mutation-matrix \
  >"$tmp_dir/mutation.stdout" 2>"$tmp_dir/mutation.stderr" ||
  fail 'sims-contracts --mutation-matrix returned nonzero for green contracts'
mutation_flutter_args="$(awk -F '\t' '$1 == "ARG" { print $2 }' "$flutter_log")"
expected_mutation_flutter_args="$(
  printf '%s\n' \
    test \
    test/tool/sims/sims_verdict_test.dart \
    test/tool/sims/sims_build_cache_test.dart \
    test/tool/sims/sims_checkpoint_test.dart \
    test/tool/sims/sims_device_binding_test.dart \
    test/tool/sims/sims_executor_test.dart \
    test/tool/sims/sims_scheduler_test.dart
)"
[ "$mutation_flutter_args" = "$expected_mutation_flutter_args" ] ||
  fail 'mutation matrix did not dispatch the exact typed causal test set'
grep -Fq 'PASS: mutation matrix caught analyzer/Dart/Go command failures' \
  "$tmp_dir/mutation.stdout" ||
  fail 'mutation matrix omitted its causal coverage summary'

printf 'PASS: sims public gate and shell contract registry\n'
