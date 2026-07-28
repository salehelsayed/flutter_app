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

runner=(dart integration_test/scripts/run_notification_tap_device_real.dart)
list_output="$tmp_dir/android.list"
"${runner[@]}" --scenario android_payload_campaign --list-scenarios \
  >"$list_output"

expected="$tmp_dir/expected.list"
printf '%s\n' \
  tc_a6_replay_before_ack_custody \
  tc_b11_payload_persist_pre_drain \
  payload_fast_path_android_receiver \
  payload_fast_path_cold_kill >"$expected"
cmp -s "$expected" "$list_output" ||
  fail 'android payload campaign does not expand to the four exact Android phases'
grep -Fq payload_fast_path_ios_receiver "$list_output" &&
  fail 'Android payload campaign incorrectly included the iOS APNs/NSE phase'

blocked_output="$tmp_dir/blocked.out"
printf 'inherited-prebuilt-apk\n' >"$tmp_dir/inherited-app.apk"
export SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$tmp_dir/inherited-app.apk"
set +e
env -u SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM \
  "${runner[@]}" --scenario android_payload_campaign >"$blocked_output"
status=$?
set -e
[ "$status" -eq 78 ] || fail "missing prebuilt artifact exited $status, expected 78"
[ "$(grep -c '^SIMS_RESULT_JSON=' "$blocked_output" || true)" -eq 1 ] ||
  fail 'campaign did not emit exactly one structured result'
grep -Fq '"status":"BLOCKED"' "$blocked_output" ||
  fail 'missing prebuilt artifact was not BLOCKED'
grep -Fq '"blocker":"missingArtifact"' "$blocked_output" ||
  fail 'campaign did not identify the missing central build artifact'
if grep -Eq '"status":"(PASS|N/A)"' "$blocked_output"; then
  fail 'missing prebuilt artifact produced false PASS/N/A'
fi

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
command_log="$tmp_dir/commands.log"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "adb %s\\n" "$*" >>"${SIMS_NOTIFICATION_COMMAND_LOG:?}"' \
  'if [ "$*" = "version" ]; then' \
  '  printf "Android Debug Bridge version 1.0.41\\n"' \
  'elif [ "$*" = "-s physical-1 get-state" ] || [ "$*" = "-s emulator-5554 get-state" ]; then' \
  '  printf "device\\n"' \
  'elif [ "$*" = "-s physical-1 shell getprop ro.kernel.qemu" ]; then' \
  '  printf "0\\n"' \
  'elif [ "$*" = "-s emulator-5554 shell getprop ro.kernel.qemu" ]; then' \
  '  printf "1\\n"' \
  'elif [[ "$*" == *"shell dumpsys connectivity" ]]; then' \
  '  printf "Active default network: 100\\n"' \
  'elif [ "$*" = "-s emulator-5554 shell cmd connectivity airplane-mode" ]; then' \
  '  printf "disabled\\n"' \
  'elif [ "$*" = "-s emulator-5554 shell settings get global wifi_on" ]; then' \
  '  printf "1\\n"' \
  'elif [ "$*" = "-s emulator-5554 shell settings get global mobile_data" ]; then' \
  '  printf "1\\n"' \
  'elif [[ "$*" == *"shell pm list packages -3" ]]; then' \
  '  exit 0' \
  'elif [ "$*" = "-s emulator-5554 shell dumpsys notification --noredact" ]; then' \
  '  printf "Ranking Config:\\n"' \
  'elif [[ "$*" == *"shell dumpsys activity activities" ]]; then' \
  '  printf "Activities:\\n"' \
  'elif [[ "$*" == *"shell am force-stop com.mknoon.app" ]]; then' \
  '  exit 0' \
  'else' \
  '  exit 23' \
  'fi' >"$fake_bin/adb"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "ssh %s\\n" "$*" >>"${SIMS_NOTIFICATION_COMMAND_LOG:?}"' \
  'printf "active\\n"' >"$fake_bin/ssh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[ "${1:-}" = manifest ]' \
  '[ "${2:-}" = application-id ]' \
  '[ -f "${3:-}" ]' \
  'printf "com.mknoon.app\\n"' >"$fake_bin/apkanalyzer"
chmod +x "$fake_bin/adb" "$fake_bin/ssh" "$fake_bin/apkanalyzer"
printf 'central-prebuilt-apk\n' >"$tmp_dir/app-debug.apk"
printf 'fixture-key\n' >"$tmp_dir/relay-key.pem"
printf '{"project_id":"fixture-project"}\n' >"$tmp_dir/fcm.json"

driver_output="$tmp_dir/driver.out"
set +e
PATH="$fake_bin:$PATH" \
  SIMS_NOTIFICATION_COMMAND_LOG="$command_log" \
  SIMS_ARTIFACT_PROFILE_ID=android.production_fcm \
  SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$tmp_dir/app-debug.apk" \
  SIMS_ANDROID_PHYSICAL_DEVICE_ID=physical-1 \
  SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
  SIMS_NOTIFICATION_RELAY_TARGET=relay.example \
  SIMS_NOTIFICATION_RELAY_KEY="$tmp_dir/relay-key.pem" \
  SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$tmp_dir/fcm.json" \
  MKNOON_RELAY_ADDRESSES=/dns4/relay.example/tcp/443/wss/p2p/relay \
  SIMS_PROOF_DIRECTORY="$tmp_dir/proofs" \
  "${runner[@]}" --scenario android_payload_campaign >"$driver_output"
driver_status=$?
set -e
[ "$driver_status" -eq 1 ] ||
  fail "bounded guarded install exited $driver_status, expected 1"
[ "$(grep -c '^SIMS_RESULT_JSON=' "$driver_output" || true)" -eq 1 ] ||
  fail 'bounded driver preflight emitted the wrong sentinel count'
grep -Fq '"status":"FAIL"' "$driver_output" ||
  fail 'post-capture install failure was not typed FAIL'
grep -Fq 'central APK could not be installed in place' \
  "$driver_output" ||
  fail 'driver did not fail at the guarded install boundary'
grep -Fq 'adb version' "$command_log" ||
  fail 'preflight did not resolve live Android targets'
grep -Fq 'ssh ' "$command_log" ||
  fail 'preflight did not verify the real relay endpoint'
if grep -Eq 'flutter (build|test|drive)|gradle|xcodebuild' "$command_log"; then
  fail 'notification campaign attempted a forbidden child build'
fi

adapter=integration_test/scripts/notification_android_payload_campaign.dart
protocol=lib/core/debug/android_notification_payload_e2e_protocol.dart
app_action=lib/core/debug/android_notification_payload_e2e.dart
app_runner=lib/core/debug/intro_e2e_runner.dart
app_main=lib/main.dart
app_composition=lib/debug/debug_e2e_composition_root.dart
python3 - "$adapter" <<'PY'
import re
import sys

source = open(sys.argv[1], encoding='utf-8').read()
start = source.index('Future<void> _launch(String device)')
end = source.index('Future<_Identity> _identity', start)
launch = source[start:end]
assert "'am'" in launch and "'start'" in launch and "'-W'" in launch
assert "'-n'" in launch and "'$packageName/.MainActivity'" in launch
assert 'result.exitCode != 0' in launch
assert r"r'^Status:[ \t]+ok[ \t]*\r?$'" in launch
assert 'monkey' not in launch

start = source.index('Future<void> _terminateReceiver()')
end = source.index('Future<bool> _receiverProcessAbsentWithin', start)
termination = source[start:end]
home = termination.index("'KEYCODE_HOME'")
settle = termination.index('Duration(milliseconds: 750)', home)
kill = termination.index("'kill'", settle)
bounded = termination.index(
    '_receiverProcessAbsentWithin(const Duration(seconds: 5))', kill
)
stop_app = termination.index("'stop-app'", bounded)
final_wait = termination.index("'receiver process termination'", stop_app)
empty_pid = termination.index('(await _pidof(emulator)).isEmpty', final_wait)
assert home < settle < kill < bounded < stop_app < final_wait < empty_pid
assert re.search(
    r"\[\s*'shell',\s*'cmd',\s*'activity',\s*'stop-app',\s*packageName,?\s*\]",
    termination,
)
assert "'force-stop'" not in termination

helper_end = source.index('Future<String> _pidof', end)
probe = source[end:helper_end]
assert 'DateTime.now().add(timeout)' in probe
assert '(await _pidof(emulator)).isEmpty' in probe
assert 'Duration(milliseconds: 500)' in probe
assert 'return false' in probe

start = source.index('Future<Map<String, Object?>> _waitForActionResult(')
end = source.index('Future<AndroidStagedEnvelopeObservation>', start)
waiter = source[start:end]
binding = waiter.index(
    'AndroidNotificationActionResultDisposition.bindingMismatch'
)
bound_failure = waiter.index(
    'AndroidNotificationActionResultDisposition.boundFailure', binding
)
invalid = waiter.index(
    'AndroidNotificationActionResultDisposition.invalidCompletion',
    bound_failure,
)
accepted = waiter.index(
    'AndroidNotificationActionResultDisposition.accepted', invalid
)
assert binding < bound_failure < invalid < accepted
assert 'returned a bound failure receipt (errorType=$errorType)' in waiter
assert 'safeAndroidNotificationActionErrorType' in waiter
assert "${result['errorType']}" not in waiter
PY
for required in \
  notification_a6_replay_observe \
  notification_stop_node_and_clear_staging \
  notification_post_tap_observe \
  notification_drain_observe \
  'airplane-mode' \
  'am' \
  'kill' \
  'stop-app' \
  'PushEnvelopeStaging' \
  'childBuildCount'; do
  grep -Fq "$required" "$adapter" "$protocol" ||
    fail "Android notification adapter is missing $required"
done
for required in \
  AndroidAppStateGuard.capture \
  prepareFreshInstall \
  restoreAll \
  appStateRestored \
  notificationStateRestored; do
  grep -Fq "$required" "$adapter" ||
    fail "Android notification adapter is missing state contract $required"
done
grep -Fq 'pm clear' "$adapter" &&
  fail 'Android notification campaign destroys Keystore state with pm clear'
grep -Fq "['logcat', '-c']" "$adapter" &&
  fail 'Android notification campaign destructively clears shared device logs'
grep -Fq '_deviceLogcatCursor' "$adapter" ||
  fail 'Android notification campaign lacks a non-destructive log window'
grep -Fq 'runAndroidNotificationPayloadE2EAction' "$app_runner" ||
  fail 'installed app poller does not dispatch notification actions'
grep -Fq 'startIntroPollerAfterColdRecovery(' "$app_main" ||
  fail 'production main does not preserve the post-recovery poller handoff'
grep -Fq 'pushEnvelopeStagingStore: pushEnvelopeStagingStore' "$app_runner" ||
  fail 'intro poller does not forward the production staging store'
grep -Fq 'pushEnvelopeStagingStore: dependencies.pushEnvelopeStagingStore' \
  "$app_composition" ||
  fail 'production staging store is not wired through the composition root into the poller'
grep -Fq 'androidNotificationPayloadE2EFailureReceipt' "$app_action" "$app_runner" ||
  fail 'notification action failures are not emitted as bounded receipts'
if grep -Eq "Process\.(run|start)\([^\n]*(flutter|gradle|xcodebuild)" "$adapter"; then
  fail 'Android notification adapter contains a child-build process call'
fi

ios_output="$tmp_dir/ios.list"
"${runner[@]}" --scenario payload_fast_path_ios_receiver --list-scenarios \
  >"$ios_output"
[ "$(cat "$ios_output")" = payload_fast_path_ios_receiver ] ||
  fail 'the iOS-specific APNs/NSE phase is not independently selectable'

printf 'PASS: notification tap Android campaign adapter contract\n'
