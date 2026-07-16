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
artifact="$tmp_dir/android-e2e-main.apk"
printf 'central-main-apk-fixture\n' >"$artifact"

missing_output="$tmp_dir/missing.out"
set +e
env -u SIMS_ARTIFACT_ANDROID_E2E_MAIN \
  dart integration_test/scripts/run_voice_message_sims.dart \
  >"$missing_output" 2>&1
missing_exit=$?
set -e
[ "$missing_exit" -eq 78 ] ||
  fail "missing artifact exited $missing_exit instead of BLOCKED/78"
grep -Fq 'SIMS_RESULT_JSON=' "$missing_output" ||
  fail 'missing artifact omitted the typed result sentinel'
grep -Fq '"status":"BLOCKED"' "$missing_output" ||
  fail 'missing artifact did not emit BLOCKED'
grep -Fq '"blocker":"missingArtifact"' "$missing_output" ||
  fail 'missing artifact did not use the typed missingArtifact blocker'

profile_output="$tmp_dir/profile.out"
set +e
SIMS_ARTIFACT_PROFILE_ID=android.e2e.standard \
  dart integration_test/scripts/run_voice_message_sims.dart \
    --artifact "$artifact" \
    --device pixel-usb \
    --device emulator-5554 \
    >"$profile_output" 2>&1
profile_exit=$?
set -e
[ "$profile_exit" -eq 78 ] || fail 'wrong build profile did not exit BLOCKED/78'
grep -Fq '"blocker":"missingArtifact"' "$profile_output" ||
  fail 'wrong build profile did not fail before device mutation'
grep -Fq 'android.e2e.main' "$profile_output" ||
  fail 'wrong-profile diagnostic omitted the required shared profile'

if rg -n 'flutter (build|drive)' \
  integration_test/scripts/android_voice_message_device_campaign.dart \
  integration_test/scripts/run_voice_message_sims.dart >/dev/null; then
  fail 'voice-message host adapter contains a child Flutter build/drive command'
fi
rg -Fq "AndroidAppStateGuard.capture" \
  integration_test/scripts/android_voice_message_device_campaign.dart ||
  fail 'voice-message adapter does not guard original app state'
rg -Fq 'prepareFreshInstall' \
  integration_test/scripts/android_voice_message_device_campaign.dart ||
  fail 'voice-message adapter does not reuse the exact supplied artifact path'

central_output="$tmp_dir/central.out"
set +e
env -u SIMS_ARTIFACT_ANDROID_E2E_MAIN \
  dart integration_test/scripts/run_1to1_device_real.dart \
  --scenario android.voice_message_e2e \
  --device pixel-usb \
  --device emulator-5554 \
  >"$central_output" 2>&1
central_exit=$?
set -e
[ "$central_exit" -eq 78 ] ||
  fail 'central voice-message scenario did not fail closed without its APK'
grep -Fq '"blocker":"missingArtifact"' "$central_output" ||
  fail 'central runner did not delegate voice-message E2E to its real adapter'

jq -e '
  .capabilities[] |
  select(.id == "android.voice_message_e2e") |
  .automationReady == true and
  .buildProfile == "android.e2e.main" and
  .dependencies == ["build.android.e2e.main"] and
  any(.resources[]; .name == "build:android.e2e.main" and .access == "read") and
  any(.resources[]; .name == "device:android-physical" and .access == "exclusive") and
  any(.resources[]; .name == "device:android-emulator" and .access == "exclusive")
' tool/sims/critical_features.json >/dev/null ||
  fail 'voice-message capability is not ready on the shared main APK/device locks'

rg -Fq 'runAndroidVoiceMessageE2EAction(' lib/core/debug/intro_e2e_runner.dart ||
  fail 'production app poller does not dispatch the voice-message action'
for dependency in \
  'mediaAttachmentRepo: mediaAttachmentRepository' \
  'mediaFileManager: mediaFileManager' \
  'audioRecorderService: audioRecorderService'; do
  rg -Fq "$dependency" lib/main.dart ||
    fail "main app bootstrap omitted voice-message dependency: $dependency"
done

printf 'PASS: voice-message adapter is wired, fail-closed, and prebuilt-only\n'
