#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <device-id> [--handoff] [--process-death] [--sqlcipher-queue-inversion [--expect-red]]" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 64
fi

DEVICE_ID=$1
shift
HANDOFF=false
PROCESS_DEATH=false
SQLCIPHER_QUEUE_INVERSION=false
EXPECT_RED=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --handoff) HANDOFF=true ;;
    --process-death) PROCESS_DEATH=true ;;
    --sqlcipher-queue-inversion) SQLCIPHER_QUEUE_INVERSION=true ;;
    --expect-red) EXPECT_RED=true ;;
    *) usage; exit 64 ;;
  esac
  shift
done

if [[ "$EXPECT_RED" == true && "$SQLCIPHER_QUEUE_INVERSION" != true ]]; then
  usage
  exit 64
fi

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP_ID=com.mknoon.app.h0probe
RECEIVER_CLASS=com.mknoon.app.CanonicalRuntimeH0ProbeReceiver
ACTION=com.mknoon.app.debug.CANONICAL_RUNTIME_H0_PROBE
REMOTE_RESULT=files/h0-probe/latest.json
APK_PATH="$REPO_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
PROBE_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mknoon-h0.XXXXXX")
PACKAGE_INSTALLED=false
cleanup() {
  rm -rf "$PROBE_TMP_DIR"
  if [[ "$PACKAGE_INSTALLED" == true ]]; then
    adb -s "$DEVICE_ID" uninstall "$APP_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! adb devices | awk 'NR > 1 && $2 == "device" { print $1 }' | grep -Fxq "$DEVICE_ID"; then
  echo "Android target is not connected and authorized: $DEVICE_ID" >&2
  exit 69
fi

python3 - "$REPO_ROOT" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
main = (root / "lib/main.dart").read_text(encoding="utf-8")
probe = (root / "lib/core/debug/android_canonical_runtime_h0_probe.dart").read_text(
    encoding="utf-8"
)
required_main = [
    "@pragma('vm:entry-point')",
    "androidCanonicalRuntimeH0ProbeMain",
    "runAndroidCanonicalRuntimeH0Probe(arguments)",
]
if any(value not in main for value in required_main):
    raise SystemExit("debug entrypoint is not source-locked to the H0 probe")
for forbidden in ("runApp(", "runApplicationBootstrap(", "ApplicationRoot"):
    if forbidden in probe:
        raise SystemExit(f"H0 probe may not construct the application root: {forbidden}")
PY

"$REPO_ROOT/android/gradlew" -p "$REPO_ROOT/android" :app:assembleDebug \
  -PandroidApplicationId="$APP_ID" \
  -PdisableGoogleServicesForDisposableProof=true

if [[ ! -f "$APK_PATH" ]]; then
  echo "Debug APK was not produced at $APK_PATH" >&2
  exit 66
fi

adb -s "$DEVICE_ID" uninstall "$APP_ID" >/dev/null 2>&1 || true
adb -s "$DEVICE_ID" install -t "$APK_PATH" >/dev/null
PACKAGE_INSTALLED=true
adb -s "$DEVICE_ID" shell am kill "$APP_ID" >/dev/null 2>&1 || true

# A freshly installed debug APK can spend most of Android's foreground-
# broadcast allowance extracting Flutter assets before the multi-engine H0
# fixture begins. Warm the runtime with the bounded, no-Activity queue fixture,
# then complete one canonical-database phase. The warmup process is killed
# before the measured run so Go initialization and process-death counts remain
# evidence from a fresh process. Both warmups fully tear down before reset.
prewarm_flutter_runtime() {
  local prewarm_nonce="h0-prewarm-$PPID-$RANDOM"
  local prewarm_result="$PROBE_TMP_DIR/runtime-prewarm.json"
  adb -s "$DEVICE_ID" shell run-as "$APP_ID" rm -f "$REMOTE_RESULT" \
    >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" shell am broadcast -W --receiver-foreground \
    -a "$ACTION" \
    -n "$APP_ID/$RECEIVER_CLASS" \
    --ez queueInversion true \
    --es runNonce "$prewarm_nonce" >/dev/null 2>&1 || true

  local attempt
  for attempt in $(seq 1 40); do
    if adb -s "$DEVICE_ID" exec-out run-as "$APP_ID" cat "$REMOTE_RESULT" \
      >"$prewarm_result" 2>/dev/null && \
      python3 - "$prewarm_result" "$prewarm_nonce" <<'PY'
import json
import sys

try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
census = payload.get("pluginWorkerCensus") or {}
writer_cipher = payload.get("writerCipherVersion")
reader_cipher = payload.get("readerCipherVersion")
passed = (
    payload.get("runNonce") == sys.argv[2] and
    payload.get("status") == "PASS" and
    payload.get("sentinelVerified") is True and
    payload.get("sqlCipherRuntimeIdentityVerified") is True and
    isinstance(writer_cipher, str) and writer_cipher and
    writer_cipher == reader_cipher and
    str(payload.get("writerJournalMode", "")).lower() == "delete" and
    payload.get("pluginWorkerCensusSettled") is True and
    census.get("liveInstances") == 0 and
    census.get("liveWorkers") == 0 and
    census.get("liveHandles") == 0 and
    census.get("queuedTasks") == 0 and
    census.get("runningTasks") == 0
)
raise SystemExit(0 if passed else 1)
PY
    then
      adb -s "$DEVICE_ID" shell run-as "$APP_ID" rm -f "$REMOTE_RESULT" \
        >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.2
  done
  echo "Flutter runtime prewarm did not produce a clean queue proof" >&2
  return 1
}

prewarm_canonical_database() {
  local prewarm_result="$PROBE_TMP_DIR/canonical-database-prewarm.json"
  local captured=false
  adb -s "$DEVICE_ID" shell run-as "$APP_ID" rm -f "$REMOTE_RESULT" \
    >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" shell am broadcast -W --receiver-foreground \
    -a "$ACTION" \
    -n "$APP_ID/$RECEIVER_CLASS" \
    --ez handoff false >/dev/null 2>&1 || true

  local attempt
  for attempt in $(seq 1 200); do
    if adb -s "$DEVICE_ID" exec-out run-as "$APP_ID" cat "$REMOTE_RESULT" \
      >"$prewarm_result" 2>/dev/null && \
      python3 - "$prewarm_result" <<'PY'
import json
import sys

try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
passed = (
    payload.get("status") == "PASS" and
    payload.get("mainActivityLaunchCount") == 0 and
    payload.get("applicationRootConstructed") is False and
    payload.get("goInitializeCount") == 1 and
    payload.get("maxObservedWritableDatabaseHandles") == 1 and
    payload.get("finalObservedWritableDatabaseHandles") == 0 and
    payload.get("finalLeaseState") == "RELEASED"
)
raise SystemExit(0 if passed else 1)
PY
    then
      captured=true
      break
    fi
    sleep 0.25
  done

  local warm_pid
  warm_pid=$(adb -s "$DEVICE_ID" shell pidof "$APP_ID" | tr -d '\r' || true)
  adb -s "$DEVICE_ID" shell am kill "$APP_ID" >/dev/null 2>&1 || true
  for attempt in $(seq 1 40); do
    local live_pid
    live_pid=$(adb -s "$DEVICE_ID" shell pidof "$APP_ID" | tr -d '\r' || true)
    [[ -z "$live_pid" ]] && break
    sleep 0.25
  done
  local remaining_pid
  remaining_pid=$(adb -s "$DEVICE_ID" shell pidof "$APP_ID" | tr -d '\r' || true)
  if [[ "$captured" != true || -z "$warm_pid" || -n "$remaining_pid" ]]; then
    echo "Canonical database prewarm did not pass and terminate cleanly" >&2
    return 1
  fi
  adb -s "$DEVICE_ID" shell run-as "$APP_ID" rm -f "$REMOTE_RESULT" \
    >/dev/null 2>&1 || true
}

if [[ "$SQLCIPHER_QUEUE_INVERSION" != true ]]; then
  prewarm_flutter_runtime
  prewarm_canonical_database
fi

if [[ "$SQLCIPHER_QUEUE_INVERSION" == true ]]; then
  RUN_NONCE=$(python3 -c 'import uuid; print(uuid.uuid4().hex)')
  LOCAL_RESULT="$PROBE_TMP_DIR/queue-inversion-runtime.json"
  LOCAL_LOG="$PROBE_TMP_DIR/queue-inversion-logcat.txt"
  OUTPUT_DIR="$REPO_ROOT/build/h0-probe/$DEVICE_ID"
  mkdir -p "$OUTPUT_DIR"
  adb -s "$DEVICE_ID" logcat -c >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" shell run-as "$APP_ID" rm -f "$REMOTE_RESULT" \
    >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" shell am broadcast -W --receiver-foreground \
    -a "$ACTION" \
    -n "$APP_ID/$RECEIVER_CLASS" \
    --ez queueInversion true \
    --es runNonce "$RUN_NONCE" >/dev/null 2>&1 || true

  CAPTURED=false
  for _ in $(seq 1 40); do
    if adb -s "$DEVICE_ID" exec-out run-as "$APP_ID" cat "$REMOTE_RESULT" \
      >"$LOCAL_RESULT" 2>/dev/null && \
      python3 - "$LOCAL_RESULT" "$RUN_NONCE" <<'PY'
import json
import sys

try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if payload.get("runNonce") == sys.argv[2] and
                 payload.get("status") in {"EXPECTED_RED", "PASS", "FAIL"}
                 else 1)
PY
    then
      CAPTURED=true
      break
    fi
    sleep 0.2
  done
  adb -s "$DEVICE_ID" logcat -d -v threadtime >"$LOCAL_LOG" 2>/dev/null || true

  ACTIVITY_RECORD_COUNT=$(adb -s "$DEVICE_ID" shell dumpsys activity activities | \
    awk -v target="$APP_ID/" \
      'index($0, target) && index($0, "ActivityRecord") { count += 1 } END { print count + 0 }')
  DEVICE_FINGERPRINT=$(adb -s "$DEVICE_ID" shell getprop ro.build.fingerprint | tr -d '\r')
  HOST_ARTIFACT=$(python3 - "$REPO_ROOT" "$APK_PATH" "$DEVICE_ID" \
    "$DEVICE_FINGERPRINT" "$RUN_NONCE" "$CAPTURED" "$LOCAL_RESULT" \
    "$LOCAL_LOG" "$OUTPUT_DIR" "$ACTIVITY_RECORD_COUNT" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
apk = pathlib.Path(sys.argv[2])
device_id = sys.argv[3]
fingerprint = sys.argv[4]
nonce = sys.argv[5]
captured = sys.argv[6] == "true"
runtime_path = pathlib.Path(sys.argv[7])
log_path = pathlib.Path(sys.argv[8])
output_dir = pathlib.Path(sys.argv[9])
activity_count = int(sys.argv[10])

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()

source_roots = [
    root / "android/app/src/debug",
    root / "android/app/src/test/kotlin/com/mknoon/app/CanonicalRuntimeH0ProbeSourceTest.kt",
    root / "lib/core/debug/android_canonical_runtime_h0_probe.dart",
    root / "lib/core/database/encrypted_db_opener.dart",
    root / "lib/core/notifications/bounded_posix_flock.dart",
    root / "lib/core/notifications/durable_conversation_notification_id_registry.dart",
    root / "lib/core/notifications/durable_notification_tone_lease.dart",
    root / "lib/features/push/application/background_message_handler.dart",
    root / "lib/features/push/application/background_storage_liveness_journal.dart",
    root / "lib/features/push/application/pending_conversation_notification_overlay.dart",
    root / "lib/main.dart",
    root / "scripts/run_android_canonical_runtime_h0_probe.sh",
    root / "third_party/sqflite_sqlcipher",
    root / "pubspec.yaml",
    root / "pubspec.lock",
]
files = []
for source_root in source_roots:
    if source_root.is_file():
        files.append(source_root)
    elif source_root.is_dir():
        files.extend(path for path in source_root.rglob("*") if path.is_file())
source_hash = hashlib.sha256()
for path in sorted(set(files)):
    source_hash.update(str(path.relative_to(root)).encode())
    source_hash.update(b"\0")
    source_hash.update(path.read_bytes())

runtime = None
capture_error = None
if captured:
    try:
        runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        capture_error = f"invalid terminal runtime artifact: {error}"
else:
    capture_error = "device did not publish a nonce-bound terminal artifact within 8 seconds"
artifact = {
    "schema": "mknoon.android.sqlcipher-queue-inversion.artifact.v1",
    "status": "CAPTURED" if runtime is not None else "CAPTURE_FAILED",
    "verdict": "UNVALIDATED",
    "runNonce": nonce,
    "deviceId": device_id,
    "sourceDigest": source_hash.hexdigest(),
    "apkDigest": digest(apk),
    "deviceDigest": hashlib.sha256(fingerprint.encode()).hexdigest(),
    "logcatDigest": digest(log_path),
    "adbActivityRecordCount": activity_count,
    "runtime": runtime,
    "captureError": capture_error,
    "cleanup": {"performed": False, "pidGone": False, "packageGone": False},
}
destination = output_dir / f"queue-inversion-{nonce}.json"
destination.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
log_destination = output_dir / f"queue-inversion-{nonce}.logcat.txt"
log_destination.write_bytes(log_path.read_bytes())
print(destination)
PY
  )

  adb -s "$DEVICE_ID" shell am kill "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" uninstall "$APP_ID" >/dev/null 2>&1 || true
  PACKAGE_INSTALLED=false
  for _ in $(seq 1 20); do
    LIVE_PID=$(adb -s "$DEVICE_ID" shell pidof "$APP_ID" | tr -d '\r' || true)
    [[ -z "$LIVE_PID" ]] && break
    sleep 0.1
  done
  LIVE_PID=$(adb -s "$DEVICE_ID" shell pidof "$APP_ID" | tr -d '\r' || true)
  PACKAGE_PATH=$(adb -s "$DEVICE_ID" shell pm path "$APP_ID" | tr -d '\r' || true)
  PID_GONE=false
  PACKAGE_GONE=false
  [[ -z "$LIVE_PID" ]] && PID_GONE=true
  [[ -z "$PACKAGE_PATH" ]] && PACKAGE_GONE=true

  python3 - "$HOST_ARTIFACT" "$EXPECT_RED" "$PID_GONE" "$PACKAGE_GONE" <<'PY'
import hashlib
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expect_red = sys.argv[2] == "true"
pid_gone = sys.argv[3] == "true"
package_gone = sys.argv[4] == "true"
artifact = json.loads(path.read_text(encoding="utf-8"))
runtime = artifact.get("runtime") or {}
phases = runtime.get("phases") or []
lifecycle = runtime.get("orderedLifecycleTransitions") or []
writer_cipher = runtime.get("writerCipherVersion")
reader_cipher = runtime.get("readerCipherVersion")
prefix = [
    "writer.database_opened",
    "reader.database_opened",
    "writer.begin_exclusive",
    "reader.query_posted",
    "writer.resume_requested",
]
common_ok = (
    runtime.get("runNonce") == artifact.get("runNonce") and
    phases[:len(prefix)] == prefix and
    isinstance(runtime.get("elapsedMs"), int) and
    runtime.get("elapsedMs") <= 8000 and
    runtime.get("storageAggregateDeadlineMs") == 8000 and
    runtime.get("storagePhaseDeadlineMs") == 2000 and
    runtime.get("encryptedReadOnlyOpenDeadlineMs") == 2000 and
    runtime.get("encryptedReadOnlyBusyTimeoutMs") == 1000 and
    runtime.get("androidFlockAcquisitionMs") == 1000 and
    runtime.get("journalMaxCallerImpactMs") == 200 and
    runtime.get("sqlCipherRuntimeIdentityVerified") is True and
    isinstance(writer_cipher, str) and bool(writer_cipher) and
    writer_cipher == reader_cipher and
    str(runtime.get("writerJournalMode", "")).lower() == "delete" and
    runtime.get("peakLiveEngineCount", 0) >= 2 and
    runtime.get("peakLivePluginWorkerCount", 0) >= 1 and
    runtime.get("peakLivePluginHandleCount", 0) >= 2 and
    runtime.get("applicationRootConstructed") is False and
    runtime.get("applicationRootConstructionCount") == 0 and
    lifecycle[:2] == ["writer.database_opened", "reader.database_opened"] and
    artifact.get("adbActivityRecordCount") == 0 and
    pid_gone and package_gone
)
if expect_red:
    semantic_ok = (
        runtime.get("status") == "EXPECTED_RED" and
        runtime.get("watchdogFired") is True and
        runtime.get("writerCommit") is False and
        runtime.get("readerQueryResult") is False
    )
    expected = "EXPECTED_RED"
else:
    census = runtime.get("pluginWorkerCensus") or {}
    lifecycle_closes = lifecycle[2:4]
    expected_lifecycle_tail = [
        "writer.engine_destroyed",
        "reader.engine_destroyed",
        "sentinel.database_opened",
        "sentinel.closed",
        "sentinel.engine_destroyed",
    ]
    semantic_ok = (
        runtime.get("status") == "PASS" and
        runtime.get("watchdogFired") is False and
        runtime.get("writerCommit") is True and
        runtime.get("readerQueryResult") is True and
        runtime.get("sentinelVerified") is True and
        runtime.get("enginesDestroyed") is True and
        runtime.get("pluginWorkerCountAvailable") is True and
        runtime.get("pluginWorkerCensusSettled") is True and
        runtime.get("peakLivePluginWorkerCount", 0) >= 2 and
        set(lifecycle_closes) == {"writer.closed", "reader.closed"} and
        len(lifecycle_closes) == 2 and
        lifecycle[4:] == expected_lifecycle_tail and
        runtime.get("livePluginWorkerCount") == 0 and
        census.get("liveInstances") == 0 and
        census.get("liveWorkers") == 0 and
        census.get("liveHandles") == 0 and
        census.get("queuedTasks") == 0 and
        census.get("runningTasks") == 0 and
        isinstance(census.get("terminatedInstances"), int) and
        census.get("terminatedInstances") >= 3
    )
    expected = "PASS"
passed = common_ok and semantic_ok
artifact["cleanup"] = {
    "performed": True,
    "pidGone": pid_gone,
    "packageGone": package_gone,
}
artifact["status"] = "PASS" if passed else "FAIL"
artifact["verdict"] = expected if passed else "INVALID"
unsigned = json.dumps(artifact, sort_keys=True, separators=(",", ":"))
artifact["contentDigest"] = hashlib.sha256(unsigned.encode()).hexdigest()
path.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if not passed:
    raise SystemExit(
        f"queue-inversion evidence invalid for {expected}: "
        f"status={runtime.get('status')} phases={phases} cleanup={artifact['cleanup']}"
    )
print(path)
PY
  exit 0
fi

RUN_FILES=()
run_probe() {
  local label=$1
  local local_result="$PROBE_TMP_DIR/runtime-$label.json"
  local captured=false
  adb -s "$DEVICE_ID" shell run-as "$APP_ID" rm -f "$REMOTE_RESULT" \
    >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" shell am broadcast -W --receiver-foreground \
    -a "$ACTION" \
    -n "$APP_ID/$RECEIVER_CLASS" \
    --ez handoff "$HANDOFF" >/dev/null

  local attempt
  for attempt in $(seq 1 120); do
    if adb -s "$DEVICE_ID" exec-out run-as "$APP_ID" cat "$REMOTE_RESULT" \
      >"$local_result" 2>/dev/null && \
      python3 - "$local_result" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if payload.get("status") in {"PASS", "FAIL"} else 1)
PY
    then
      captured=true
      break
    fi
    sleep 0.25
  done
  if [[ "$captured" != true ]]; then
    echo "H0 probe did not produce a complete result for $label" >&2
    return 1
  fi

  local activity_record_count
  activity_record_count=$(adb -s "$DEVICE_ID" shell dumpsys activity activities | \
    awk -v target="$APP_ID/" \
      'index($0, target) && index($0, "ActivityRecord") { count += 1 } END { print count + 0 }')
  if [[ "$activity_record_count" != 0 ]]; then
    echo "H0 probe launched an Activity according to dumpsys: $activity_record_count" >&2
    exit 1
  fi
  python3 - "$local_result" "$activity_record_count" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["adbActivityRecordCount"] = int(sys.argv[2])
path.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")), encoding="utf-8")
PY

  python3 - "$local_result" "$HANDOFF" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
handoff = sys.argv[2] == "true"
required = {
    "status": "PASS",
    "mainActivityLaunchCount": 0,
    "applicationRootConstructed": False,
    "adbActivityRecordCount": 0,
    "goInitializeCount": 1,
    "maxWritableDatabaseOwners": 1,
    "maxObservedWritableDatabaseHandles": 1,
    "finalObservedWritableDatabaseHandles": 0,
    "staleCallbackDeliveries": 0,
    "staleResultDeliveries": 0,
    "finalLeaseState": "RELEASED",
    "recoveryWorkActivated": False,
}
bad = {key: (payload.get(key), expected) for key, expected in required.items()
       if payload.get(key) != expected}
if bad:
    raise SystemExit(f"H0 invariant failure: {bad}")
generations = payload.get("observedWritableGenerations", [])
expected_phases = 2 if handoff else 1
if len(generations) != expected_phases or any(
    after <= before for before, after in zip(generations, generations[1:])
):
    raise SystemExit(f"invalid writable generation transfer: {generations}")
if handoff:
    handoff_required = {
        "activeContentionPassed": True,
        "closeFailureRetentionPassed": True,
        "admittedGoJniWorkHeld": True,
        "admittedGoJniWorkSettled": True,
        "flutterFireReadOnlyPeerPassed": True,
        "threeEngineConcurrencyObserved": True,
        "maxObservedReadOnlyDatabaseHandles": 1,
        "finalReadOnlyDatabaseHandles": 0,
    }
    bad_handoff = {
        key: (payload.get(key), expected)
        for key, expected in handoff_required.items()
        if payload.get(key) != expected
    }
    if bad_handoff:
        raise SystemExit(f"H0 handoff invariant failure: {bad_handoff}")
    contentions = payload.get("contentions", [])
    if [item.get("kind") for item in contentions] != ["active", "close-failure"]:
        raise SystemExit(f"missing exact contention legs: {contentions}")
    for item in contentions:
        dart = item.get("dart", {})
        if not item.get("verified") or not dart.get("leaseRejected"):
            raise SystemExit(f"contender was not fenced: {item}")
        if dart.get("databaseOpened") is not False:
            raise SystemExit(f"contender opened a writable database: {item}")
for phase in payload.get("phases", []):
    trace = phase.get("dart", {}).get("trace", [])
    ordered = [
        "lease.acquire",
        "database.opened",
        "runtime.attach",
        "lease.begin_drain",
        "runtime.quiesce",
        "database.close.done",
        "lease.release:true",
    ]
    positions = [trace.index(item) if item in trace else -1 for item in ordered]
    if -1 in positions or positions != sorted(positions):
        raise SystemExit(f"invalid H0 phase order: {trace}")
PY
  RUN_FILES+=("$local_result")
}

run_probe initial

if [[ "$PROCESS_DEATH" == true ]]; then
  FIRST_PID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "${RUN_FILES[0]}")
  adb -s "$DEVICE_ID" shell am kill "$APP_ID" >/dev/null
  for _ in $(seq 1 40); do
    CURRENT_PID=$(adb -s "$DEVICE_ID" shell pidof "$APP_ID" | tr -d '\r' || true)
    [[ -z "$CURRENT_PID" ]] && break
    sleep 0.25
  done
  run_probe after-process-death
  SECOND_PID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "${RUN_FILES[1]}")
  if [[ "$FIRST_PID" == "$SECOND_PID" ]]; then
    echo "Process-death leg reused PID $FIRST_PID" >&2
    exit 1
  fi
fi

DEVICE_FINGERPRINT=$(adb -s "$DEVICE_ID" shell getprop ro.build.fingerprint | tr -d '\r')
OUTPUT_DIR="$REPO_ROOT/build/h0-probe/$DEVICE_ID"
mkdir -p "$OUTPUT_DIR"
python3 - "$REPO_ROOT" "$APK_PATH" "$DEVICE_ID" "$DEVICE_FINGERPRINT" \
  "$HANDOFF" "$PROCESS_DEATH" "$OUTPUT_DIR" "${RUN_FILES[@]}" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
apk = pathlib.Path(sys.argv[2])
device_id = sys.argv[3]
fingerprint = sys.argv[4]
handoff = sys.argv[5] == "true"
process_death = sys.argv[6] == "true"
output_dir = pathlib.Path(sys.argv[7])
run_files = [pathlib.Path(value) for value in sys.argv[8:]]

source_roots = [
    root / "android/app/src/main/kotlin/com/mknoon/app",
    root / "android/app/src/debug",
    root / "lib/core/debug",
    root / "lib/core/database/encrypted_db_opener.dart",
    root / "lib/core/notifications",
    root / "lib/features/push/application/background_message_handler.dart",
    root / "lib/features/push/application/background_storage_liveness_journal.dart",
    root / "lib/features/push/application/pending_conversation_notification_overlay.dart",
    root / "lib/main.dart",
    root / "scripts/run_android_canonical_runtime_h0_probe.sh",
]
source_hash = hashlib.sha256()
files = []
for source_root in source_roots:
    if source_root.is_file():
        files.append(source_root)
    elif source_root.is_dir():
        files.extend(path for path in source_root.rglob("*") if path.is_file())
for path in sorted(files):
    source_hash.update(str(path.relative_to(root)).encode())
    source_hash.update(b"\0")
    source_hash.update(path.read_bytes())

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()

runs = [json.loads(path.read_text(encoding="utf-8")) for path in run_files]
artifact = {
    "schema": "mknoon.android.canonical-runtime-h0.artifact.v1",
    "status": "PASS" if all(run.get("status") == "PASS" for run in runs) else "FAIL",
    "deviceId": device_id,
    "sourceDigest": source_hash.hexdigest(),
    "apkDigest": digest(apk),
    "deviceDigest": hashlib.sha256(fingerprint.encode()).hexdigest(),
    "handoff": handoff,
    "processDeath": process_death,
    "runtimePrewarm": "queue_inversion_then_canonical_phase_pass_process_killed",
    "runs": runs,
}
rendered = json.dumps(artifact, sort_keys=True, separators=(",", ":"))
content_digest = hashlib.sha256(rendered.encode()).hexdigest()
artifact["contentDigest"] = content_digest
destination = output_dir / f"{content_digest}.json"
destination.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(destination)
PY
