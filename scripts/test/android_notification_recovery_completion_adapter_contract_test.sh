#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RUNNER="$ROOT/integration_test/scripts/run_android_notification_recovery_completion.dart"
WRAPPER_ENTRYPOINT=integration_test/scripts/run_android_notification_recovery_completion_sims.dart
WRAPPER="$ROOT/$WRAPPER_ENTRYPOINT"
FULL_REGRESSION_RUNNER="$ROOT/scripts/run_flutter_full_regression.sh"
CAPTURE="$ROOT/integration_test/scripts/capture_1to1_reaction_head_provenance.dart"
CRITERIA="$ROOT/integration_test/scripts/android_notification_recovery_completion_criteria.dart"
FIXTURE="$ROOT/go-relay-server/direct_media_blob_custody_device_fixture_test.go"
RECEIVER="$ROOT/android/app/src/main/kotlin/com/mknoon/app/MknoonFirebaseMessagingReceiver.kt"
MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"

for file in "$RUNNER" "$WRAPPER" "$FULL_REGRESSION_RUNNER" "$CAPTURE" "$CRITERIA" "$FIXTURE" "$RECEIVER" "$MANIFEST"; do
  [[ -f "$file" ]] || {
    echo "missing recovery source: $file" >&2
    exit 1
  }
done

wrapper_probe=$(cd "$ROOT" && dart "$WRAPPER_ENTRYPOINT" --probe-source-extension)
WRAPPER_PROBE="$wrapper_probe" python3 - <<'PY'
import json
import os

p = json.loads(os.environ["WRAPPER_PROBE"])
assert p == {
    "scenario": "notifications.android_recovery_completion",
    "executionBoundary": "ephemeral_production_redis_fixture",
    "pushTokenState": "encrypted",
    "wakeOutcomeLedger": "redis",
    "provider": "fcm",
    "centralPreparation": True,
}
PY

probe=$(cd "$ROOT" && dart "$RUNNER" --probe-source-extension)
PROBE="$probe" python3 - <<'PY'
import json
import os

p = json.loads(os.environ["PROBE"])
assert p == {
    "scenario": "android_fixed_wake_direct_reaction_recovery",
    "captureDriver": "integration_test/scripts/capture_1to1_reaction_head_provenance.dart",
    "buildProfile": "android.production_fcm.fixed_wake",
    "artifactEnvironment": "SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_FIXED_WAKE",
    "physicalIdPinned": False,
    "emulatorIdPinned": False,
    "legacyMissingSourcesRequired": False,
}
PY

expected=$(mktemp)
actual=$(mktemp)
trap 'rm -f "$expected" "$actual"' EXIT
printf '%s\n' \
  notifications.fixed_wake_live_route_selected \
  notifications.direct_reaction_canonical_recovery \
  notifications.generic_recovery_card_retired \
  notifications.no_duplicate_or_second_tone \
  notifications.state_and_route_restored \
  notifications.zero_taps_zero_child_builds >"$expected"
(cd "$ROOT" && dart "$RUNNER" --list-criteria) >"$actual"
cmp "$expected" "$actual"

rg -q "SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_FIXED_WAKE" "$CRITERIA"
rg -q -- "--fixed-wake-recovery" "$RUNNER"
rg -q "AndroidAppStateGuard\.capture" "$RUNNER"
rg -q "stateGuard\.restoreAll" "$RUNNER"
rg -q "validateAndroidNotificationRecoveryRawArtifact" "$RUNNER"
rg -q "authenticatedRouteUnregister" "$RUNNER"
rg -q "routeAbsentReadback" "$RUNNER"
rg -q "relay_push_route_selected_total" "$CAPTURE"
rg -q "notification_unregister_push" "$CAPTURE"
rg -q "arm-fixed-wake" "$CAPTURE"
rg -q "runAttemptCount" "$CAPTURE"
rg -q "processAbsentBeforeSend" "$CAPTURE"
rg -q "productionIngressInjectionCount" "$CAPTURE"
rg -q "'productionIngressInjectionCount': 0" "$CAPTURE"
rg -q "fixed-wake-timeout.v1" "$CAPTURE"
rg -q "reactionSuccessObserved" "$CAPTURE"
rg -q "opaqueRouteDelta" "$CAPTURE"
rg -q -- "--relay-fixture-probe" "$RUNNER" "$CAPTURE"
rg -q "run_android_notification_recovery_completion_sims" "$WRAPPER"
rg -q "fixedWakeRecovery: true" "$WRAPPER"
rg -q -- "--prepare-builds" "$WRAPPER"
rg -q "ephemeral_production_redis_fixture" "$WRAPPER" "$CRITERIA"
rg -q "pushTokenStateEncrypted" "$FIXTURE"
rg -q "WakeOutcomeCoordinator.Start" "$FIXTURE"
rg -q "SIMS_PROVIDER_FCM_CREDENTIAL_PATH" "$FIXTURE"
rg -q "isExactFixedOpaqueWake" "$RECEIVER"
rg -q "delegateRichMessageToFlutterFire" "$RECEIVER"
rg -q "parseAndroidCanonicalRecoveryJobIds" "$CAPTURE" "$CRITERIA"
rg -q "#HeadlessCanonicalRecoveryWorker#" "$CRITERIA"
rg -q 'android:name="\.MknoonFirebaseMessagingReceiver"' "$MANIFEST"
rg -q 'io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver' "$MANIFEST"

FULL_REGRESSION_SOURCE="$FULL_REGRESSION_RUNNER" python3 - <<'PY'
import os
from pathlib import Path

source = Path(os.environ["FULL_REGRESSION_SOURCE"]).read_text()
function_start = source.index("run_android_notification_recovery_completion() {")
function_end = source.index("\n}\n", function_start)
function = source[function_start:function_end]
assert "run_android_notification_recovery_completion_sims.dart" in function
assert "--mode major" in function
assert "--scenario notifications.android_recovery_completion" in function

route_start = source.index("android_notification_recovery_completion_proof_test.dart)")
route_end = source.index(";;", route_start)
route = source[route_start:route_end]
assert "run_android_notification_recovery_completion" in route
assert "run_sims_capability" not in route
PY

if rg -q "block\.contains\('mknoon-canonical-recovery'\)" "$CAPTURE" "$CRITERIA"; then
  echo "recovery JobScheduler parser depends on an unrendered WorkManager name" >&2
  exit 1
fi

CAPTURE_SOURCE="$CAPTURE" python3 - <<'PY'
import os
from pathlib import Path

source = Path(os.environ["CAPTURE_SOURCE"]).read_text()
block = source.index("if (!forcedKeys.contains(forceKey)) {")
backoff = source.index("retryAge < const Duration(seconds: 31)", block)
unsafe_guard = source.index("if (!unsafe) {", block)
spend = source.index("forcedKeys.add(forceKey);", unsafe_guard)
force_run = source.index("'jobscheduler',\n                'run',", spend)
assert block < backoff < unsafe_guard < spend < force_run
assert "final forceKey = '$latestRetryAttempt';" in source
assert "final forceKey = '$latestRetryAttempt:$jobId';" not in source
assert "if (forcedKeys.add(forceKey)) {" not in source

unregister = source.index("await _stopRecipientAfterRouteUnregister();", source.index("recipient-route-unregister.json"))
fresh_marker = source.index("final routeAbsenceMarker =", unregister)
seed = source.index("await _sendUiMessageFromSender(routeAbsenceMarker);", fresh_marker)
probe = source.index("await _captureRouteAbsenceProbe(routeAbsenceMarker);", seed)
assert unregister < fresh_marker < seed < probe
stop_start = source.index("Future<void> _stopRecipientAfterRouteUnregister() async {")
stop_end = source.index("\n  }", stop_start)
stop_body = source[stop_start:stop_end]
stop_app = stop_body.index("'stop-app'")
absent = stop_body.index("await _waitForProcessAndActivityAbsent(recipientId);", stop_app)
assert stop_app < absent
assert "'force-stop'" not in stop_body
assert "'kill'" not in stop_body
assert "_captureRouteAbsenceProbe(secondMarker)" not in source
assert "decoded['status'] == 'failed'" in source
assert "if (receipt['status'] != 'complete')" in source
assert "Authenticated notification action $action reported" in source
PY

if rg -q "21071FDF600CSC|emulator-5554" "$RUNNER" "$CRITERIA" || \
  rg -q \
    "NotificationRecoveryCompletionReceiver|android_notification_recovery_completion_campaign_driver" \
    "$RUNNER"; then
  echo "recovery adapter retained a Plan-331 pin or nonexistent seam" >&2
  exit 1
fi

echo "PASS: TC-393-12 recovery adapter is one fixed-cohort two-transition campaign"
