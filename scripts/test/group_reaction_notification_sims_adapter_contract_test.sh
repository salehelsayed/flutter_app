#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_one_blocked_result() {
  local output="$1"
  local blocker="$2"
  [ "$(printf '%s\n' "$output" | grep -c '^SIMS_RESULT_JSON=' || true)" -eq 1 ] ||
    fail 'adapter did not emit exactly one structured result'
  [ "$(printf '%s\n' "$output" | awk 'NF { count++ } END { print count + 0 }')" -eq 1 ] ||
    fail 'adapter emitted non-sentinel stdout'
  printf '%s\n' "$output" | grep -q '"status":"BLOCKED"' ||
    fail "adapter did not block: $output"
  printf '%s\n' "$output" | grep -q "\"blocker\":\"$blocker\"" ||
    fail "adapter did not classify blocker=$blocker"
  printf '%s\n' "$output" | grep -q '"assertionsAttempted":0' ||
    fail 'blocked adapter claimed attempted assertions'
  printf '%s\n' "$output" | grep -q '"artifactPresent":false' ||
    fail 'blocked adapter claimed authoritative evidence'
}

DART_BIN="$(command -v dart)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# This host contract tests unavailable targets, independent of attached devices.
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/adb" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$*" = devices ] || exit 99
printf 'List of devices attached\n\n'
EOF
cat >"$FAKE_BIN/flutter" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$*" = 'devices --machine' ] || exit 99
printf '[]\n'
EOF
chmod +x "$FAKE_BIN/adb" "$FAKE_BIN/flutter"
export PATH="$FAKE_BIN:$PATH"

APK="$TMP_DIR/production-fcm.apk"
CREDENTIAL="$TMP_DIR/service-account.json"
RELAY_KEY="$TMP_DIR/staging.pem"
STAGING="$TMP_DIR/staging.json"
: >"$APK"
: >"$RELAY_KEY"
printf '%s\n' '{"project_id":"contract-project"}' >"$CREDENTIAL"
printf '%s\n' \
  '{"schema":"mknoon.plan257.staging-prerequisites.v1","version":1,"environment":"staging","relayActive":true,"providerConfigured":true,"providerProbeSucceeded":true,"productionDeploymentPerformed":false,"allowAppDataReset":true,"candidateRelayRevision":"contract-revision","candidateRelaySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider":"fcm","relayAddresses":["127.0.0.1:4001"]}' \
  >"$STAGING"

ADAPTER='integration_test/scripts/run_group_reaction_notification_sims.dart'
run_adapter() {
  env \
    MKNOON_RELAY_ADDRESSES='127.0.0.1:4001' \
    MKNOON_257_RELAY_TARGET='staging@example.invalid' \
    MKNOON_257_RELAY_KEY="$RELAY_KEY" \
    MKNOON_257_STAGING_MANIFEST="$STAGING" \
    SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$APK" \
    SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$CREDENTIAL" \
    FIREBASE_SERVICE_ACCOUNT="$CREDENTIAL" \
    SIMS_ANDROID_PHYSICAL_DEVICE_ID='PHYSICAL123' \
    SIMS_ANDROID_EMULATOR_DEVICE_ID='emulator-0000' \
    "$@"
}

set +e
output="$(run_adapter "$DART_BIN" "$ADAPTER")"
status=$?
set -e
[ "$status" -eq 78 ] || fail "availability-bounded adapter exited $status"
assert_one_blocked_result "$output" deviceLost
for scenario in \
  android_group_message_unread_lifecycle \
  android_announcement_message_unread_lifecycle \
  android_group_reaction_recipient \
  android_announcement_reaction_recipient; do
  printf '%s\n' "$output" | grep -q "$scenario" ||
    fail "availability result dropped Android scenario $scenario"
done

assert_typed_preflight() {
  local blocker="$1"
  shift
  set +e
  local result
  result="$(run_adapter "$@")"
  local code=$?
  set -e
  [ "$code" -eq 78 ] || fail "$blocker preflight exited $code"
  assert_one_blocked_result "$result" "$blocker"
}

assert_typed_preflight environment \
  env -u MKNOON_RELAY_ADDRESSES "$DART_BIN" "$ADAPTER"
assert_typed_preflight missingArtifact \
  env -u SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM "$DART_BIN" "$ADAPTER"
assert_typed_preflight credentials \
  env -u SIMS_PROVIDER_FCM_CREDENTIAL_PATH -u FIREBASE_SERVICE_ACCOUNT \
    "$DART_BIN" "$ADAPTER"
assert_typed_preflight environment \
  env -u MKNOON_257_STAGING_MANIFEST "$DART_BIN" "$ADAPTER"
assert_typed_preflight targetUnavailable \
  env -u SIMS_ANDROID_EMULATOR_DEVICE_ID "$DART_BIN" "$ADAPTER"

grep -q -- "--prebuilt-android-apk" \
  integration_test/scripts/run_group_reaction_notification_device.dart ||
  fail 'device runner does not forward the central prepared APK'
python3 - integration_test/scripts/run_group_reaction_notification_device.dart <<'PY'
import sys

source = open(sys.argv[1], encoding='utf-8').read()
start = source.index('final adapter = PhysicalDeviceCaptureAdapter(')
end = source.index('final capture = await runPhysicalDeviceCapture(', start)
adapter = source[start:end]
assert 'additionalArguments: <String>[' in adapter
assert "if (args.contains('--android-state-prepared'))" in adapter
assert "'--android-state-prepared'" in adapter
PY
grep -q -- "--no-child-builds" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'capture driver lacks the fail-closed no-child-build contract'
grep -q "group_reaction_sqlcipher_observe" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'capture driver does not stage the installed-app SQLCipher action'
grep -q "group_reaction_exact_add_redrive" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'capture driver does not stage the installed-app exact ADD redrive'
grep -q "_runInstalledGroupReactionProbe" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'capture driver does not consume nonce-bound installed-app results'
grep -q "file.absolute.path == preparedPath" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'capture cleanup can delete the centrally shared APK between scenarios'
! grep -q 'group_reaction_runtime_sqlcipher_and_duplicate_redrive_driver_missing' \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'capture driver still stops at the old missing-driver placeholder'
grep -q "for (final scenario in _androidScenarios)" "$ADAPTER" ||
  fail 'adapter does not orchestrate the four Android scenarios'
grep -q "writeSimsArtifactEvidenceSync" "$ADAPTER" ||
  fail 'adapter does not write one durable aggregate artifact'
grep -q "'childBuildCount': 0" "$ADAPTER" ||
  fail 'adapter does not attest zero campaign child builds'

CAPTURE_DIR="$TMP_DIR/capture"
set +e
"$DART_BIN" integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario android_group_reaction_recipient \
  --sender emulator-0000 \
  --recipient PHYSICAL123 \
  --artifact-dir "$CAPTURE_DIR" \
  --staging-manifest "$STAGING" \
  --prebuilt-android-apk "$APK" \
  --no-child-builds \
  >"$TMP_DIR/capture.stdout" 2>"$TMP_DIR/capture.stderr"
capture_status=$?
set -e
if [ "$capture_status" -ne 78 ]; then
  cat "$TMP_DIR/capture.stderr" >&2
  fail "no-child capture preflight exited $capture_status instead of 78"
fi
capture_verdict="$CAPTURE_DIR/android_group_reaction_recipient_orchestrator_verdict.json"
[ -f "$capture_verdict" ] || fail 'no-child capture omitted its typed verdict'
grep -q 'explicit_device_unavailable' \
  "$capture_verdict" ||
  fail 'capture did not honor availability-bounded device discovery'
grep -q '"status":"environment_blocked"' "$capture_verdict" ||
  fail 'capture mislabeled its unavailable target blocker'

# Resolve the SDK executable before the controls get tool-only PATHs. Running
# the Dart entrypoint directly avoids package build-hook tool discovery.
cat >"$TMP_DIR/resolved-dart.dart" <<'DART'
import 'dart:io';
void main() => stdout.writeln(Platform.resolvedExecutable);
DART
DART_VM="$("$DART_BIN" "$TMP_DIR/resolved-dart.dart")"
[ -x "$DART_VM" ] || fail 'SDK executable did not resolve'

NO_ADB_BIN="$TMP_DIR/no-adb-bin"
NO_FLUTTER_BIN="$TMP_DIR/no-flutter-bin"
mkdir -p "$NO_ADB_BIN" "$NO_FLUTTER_BIN"
cat >"$NO_ADB_BIN/flutter" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$*" = 'devices --machine' ] || exit 99
printf '%s\n' '[{"id":"emulator-0000","targetPlatform":"android-x64"},{"id":"PHYSICAL123","targetPlatform":"android-arm64"}]'
EOF
chmod +x "$NO_ADB_BIN/flutter"
cp "$FAKE_BIN/adb" "$NO_FLUTTER_BIN/adb"
# Failure artifacts still require the host's file-permission utility.
ln -s "$(command -v chmod)" "$NO_ADB_BIN/chmod"
ln -s "$(command -v chmod)" "$NO_FLUTTER_BIN/chmod"
ln -s "$(command -v python3)" "$NO_ADB_BIN/python3"
ln -s "$(command -v python3)" "$NO_FLUTTER_BIN/python3"

for control in missing-adb missing-flutter; do
  if [ "$control" = missing-adb ]; then
    tool_path="$NO_ADB_BIN"
    expected_exit=78
    expected_status=environment_blocked
    expected_detail=adb_unavailable
  else
    tool_path="$NO_FLUTTER_BIN"
    expected_exit=1
    expected_status=capture_failed
    expected_detail=unexpected_ProcessException
  fi
  control_dir="$TMP_DIR/$control"
  set +e
  PATH="$tool_path" "$DART_VM" \
    "$ROOT_DIR/integration_test/scripts/capture_group_reaction_notification_device.dart" \
    --scenario android_group_reaction_recipient \
    --sender emulator-0000 \
    --recipient PHYSICAL123 \
    --artifact-dir "$control_dir" \
    --staging-manifest "$STAGING" \
    --prebuilt-android-apk "$APK" \
    --no-child-builds \
    >"$TMP_DIR/$control.stdout" 2>"$TMP_DIR/$control.stderr"
  control_exit=$?
  set -e
  if [ "$control_exit" -ne "$expected_exit" ]; then
    cat "$TMP_DIR/$control.stderr" >&2
    fail "$control exited $control_exit instead of $expected_exit"
  fi
  verdict="$control_dir/android_group_reaction_recipient_orchestrator_verdict.json"
  [ -f "$verdict" ] || fail "$control omitted its typed verdict"
  grep -q '"stage":"device_inventory"' "$verdict" || fail "$control left inventory"
  grep -q "\"status\":\"$expected_status\"" "$verdict" || fail "$control changed classification"
  grep -q "$expected_detail" "$verdict" || fail "$control changed failure detail"
  printf 'PASS: controlled %s preflight (exit %s)\n' "$control" "$control_exit"
done

printf 'PASS: group reaction notification Sims adapter uses one prebuilt campaign path\n'
