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

real_path="$PATH"
shim_dir="$tmp_dir/bin"
mkdir -p "$shim_dir"
command_log="$tmp_dir/commands.log"
artifact="$tmp_dir/android-e2e-standard.apk"
config_capture="$tmp_dir/runtime-config.json"
ack_file="$tmp_dir/runtime-ack.json"
result_file="$tmp_dir/runtime-result.json"
proof_dir="$tmp_dir/proofs"
app_state="$tmp_dir/app-installed"
drive_state="$tmp_dir/drive-completed"
printf 'prebuilt-performance-apk-fixture\n' >"$artifact"
artifact_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"

cat >"$shim_dir/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'adb' >>"$COMMAND_LOG"
printf ' %q' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"

case "${1:-}" in
  version)
    printf 'Android Debug Bridge version fixture\n'
    ;;
  devices)
    printf 'List of devices attached\n'
    printf 'pixel-usb\tdevice usb:1-1 product:oriole model:Pixel_6 transport_id:1\n'
    printf 'emulator-5554\tdevice product:sdk_gphone model:sdk_gphone transport_id:2\n'
    ;;
  -s)
    serial="${2:-}"
    shift 2
    case "$serial" in
      pixel-usb|emulator-5554) ;;
      *) exit 1 ;;
    esac
    case "${1:-}" in
      get-state)
        printf 'device\n'
        ;;
      install)
        [ "$serial" = pixel-usb ] || exit 1
        [ "${2:-}" = -r ] || exit 1
        [ "${3:-}" = -d ] || exit 1
        [ "${4:-}" = -t ] || exit 1
        [ "${5:-}" = "$EXPECTED_ARTIFACT" ] || exit 1
        : >"$APP_STATE"
        printf 'Success\n'
        ;;
      uninstall)
        rm -f "$APP_STATE"
        printf 'Success\n'
        ;;
      push)
        [ "$serial" = pixel-usb ] || exit 1
        [ -f "${2:-}" ] || exit 1
        cp "${2:-}" "$CONFIG_CAPTURE"
        ;;
      shell)
        shift
        case "$*" in
          'getprop ro.kernel.qemu')
            if [ "$serial" = emulator-5554 ]; then
              printf '1\n'
            else
              printf '0\n'
            fi
            ;;
          'pm path com.mknoon.app')
            [ ! -f "$APP_STATE" ] || printf 'package:/data/app/base.apk\n'
            ;;
          'pm list packages -3')
            [ ! -f "$APP_STATE" ] || printf 'package:com.mknoon.app\n'
            ;;
          'sha256sum /data/app/base.apk')
            [ -f "$APP_STATE" ]
            printf '%s  /data/app/base.apk\n' \
              "$(shasum -a 256 "$EXPECTED_ARTIFACT" | awk '{print $1}')"
            ;;
          'pidof com.mknoon.app'|'dumpsys activity activities'|\
          'run-as com.mknoon.app ls -1 -A .')
            ;;
          'run-as com.mknoon.app mkdir -p files/sims')
            ;;
          'run-as com.mknoon.app rm -f files/sims/runtime-config.json files/sims/runtime-ack.json files/sims/runtime-result.json')
            rm -f "$ACK_FILE" "$RESULT_FILE"
            ;;
          run-as\ com.mknoon.app\ cp\ /data/local/tmp/mknoon-sims-runtime-*\ files/sims/runtime-config.json)
            ;;
          'run-as com.mknoon.app cat files/sims/runtime-ack.json')
            [ -f "$ACK_FILE" ] || exit 1
            cat "$ACK_FILE"
            ;;
          'run-as com.mknoon.app cat files/sims/runtime-result.json')
            [ -f "$RESULT_FILE" ] || exit 1
            cat "$RESULT_FILE"
            ;;
          'am force-stop com.mknoon.app')
            if [ "${CLEANUP_FAIL:-false}" = true ] && [ -f "$DRIVE_STATE" ]; then
              rm -f "$DRIVE_STATE"
              exit 9
            fi
            ;;
          rm\ -f\ /data/local/tmp/mknoon-sims-runtime-*)
            ;;
          *)
            exit 1
            ;;
        esac
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$shim_dir/adb"

cat >"$shim_dir/apkanalyzer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = manifest ]
[ "${2:-}" = application-id ]
[ -f "${3:-}" ]
printf 'com.mknoon.app\n'
EOF
chmod +x "$shim_dir/apkanalyzer"

cat >"$shim_dir/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'flutter' >>"$COMMAND_LOG"
printf ' %q' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"
[ "${1:-}" = drive ] || exit 91

case "${ACK_MODE:-accepted}" in
  accepted)
    printf '%s\n' '{"schema":"mknoon.sims.runtime-ack.v1","profileId":"android.e2e.standard","scenarioId":"performance.device.critical","role":"primary","runId":"run-performance-contract-1","nonce":"nonce-performance-contract-1","accepted":true,"detail":"runtime invocation accepted"}' >"$ACK_FILE"
    ;;
  stale)
    printf '%s\n' '{"schema":"mknoon.sims.runtime-ack.v1","profileId":"android.e2e.standard","scenarioId":"performance.device.critical","role":"primary","runId":"run-performance-contract-1","nonce":"nonce-stale","accepted":true,"detail":"runtime invocation accepted"}' >"$ACK_FILE"
    ;;
  rejected)
    printf '%s\n' '{"schema":"mknoon.sims.runtime-ack.v1","profileId":"android.e2e.standard","scenarioId":"performance.device.critical","role":"primary","runId":"run-performance-contract-1","nonce":"nonce-performance-contract-1","accepted":false,"detail":"fixture rejected invocation"}' >"$ACK_FILE"
    ;;
  missing)
    rm -f "$ACK_FILE"
    ;;
  *)
    exit 92
    ;;
esac

artifact_sha="$(sed -n 's/.*"buildArtifactSha256":"\([0-9a-f]*\)".*/\1/p' "$CONFIG_CAPTURE")"
proof_nonce=nonce-performance-contract-1
frame_source=android.engine.FrameTiming
case "${RESULT_MODE:-valid}" in
  valid) ;;
  stale_tuple) proof_nonce=nonce-stale-proof ;;
  fake_source) frame_source=fake.host.stopwatch ;;
  missing)
    rm -f "$RESULT_FILE"
    exit "${DRIVE_EXIT_CODE:-0}"
    ;;
  *) exit 93 ;;
esac

cat >"$RESULT_FILE" <<JSON
{"schema":"mknoon.sims.android-critical-performance.v1","scenario":"performance.device.critical","status":"passed","platform":"android","physicalTarget":true,"targetId":"pixel-usb","runtimeDispatched":true,"runtime":{"profileId":"android.e2e.standard","scenarioId":"performance.device.critical","role":"primary","runId":"run-performance-contract-1","nonce":"$proof_nonce"},"sharedArtifact":{"profileId":"android.e2e.standard","sha256":"$artifact_sha"},"measurements":{"feedScroll":{"source":"$frame_source","frameCount":180,"averageBuildMs":3.0,"p99BuildMs":9.0,"worstBuildMs":17.0},"goBridge":{"source":"android.MethodChannel.GoBridgeClient","command":"node:status","stateMutation":false,"sampleCount":200,"p50Ms":1.0,"p95Ms":2.0,"p99Ms":3.0}},"assertionsAttempted":4,"budgetAssertions":[{"id":"feed.scroll.average_build","source":"android.engine.FrameTiming","comparison":"lessThan","observedMs":3.0,"budgetMs":8.0,"passed":true},{"id":"feed.scroll.p99_build","source":"android.engine.FrameTiming","comparison":"lessThan","observedMs":9.0,"budgetMs":24.0,"passed":true},{"id":"feed.scroll.worst_build","source":"android.engine.FrameTiming","comparison":"lessThan","observedMs":17.0,"budgetMs":100.0,"passed":true},{"id":"bridge.node_status.p99","source":"android.MethodChannel.GoBridgeClient","comparison":"lessThan","observedMs":3.0,"budgetMs":50.0,"passed":true}]}
JSON
if [ "${MUTATE_ARTIFACT:-false}" = true ]; then
  printf 'mutated-after-staging\n' >>"$EXPECTED_ARTIFACT"
fi
: >"$DRIVE_STATE"
exit "${DRIVE_EXIT_CODE:-0}"
EOF
chmod +x "$shim_dir/flutter"

runner=(
  dart integration_test/scripts/run_1to1_device_real.dart
  --scenario performance.device.critical
)

run_performance() {
  local output="$1"
  shift
  : >"$command_log"
  rm -f "$app_state" "$drive_state"
  rm -f "$config_capture" "$ack_file" "$result_file"
  env \
    PATH="$shim_dir:$real_path" \
    COMMAND_LOG="$command_log" \
    EXPECTED_ARTIFACT="$artifact" \
    CONFIG_CAPTURE="$config_capture" \
    ACK_FILE="$ack_file" \
    RESULT_FILE="$result_file" \
    APP_STATE="$app_state" \
    DRIVE_STATE="$drive_state" \
    SIMS_PROOF_DIRECTORY="$proof_dir" \
    SIMS_RUNTIME_RUN_ID=run-performance-contract-1 \
    SIMS_RUNTIME_NONCE=nonce-performance-contract-1 \
    "$@" \
    "${runner[@]}" >"$output"
}

assert_one_result() {
  local output="$1"
  local count
  count="$(grep -c '^SIMS_RESULT_JSON=' "$output" || true)"
  [ "$count" -eq 1 ] || fail "expected one typed result, found $count"
}

pass_output="$tmp_dir/pass.out"
run_performance "$pass_output" \
  ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact"
assert_one_result "$pass_output"
grep -Fq '"status":"PASS"' "$pass_output" ||
  fail 'successful prebuilt performance drive did not emit PASS'
grep -Fq '"assertionsAttempted":4' "$pass_output" ||
  fail 'typed PASS did not report all four performance budgets'
grep -Fq '"validatorIds":["performance.device.runtime_budget_artifact"]' \
  "$pass_output" || fail 'typed PASS omitted the exact performance validator'
proof_path="$(sed -n 's/.*"artifactEvidence":{"path":"\([^"]*\)".*/\1/p' "$pass_output")"
proof_sha="$(sed -n 's/.*"artifactEvidence":{"path":"[^"]*","sha256":"\([0-9a-f]*\)".*/\1/p' "$pass_output")"
[ -f "$proof_path" ] || fail 'typed PASS pointed to a missing proof artifact'
[ "$(shasum -a 256 "$proof_path" | awk '{print $1}')" = "$proof_sha" ] ||
  fail 'typed PASS reported the wrong durable proof digest'
for field in \
  '"schema":"mknoon.sims.proof.v1"' \
  '"capabilityId":"performance.device.critical"' \
  '"validatorIds":["performance.device.runtime_budget_artifact"]' \
  '"runtimeProof":{"schema":"mknoon.sims.android-critical-performance.v1"'; do
  grep -Fq "$field" "$proof_path" ||
    fail "durable performance proof omitted $field"
done

grep -Fq "adb -s pixel-usb install -r -d -t $artifact" "$command_log" ||
  fail 'runner did not install the supplied prebuilt APK'
grep -Fq 'adb -s pixel-usb uninstall com.mknoon.app' "$command_log" ||
  fail 'runner did not restore the originally absent package state'
grep -Fq 'flutter drive' "$command_log" ||
  fail 'runner did not invoke flutter drive'
grep -Fq -- '--device-id pixel-usb' "$command_log" ||
  fail 'flutter drive was not pinned to the physical Android ID'
grep -Fq -- '--driver test_driver/integration_test.dart' "$command_log" ||
  fail 'flutter drive did not use the integration-test driver'
grep -Fq -- '--target integration_test/sims_dispatcher.dart' "$command_log" ||
  fail 'flutter drive did not target the universal runtime dispatcher'
grep -Fq -- "--use-application-binary=$artifact" "$command_log" ||
  fail 'flutter drive did not reuse the exact supplied APK'
grep -Fq -- '--keep-app-running' "$command_log" ||
  fail 'flutter drive would remove the app before proof collection'
if grep -Eq '(^| )flutter build( |$)' "$command_log"; then
  fail 'performance runner rebuilt instead of consuming the prepared artifact'
fi
if grep -Fq 'RECORD_AUDIO' "$command_log"; then
  fail 'performance proof incorrectly inherited recorder permission mutation'
fi
grep -Fq 'run-as com.mknoon.app cat files/sims/runtime-ack.json' "$command_log" ||
  fail 'runner did not read the exact runtime acknowledgement'
grep -Fq 'run-as com.mknoon.app cat files/sims/runtime-result.json' "$command_log" ||
  fail 'runner did not read the app performance artifact'
grep -Fq 'adb -s pixel-usb shell am force-stop com.mknoon.app' "$command_log" ||
  fail 'runner did not stop the retained dispatcher during cleanup'

[ -s "$config_capture" ] || fail 'adb shim did not capture the staged config'
for field in \
  '"schema":"mknoon.sims.runtime-config.v1"' \
  '"profileId":"android.e2e.standard"' \
  '"scenarioId":"performance.device.critical"' \
  '"role":"primary"' \
  '"runId":"run-performance-contract-1"' \
  '"nonce":"nonce-performance-contract-1"' \
  '"targetId":"pixel-usb"' \
  '"targetKind":"physical"' \
  "\"buildArtifactSha256\":\"$artifact_sha\""; do
  grep -Fq "$field" "$config_capture" ||
    fail "staged performance config omitted $field"
done

stage_line="$(grep -n 'run-as com.mknoon.app cp /data/local/tmp/mknoon-sims-runtime-nonce-performance-contract-1.json files/sims/runtime-config.json' "$command_log" | cut -d: -f1)"
drive_line="$(grep -n '^flutter drive' "$command_log" | cut -d: -f1)"
ack_line="$(grep -n 'run-as com.mknoon.app cat files/sims/runtime-ack.json' "$command_log" | cut -d: -f1)"
proof_line="$(grep -n 'run-as com.mknoon.app cat files/sims/runtime-result.json' "$command_log" | cut -d: -f1)"
cleanup_line="$(awk -v proof="$proof_line" '
  NR > proof && /adb -s pixel-usb shell am force-stop com.mknoon.app/ {
    print NR
    exit
  }
' "$command_log")"
[ "$stage_line" -lt "$drive_line" ] &&
  [ "$drive_line" -lt "$ack_line" ] &&
  [ "$ack_line" -lt "$proof_line" ] &&
  [ "$proof_line" -lt "$cleanup_line" ] ||
  fail 'stage/drive/ack/proof/cleanup order is not fail-safe'

# A stale or rejected acknowledgement fails closed before trusting a result.
for ack_mode in stale rejected missing; do
  output="$tmp_dir/ack-$ack_mode.out"
  set +e
  run_performance "$output" \
    ANDROID_SERIAL=pixel-usb \
    SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
    ACK_MODE="$ack_mode"
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "$ack_mode acknowledgement produced a false zero exit"
  assert_one_result "$output"
  grep -Fq '"status":"FAIL"' "$output" ||
    fail "$ack_mode acknowledgement did not fail closed"
  grep -Fq '"blocker":"harness"' "$output" ||
    fail "$ack_mode acknowledgement was not a harness failure"
  grep -Fq 'adb -s pixel-usb shell am force-stop com.mknoon.app' "$command_log" ||
    fail "$ack_mode acknowledgement skipped cleanup"
done

# A semantically invalid proof and a valid-but-stale tuple both fail closed.
for result_mode in fake_source stale_tuple missing; do
  output="$tmp_dir/result-$result_mode.out"
  set +e
  run_performance "$output" \
    ANDROID_SERIAL=pixel-usb \
    SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
    RESULT_MODE="$result_mode"
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "$result_mode proof produced a false zero exit"
  assert_one_result "$output"
  grep -Fq '"status":"FAIL"' "$output" ||
    fail "$result_mode proof did not emit FAIL"
  grep -Fq '"blocker":"harness"' "$output" ||
    fail "$result_mode proof was not classified as a harness failure"
  if grep -Fq '"artifactEvidence"' "$output"; then
    fail "$result_mode proof exposed durable evidence on failure"
  fi
done
grep -Fq 'does not match the acknowledged target' "$tmp_dir/result-stale_tuple.out" ||
  fail 'host did not bind the app proof to the acknowledged runtime tuple'

# An acknowledged device-test failure remains FAIL/test and still cleans up.
drive_fail_output="$tmp_dir/drive-fail.out"
set +e
run_performance "$drive_fail_output" \
  ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
  DRIVE_EXIT_CODE=7
drive_fail_status=$?
set -e
[ "$drive_fail_status" -eq 7 ] ||
  fail "failing performance drive exited $drive_fail_status instead of 7"
assert_one_result "$drive_fail_output"
grep -Fq '"status":"FAIL"' "$drive_fail_output" ||
  fail 'failing performance drive did not emit FAIL'
grep -Fq '"blocker":"test"' "$drive_fail_output" ||
  fail 'failing performance drive was not classified as a test failure'
grep -Fq '"assertionsAttempted":4' "$drive_fail_output" ||
  fail 'failing performance drive lost the budget assertion count'
grep -Fq 'adb -s pixel-usb shell am force-stop com.mknoon.app' "$command_log" ||
  fail 'failing performance drive skipped cleanup'

# Cleanup failure overrides an otherwise valid proof and removes its durable
# artifact so a failed run cannot be discovered later as release evidence.
proof_count_before="$(find "$proof_dir" -type f | wc -l | tr -d ' ')"
cleanup_fail_output="$tmp_dir/cleanup-fail.out"
set +e
run_performance "$cleanup_fail_output" \
  ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
  CLEANUP_FAIL=true
cleanup_fail_status=$?
set -e
[ "$cleanup_fail_status" -ne 0 ] || fail 'runtime cleanup failure exited zero'
assert_one_result "$cleanup_fail_output"
grep -Fq '"status":"FAIL"' "$cleanup_fail_output" ||
  fail 'runtime cleanup failure did not override PASS'
grep -Fq '"blocker":"harness"' "$cleanup_fail_output" ||
  fail 'runtime cleanup failure was not classified as a harness failure'
if grep -Fq '"artifactEvidence"' "$cleanup_fail_output"; then
  fail 'runtime cleanup failure exposed passing durable evidence'
fi
proof_count_after="$(find "$proof_dir" -type f | wc -l | tr -d ' ')"
[ "$proof_count_after" -eq "$proof_count_before" ] ||
  fail 'runtime cleanup failure left behind a passing proof artifact'

# The prepared file must remain byte-for-byte stable through collection; a
# stale digest cannot be promoted merely because the app echoed it back.
artifact_mutation_output="$tmp_dir/artifact-mutation.out"
set +e
run_performance "$artifact_mutation_output" \
  ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
  MUTATE_ARTIFACT=true
artifact_mutation_status=$?
set -e
[ "$artifact_mutation_status" -ne 0 ] ||
  fail 'mutated prepared APK produced a false zero exit'
assert_one_result "$artifact_mutation_output"
grep -Fq '"status":"FAIL"' "$artifact_mutation_output" ||
  fail 'mutated prepared APK did not fail closed'
grep -Fq 'prepared APK changed after its runtime invocation' \
  "$artifact_mutation_output" || fail 'prepared APK stability check was skipped'
printf 'prebuilt-performance-apk-fixture\n' >"$artifact"

# Missing prepared artifacts and virtual targets are typed BLOCKED, never PASS.
for fixture in missing-artifact emulator-target; do
  output="$tmp_dir/$fixture.out"
  set +e
  if [ "$fixture" = missing-artifact ]; then
    run_performance "$output" ANDROID_SERIAL=pixel-usb
  else
    run_performance "$output" \
      ANDROID_SERIAL=emulator-5554 \
      SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact"
  fi
  status=$?
  set -e
  [ "$status" -eq 78 ] || fail "$fixture exited $status instead of BLOCKED (78)"
  assert_one_result "$output"
  grep -Fq '"status":"BLOCKED"' "$output" ||
    fail "$fixture did not emit BLOCKED"
  if grep -Eq '"status":"(PASS|N/A)"' "$output"; then
    fail "$fixture emitted a false PASS/N/A"
  fi
done

list_output="$tmp_dir/list.out"
dart integration_test/scripts/run_1to1_device_real.dart --list-scenarios >"$list_output"
grep -Fxq 'performance.device.critical' "$list_output" ||
  fail '1:1 catalog omitted performance.device.critical'

printf 'PASS: performance prebuilt Android runner contract\n'
