#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_one_typed_result() {
  local output="$1"
  local expected_status="$2"
  local count
  count="$(printf '%s\n' "$output" | grep -c '^SIMS_RESULT_JSON=' || true)"
  [ "$count" -eq 1 ] ||
    fail "adapter emitted $count result sentinels; expected exactly one"
  [ "$(printf '%s\n' "$output" | awk 'NF { count++ } END { print count + 0 }')" -eq 1 ] ||
    fail "adapter wrote non-sentinel output to stdout"
  printf '%s\n' "$output" | grep -q "\"status\":\"$expected_status\"" ||
    fail "adapter did not emit $expected_status: $output"
  printf '%s\n' "$output" | grep -q '"assertionsAttempted":' ||
    fail "typed result omitted assertionsAttempted"
  printf '%s\n' "$output" | grep -q '"artifactPresent":' ||
    fail "typed result omitted artifactPresent"
  printf '%s\n' "$output" | grep -q '"printOnly":false' ||
    fail "typed result omitted printOnly=false"
}

DART_BIN="$(command -v dart)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SHIM_DIR="$TMP_DIR/shims"
RUNNER_APP="$TMP_DIR/cache/Runner.app"
CHILD_LOG="$TMP_DIR/child.log"
CHILD_ENV_LOG="$TMP_DIR/child-env.log"
STDERR_LOG="$TMP_DIR/adapter.stderr"
PROOF_DIR="$TMP_DIR/proofs"
mkdir -p "$SHIM_DIR" "$RUNNER_APP"
: >"$RUNNER_APP/Info.plist"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf '\''%s\n'\'' "$*" >>"$SIMS_TEST_CHILD_LOG"' \
  'printf '\''artifact=%s\nskip=%s\n'\'' "${SIMS_ARTIFACT_IOS_SIMULATOR_E2E:-}" "${GMP_SKIP_HARNESS_BUILD:-}" >>"$SIMS_TEST_CHILD_ENV_LOG"' \
  'printf '\''child diagnostic\n'\''' \
  'exit "${SIMS_TEST_CHILD_EXIT:-0}"' \
  >"$SHIM_DIR/dart"
chmod +x "$SHIM_DIR/dart"

SIM_A='11111111-1111-1111-1111-111111111111'
SIM_B='22222222-2222-2222-2222-222222222222'
SIM_C='33333333-3333-3333-3333-333333333333'
SIM_D='44444444-4444-4444-4444-444444444444'
DEVICE_CSV="$SIM_A,$SIM_B,$SIM_C,$SIM_D"
ADAPTER='integration_test/scripts/run_group_multi_party_sims.dart'

run_adapter() {
  env \
    PATH="$SHIM_DIR:$PATH" \
    SIMS_TEST_CHILD_LOG="$CHILD_LOG" \
    SIMS_TEST_CHILD_ENV_LOG="$CHILD_ENV_LOG" \
    SIMS_PROOF_DIRECTORY="$PROOF_DIR" \
    MKNOON_RELAY_ADDRESSES='127.0.0.1:4001' \
    SIMS_ARTIFACT_IOS_SIMULATOR_E2E="$RUNNER_APP" \
    SIMS_IOS_SIMULATOR_A_DEVICE_ID="$SIM_A" \
    SIMS_IOS_SIMULATOR_B_DEVICE_ID="$SIM_B" \
    SIMS_IOS_SIMULATOR_C_DEVICE_ID="$SIM_C" \
    SIMS_IOS_SIMULATOR_D_DEVICE_ID="$SIM_D" \
    SIMS_IOS_DISPOSABLE_SIMULATOR_IDS="$DEVICE_CSV" \
    "$@"
}

: >"$CHILD_LOG"
: >"$CHILD_ENV_LOG"
output="$(run_adapter "$DART_BIN" "$ADAPTER" 2>"$STDERR_LOG")"
assert_one_typed_result "$output" 'PASS'
printf '%s\n' "$output" | grep -q '"assertionsAttempted":9' ||
  fail "PASS did not account for all nine smoke scenarios"
printf '%s\n' "$output" | grep -q '"artifactEvidence":' ||
  fail "PASS omitted durable artifact evidence"
printf '%s\n' "$output" | grep -q '"validatorIds":\["validateGroupMultiPartyLedger"\]' ||
  fail "PASS omitted the exact group ledger validator ID"
proof_path="$(printf '%s\n' "$output" | sed -n 's/.*"artifactEvidence":{"path":"\([^"]*\)".*/\1/p')"
[ -f "$proof_path" ] || fail "PASS pointed to a missing group proof artifact"
[ "$(wc -l <"$CHILD_LOG" | tr -d ' ')" -eq 1 ] ||
  fail "adapter launched the aggregate runner more than once"
grep -Fxq \
  "run integration_test/scripts/run_group_multi_party_device_real.dart --scenario smoke -d $DEVICE_CSV" \
  "$CHILD_LOG" || fail "adapter passed the wrong aggregate runner arguments"
grep -q 'build' "$CHILD_LOG" &&
  fail "adapter launched a build command despite the prepared Runner.app"
grep -Fxq "artifact=$RUNNER_APP" "$CHILD_ENV_LOG" ||
  fail "adapter did not pass the prepared Runner.app to the aggregate runner"
grep -Fxq 'skip=1' "$CHILD_ENV_LOG" ||
  fail "adapter did not preserve GMP_SKIP_HARNESS_BUILD reuse behavior"
grep -q 'child diagnostic' "$STDERR_LOG" ||
  fail "child diagnostics were not preserved on stderr"

assert_blocked_without_child() {
  local expected_blocker="$1"
  shift
  : >"$CHILD_LOG"
  set +e
  local blocked_output
  blocked_output="$(run_adapter "$@" 2>"$STDERR_LOG")"
  local status=$?
  set -e
  [ "$status" -eq 78 ] ||
    fail "$expected_blocker blocker exited $status instead of 78"
  assert_one_typed_result "$blocked_output" 'BLOCKED'
  printf '%s\n' "$blocked_output" | grep -q "\"blocker\":\"$expected_blocker\"" ||
    fail "BLOCKED result did not use blocker=$expected_blocker"
  [ ! -s "$CHILD_LOG" ] ||
    fail "$expected_blocker blocker launched the aggregate runner"
}

assert_blocked_without_child \
  environment \
  env -u MKNOON_RELAY_ADDRESSES "$DART_BIN" "$ADAPTER"
assert_blocked_without_child \
  missingArtifact \
  env -u SIMS_ARTIFACT_IOS_SIMULATOR_E2E "$DART_BIN" "$ADAPTER"
assert_blocked_without_child \
  targetUnavailable \
  env -u SIMS_IOS_SIMULATOR_D_DEVICE_ID "$DART_BIN" "$ADAPTER"
assert_blocked_without_child \
  permissions \
  env -u SIMS_IOS_DISPOSABLE_SIMULATOR_IDS "$DART_BIN" "$ADAPTER"

RUNNER='integration_test/scripts/run_group_multi_party_device_real.dart'
grep -Fq 'groupMultiPartySimulatorTargetsAreDisposable(devices)' "$RUNNER" ||
  fail 'direct group runner bypasses disposable-simulator authorization'
authorization_line="$(grep -n 'groupMultiPartySimulatorTargetsAreDisposable(devices)' "$RUNNER" | head -1 | cut -d: -f1)"
sweep_line="$(grep -n 'final result = await runGroupMultiPartyScenarioSweep' "$RUNNER" | head -1 | cut -d: -f1)"
[ "$authorization_line" -lt "$sweep_line" ] ||
  fail 'direct runner authorizes disposable simulators only after scenario mutation starts'

: >"$CHILD_LOG"
set +e
failed_output="$(
  run_adapter env SIMS_TEST_CHILD_EXIT=1 "$DART_BIN" "$ADAPTER" \
    2>"$STDERR_LOG"
)"
failed_status=$?
set -e
[ "$failed_status" -eq 1 ] || fail "child failure was not propagated"
assert_one_typed_result "$failed_output" 'FAIL'
[ "$(wc -l <"$CHILD_LOG" | tr -d ' ')" -eq 1 ] ||
  fail "failed aggregate runner was launched more than once"

printf 'PASS: group multi-party sims adapter contract\n'
