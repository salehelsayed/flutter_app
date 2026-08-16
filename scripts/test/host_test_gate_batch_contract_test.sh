#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

count_lines() {
  awk 'NF { count++ } END { print count + 0 }'
}

expect_error() {
  local expected_message="$1"
  shift

  local output
  local status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  [ "$status" -eq 2 ] ||
    fail "invalid option path exited with $status instead of 2: $*"
  grep -Fq "$expected_message" <<<"$output" ||
    fail "invalid option path did not report '$expected_message': $*"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
flutter_log="$tmp_dir/flutter.log"
go_log="$tmp_dir/go.log"
native_log="$tmp_dir/native.log"
real_bash="$(command -v bash)"
mkdir -p "$fake_bin"
touch "$flutter_log" "$go_log" "$native_log"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  '{' \
  '  printf "CALL\n"' \
  '  printf "ARG\t%s\n" "$@"' \
  '  printf "END\n"' \
  '} >>"${FAKE_FLUTTER_LOG:?}"' \
  'exit "${FAKE_FLUTTER_STATUS:-0}"' \
  >"$fake_bin/flutter"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  '{' \
  '  printf "CALL\n"' \
  '  printf "ENV\t%s\n" "${GOTOOLCHAIN:-}"' \
  '  printf "ARG\t%s\n" "$@"' \
  '  printf "END\n"' \
  '} >>"${FAKE_GO_LOG:?}"' \
  'push_vault_process=0' \
  'wake_outcome_process=0' \
  'wake_outcome_node=0' \
  'wake_outcome_bridge=0' \
  'go_mode=""' \
  'for arg in "$@"; do' \
  '  case "$arg" in' \
  '    *TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff*) push_vault_process=1 ;;' \
  '    *TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff*) wake_outcome_process=1 ;;' \
  '    *TestInboxWakeOutcomeAllRelayCompletion*) wake_outcome_node=1 ;;' \
  '    *TestInboxWakeOutcomeBridgeStrictRequest*) wake_outcome_bridge=1 ;;' \
  '    -list) go_mode="list" ;;' \
  '    -run) go_mode="run" ;;' \
  '  esac' \
  'done' \
  'if [ "$push_vault_process" -eq 1 ]; then' \
  '  case "$go_mode" in' \
  '    list)' \
  '      printf "%s\n" TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff' \
  '      ;;' \
  '    run)' \
  '      printf "%s\n" \' \
  '        "=== RUN   TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff" \' \
  '        "--- PASS: TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff (0.01s)" \' \
  '        "PASS" \' \
  '        "ok  \tgithub.com/mknoon/relay-server\t0.01s"' \
  '      ;;' \
  '  esac' \
  'fi' \
  'if [ "$wake_outcome_process" -eq 1 ]; then' \
  '  case "$go_mode" in' \
  '    list)' \
  '      printf "%s\n" TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff' \
  '      ;;' \
  '    run)' \
  '      printf "%s\n" \' \
  '        "=== RUN   TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff" \' \
  '        "--- PASS: TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff (0.01s)" \' \
  '        "PASS" \' \
  '        "ok  \tgithub.com/mknoon/relay-server\t0.01s"' \
  '      ;;' \
  '  esac' \
  'fi' \
  'if [ "$wake_outcome_node" -eq 1 ]; then' \
  '  case "$go_mode" in' \
  '    list)' \
  '      printf "%s\n" TestInboxWakeOutcomeAllRelayCompletion' \
  '      ;;' \
  '    run)' \
  '      printf "%s\n" \' \
  '        "=== RUN   TestInboxWakeOutcomeAllRelayCompletion" \' \
  '        "--- PASS: TestInboxWakeOutcomeAllRelayCompletion (0.01s)" \' \
  '        "PASS" \' \
  '        "ok  \tgithub.com/mknoon/go-mknoon/node\t0.01s"' \
  '      ;;' \
  '  esac' \
  'fi' \
  'if [ "$wake_outcome_bridge" -eq 1 ]; then' \
  '  case "$go_mode" in' \
  '    list)' \
  '      printf "%s\n" TestInboxWakeOutcomeBridgeStrictRequest' \
  '      ;;' \
  '    run)' \
  '      printf "%s\n" \' \
  '        "=== RUN   TestInboxWakeOutcomeBridgeStrictRequest" \' \
  '        "--- PASS: TestInboxWakeOutcomeBridgeStrictRequest (0.01s)" \' \
  '        "PASS" \' \
  '        "ok  \tgithub.com/mknoon/go-mknoon/bridge\t0.01s"' \
  '      ;;' \
  '  esac' \
  'fi' \
  'exit "${FAKE_GO_STATUS:-0}"' \
  >"$fake_bin/go"

printf '%s\n' \
  '#!/bin/sh' \
  'set -u' \
  'case "${1:-}" in' \
  '  scripts/test/run_app_visibility_native_371.sh|scripts/test/run_ios_nse_native_373.sh|scripts/test/run_android_headless_recovery_native_374.sh)' \
  '    printf "%s\n" "$1" >>"${FAKE_NATIVE_LOG:?}"' \
  '    exit "${FAKE_NATIVE_STATUS:-0}"' \
  '    ;;' \
  '  *) exec "${REAL_BASH:?}" "$@" ;;' \
  'esac' \
  >"$fake_bin/bash"

chmod +x "$fake_bin/flutter" "$fake_bin/go" "$fake_bin/bash"

export PATH="$fake_bin:$PATH"
export FAKE_FLUTTER_LOG="$flutter_log"
export FAKE_GO_LOG="$go_log"
export FAKE_NATIVE_LOG="$native_log"
export REAL_BASH="$real_bash"

expected_dart_paths="$({
  rg --files test -g '*_test.dart' |
    awk '$0 !~ /^test\/performance\//' |
    sort
})"
expected_dart_count="$(printf '%s\n' "$expected_dart_paths" | count_lines)"
[ "$expected_dart_count" -gt 0 ] ||
  fail 'host-all Dart inventory was unexpectedly empty'

# RED/GREEN 0: the wrapper's zero-extra-argument path remains nounset-safe,
# while the same curated gate rejects a host-batch control before dispatch.
zero_arg_output="$(./scripts/run_test_gates.sh completeness-check)"
grep -Fq 'Completeness check PASS.' <<<"$zero_arg_output" ||
  fail 'zero-argument completeness-check did not complete successfully'
expect_error 'Host batch options are not supported for gate: completeness-check' \
  ./scripts/run_test_gates.sh completeness-check --batch-flutter

# RED/GREEN 1: batch options retain the individual canonical dry-run plan and
# execute no command.
dry_output="$(
  ./scripts/run_test_gates.sh host-all \
    --batch-flutter \
    --concurrency 4 \
    --reporter failures-only \
    --dry-run
)"
dry_dart_count="$(
  printf '%s\n' "$dry_output" |
    awk '/^  *[0-9]+\. Flutter batch path / { count++ } END { print count + 0 }'
)"
dry_synthetic_count="$(
  printf '%s\n' "$dry_output" |
    awk '/^  *[0-9]+\. / && $0 !~ /Flutter batch path / { count++ } END { print count + 0 }'
)"
[ "$dry_dart_count" -eq "$expected_dart_count" ] ||
  fail "batch dry-run listed $dry_dart_count Dart paths instead of $expected_dart_count"
[ "$dry_synthetic_count" -eq 16 ] ||
  fail "batch dry-run listed $dry_synthetic_count synthetic rows instead of 16"
[ $((dry_dart_count + dry_synthetic_count)) -eq $((expected_dart_count + 16)) ] ||
  fail 'batch dry-run did not preserve every indexed planned item'
grep -Fq 'Host test planned-item inventory: host-all' <<<"$dry_output" ||
  fail 'batch dry-run mislabeled the indexed inventory as serial commands'
grep -Fq \
  "Batch execution shape: 1 Flutter invocation for $expected_dart_count exact Dart path(s)" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the truthful Flutter aggregate shape'
grep -Fq '16 separate non-Flutter invocation(s)' <<<"$dry_output" ||
  fail 'batch dry-run omitted the sixteen separate synthetic inventory rows'
grep -Fq \
  "go test -tags integration . -list '^TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff$'" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the exact push-vault process discovery command'
grep -Fq \
  "go test -tags integration . -run '^TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff$' -count=1 -v" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the exact push-vault process execution command'
grep -Fq \
  "rg -c '^--- PASS: TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff '" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the push-vault exact PASS cardinality check'
grep -Fq \
  "rg -q '^[[:space:]]*--- SKIP: TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff'" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the push-vault no-skip check'
grep -Fq \
  "go test -tags integration . -list '^TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff$'" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the exact wake-outcome process discovery command'
grep -Fq \
  "go test -tags integration . -run '^TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff$' -count=1 -v" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the exact wake-outcome process execution command'
grep -Fq \
  "rg -c '^--- PASS: TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff '" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the wake-outcome exact PASS cardinality check'
grep -Fq \
  "rg -q '^[[:space:]]*--- SKIP: TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff'" \
  <<<"$dry_output" ||
  fail 'batch dry-run omitted the wake-outcome no-skip check'
for spec in \
  'node TestInboxWakeOutcomeAllRelayCompletion' \
  'bridge TestInboxWakeOutcomeBridgeStrictRequest'; do
  pkg="${spec%% *}"
  name="${spec#* }"
  grep -Fq "go test ./$pkg -list '^$name$'" <<<"$dry_output" ||
    fail "batch dry-run omitted exact $pkg wake-outcome discovery"
  grep -Fq "go test ./$pkg -run '^$name$' -count=1 -v" <<<"$dry_output" ||
    fail "batch dry-run omitted exact $pkg wake-outcome execution"
  grep -Fq "rg -c '^--- PASS: $name '" <<<"$dry_output" ||
    fail "batch dry-run omitted exact $pkg wake-outcome PASS check"
  grep -Fq "rg -q '^[[:space:]]*--- SKIP: $name'" <<<"$dry_output" ||
    fail "batch dry-run omitted exact $pkg wake-outcome no-skip check"
done
[ "$(grep -Ec '^  *[0-9]+\. bash scripts/test/run_relay_all_go_309\.sh$' <<<"$dry_output" || true)" -eq 1 ] ||
  fail 'batch dry-run did not print the relay-all script through bash exactly once'
grep -Fq 'planned items, not serial execution commands' <<<"$dry_output" ||
  fail 'batch dry-run did not distinguish inventory rows from execution'
[ ! -s "$flutter_log" ] || fail 'batch dry-run invoked Flutter'
[ ! -s "$go_log" ] || fail 'batch dry-run invoked Go'
[ ! -s "$native_log" ] || fail 'batch dry-run invoked a native script'

# RED/GREEN 1b: major sims composes the exact Dart host inventory with its own
# full-Go lane. --dart-only must therefore remove all sixteen synthetic non-Dart tails
# without changing a single Dart path or the one-invocation batch shape.
dart_only_dry_output="$(
  ./scripts/run_test_gates.sh host-all \
    --dart-only \
    --batch-flutter \
    --concurrency 4 \
    --reporter failures-only \
    --dry-run
)"
dart_only_dry_paths="$(
  printf '%s\n' "$dart_only_dry_output" |
    sed -n "s/^  *[0-9][0-9]*\. Flutter batch path '\(test\/.*_test\.dart\)'$/\1/p"
)"
[ "$dart_only_dry_paths" = "$expected_dart_paths" ] ||
  fail '--dart-only dry-run changed the exact sorted Dart inventory'
if grep -Eq 'go test|run_relay_all_go_309' <<<"$dart_only_dry_output"; then
  fail '--dart-only dry-run retained a non-Dart command'
fi
grep -Fq '0 separate non-Flutter invocation(s)' <<<"$dart_only_dry_output" ||
  fail '--dart-only dry-run did not report zero trailing Go invocations'

broad_scope_dry="$({
  ./scripts/run_test_gates.sh core-host-all \
    --batch-flutter \
    --concurrency 2 \
    --reporter compact \
    --dry-run
})"
grep -Fq 'Host test planned-item inventory: core-host-all' \
  <<<"$broad_scope_dry" ||
  fail 'public wrapper did not forward batch controls to a broad host scope'
grep -Fq 'concurrency=2, reporter=compact' <<<"$broad_scope_dry" ||
  fail 'public wrapper changed forwarded broad-scope batch controls'

# DTR-11: core-host-all owns every unit-level tooling/policy suite as an exact
# sorted family, not only test/core. This assertion is intentionally added
# before the host planner changes so its first run is the causal registration
# RED.
expected_unit_paths="$(rg --files test/unit -g '*_test.dart' | sort)"
actual_unit_paths="$(
  printf '%s\n' "$broad_scope_dry" |
    sed -n "s/^  *[0-9][0-9]*\. Flutter batch path '\(test\/.*_test\.dart\)'$/\1/p" |
    awk '$0 ~ /^test\/unit\//'
)"
[ "$actual_unit_paths" = "$expected_unit_paths" ] ||
  fail 'core-host-all omitted or duplicated test/unit paths'

# RED/GREEN 2: the full batch is one exact-path Flutter command followed by the
# sixteen synthetic rows: nine one-call Go legs, four exact-test Go rows'
# discovery/execution pairs, and three native scripts (seventeen Go calls in total).
batch_output="$(
  ./scripts/run_test_gates.sh host-all \
    --batch-flutter \
    --concurrency 4 \
    --reporter failures-only
)"
flutter_call_count="$(grep -c '^CALL$' "$flutter_log" || true)"
go_call_count="$(grep -c '^CALL$' "$go_log" || true)"
[ "$flutter_call_count" -eq 1 ] ||
  fail "batch mode invoked Flutter $flutter_call_count times instead of once"
[ "$go_call_count" -eq 17 ] ||
  fail "batch mode invoked Go $go_call_count times instead of seventeen"
expected_native_paths="$(printf '%s\n' \
  scripts/test/run_android_headless_recovery_native_374.sh \
  scripts/test/run_app_visibility_native_371.sh \
  scripts/test/run_ios_nse_native_373.sh)"
actual_native_paths="$(sort "$native_log")"
[ "$actual_native_paths" = "$expected_native_paths" ] ||
  fail 'batch mode did not execute the exact three native synthetic rows once each'

actual_dart_paths="$({
  awk -F '\t' '$1 == "ARG" && $2 ~ /^test\// { print $2 }' "$flutter_log"
})"
actual_dart_count="$(printf '%s\n' "$actual_dart_paths" | count_lines)"
[ "$actual_dart_count" -eq "$expected_dart_count" ] ||
  fail "batch Flutter call received $actual_dart_count paths instead of $expected_dart_count"
[ "$actual_dart_paths" = "$expected_dart_paths" ] ||
  fail 'batch Flutter paths were not the exact unique sorted host-all inventory'
if grep -q '^test/performance/' <<<"$actual_dart_paths"; then
  fail 'batch Flutter paths included test/performance'
fi
if printf '%s\n' "$actual_dart_paths" |
  awk '$0 !~ /_test\.dart$/ { bad = 1 } END { exit bad ? 0 : 1 }'; then
  fail 'batch Flutter call used a directory shorthand or non-test path'
fi
grep -Fxq $'ARG\t--concurrency=4' "$flutter_log" ||
  fail 'batch Flutter call did not receive --concurrency=4'
grep -Fxq $'ARG\t--reporter=failures-only' "$flutter_log" ||
  fail 'batch Flutter call did not receive --reporter=failures-only'

[ "$(grep -c $'^ENV\tgo1.25.0$' "$go_log" || true)" -eq 17 ] ||
  fail 'one or more Go legs lost the pinned GOTOOLCHAIN'
[ "$(grep -c $'^ARG\ttest$' "$go_log" || true)" -eq 17 ] ||
  fail 'the thirteen Go-backed synthetic rows did not retain their seventeen separate go test invocations'
[ "$(grep -c $'^ARG\t-run$' "$go_log" || true)" -eq 12 ] ||
  fail 'one or more separate Go legs lost its -run selector'
[ "$(grep -c $'^ARG\t-count=1$' "$go_log" || true)" -eq 13 ] ||
  fail 'one or more separate Go legs lost -count=1'
[ "$(grep -c $'^ARG\t-list$' "$go_log" || true)" -eq 4 ] ||
  fail 'the four exact-test rows did not retain their discovery calls'
[ "$(grep -c $'^ARG\t-tags$' "$go_log" || true)" -eq 4 ] ||
  fail 'the process discovery/execution calls lost -tags integration'
[ "$(grep -c $'^ARG\tintegration$' "$go_log" || true)" -eq 4 ] ||
  fail 'the process discovery/execution calls changed the integration tag'
[ "$(grep -c $'^ARG\t\.$' "$go_log" || true)" -eq 4 ] ||
  fail 'the process discovery/execution calls changed the relay package target'
[ "$(grep -c $'^ARG\t-v$' "$go_log" || true)" -eq 4 ] ||
  fail 'an exact-test execution call lost verbose PASS evidence'
[ "$(grep -c $'^ARG\t\./\.\.\.$' "$go_log" || true)" -eq 1 ] ||
  fail 'the relay-all script did not retain its exact unfiltered module target'
[ "$(grep -c $'^ARG\t./bridge$' "$go_log" || true)" -eq 5 ] ||
  fail 'batch mode did not preserve the five bridge-package Go calls'
[ "$(grep -c $'^ARG\t./node$' "$go_log" || true)" -eq 6 ] ||
  fail 'batch mode did not preserve the six node-package Go calls'
[ "$(grep -c $'^ARG\t./node/$' "$go_log" || true)" -eq 1 ] ||
  fail 'batch mode did not preserve the addr-visibility node/ Go leg'
for sentinel in \
  TestGroupSendReliable_ReportsConnectedTopicPeerCount \
  KeyRotation \
  AnnouncedAddrsSurvive \
  FeatureFlag \
  PartialFeatureFlags \
  WakeToken \
  TestGoLibp2pProductionShapeBudget \
  TestSendMessageWithTransport_AckFrameValidation \
  TestR3Deadline_ \
  TestSendMessage_ReturnsUnackedWhenReceiverDoesNotConfirmDirectChat \
  TestHandleIncomingMessage_BindsAuthenticatedRemotePeerAndClassifiedTransport \
  TestHandleIncomingMessage_DeferredDirectAck_FalseConfirmDoesNotAck \
  TestInboxWakeOutcomeAllRelayCompletion \
  TestInboxWakeOutcomeBridgeStrictRequest \
  TestBridgeExportedHandlersUseSharedEntrypoint; do
  grep -Fq "$sentinel" "$go_log" ||
    fail "batch mode omitted Go sentinel: $sentinel"
done
grep -Fq 'PASS: host tests completed for scope: host-all' <<<"$batch_output" ||
  fail 'batch mode did not report host-all completion'

# RED/GREEN 2b: execute the Dart-only shape. This is the no-duplicate-Go lock
# for the major gate: Flutter runs once with the unchanged inventory and Go is
# not invoked at all.
: >"$flutter_log"
: >"$go_log"
./scripts/run_test_gates.sh host-all \
  --dart-only \
  --batch-flutter \
  --concurrency 4 \
  --reporter failures-only \
  >"$tmp_dir/dart-only.stdout"
[ "$(grep -c '^CALL$' "$flutter_log" || true)" -eq 1 ] ||
  fail '--dart-only batch did not invoke Flutter exactly once'
[ ! -s "$go_log" ] || fail '--dart-only batch invoked a duplicate Go leg'
dart_only_actual_paths="$(
  awk -F '\t' '$1 == "ARG" && $2 ~ /^test\// { print $2 }' "$flutter_log"
)"
[ "$dart_only_actual_paths" = "$expected_dart_paths" ] ||
  fail '--dart-only batch changed the exact sorted Dart inventory'

# RED/GREEN 3: default serial behavior remains byte-shape compatible for a
# focused Dart path; new batch controls are never forwarded unless requested.
: >"$flutter_log"
: >"$go_log"
IFS= read -r first_dart_path <<<"$expected_dart_paths"
./scripts/run_host_test_gates.sh host-all --only "$first_dart_path" >/dev/null
[ "$(grep -c '^CALL$' "$flutter_log" || true)" -eq 1 ] ||
  fail 'default --only Dart path did not invoke Flutter exactly once'
serial_args="$(awk -F '\t' '$1 == "ARG" { print $2 }' "$flutter_log")"
[ "$serial_args" = "$(printf 'test\n%s' "$first_dart_path")" ] ||
  fail 'default behavior unexpectedly forwarded batch-only arguments'
[ ! -s "$go_log" ] || fail 'default Dart --only unexpectedly invoked Go'

# RED/GREEN 4: --only and --start-at filter the indexed plan before batching.
: >"$flutter_log"
: >"$go_log"
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter \
  --concurrency 3 \
  --reporter compact \
  --only "$first_dart_path" \
  >/dev/null
only_paths="$(
  awk -F '\t' '$1 == "ARG" && $2 ~ /^test\// { print $2 }' "$flutter_log"
)"
[ "$only_paths" = "$first_dart_path" ] ||
  fail 'batch --only did not preserve exactly one Dart path'
[ ! -s "$go_log" ] || fail 'batch Dart --only unexpectedly invoked Go'

: >"$flutter_log"
: >"$go_log"
last_dart_path="${expected_dart_paths##*$'\n'}"
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter \
  --start-at "$expected_dart_count" \
  >/dev/null
start_paths="$(
  awk -F '\t' '$1 == "ARG" && $2 ~ /^test\// { print $2 }' "$flutter_log"
)"
[ "$start_paths" = "$last_dart_path" ] ||
  fail 'batch --start-at did not filter before the Flutter batch'
[ "$(grep -c '^CALL$' "$go_log" || true)" -eq 17 ] ||
  fail 'batch --start-at did not retain the sixteen trailing rows and seventeen Go calls'

: >"$flutter_log"
: >"$go_log"
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter \
  --only go-mknoon/node/feature_flags_merge_test.go \
  >/dev/null
[ ! -s "$flutter_log" ] || fail 'Go-only batch selection invoked Flutter'
[ "$(grep -c '^CALL$' "$go_log" || true)" -eq 1 ] ||
  fail 'Go-only batch selection did not invoke exactly one Go leg'
grep -Fq 'FeatureFlag' "$go_log" ||
  fail 'Go-only batch selection invoked the wrong leg'

: >"$flutter_log"
: >"$go_log"
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter \
  --only scripts/test/run_relay_all_go_309.sh \
  >"$tmp_dir/relay-all.stdout"
[ ! -s "$flutter_log" ] || fail 'relay-all batch selection invoked Flutter'
[ "$(grep -c '^CALL$' "$go_log" || true)" -eq 1 ] ||
  fail 'relay-all batch selection did not invoke Go exactly once'
expected_relay_all_args="$(printf 'test\n./...\n-count=1')"
actual_relay_all_args="$(awk -F '\t' '$1 == "ARG" { print $2 }' "$go_log")"
[ "$actual_relay_all_args" = "$expected_relay_all_args" ] ||
  fail 'relay-all batch selection changed the exact unfiltered Go command'
[ "$(grep -c $'^ENV\tgo1.25.0$' "$go_log" || true)" -eq 1 ] ||
  fail 'relay-all batch selection lost the pinned GOTOOLCHAIN'

# RED/GREEN 5: a failed Flutter batch remains fail-fast by default and
# --continue-on-failure still runs every trailing Go leg before returning 1.
: >"$flutter_log"
: >"$go_log"
: >"$native_log"
set +e
FAKE_FLUTTER_STATUS=7 ./scripts/run_host_test_gates.sh host-all \
  --batch-flutter \
  --reporter failures-only \
  >"$tmp_dir/fail-fast.stdout" 2>"$tmp_dir/fail-fast.stderr"
fail_fast_status=$?
set -e
[ "$fail_fast_status" -eq 7 ] ||
  fail "batch fail-fast returned $fail_fast_status instead of Flutter status 7"
grep -Fxq $'ARG\t--concurrency=1' "$flutter_log" ||
  fail 'batch mode without --concurrency did not use the safe default of 1'
[ ! -s "$go_log" ] ||
  fail 'batch fail-fast continued into Go without --continue-on-failure'
[ ! -s "$native_log" ] ||
  fail 'batch fail-fast continued into native scripts without --continue-on-failure'

: >"$flutter_log"
: >"$go_log"
: >"$native_log"
set +e
FAKE_FLUTTER_STATUS=7 ./scripts/run_host_test_gates.sh host-all \
  --batch-flutter \
  --continue-on-failure \
  --reporter failures-only \
  >"$tmp_dir/continue.stdout" 2>"$tmp_dir/continue.stderr"
continue_status=$?
set -e
[ "$continue_status" -eq 1 ] ||
  fail "batch continue returned $continue_status instead of aggregate status 1"
[ "$(grep -c '^CALL$' "$go_log" || true)" -eq 17 ] ||
  fail 'batch continue did not execute all sixteen synthetic rows and seventeen Go calls'
[ "$(count_lines <"$native_log")" -eq 3 ] ||
  fail 'batch continue did not execute all three native synthetic rows'
grep -Fq 'Flutter batch exited with 7' "$tmp_dir/continue.stderr" ||
  fail 'batch continue failure summary omitted the Flutter status'

# RED/GREEN 6: reject ambiguous or unsupported batch controls before planning.
expect_error 'requires --batch-flutter' \
  ./scripts/run_host_test_gates.sh host-all --concurrency 4 --dry-run
expect_error 'requires --batch-flutter' \
  ./scripts/run_host_test_gates.sh host-all --reporter compact --dry-run
expect_error 'Invalid --concurrency value' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 0 --dry-run
expect_error 'Invalid --concurrency value' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency nope --dry-run
expect_error 'Invalid --reporter value' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --reporter noisy --dry-run
expect_error 'Invalid --reporter value' \
  ./scripts/run_test_gates.sh host-all --batch-flutter --reporter json --dry-run
expect_error 'Invalid --reporter value' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --reporter github --dry-run
expect_error 'Invalid --reporter value' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --reporter silent --dry-run
expect_error 'Invalid --concurrency value' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 65 --dry-run
expect_error 'Invalid --concurrency value' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter \
    --concurrency 999999999999999999999999999999999999999999 --dry-run
expect_error 'Missing value for --concurrency' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency
expect_error 'Missing value for --reporter' \
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --reporter

# Public curated gates must reject host-batch controls instead of silently
# delegating to a host-only subset or ignoring the options.
expect_error 'not supported for gate: 1to1' \
  ./scripts/run_test_gates.sh 1to1 --batch-flutter --dry-run
expect_error 'not supported for gate: 1to1' \
  ./scripts/run_test_gates.sh 1to1 --reporter compact
expect_error 'not supported for gate: groups' \
  ./scripts/run_test_gates.sh groups --batch-flutter
expect_error 'not supported for gate: groups' \
  ./scripts/run_test_gates.sh groups --concurrency 4
expect_error 'not supported for gate: groups' \
  ./scripts/run_test_gates.sh groups --reporter=json
expect_error 'not supported for gate: groups' \
  ./scripts/run_test_gates.sh groups --dart-only
expect_error 'not supported for host scope: 1to1' \
  ./scripts/run_host_test_gates.sh 1to1 --batch-flutter --dry-run
expect_error 'not supported for host scope: 1to1' \
  ./scripts/run_host_test_gates.sh 1to1 --dart-only --dry-run

printf 'PASS: batched host test gate contract\n'
