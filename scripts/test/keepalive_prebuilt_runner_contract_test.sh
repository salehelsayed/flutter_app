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

runner=(
  dart integration_test/scripts/run_1to1_device_real.dart
  --scenario android.keepalive_drop_skip_direct
)
campaign='integration_test/scripts/android_keepalive_drop_campaign.dart'
support='integration_test/support/android_keepalive_drop_campaign.dart'
state_guard='integration_test/support/android_app_state_guard.dart'

assert_one_result() {
  local output="$1"
  local count
  count="$(grep -c '^SIMS_RESULT_JSON=' "$output" || true)"
  [ "$count" -eq 1 ] || fail "expected one typed result, found $count"
}

missing_output="$tmp_dir/missing.out"
set +e
"${runner[@]}" >"$missing_output"
missing_status=$?
set -e
[ "$missing_status" -eq 78 ] ||
  fail "missing main APK exited $missing_status instead of 78"
assert_one_result "$missing_output"
grep -Fq '"status":"BLOCKED"' "$missing_output" ||
  fail 'missing main APK was not BLOCKED'
grep -Fq '"blocker":"missingArtifact"' "$missing_output" ||
  fail 'missing main APK was not classified as missingArtifact'

shim_dir="$tmp_dir/bin"
mkdir -p "$shim_dir"
command_log="$tmp_dir/commands.log"
artifact="$tmp_dir/android-e2e-main.apk"
printf 'central-main-prebuilt\n' >"$artifact"

cat >"$shim_dir/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'adb' >>"${COMMAND_LOG:?}"
printf ' %q' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"
exit 23
EOF
chmod +x "$shim_dir/adb"

profile_output="$tmp_dir/profile.out"
: >"$command_log"
set +e
env \
  PATH="$shim_dir:$PATH" \
  COMMAND_LOG="$command_log" \
  SIMS_ARTIFACT_PROFILE_ID=android.e2e.standard \
  SIMS_ARTIFACT_ANDROID_E2E_MAIN="$artifact" \
  SIMS_ANDROID_PHYSICAL_DEVICE_ID=pixel-usb \
  SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
  "${runner[@]}" >"$profile_output"
profile_status=$?
set -e
[ "$profile_status" -eq 78 ] ||
  fail "wrong build profile exited $profile_status instead of 78"
assert_one_result "$profile_output"
grep -Fq '"blocker":"missingArtifact"' "$profile_output" ||
  fail 'wrong build profile was not rejected as missingArtifact'
[ ! -s "$command_log" ] ||
  fail 'wrong build profile touched adb before failing closed'

topology_output="$tmp_dir/topology.out"
: >"$command_log"
set +e
env \
  PATH="$shim_dir:$PATH" \
  COMMAND_LOG="$command_log" \
  SIMS_ARTIFACT_PROFILE_ID=android.e2e.main \
  SIMS_ARTIFACT_ANDROID_E2E_MAIN="$artifact" \
  "${runner[@]}" --device pixel-usb >"$topology_output"
topology_status=$?
set -e
[ "$topology_status" -eq 78 ] ||
  fail "one-target topology exited $topology_status instead of 78"
assert_one_result "$topology_output"
grep -Fq '"blocker":"targetUnavailable"' "$topology_output" ||
  fail 'one-target topology was not rejected as targetUnavailable'
[ ! -s "$command_log" ] ||
  fail 'invalid topology touched adb before failing closed'

adb_output="$tmp_dir/adb.out"
: >"$command_log"
set +e
env \
  PATH="$shim_dir:$PATH" \
  COMMAND_LOG="$command_log" \
  SIMS_ARTIFACT_PROFILE_ID=android.e2e.main \
  SIMS_ARTIFACT_ANDROID_E2E_MAIN="$artifact" \
  SIMS_ANDROID_PHYSICAL_DEVICE_ID=pixel-usb \
  SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
  "${runner[@]}" >"$adb_output"
adb_status=$?
set -e
[ "$adb_status" -eq 78 ] ||
  fail "unavailable adb exited $adb_status instead of 78"
assert_one_result "$adb_output"
grep -Fq '"status":"BLOCKED"' "$adb_output" ||
  fail 'unavailable adb produced a false live verdict'
grep -Fq 'adb version' "$command_log" ||
  fail 'valid inputs did not enter keepalive preflight'
if grep -Eq ' install | force-stop | pm clear | push ' "$command_log"; then
  fail 'failed preflight mutated an Android target'
fi

grep -Fq "SIMS_ARTIFACT_ANDROID_E2E_MAIN" \
  integration_test/scripts/run_1to1_device_real.dart ||
  fail '1:1 adapter does not route the shared main APK'
grep -Fq "profileId: _mainArtifactProfile" "$campaign" ||
  fail 'campaign is not bound to android.e2e.main'
grep -Fq "'childFlutterBuilds': 0" "$campaign" ||
  fail 'campaign does not attest zero child Flutter builds'
if rg -q "Process\.(run|start)\('(flutter|gradle|xcodebuild)'|flutter drive|flutter build" \
  "$campaign"; then
  fail 'campaign contains a forbidden child build command'
fi

for marker in \
  P2P_SERVICE_PEER_PING_BEGIN \
  P2P_SERVICE_PEER_PING_FAILED \
  KEEPALIVE_PEER_DROP \
  P2P_SERVICE_DIAL_PEER_ERROR \
  keepaliveDroppedSendAction \
  keepaliveRecoveryObserveAction \
  receiverMessageIdMatched \
  naturalProbeSpacingMs \
  stateRestored \
  writeSimsArtifactEvidenceSync
do
  grep -Fq "$marker" "$campaign" ||
    fail "implemented campaign omitted $marker"
done

for marker in \
  CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN \
  SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP \
  CHAT_MSG_SEND_CUSTODY_CONFIRMED \
  DELIVERY_RECEIPT_APPLIED \
  P2P_SERVICE_PEER_PING_SUCCESS \
  validateKeepaliveDropArtifact
do
  grep -Fq "$marker" "$support" ||
    fail "evidence validator omitted $marker"
done

grep -Fq "AndroidAppStateGuard.capture" "$campaign" ||
  fail 'campaign does not capture both package snapshots'
grep -Fq "stateGuard.restoreAll()" "$campaign" ||
  fail 'campaign does not restore both package snapshots'
grep -Fq "private-data.tar" "$state_guard" ||
  fail 'campaign does not preserve private app data'
grep -Fq "original APK bytes did not restore" "$state_guard" ||
  fail 'campaign does not verify original APK restoration'
grep -Fq "no passing artifact was" "$campaign" ||
  fail 'restoration failure is not explicitly fail-closed'

printf 'PASS: keepalive main-prebuilt automated campaign contract\n'
