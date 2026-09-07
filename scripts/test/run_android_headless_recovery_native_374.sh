#!/usr/bin/env bash

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GRADLEW="$REPO_ROOT/android/gradlew"
readonly JVM_RESULTS="$REPO_ROOT/build/app/test-results/testDebugUnitTest"
readonly MERGED_MANIFEST="$REPO_ROOT/build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml"

readonly -a SELECTED_CLASSES=(
  com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test
  com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest
  com.mknoon.app.DroppedPushRecoveryStoreTest
  com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest
  com.mknoon.app.CanonicalRuntimeLeaseTest
  com.mknoon.app.GoRuntimeHostTest
  com.mknoon.app.MknoonFirebaseMessagingServiceTest
  com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest
  com.mknoon.app.NativeRuntimeOwnershipSourceTest
)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

run_logged() {
  local label="$1"
  local log="$2"
  shift 2
  printf 'Running %s\n' "$label"
  if ! "$@" >"$log" 2>&1; then
    tail -n 180 "$log" >&2 || true
    fail "$label failed; full log retained at $log"
  fi
}

for command_name in cp python3 rg rm tail; do
  require_command "$command_name"
done
[[ -x "$GRADLEW" ]] || fail "Gradle wrapper is not executable: $GRADLEW"
[[ "${#SELECTED_CLASSES[@]}" -eq 9 ]] ||
  fail "the frozen native class selection must contain exactly nine classes"
[[ "$(printf '%s\n' "${SELECTED_CLASSES[@]}" | sort -u | wc -l | tr -d '[:space:]')" -eq 9 ]] ||
  fail "the frozen native class selection contains a duplicate"

if [[ -n "${PLAN374_NATIVE_RESULT_DIR:-}" ]]; then
  result_dir="$PLAN374_NATIVE_RESULT_DIR"
  mkdir -p "$result_dir"
else
  result_dir="$(mktemp -d /tmp/plan374-native.XXXXXX)"
fi
result_dir="$(cd "$result_dir" && pwd)"
readonly RESULT_DIR="$result_dir"
readonly JVM_LOG="$RESULT_DIR/android-jvm.log"
readonly COMPILE_LOG="$RESULT_DIR/android-compile-manifest.log"
readonly OBSERVED_MANIFEST="$RESULT_DIR/android-junit-method-manifest.txt"

# Gradle's filtered task may leave output from a prior interrupted selector.
# Remove only this frozen class set, then later parse only those exact paths.
mkdir -p "$JVM_RESULTS"
for class_name in "${SELECTED_CLASSES[@]}"; do
  rm -f "$JVM_RESULTS/TEST-$class_name.xml"
done

gradle_test_args=(
  -p "$REPO_ROOT/android"
  --console=plain
  :app:testDebugUnitTest
)
for class_name in "${SELECTED_CLASSES[@]}"; do
  gradle_test_args+=(--tests "$class_name")
done

run_logged \
  "the exact nine-class Plan 374 JVM suite" \
  "$JVM_LOG" \
  "$GRADLEW" "${gradle_test_args[@]}"
rg -Fq 'BUILD SUCCESSFUL' "$JVM_LOG" ||
  fail "the exact nine-class Gradle invocation did not report BUILD SUCCESSFUL"
[[ -d "$JVM_RESULTS" ]] || fail "JUnit result directory is missing: $JVM_RESULTS"

python3 - "$JVM_RESULTS" "${SELECTED_CLASSES[@]}" <<'PY' >"$OBSERVED_MANIFEST"
from collections import Counter
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

result_dir = Path(sys.argv[1])
selected_classes = sys.argv[2:]
expected_text = r"""
com.mknoon.app.DroppedPushRecoveryStoreTest|testTC37502FixedAndDeletedTriggersShareOneCrashSafeAudibleDisposition
com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest|testTC37503FixedWakeUsesExistingUniqueExpeditedChain
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|testTC37503WorkerAdoptsCurrentTriggerAcrossRetryProcessDeathAndPeriodicContinuation
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|immediate retry re-signals the warm owner with the authoritative generation
com.mknoon.app.MknoonFirebaseMessagingServiceTest|testTC37501ExactFixedWakeInterceptsAndAllOtherShapesDelegateOnce
com.mknoon.app.MknoonFirebaseMessagingServiceTest|VC2-04 call wake has a separate strict ingress and never enters ordinary recovery
com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test|TC-375-06 native read back advertises exact fixed consumer version kind and disposition
com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest|ADB script pins a device and supports handoff and process death
com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest|TC-393 arm-only fixed wake phase cannot inject production ingress
com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest|Dart entrypoint opens only through lease and cannot drain or acknowledge recovery
com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest|debug receiver is no Activity and uses an explicit minimal plugin allowlist
com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest|queue artifact timeout literals stay bound to Dart production constants
com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest|queue inversion receiver fixes the causal order and preserves RED before cleanup
com.mknoon.app.CanonicalRuntimeLeaseTest|active owner can rotate opaque account binding without opening a second writer
com.mknoon.app.CanonicalRuntimeLeaseTest|close failure retry accepts an already quiesced Go runtime
com.mknoon.app.CanonicalRuntimeLeaseTest|database close fences transfer and close failure retains owner
com.mknoon.app.CanonicalRuntimeLeaseTest|foreground worker and fcm ownership matrix permits one writable owner
com.mknoon.app.CanonicalRuntimeLeaseTest|method channel binds owner identity and requires explicit close acknowledgement
com.mknoon.app.DroppedPushRecoveryStoreTest|TC-374-05 binding publication toggles recovery work only for exact committed binding
com.mknoon.app.DroppedPushRecoveryStoreTest|binding rotation durably retires malformed orphan marker keys
com.mknoon.app.DroppedPushRecoveryStoreTest|binding rotation retires stale generation and prevents cross account acknowledgement
com.mknoon.app.DroppedPushRecoveryStoreTest|concurrent writers allocate unique generations and publish the newest pending value
com.mknoon.app.DroppedPushRecoveryStoreTest|deletion without a current binding cannot create an unowned marker
com.mknoon.app.DroppedPushRecoveryStoreTest|notification attempt observes committed marker and remains serialized with acknowledgement
com.mknoon.app.DroppedPushRecoveryStoreTest|read is non-consuming and matching acknowledgement retains monotonic last generation
com.mknoon.app.DroppedPushRecoveryStoreTest|stale acknowledgement cannot clear a newer generation or cancel its card
com.mknoon.app.DroppedPushRecoveryStoreTest|stale-card reconciliation runs only without a pending generation
com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest|deleted batch commits then enqueues unique connected work
com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest|enabling same binding with marker enqueues immediate and periodic exactly once
com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest|expedited work has data sync foreground contract on API 30
com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest|expedited work has pre Android 12 foreground contract on API 24
com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest|generation arriving during active work is resnapshotted
com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest|periodic sweep is unique bounded and account gated
com.mknoon.app.GoRuntimeHostTest|Initialize does not hold the ownership monitor across JNI
com.mknoon.app.GoRuntimeHostTest|callback and owner event arriving after drain are rejected
com.mknoon.app.GoRuntimeHostTest|dispose cannot leak engine callback or result
com.mknoon.app.GoRuntimeHostTest|draining fences late call result and callback
com.mknoon.app.GoRuntimeHostTest|failed StopNode retains draining ownership
com.mknoon.app.GoRuntimeHostTest|one initialization and active owner admission
com.mknoon.app.GoRuntimeHostTest|stop waits for start
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|Dart close release flags cannot destroy while either native owner is active
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|account cutover accepts only an explicitly stale safely released result
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|completion protocol rejects forged and late run identities exactly once
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|disabled stale or malformed wake exits without constructing an engine
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|engine exception and cleanup exception both remain retry
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|exact current generation succeeds only after close release and final resnapshot
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|newer generation surviving stale completion retries instead of reporting success
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|periodic success retries when a marker arrives and never consumes it
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|stop only signals while execute finally performs cleanup
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|success without database close or lease release is retry
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|timeout signals cooperative stop and finally owns cleanup
com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest|worker source keeps engine lifecycle on main with explicit plugin allowlist
com.mknoon.app.MknoonFirebaseMessagingServiceTest|API 33 denied notification permission still persists generation and creates channel
com.mknoon.app.MknoonFirebaseMessagingServiceTest|denied notification permission still schedules after committed bound marker
com.mknoon.app.MknoonFirebaseMessagingServiceTest|disabled recovery readiness records marker without scheduling work
com.mknoon.app.MknoonFirebaseMessagingServiceTest|matching acknowledgement alone clears marker and exact reserved card
com.mknoon.app.MknoonFirebaseMessagingServiceTest|real deletion override creates reserved channel and coalesces reserved card on API 26
com.mknoon.app.MknoonFirebaseMessagingServiceTest|real deletion override persists before posting without creating a channel on API 24
com.mknoon.app.MknoonFirebaseMessagingServiceTest|recovery card uses Arabic resources
com.mknoon.app.MknoonFirebaseMessagingServiceTest|recovery copy follows locale and refreshes existing channel
com.mknoon.app.MknoonFirebaseMessagingServiceTest|unsupported locale falls back to complete default recovery resources
com.mknoon.app.NativeRuntimeOwnershipSourceTest|GoBridge uses process host and deterministic detach instead of per engine initialize
com.mknoon.app.NativeRuntimeOwnershipSourceTest|MainActivity retains the engine for Dart DB close acknowledgement
com.mknoon.app.NativeRuntimeOwnershipSourceTest|production Dart shutdown quiesces Go closes DB and releases through one handshake
com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test|TC-374-05 account rotation retires old marker instead of operational rollback preservation
com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test|TC-374-05 same binding rollback preserves marker and atomically fences late headless ACK
com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test|TC-374-05 typed readiness requires and echoes exact binding and enabled bit
com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test|TC-374-08 Firebase deletion override delegates to the one production seam
com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test|TC-374-08 default off shared seam stays serialized with acknowledgement without scheduling
com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test|TC-374-08 shared deleted batch seam commits resnapshots and schedules before caller work
"""
expected = [line for line in expected_text.strip().splitlines() if line]
if len(expected) != 70 or len(set(expected)) != 70:
    raise SystemExit(
        "the frozen Plan 374/375/393 JUnit manifest must contain 70 unique methods"
    )

xml_files = [result_dir / f"TEST-{name}.xml" for name in selected_classes]
missing_xml = [str(path) for path in xml_files if not path.is_file()]
if missing_xml:
    raise SystemExit(f"selected JUnit XML files are missing: {missing_xml!r}")
if len(xml_files) != 9:
    raise SystemExit(f"expected exactly nine selected JUnit XML files, got {len(xml_files)}")
observed = []
for path in xml_files:
    root = ET.parse(path).getroot()
    for key in ("failures", "errors", "skipped"):
        if int(root.attrib.get(key, "0")) != 0:
            raise SystemExit(f"{path} reports non-zero {key}")
    for case in root.findall(".//testcase"):
        if any(case.find(tag) is not None for tag in ("failure", "error", "skipped")):
            raise SystemExit(f"{path} contains a non-passing testcase")
        observed.append(f"{case.attrib.get('classname', '')}|{case.attrib.get('name', '')}")

if Counter(observed) != Counter(expected):
    missing = sorted((Counter(expected) - Counter(observed)).elements())
    extra = sorted((Counter(observed) - Counter(expected)).elements())
    raise SystemExit(
        "JUnit method manifest drifted; "
        f"missing={missing!r}, extra_or_duplicate={extra!r}"
    )
expected_classes = {
    "com.mknoon.app.ProductionHeadlessCanonicalRecovery374Test",
    "com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest",
    "com.mknoon.app.DroppedPushRecoveryStoreTest",
    "com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest",
    "com.mknoon.app.CanonicalRuntimeLeaseTest",
    "com.mknoon.app.GoRuntimeHostTest",
    "com.mknoon.app.MknoonFirebaseMessagingServiceTest",
    "com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest",
    "com.mknoon.app.NativeRuntimeOwnershipSourceTest",
}
observed_classes = {row.split("|", 1)[0] for row in observed}
if observed_classes != expected_classes:
    raise SystemExit(
        f"expected exact nine-class set, observed {sorted(observed_classes)!r}"
    )
for row in sorted(observed):
    print(row)
PY

[[ "$(wc -l <"$OBSERVED_MANIFEST" | tr -d '[:space:]')" -eq 70 ]] ||
  fail "the parsed JUnit method manifest did not contain exactly 70 methods"
[[ "$(rg -c '\|TC-374-(05|08) ' "$OBSERVED_MANIFEST")" -eq 7 ]] ||
  fail "the seven planned native TC-374 methods were not observed exactly once"
[[ "$(rg -c '\|(testTC375|TC-375-)' "$OBSERVED_MANIFEST")" -eq 5 ]] ||
  fail "the five planned native TC-375 methods were not observed exactly once"
[[ "$(rg -F -c '|TC-393 arm-only fixed wake phase cannot inject production ingress' "$OBSERVED_MANIFEST")" -eq 1 ]] ||
  fail "the Plan 393 arm-only native source sentinel was not observed exactly once"
mkdir -p "$RESULT_DIR/android-junit-results"
for class_name in "${SELECTED_CLASSES[@]}"; do
  cp "$JVM_RESULTS/TEST-$class_name.xml" "$RESULT_DIR/android-junit-results/"
done

run_logged \
  "Plan 374 production/test Kotlin and merged-manifest compilation" \
  "$COMPILE_LOG" \
  "$GRADLEW" -p "$REPO_ROOT/android" --console=plain \
    :app:compileDebugKotlin \
    :app:compileDebugUnitTestKotlin \
    :app:processDebugMainManifest
rg -Fq 'BUILD SUCCESSFUL' "$COMPILE_LOG" ||
  fail "the Plan 374 compile/manifest invocation did not report BUILD SUCCESSFUL"
[[ -s "$MERGED_MANIFEST" ]] ||
  fail "merged debug manifest is missing or empty: $MERGED_MANIFEST"

python3 - "$MERGED_MANIFEST" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1])
root = ET.parse(path).getroot()
android = "{http://schemas.android.com/apk/res/android}"
application = root.find("application")
if application is None:
    raise SystemExit("merged manifest has no application")

services = [
    node for node in application.findall("service")
    if node.attrib.get(android + "name") == "com.mknoon.app.MknoonFirebaseMessagingService"
]
if len(services) != 1:
    raise SystemExit(f"expected one Mknoon Firebase service, found {len(services)}")
service = services[0]
if service.attrib.get(android + "exported") != "false":
    raise SystemExit("Mknoon Firebase service must remain non-exported")
actions = {
    action.attrib.get(android + "name")
    for action in service.findall("./intent-filter/action")
}
if actions != {"com.google.firebase.MESSAGING_EVENT"}:
    raise SystemExit(f"Firebase service action drifted: {sorted(actions)!r}")

c2dm_receivers = [
    node for node in application.findall("receiver")
    if node.attrib.get(android + "name") == "com.mknoon.app.MknoonFirebaseMessagingReceiver"
]
if len(c2dm_receivers) != 1:
    raise SystemExit(f"expected one Mknoon C2DM receiver, found {len(c2dm_receivers)}")
c2dm_receiver = c2dm_receivers[0]
if c2dm_receiver.attrib.get(android + "exported") != "true":
    raise SystemExit("Mknoon C2DM receiver must remain exported")
if c2dm_receiver.attrib.get(android + "permission") != "com.google.android.c2dm.permission.SEND":
    raise SystemExit("Mknoon C2DM receiver lost its sender permission fence")
c2dm_actions = {
    action.attrib.get(android + "name")
    for action in c2dm_receiver.findall("./intent-filter/action")
}
if c2dm_actions != {"com.google.android.c2dm.intent.RECEIVE"}:
    raise SystemExit(f"Mknoon C2DM receiver action drifted: {sorted(c2dm_actions)!r}")
if any(
    node.attrib.get(android + "name") ==
    "io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver"
    for node in application.findall("receiver")
):
    raise SystemExit("FlutterFire C2DM receiver bypass was reintroduced")

receivers = [
    node for node in application.findall("receiver")
    if node.attrib.get(android + "name") == "com.mknoon.app.CanonicalRuntimeH0ProbeReceiver"
]
if len(receivers) != 1:
    raise SystemExit(f"expected one debug H0 receiver, found {len(receivers)}")
receiver = receivers[0]
if receiver.attrib.get(android + "permission") != "android.permission.DUMP":
    raise SystemExit("debug H0 receiver lost its DUMP permission fence")
if receiver.attrib.get(android + "exported") != "true":
    raise SystemExit("debug H0 receiver must remain explicitly exported for adb")
PY

readonly SERVICE_SOURCE="$REPO_ROOT/android/app/src/main/kotlin/com/mknoon/app/MknoonFirebaseMessagingService.kt"
readonly RECEIVER_SOURCE="$REPO_ROOT/android/app/src/main/kotlin/com/mknoon/app/MknoonFirebaseMessagingReceiver.kt"
readonly SEAM_SOURCE="$REPO_ROOT/android/app/src/main/kotlin/com/mknoon/app/ProductionDeletedBatchRecovery.kt"
readonly STORE_SOURCE="$REPO_ROOT/android/app/src/main/kotlin/com/mknoon/app/DroppedPushRecoveryStore.kt"
readonly BRIDGE_SOURCE="$REPO_ROOT/android/app/src/main/kotlin/com/mknoon/app/DroppedPushRecoveryBridge.kt"

[[ "$(rg -F -c 'ProductionDeletedBatchRecovery(' "$SERVICE_SOURCE")" -eq 1 ]] ||
  fail "Firebase service must construct the one production recovery seam"
[[ "$(rg -F -c '.recordGenericRecoveryTrigger(' "$SERVICE_SOURCE")" -eq 2 ]] ||
  fail "deletion and fixed ingress must both use the one generic trigger seam"
! rg -Fq '.recordDeletion' "$SERVICE_SOURCE" ||
  fail "Firebase service bypasses the shared production recovery seam"
! rg -Fq '.recordFixedWake' "$SERVICE_SOURCE" ||
  fail "Firebase service bypasses the shared production recovery seam"
[[ "$(rg -F -c 'override fun onMessageReceived(' "$SERVICE_SOURCE")" -eq 1 ]] ||
  fail "Firebase service must own exactly one fixed-wake classifier override"
[[ "$(rg -F -c 'super.onMessageReceived(message)' "$SERVICE_SOURCE")" -eq 1 ]] ||
  fail "exactly one FlutterFire delegation seam may call super"
[[ "$(rg -F -c 'fun isExactFixedOpaqueWake(' "$SERVICE_SOURCE")" -eq 1 ]] ||
  fail "the exact fixed classifier must exist exactly once"
[[ "$(rg -F -c 'MknoonFirebaseMessagingService.isExactFixedOpaqueWake(' "$RECEIVER_SOURCE")" -eq 1 ]] ||
  fail "the C2DM receiver must share the exact fixed classifier"
[[ "$(rg -F -c 'super.onReceive(context, intent)' "$RECEIVER_SOURCE")" -eq 1 ]] ||
  fail "the C2DM receiver must retain exactly one FlutterFire rich delegation seam"
[[ "$(rg -F -c 'store.recordDeletion { generation ->' "$SEAM_SOURCE")" -eq 1 ]] ||
  fail "production seam must own one deleted-batch store transaction"
[[ "$(rg -F -c 'store.recordFixedWake { generation ->' "$SEAM_SOURCE")" -eq 1 ]] ||
  fail "production seam must own one fixed-wake store transaction"
[[ "$(rg -F -c 'DroppedPushRecoveryWorkScheduler(context)' "$SEAM_SOURCE")" -eq 1 ]] ||
  fail "production seam must construct the incumbent scheduler exactly once"
[[ "$(rg -F -c 'scheduler::enqueueDeletedBatch' "$SEAM_SOURCE")" -eq 1 ]] ||
  fail "production seam must delegate deletions to the incumbent chain"
[[ "$(rg -F -c 'scheduler::enqueueFixedWake' "$SEAM_SOURCE")" -eq 1 ]] ||
  fail "production seam must delegate fixed wakes to the incumbent chain"
[[ "$(rg -F -c 'fun recoveryAuthority()' "$STORE_SOURCE")" -eq 1 ]] ||
  fail "store must expose one atomic read-only recovery authority snapshot"
[[ "$(rg -F -c 'fun acknowledgeHeadlessRecovery(' "$STORE_SOURCE")" -eq 1 ]] ||
  fail "store must expose one readiness-fenced headless acknowledgement"
[[ "$(rg -F -c '"recoveryAuthority" ->' "$BRIDGE_SOURCE")" -eq 1 ]] ||
  fail "native bridge must expose one recoveryAuthority method"
[[ "$(rg -F -c '"headlessAcknowledgeRecovery" ->' "$BRIDGE_SOURCE")" -eq 1 ]] ||
  fail "native bridge must expose one headless acknowledgement method"

printf 'PASS: Plan 374/375/393 Android native suite selected 9 classes / 70 methods; artifacts: %s\n' \
  "$RESULT_DIR"
