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
  --scenario android.wake_token_directionality
)

assert_one_result() {
  local output="$1"
  local count
  count="$(grep -c '^SIMS_RESULT_JSON=' "$output" || true)"
  [ "$count" -eq 1 ] || fail "expected one typed result, found $count"
}

missing_output="$tmp_dir/missing.out"
set +e
SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$tmp_dir/wrong-profile.apk" \
  "${runner[@]}" >"$missing_output"
missing_status=$?
set -e
[ "$missing_status" -eq 78 ] ||
  fail "missing wake-token APK exited $missing_status instead of 78"
assert_one_result "$missing_output"
grep -Fq '"status":"BLOCKED"' "$missing_output" ||
  fail 'missing wake-token APK was not BLOCKED'
grep -Fq '"blocker":"missingArtifact"' "$missing_output" ||
  fail 'missing wake-token APK was not classified as missingArtifact'
grep -Fq 'android.e2e.wake_token APK is required' "$missing_output" ||
  fail 'runner did not request the dedicated wake-token APK'

shim_dir="$tmp_dir/bin"
mkdir -p "$shim_dir"
command_log="$tmp_dir/commands.log"
artifact="$tmp_dir/android-e2e-wake-token.apk"
printf 'central-wake-token-prebuilt\n' >"$artifact"

cat >"$shim_dir/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'adb' >>"${COMMAND_LOG:?}"
printf ' %q' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"

case "$*" in
  'version')
    printf 'Android Debug Bridge version 1.0.41\n'
    ;;
  'devices -l')
    printf 'List of devices attached\n'
    printf 'pixel-usb device usb:1-1 model:Pixel_6\n'
    printf 'emulator-5554 device product:sdk_gphone\n'
    ;;
  '-s pixel-usb shell getprop ro.kernel.qemu')
    printf '0\n'
    ;;
  '-s emulator-5554 shell getprop ro.kernel.qemu')
    printf '1\n'
    ;;
  '-s pixel-usb shell pm path com.mknoon.app'|\
  '-s emulator-5554 shell pm path com.mknoon.app'|\
  '-s pixel-usb shell pidof com.mknoon.app'|\
  '-s emulator-5554 shell pidof com.mknoon.app'|\
  '-s pixel-usb shell dumpsys activity activities'|\
  '-s emulator-5554 shell dumpsys activity activities'|\
  '-s pixel-usb shell am force-stop com.mknoon.app'|\
  '-s emulator-5554 shell am force-stop com.mknoon.app')
    ;;
  "-s pixel-usb install -r -d -t $EXPECTED_ARTIFACT")
    exit 23
    ;;
  *)
    exit 23
    ;;
esac
EOF
chmod +x "$shim_dir/adb"

preflight_output="$tmp_dir/preflight.out"
: >"$command_log"
set +e
env \
  PATH="$shim_dir:$PATH" \
  COMMAND_LOG="$command_log" \
  EXPECTED_ARTIFACT="$artifact" \
  SIMS_ARTIFACT_PROFILE_ID=android.e2e.wake_token \
  SIMS_ARTIFACT_ANDROID_E2E_WAKE_TOKEN="$artifact" \
  SIMS_ARTIFACT_ANDROID_E2E_STANDARD="$tmp_dir/not-the-wake-artifact.apk" \
  SIMS_ANDROID_PHYSICAL_DEVICE_ID=pixel-usb \
  SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
  "${runner[@]}" >"$preflight_output"
preflight_status=$?
set -e
[ "$preflight_status" -eq 1 ] ||
  fail "post-preflight install failure exited $preflight_status instead of 1"
assert_one_result "$preflight_output"
grep -Fq '"status":"FAIL"' "$preflight_output" ||
  fail 'a post-mutation install failure did not fail the campaign'
grep -Fq '"blocker":"environment"' "$preflight_output" ||
  fail 'the install failure was not classified as an environment failure'

grep -Fq 'adb devices -l' "$command_log" ||
  fail 'wake preflight did not discover attached targets'
grep -Fq 'adb -s pixel-usb shell getprop ro.kernel.qemu' "$command_log" ||
  fail 'wake preflight did not verify the physical target role'
grep -Fq 'adb -s emulator-5554 shell getprop ro.kernel.qemu' "$command_log" ||
  fail 'wake preflight did not verify the emulator target role'
grep -Fq "adb -s pixel-usb install -r -d -t $artifact" "$command_log" ||
  fail 'wake campaign did not consume the central APK after preflight'
if grep -Eq '^(flutter|gradle|xcodebuild)( |$)' "$command_log"; then
  fail 'wake campaign invoked a child build tool'
fi

profile_output="$tmp_dir/profile.out"
: >"$command_log"
set +e
env \
  PATH="$shim_dir:$PATH" \
  COMMAND_LOG="$command_log" \
  SIMS_ARTIFACT_PROFILE_ID=android.e2e.standard \
  SIMS_ARTIFACT_ANDROID_E2E_WAKE_TOKEN="$artifact" \
  SIMS_ANDROID_PHYSICAL_DEVICE_ID=pixel-usb \
  SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
  "${runner[@]}" >"$profile_output"
profile_status=$?
set -e
[ "$profile_status" -eq 78 ] ||
  fail "wrong build profile exited $profile_status instead of 78"
assert_one_result "$profile_output"
grep -Fq '"blocker":"missingArtifact"' "$profile_output" ||
  fail 'wrong build profile was not rejected before target access'
[ ! -s "$command_log" ] ||
  fail 'wrong build profile touched adb before failing closed'

cli_output="$tmp_dir/cli.out"
: >"$command_log"
set +e
env -u SIMS_ARTIFACT_PROFILE_ID \
  PATH="$shim_dir:$PATH" COMMAND_LOG="$command_log" \
  EXPECTED_ARTIFACT="$artifact" \
  "${runner[@]}" --device pixel-usb,emulator-5554 \
  --artifact "$artifact" >"$cli_output"
cli_status=$?
set -e
[ "$cli_status" -eq 1 ] ||
  fail "explicit pair inputs exited $cli_status instead of 1"
assert_one_result "$cli_output"
grep -Fq '"status":"FAIL"' "$cli_output" ||
  fail 'explicit pair inputs did not reach the executable campaign'

grep -Fq 'runAndroidWakeTokenDirectionalityCampaign' \
  integration_test/scripts/run_1to1_device_real.dart ||
  fail '1:1 facade does not delegate to the wake-token host campaign'
grep -Fq 'registeredTokenSha256' \
  integration_test/scripts/android_wake_token_directionality_campaign.dart ||
  fail 'host campaign does not bind the relay-registered hash'
grep -Fq 'storedTokenSha256' \
  integration_test/scripts/android_wake_token_directionality_campaign.dart ||
  fail 'host campaign does not bind the receiver-store hash'
grep -Fq 'attachedTokenSha256' \
  integration_test/scripts/android_wake_token_directionality_campaign.dart ||
  fail 'host campaign does not bind the accepted attachment hash'
if grep -Eq 'flutter (build|drive|run)' \
  integration_test/scripts/android_wake_token_directionality_campaign.dart; then
  fail 'host campaign source contains a child Flutter invocation'
fi

printf 'PASS: wake-token shared-prebuilt executable campaign contract\n'
