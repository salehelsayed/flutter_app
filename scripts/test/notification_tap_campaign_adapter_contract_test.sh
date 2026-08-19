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
  payload_fast_path_cold_kill \
  tc_b13_dual_path_single_alert \
  tc_g7_permission_denied \
  tc_g7_token_refresh_mid_session \
  tc_g7_channel_disabled \
  tc_g7_doze_delivery >"$expected"
cmp -s "$expected" "$list_output" ||
  fail 'android payload campaign does not expand to the nine exact Android phases'
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
  'elif [[ "$*" == *"logcat -T 1 -v brief" ]]; then' \
  '  printf "I/flutter( 1): campaign log stream started\\n"' \
  '  exec sleep 120' \
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
app_bootstrap=lib/app/bootstrap/production_application_bootstrap.dart
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
  notification_delete_push_token \
  'force-idle' \
  'deviceidle' \
  'set-permission-flags' \
  'CHANNEL_NOTIFICATION_SETTINGS' \
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
# The window must come from a LIVE reader started before the legs. A post-hoc
# `logcat -d -t <cursor>` read is unsound here: the emulator's main ring is
# 2 MiB and a busy campaign minute emits ~1.6 MB, so an aged-out event returns
# an EMPTY window that reads as "the app never emitted it".
grep -Fq '_startDeviceLogStream' "$adapter" ||
  fail 'Android notification campaign reads log windows without a live stream'
if grep -Fq "'logcat'," "$adapter" && grep -Fq "'-d'," "$adapter"; then
  fail 'Android notification campaign still uses a post-hoc logcat -d window'
fi
grep -Fq 'runAndroidNotificationPayloadE2EAction' "$app_runner" ||
  fail 'installed app poller does not dispatch notification actions'
grep -Fq 'startIntroPollerAfterColdRecovery(' "$app_bootstrap" ||
  fail 'production bootstrap does not preserve the post-recovery poller handoff'
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

# --- Plan 388 (G21): the cold graded wake is classified, not just timed out ---
# The cold leg's graded push is the FIRST wake after the kill, so a wake that
# exhausts a storage phase budget shows NO card: the leg dies inside
# `_waitForNotification`, 48 lines before it reads its own log window, as an
# untyped timeout. Classification has to happen where the cursor is still
# reachable, and the graded window has to close before the tap.
#
# Every assertion about the LEG is scoped to the leg slice on purpose. The
# classifier further down repeats the same literals, so a file-wide `grep -Fq`
# would stay green after the leg's own scan or throw was deleted.
cold_start="$(grep -Fn 'Future<Map<String, Object?>> _runColdPayloadLeg()' \
  "$adapter" | head -1 | cut -d: -f1)"
cold_end="$(grep -Fn 'Future<Map<String, Object?>> _restartAndDrain' \
  "$adapter" | head -1 | cut -d: -f1)"
[ -n "$cold_start" ] && [ -n "$cold_end" ] && [ "$cold_end" -gt "$cold_start" ] ||
  fail 'could not delimit the cold payload leg in the adapter'
cold_leg="$tmp_dir/cold-leg.dart"
sed -n "${cold_start},${cold_end}p" "$adapter" >"$cold_leg"

grep -Fq '_coldWakeLogcatCursor = logcatCursor;' "$cold_leg" ||
  fail 'cold leg does not keep its graded-wake log cursor on the instance'
grep -Fq 'await _coldWakeDeferralsSince(logcatCursor);' "$cold_leg" ||
  fail 'the cold leg does not scan its own graded-wake window'
grep -Fq 'if (coldWakeDeferrals.isNotEmpty) {' "$cold_leg" ||
  fail 'the cold leg does not act on its own scan result'
grep -Fq 'throw _Failure(' "$cold_leg" ||
  fail 'the cold leg does not raise a failure on its own scan result'
grep -Fq '$_coldWakeDeferralFailure' "$cold_leg" ||
  fail 'a storage-deferred cold wake is not raised as a named failure by the leg'
grep -Fq \
  "_coldWakeDeferralFailure =" "$adapter" ||
  fail 'the named storage-deferral failure prefix is not a shared constant'
grep -Fq \
  "'Cold graded wake was storage-deferred: '" "$adapter" ||
  fail 'the storage-deferral failure prefix lost its diagnostic wording'
grep -Fq '_coldWakeWindowScannedClean = true;' "$cold_leg" ||
  fail 'the cold leg does not latch a clean graded window'
grep -Fq "'coldWakeDeferralScan': coldWakeDeferralScan," "$cold_leg" ||
  fail 'the cold artifact does not record its wake-deferral scan result'

# Order inside the leg: scan -> act on the scan -> latch/record -> tap, and the
# whole thing strictly before the wide pre-restore window read. `preRestoreLog`
# spans the tap, the cold relaunch, the observer action and the UI wait — about
# a minute — and `engineRole` on the deferral record is a hard-coded constant,
# so a later wake read from that span would be misattributed to the graded one.
leg_line() {
  grep -Fn "$1" "$cold_leg" | head -1 | cut -d: -f1
}
scan_at="$(leg_line 'await _coldWakeDeferralsSince(logcatCursor);' || true)"
throw_at="$(leg_line '$_coldWakeDeferralFailure' || true)"
latch_at="$(leg_line '_coldWakeWindowScannedClean = true;' || true)"
tap_at="$(leg_line '_tapNotification(marker)' || true)"
prerestore_at="$(leg_line 'preRestoreLog = await _logcatSince' || true)"
for probe in "$scan_at" "$throw_at" "$latch_at" "$tap_at" "$prerestore_at"; do
  [ -n "$probe" ] ||
    fail 'could not order the cold-wake scan against the tap and the wide window'
done
[ "$scan_at" -lt "$throw_at" ] ||
  fail 'the named storage-deferral failure must follow the graded-wake scan'
[ "$throw_at" -lt "$latch_at" ] ||
  fail 'the clean-window latch must come after the deferral failure'
[ "$latch_at" -lt "$tap_at" ] ||
  fail 'the cold-wake deferral scan must close its window before the tap'
[ "$scan_at" -lt "$prerestore_at" ] ||
  fail 'the cold-wake deferral scan must not read the wide pre-restore window'

# The scan's predicate. The record's `outcome` is the enum WIRE name, so the
# handler's caller-side spelling `post_show_unknown` matches nothing — the
# post-show family is `shown_state_unknown`. And `pending_overlay` is the one
# `storage_deferred` site that records and then falls through, so the card is
# still published; keeping it would fail a run that delivered correctly.
grep -Fq "record.event == 'PUSH_BACKGROUND_STORAGE_DEFERRED'" "$adapter" ||
  fail 'the cold-wake scan does not filter the storage-deferral event'
grep -Fq 'await _flowRecordsSince(cursor)' "$adapter" ||
  fail 'the cold-wake scan does not read the cursor-scoped flow records'
grep -Fq "'storage_deferred'," "$adapter" ||
  fail 'the cold-wake scan does not accept the storage_deferred outcome'
grep -Fq "'custody_write_pending'," "$adapter" ||
  fail 'the cold-wake scan does not accept the custody_write_pending outcome'
if grep -Fq "'post_show_unknown'" "$adapter"; then
  fail 'the cold-wake scan filters a caller-side spelling the record never carries'
fi
grep -Fq "record.details['phase'] != 'pending_overlay'" "$adapter" ||
  fail 'the cold-wake scan does not exclude the fall-through overlay phase'

# The diagnosis has to name the phase and the exact milliseconds, otherwise the
# classifier is just a rename of the untyped timeout it replaces.
grep -Fq "record.details['phaseName']" "$adapter" ||
  fail 'the storage-deferral diagnosis does not name the phase'
grep -Fq "record.details['phaseElapsedMs']" "$adapter" ||
  fail 'the storage-deferral diagnosis does not name the exact phase-local ms'
grep -Fq "record.details['budgetMs']" "$adapter" ||
  fail 'the storage-deferral diagnosis does not name the budget it overran'
# On the aggregate-exhausted branch the phase never started, so phase-local ms
# and the budget are BOTH zero and only the whole-wake total carries a number.
grep -Fq "record.details['elapsedMs']" "$adapter" ||
  fail 'the storage-deferral diagnosis cannot describe an exhausted aggregate'
grep -Fq 'if (error.detail.startsWith(_coldWakeDeferralFailure)) rethrow;' \
  "$adapter" ||
  fail 'the classifier re-wraps the diagnosis the leg already named'

# run() must dispatch through the classifier, the classifier must not re-type
# an environment blocker (a `_Blocked` keeps exit 78), and it must stand down
# once the graded window has already been cleared.
grep -Fq 'await _runColdPayloadLegClassified();' "$adapter" ||
  fail 'run() still dispatches the cold leg without a deferral classifier'
classifier_at="$(grep -Fn \
  'Future<Map<String, Object?>> _runColdPayloadLegClassified()' \
  "$adapter" | head -1 | cut -d: -f1)"
[ -n "$classifier_at" ] ||
  fail 'the cold-wake deferral classifier is missing'
classifier="$tmp_dir/cold-classifier.dart"
sed -n "${classifier_at},$((classifier_at + 40))p" "$adapter" >"$classifier"
first_catch="$(grep -o 'on _Failure catch\|on Object catch' "$classifier" \
  | head -1 || true)"
[ "$first_catch" = 'on _Failure catch' ] ||
  fail 'the cold-wake classifier must not re-type environment blockers'
grep -Fq 'if (_coldWakeWindowScannedClean) rethrow;' "$classifier" ||
  fail 'the classifier can blame the graded wake for a later failure'

ios_output="$tmp_dir/ios.list"
"${runner[@]}" --scenario payload_fast_path_ios_receiver --list-scenarios \
  >"$ios_output"
[ "$(cat "$ios_output")" = payload_fast_path_ios_receiver ] ||
  fail 'the iOS-specific APNs/NSE phase is not independently selectable'

printf 'PASS: notification tap Android campaign adapter contract\n'
