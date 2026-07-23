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
printf 'prebuilt-apk-fixture\n' >"$artifact"

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
    [ "$serial" = pixel-usb ] || exit 1
    case "${1:-}" in
      get-state)
        printf 'device\n'
        ;;
      install)
        [ "${2:-}" = -r ] || exit 1
        [ "${3:-}" = -d ] || exit 1
        [ "${4:-}" = -t ] || exit 1
        [ "${5:-}" = "$EXPECTED_ARTIFACT" ] || exit 1
        : >"$APP_STATE"
        printf 'Success\n'
        ;;
      uninstall)
        if [ "${RESTORE_FAIL:-false}" = true ]; then exit 9; fi
        rm -f "$APP_STATE"
        printf 'Success\n'
        ;;
      push)
        [ -f "${2:-}" ] || exit 1
        cp "${2:-}" "$CONFIG_CAPTURE"
        ;;
      shell)
        shift
        case "$*" in
          'getprop ro.kernel.qemu')
            printf '0\n'
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
          'dumpsys package com.mknoon.app')
            if [ "${INITIAL_PERMISSION_GRANTED:-false}" = true ]; then
              printf '    android.permission.RECORD_AUDIO: granted=true, flags=[ USER_SET ]\n'
            else
              printf '    android.permission.RECORD_AUDIO: granted=false, flags=[ USER_SET ]\n'
            fi
            ;;
          'pm grant com.mknoon.app android.permission.RECORD_AUDIO'|\
          'pm revoke com.mknoon.app android.permission.RECORD_AUDIO')
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
    printf '%s\n' '{"schema":"mknoon.sims.runtime-ack.v1","profileId":"android.e2e.standard","scenarioId":"android.voice_recorder_native_smoke","role":"primary","runId":"run-contract-1","nonce":"nonce-contract-1","accepted":true,"detail":"runtime invocation accepted"}' >"$ACK_FILE"
    printf '%s\n' '{"scenario":"android.voice_recorder_native_smoke","status":"passed","permissionPregranted":true,"realRecordPlugin":true,"mime":"audio/mp4","sizeBytes":4096,"durationMs":2050,"decodable":true,"temporaryFileDeleted":true}' >"$RESULT_FILE"
    ;;
  stale)
    printf '%s\n' '{"schema":"mknoon.sims.runtime-ack.v1","profileId":"android.e2e.standard","scenarioId":"android.voice_recorder_native_smoke","role":"primary","runId":"run-contract-1","nonce":"nonce-stale","accepted":true,"detail":"runtime invocation accepted"}' >"$ACK_FILE"
    ;;
  rejected)
    printf '%s\n' '{"schema":"mknoon.sims.runtime-ack.v1","profileId":"android.e2e.standard","scenarioId":"android.voice_recorder_native_smoke","role":"primary","runId":"run-contract-1","nonce":"nonce-contract-1","accepted":false,"detail":"fixture rejected invocation"}' >"$ACK_FILE"
    ;;
  missing)
    rm -f "$ACK_FILE"
    ;;
  *)
    exit 92
    ;;
esac
exit "${DRIVE_EXIT_CODE:-0}"
EOF
chmod +x "$shim_dir/flutter"

runner=(
  dart integration_test/scripts/run_1to1_device_real.dart
  --scenario android.voice_recorder_native_smoke
)

run_voice() {
  local output="$1"
  shift
  : >"$command_log"
  rm -f "$app_state"
  rm -f "$config_capture" "$ack_file" "$result_file"
  env \
    PATH="$shim_dir:$real_path" \
    COMMAND_LOG="$command_log" \
    EXPECTED_ARTIFACT="$artifact" \
    CONFIG_CAPTURE="$config_capture" \
    ACK_FILE="$ack_file" \
    RESULT_FILE="$result_file" \
    APP_STATE="$app_state" \
    SIMS_PROOF_DIRECTORY="$proof_dir" \
    SIMS_RUNTIME_RUN_ID=run-contract-1 \
    SIMS_RUNTIME_NONCE=nonce-contract-1 \
    "$@" \
    "${runner[@]}"
}

assert_one_result() {
  local output="$1"
  local count
  count="$(grep -c '^SIMS_RESULT_JSON=' "$output" || true)"
  [ "$count" -eq 1 ] || fail "expected one typed result, found $count"
}

pass_output="$tmp_dir/pass.out"
run_voice "$pass_output" \
  ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
  >"$pass_output"
assert_one_result "$pass_output"
grep -Fq '"status":"PASS"' "$pass_output" ||
  fail 'successful prebuilt drive did not emit PASS'
grep -Fq '"assertionsAttempted":' "$pass_output" ||
  fail 'typed PASS omitted assertion count'
grep -Fq '"artifactEvidence":' "$pass_output" ||
  fail 'typed PASS omitted durable artifact evidence'
grep -Fq '"validatorIds":["validateVoiceRecorderArtifact"]' "$pass_output" ||
  fail 'typed PASS omitted the exact voice recorder validator ID'
proof_path="$(sed -n 's/.*"artifactEvidence":{"path":"\([^"]*\)".*/\1/p' "$pass_output")"
[ -f "$proof_path" ] || fail 'typed PASS pointed to a missing proof artifact'

grep -Fq "adb -s pixel-usb install -r -d -t $artifact" "$command_log" ||
  fail 'runner did not install the supplied prebuilt APK'
grep -Fq 'adb -s pixel-usb shell pm grant com.mknoon.app android.permission.RECORD_AUDIO' \
  "$command_log" || fail 'runner did not pregrant RECORD_AUDIO'
grep -Fq 'adb -s pixel-usb uninstall com.mknoon.app' "$command_log" ||
  fail 'runner did not remove an originally absent test install'
grep -Fq 'flutter drive' "$command_log" || fail 'runner did not invoke flutter drive'
grep -Fq -- '--device-id pixel-usb' "$command_log" ||
  fail 'flutter drive was not pinned to the physical Android ID'
grep -Fq -- '--driver test_driver/integration_test.dart' "$command_log" ||
  fail 'flutter drive did not use the integration-test driver'
grep -Fq -- '--target integration_test/sims_dispatcher.dart' "$command_log" ||
  fail 'flutter drive did not target the universal runtime dispatcher'
grep -Fq -- "--use-application-binary=$artifact" "$command_log" ||
  fail 'flutter drive did not reuse the exact supplied APK'
grep -Fq -- '--keep-app-running' "$command_log" ||
  fail 'flutter drive would uninstall the shared APK before ack collection'
if grep -Eq '(^| )flutter build( |$)' "$command_log"; then
  fail 'voice runner rebuilt instead of consuming the prepared artifact'
fi
grep -Fq 'adb -s pixel-usb push' "$command_log" ||
  fail 'runner did not stage a runtime config over adb'
grep -Fq 'run-as com.mknoon.app cp /data/local/tmp/mknoon-sims-runtime-nonce-contract-1.json files/sims/runtime-config.json' \
  "$command_log" || fail 'runtime config was not copied into private app data'
grep -Fq 'run-as com.mknoon.app cat files/sims/runtime-ack.json' "$command_log" ||
  fail 'runner did not read the app acknowledgement'
grep -Fq 'run-as com.mknoon.app cat files/sims/runtime-result.json' "$command_log" ||
  fail 'runner did not read and validate the app proof artifact'
grep -Fq 'adb -s pixel-usb shell am force-stop com.mknoon.app' "$command_log" ||
  fail 'runner did not stop the retained dispatcher process during cleanup'
[ -s "$config_capture" ] || fail 'adb shim did not capture the staged config'
for field in \
  '"schema":"mknoon.sims.runtime-config.v1"' \
  '"profileId":"android.e2e.standard"' \
  '"scenarioId":"android.voice_recorder_native_smoke"' \
  '"role":"primary"' \
  '"runId":"run-contract-1"' \
  '"nonce":"nonce-contract-1"' \
  '"permissionPregranted":true'; do
  grep -Fq "$field" "$config_capture" ||
    fail "staged runtime config omitted $field"
done
grep -Fq "'android.e2e.standard' => 'integration_test/sims_dispatcher.dart'" \
  tool/sims/build_orchestrator.dart ||
  fail 'central Android E2E build does not target the universal dispatcher'
grep -Fq "defines['SIMS_BUILD_PROFILE_ID'] = profile.id" \
  tool/sims/build_orchestrator.dart ||
  fail 'central Android E2E build does not embed its profile handshake'

snapshot_line="$(grep -n 'adb -s pixel-usb shell pm path com.mknoon.app' "$command_log" | head -1 | cut -d: -f1)"
install_line="$(grep -n 'adb -s pixel-usb install -r -d -t' "$command_log" | cut -d: -f1)"
grant_line="$(grep -n 'adb -s pixel-usb shell pm grant' "$command_log" | head -1 | cut -d: -f1)"
stage_line="$(grep -n 'run-as com.mknoon.app cp /data/local/tmp/mknoon-sims-runtime-nonce-contract-1.json files/sims/runtime-config.json' "$command_log" | cut -d: -f1)"
drive_line="$(grep -n '^flutter drive' "$command_log" | cut -d: -f1)"
ack_line="$(grep -n 'run-as com.mknoon.app cat files/sims/runtime-ack.json' "$command_log" | cut -d: -f1)"
restore_line="$(grep -n 'adb -s pixel-usb uninstall com.mknoon.app' "$command_log" | cut -d: -f1)"
[ "$snapshot_line" -lt "$install_line" ] &&
  [ "$install_line" -lt "$grant_line" ] &&
  [ "$grant_line" -lt "$stage_line" ] &&
  [ "$stage_line" -lt "$drive_line" ] &&
  [ "$drive_line" -lt "$ack_line" ] &&
  [ "$ack_line" -lt "$restore_line" ] ||
  fail 'snapshot/install/pregrant/drive/ack/restore order is not fail-safe'

# A stale or rejected acknowledgement fails closed even when flutter exits zero.
for ack_mode in stale rejected missing; do
  ack_fail_output="$tmp_dir/ack-$ack_mode.out"
  set +e
  run_voice "$ack_fail_output" \
    ANDROID_SERIAL=pixel-usb \
    SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
    ACK_MODE="$ack_mode" \
    >"$ack_fail_output"
  ack_fail_status=$?
  set -e
  [ "$ack_fail_status" -ne 0 ] ||
    fail "$ack_mode acknowledgement produced a false zero exit"
  assert_one_result "$ack_fail_output"
  grep -Fq '"status":"FAIL"' "$ack_fail_output" ||
    fail "$ack_mode acknowledgement did not fail closed"
  grep -Fq '"blocker":"harness"' "$ack_fail_output" ||
    fail "$ack_mode acknowledgement was not classified as a harness failure"
done

# A failed test still restores the originally absent package and produces FAIL.
drive_fail_output="$tmp_dir/drive-fail.out"
set +e
run_voice "$drive_fail_output" \
  ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
  DRIVE_EXIT_CODE=7 \
  >"$drive_fail_output"
drive_fail_status=$?
set -e
[ "$drive_fail_status" -ne 0 ] || fail 'failing flutter drive exited zero'
assert_one_result "$drive_fail_output"
grep -Fq '"status":"FAIL"' "$drive_fail_output" ||
  fail 'failing drive did not emit FAIL'
grep -Fq 'adb -s pixel-usb uninstall com.mknoon.app' "$command_log" ||
  fail 'originally absent package was not restored after drive failure'

# Restoration failure overrides a passing drive, so cleanup can never be green.
restore_fail_output="$tmp_dir/restore-fail.out"
set +e
run_voice "$restore_fail_output" \
  ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
  RESTORE_FAIL=true \
  >"$restore_fail_output"
restore_fail_status=$?
set -e
[ "$restore_fail_status" -ne 0 ] || fail 'package restore failure exited zero'
assert_one_result "$restore_fail_output"
grep -Fq '"status":"FAIL"' "$restore_fail_output" ||
  fail 'package restore failure did not override PASS'
grep -Fq 'initially absent package could not be removed' "$restore_fail_output" ||
  fail 'package restore failure detail was lost'

# The recorder permission is granted exactly for the isolated test install.
granted_output="$tmp_dir/granted.out"
run_voice "$granted_output" \
  ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
  INITIAL_PERMISSION_GRANTED=true \
  >"$granted_output"
assert_one_result "$granted_output"
grant_count="$(grep -c 'adb -s pixel-usb shell pm grant com.mknoon.app android.permission.RECORD_AUDIO' "$command_log")"
[ "$grant_count" -eq 1 ] ||
  fail 'isolated recorder permission was not granted exactly once'

# Explicit CLI inputs work without the environment fallbacks.
cli_output="$tmp_dir/cli.out"
: >"$command_log"
rm -f "$app_state"
env \
  PATH="$shim_dir:$real_path" \
  COMMAND_LOG="$command_log" \
  EXPECTED_ARTIFACT="$artifact" \
  CONFIG_CAPTURE="$config_capture" \
  ACK_FILE="$ack_file" \
  RESULT_FILE="$result_file" \
  APP_STATE="$app_state" \
  SIMS_PROOF_DIRECTORY="$proof_dir" \
  SIMS_RUNTIME_RUN_ID=run-contract-1 \
  SIMS_RUNTIME_NONCE=nonce-contract-1 \
  "${runner[@]}" --device pixel-usb --artifact "$artifact" >"$cli_output"
assert_one_result "$cli_output"
grep -Fq '"status":"PASS"' "$cli_output" ||
  fail 'explicit --device/--artifact path did not pass'

# Every manifest-owned ID is recognized. Capabilities without a driver remain
# typed BLOCKED (never argument-error 64) and do no device work.
manifest_ids=(
  android.connectivity_restore_inbox_drain
  android.keepalive_drop_skip_direct
  android.wake_token_directionality
  android.voice_recorder_native_smoke
  android.voice_message_e2e
  performance.device.critical
  vc02.dcutr_upgrade
  vc02.dcutr_symmetric_cgnat_negative
)
list_output="$tmp_dir/list.out"
dart integration_test/scripts/run_1to1_device_real.dart --list-scenarios \
  >"$list_output"
for id in "${manifest_ids[@]}"; do
  grep -Fxq "$id" "$list_output" || fail "catalog omitted manifest ID $id"
done

unimplemented_ids=(
  fdc11_lan_direct_d1
  android.connectivity_restore_inbox_drain
  vc02.dcutr_upgrade
  vc02.dcutr_symmetric_cgnat_negative
)
for id in "${unimplemented_ids[@]}"; do
  blocked_output="$tmp_dir/unimplemented-${id//[^A-Za-z0-9]/_}.out"
  : >"$command_log"
  set +e
  env PATH="$shim_dir:$real_path" COMMAND_LOG="$command_log" \
    dart integration_test/scripts/run_1to1_device_real.dart \
    --scenario "$id" >"$blocked_output"
  blocked_status=$?
  set -e
  [ "$blocked_status" -eq 78 ] ||
    fail "$id exited $blocked_status instead of typed BLOCKED (78)"
  assert_one_result "$blocked_output"
  grep -Fq '"status":"BLOCKED"' "$blocked_output" ||
    fail "$id did not emit BLOCKED"
  grep -Fq '"blocker":"missingDriver"' "$blocked_output" ||
    fail "$id did not name its missing driver"
  [ ! -s "$command_log" ] || fail "$id touched a device"
done

# Missing artifact and nonphysical target are BLOCKED, never N/A/PASS.
for fixture in missing-artifact emulator-target; do
  fixture_output="$tmp_dir/$fixture.out"
  : >"$command_log"
  set +e
  if [ "$fixture" = missing-artifact ]; then
    env PATH="$shim_dir:$real_path" COMMAND_LOG="$command_log" \
      EXPECTED_ARTIFACT="$artifact" ANDROID_SERIAL=pixel-usb \
      "${runner[@]}" >"$fixture_output"
  else
    env PATH="$shim_dir:$real_path" COMMAND_LOG="$command_log" \
      EXPECTED_ARTIFACT="$artifact" ANDROID_SERIAL=emulator-5554 \
      SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
      "${runner[@]}" >"$fixture_output"
  fi
  fixture_status=$?
  set -e
  [ "$fixture_status" -eq 78 ] ||
    fail "$fixture exited $fixture_status instead of BLOCKED (78)"
  assert_one_result "$fixture_output"
  grep -Fq '"status":"BLOCKED"' "$fixture_output" ||
    fail "$fixture did not emit BLOCKED"
  if grep -Eq '"status":"(PASS|N/A)"' "$fixture_output"; then
    fail "$fixture emitted a false PASS/N/A"
  fi
done

# A PATH without adb is a typed missing-driver blocker, not N/A or PASS.
missing_adb_output="$tmp_dir/missing-adb.out"
empty_path="$tmp_dir/no-adb"
mkdir -p "$empty_path"
dart_bin="$(command -v dart || true)"
[ -n "$dart_bin" ] && [ -x "$dart_bin" ] ||
  fail 'unable to locate the Dart binary fixture'
set +e
env PATH="$empty_path:/usr/bin:/bin" ANDROID_SERIAL=pixel-usb \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$artifact" \
  "$dart_bin" integration_test/scripts/run_1to1_device_real.dart \
  --scenario android.voice_recorder_native_smoke >"$missing_adb_output"
missing_adb_status=$?
set -e
[ "$missing_adb_status" -eq 78 ] ||
  fail "missing adb exited $missing_adb_status instead of BLOCKED (78)"
assert_one_result "$missing_adb_output"
grep -Fq '"status":"BLOCKED"' "$missing_adb_output" ||
  fail 'missing adb did not emit BLOCKED'
grep -Fq '"blocker":"missingDriver"' "$missing_adb_output" ||
  fail 'missing adb did not identify the driver blocker'
if grep -Eq '"status":"(PASS|N/A)"' "$missing_adb_output"; then
  fail 'missing adb emitted a false PASS/N/A'
fi

printf 'PASS: voice recorder prebuilt Android runner contract\n'
