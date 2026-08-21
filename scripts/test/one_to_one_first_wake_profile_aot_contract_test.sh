#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

runner=integration_test/scripts/run_1to1_reaction_notification_device.dart
capture=integration_test/scripts/capture_1to1_reaction_head_provenance.dart
proof=integration_test/one_to_one_reaction_notification_proof_test.dart
journal=lib/features/push/application/background_storage_liveness_journal.dart
handler=lib/features/push/application/background_message_handler.dart

[ -f "$runner" ] || fail 'shared 1:1 device runner is missing'
[ -f "$capture" ] || fail 'shared 1:1 capture driver is missing'
[ -f "$proof" ] || fail 'shared 1:1 proof oracle is missing'

[ "$(dart run "$runner" --scenario android_first_wake_profile_aot --list-scenarios | grep -o 'android_first_wake_profile_aot' | tail -1)" = \
  'android_first_wake_profile_aot' ] ||
  fail 'profile-AOT scenario is not discoverable exactly once'

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

set +e
dart run "$runner" \
  --scenario android_first_wake_profile_aot \
  --sender PHYSICAL \
  --recipient emulator-6554 \
  --artifact-dir "$tmp_dir/missing-mode" \
  >"$tmp_dir/missing-mode.out" 2>&1
missing_mode_status=$?
dart run "$runner" \
  --scenario android_first_wake_profile_aot \
  --sender PHYSICAL \
  --recipient emulator-6554 \
  --artifact-dir "$tmp_dir/both-modes" \
  --measurement-only --require-alert \
  >"$tmp_dir/both-modes.out" 2>&1
both_modes_status=$?
dart run "$capture" \
  --sender PHYSICAL \
  --recipient emulator-6554 \
  --artifact-dir "$tmp_dir/missing-inputs" \
  --first-wake-profile-aot --measurement-only \
  >"$tmp_dir/missing-inputs.out" 2>&1
missing_inputs_status=$?
set -e

[ "$missing_mode_status" -eq 64 ] || fail 'missing measurement/acceptance mode did not exit 64'
[ "$both_modes_status" -eq 64 ] || fail 'ambiguous measurement/acceptance mode did not exit 64'
[ "$missing_inputs_status" -eq 64 ] || fail 'missing credential/manifest inputs did not exit 64'

python3 - "$runner" "$capture" "$proof" "$journal" "$handler" <<'PY'
import re
import sys

runner, capture, proof, journal, handler = [
    open(path, encoding="utf-8").read() for path in sys.argv[1:]
]

for token in (
    "android_first_wake_profile_aot",
    "--first-wake-profile-aot",
    "--measurement-only",
    "--require-alert",
    "--service-account",
    "--staging-manifest",
):
    assert token in runner, f"runner dropped {token}"

for token in (
    "--profile",
    "--dart-define=E2E_TEST_MODE=true",
    "--dart-define=PRODUCTION_FCM=true",
    "--dart-define=MKNOON_EMIT_WAKE_TOKEN=true",
    "--dart-define=MKNOON_NOTIFICATION_G21_MEASUREMENT=true",
    "app-arm64-v8a-profile.apk",
    "_captureInitialDeviceState",
    "_restoreExactInitialDeviceState",
    "_g21MeasurementInventory",
    "recipientProcessAbsentBeforeSend",
    "selectedProductionReserveMs",
    "passWrittenAfterRestoration",
):
    assert token in capture, f"capture dropped {token}"

profile_anchor = "'--profile',\n        '--target-platform=android-arm64'"
profile_index = capture.index(profile_anchor)
profile_start = capture.rfind("await _runStreaming('flutter'", 0, profile_index)
profile_end = capture.index("], workingDirectory: sourceRoot.path);", profile_index)
profile_build = capture[profile_start:profile_end]
for define in (
    "E2E_TEST_MODE=true",
    "PRODUCTION_FCM=true",
    "MKNOON_EMIT_WAKE_TOKEN=true",
):
    assert profile_build.count(define) == 1, f"profile build does not contain exact base define {define}"
assert "MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR" not in profile_build

assert re.search(
    r"if \(measurementOnly\)\s*'--dart-define=MKNOON_NOTIFICATION_G21_MEASUREMENT=true'",
    capture,
), "measurement define is not conditional on measurement-only mode"

restore = capture.index("await _restoreExactInitialDeviceState();", capture.index("if (firstWakeProfileAot)"))
publish = capture.index("_writeFirstWakeProfileAotArtifact(", restore)
assert restore < publish, "PASS artifact can be written before exact restoration"

for token in (
    "mknoon.plan393.g21-measurement.v1",
    "aggregateElapsedAtEligibilityStartMs",
    "remainingAtEligibilityStartMs",
    "eligibilityElapsedMs",
    "nativeEntryTailMs",
    "terminalOutcome",
    "buildMode",
    "engineRole",
):
    assert token in journal, f"measurement receipt dropped {token}"

assert "MKNOON_NOTIFICATION_G21_MEASUREMENT" in handler
assert "runWithRawAggregateRemainder" in handler
assert "recordG21Measurement" in handler
assert "_backgroundStorageG21MeasurementBuild &&" in handler
assert "test('android_first_wake_profile_aot'" in proof
assert "selectedProductionReserveMs" in proof
assert "remaining - reserve" in proof
PY

printf 'PASS: TC-393-06 profile-AOT first-wake capture is explicit and fail closed\n'
