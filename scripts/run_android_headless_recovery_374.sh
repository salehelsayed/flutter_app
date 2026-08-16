#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  run_android_headless_recovery_374.sh --build-only --output DIR
  run_android_headless_recovery_374.sh --device-id ID --apk APK --skip-build \
    --production-deleted-batch-seam --no-activity --process-death --output DIR
EOF
}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly APP_ID=com.mknoon.app.plan374proof
readonly RECEIVER_CLASS=com.mknoon.app.CanonicalRuntimeH0ProbeReceiver
readonly ACTION=com.mknoon.app.debug.CANONICAL_RUNTIME_H0_PROBE
readonly REMOTE_DIRECTORY=files/plan374-headless-recovery
readonly WORKER_LOG_TAG=MknoonPlan374Recovery
readonly WORK_MANAGER_JOB_NAMESPACE=androidx.work.systemjobscheduler
readonly WORKER_JOB_TAG='#HeadlessCanonicalRecoveryWorker#'
readonly BUILT_APK="$REPO_ROOT/build/app/outputs/flutter-apk/app-debug.apk"

DEVICE_ID=
APK_PATH=
OUTPUT_DIR=
BUILD_ONLY=false
SKIP_BUILD=false
PRODUCTION_DELETED_BATCH_SEAM=false
NO_ACTIVITY=false
PROCESS_DEATH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-id)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      DEVICE_ID=$2
      shift 2
      ;;
    --apk)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      APK_PATH=$2
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      OUTPUT_DIR=$2
      shift 2
      ;;
    --build-only) BUILD_ONLY=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --production-deleted-batch-seam)
      PRODUCTION_DELETED_BATCH_SEAM=true
      shift
      ;;
    --no-activity) NO_ACTIVITY=true; shift ;;
    --process-death) PROCESS_DEATH=true; shift ;;
    *) usage; exit 64 ;;
  esac
done

[[ -n "$OUTPUT_DIR" ]] || { usage; exit 64; }

build_apk() {
  "$REPO_ROOT/android/gradlew" -p "$REPO_ROOT/android" :app:assembleDebug \
    -PandroidApplicationId="$APP_ID" \
    -PdisableGoogleServicesForDisposableProof=true
  [[ -f "$BUILT_APK" ]] || {
    echo "Plan-374 debug APK was not produced: $BUILT_APK" >&2
    exit 66
  }
}

if [[ "$BUILD_ONLY" == true ]]; then
  if [[ -n "$DEVICE_ID" || -n "$APK_PATH" || "$SKIP_BUILD" == true || \
        "$PRODUCTION_DELETED_BATCH_SEAM" == true || "$NO_ACTIVITY" == true || \
        "$PROCESS_DEATH" == true ]]; then
    usage
    exit 64
  fi
  mkdir -p "$OUTPUT_DIR"
  build_apk
  cp "$BUILT_APK" "$OUTPUT_DIR/app-plan374-debug.apk"
  shasum -a 256 "$OUTPUT_DIR/app-plan374-debug.apk" \
    >"$OUTPUT_DIR/app-plan374-debug.apk.sha256"
  exit 0
fi

if [[ -z "$DEVICE_ID" || "$PRODUCTION_DELETED_BATCH_SEAM" != true || \
      "$NO_ACTIVITY" != true || "$PROCESS_DEATH" != true ]]; then
  usage
  exit 64
fi
if [[ -n "${ANDROID_SERIAL:-}" && "$ANDROID_SERIAL" != "$DEVICE_ID" ]]; then
  echo "ANDROID_SERIAL does not match --device-id" >&2
  exit 64
fi
if [[ "$SKIP_BUILD" == true ]]; then
  [[ -n "$APK_PATH" && -f "$APK_PATH" ]] || { usage; exit 64; }
else
  [[ -z "$APK_PATH" ]] || { usage; exit 64; }
  build_apk
  APK_PATH=$BUILT_APK
fi

mkdir -p "$OUTPUT_DIR"
readonly RUN_NONCE=$(python3 -c 'import uuid; print(uuid.uuid4().hex)')
readonly RUN_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mknoon-plan374.XXXXXX")
PACKAGE_INSTALLED=false
cleanup() {
  rm -rf "$RUN_TMP"
  if [[ "$PACKAGE_INSTALLED" == true ]]; then
    adb -s "$DEVICE_ID" uninstall "$APP_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$(adb -s "$DEVICE_ID" get-state 2>/dev/null | tr -d '\r')" != device ]]; then
  echo "Android target is not connected and authorized: $DEVICE_ID" >&2
  exit 69
fi

python3 - "$REPO_ROOT" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
receiver = (root / "android/app/src/debug/kotlin/com/mknoon/app/CanonicalRuntimeH0ProbeReceiver.kt").read_text()
fixture = (root / "lib/core/debug/android_headless_recovery_374_fixture.dart").read_text()
main = (root / "lib/main.dart").read_text()
service = (root / "android/app/src/main/kotlin/com/mknoon/app/MknoonFirebaseMessagingService.kt").read_text()
seam = (root / "android/app/src/main/kotlin/com/mknoon/app/ProductionDeletedBatchRecovery.kt").read_text()

required = {
    "receiver": ["EXTRA_PLAN374_PHASE", "ProductionDeletedBatchRecovery(", "Plan374FixtureRunner"],
    "fixture": [
        "runAndroidHeadlessRecovery374Fixture",
        "currentIdentityDatabaseVersion",
        "direct_notification_display_outbox",
        "direct_notification_reconciliation_outbox",
        "group_notification_display_outbox",
        "group_notification_reconciliation_outbox",
        "LocalNotificationLedgerStore",
    ],
    "main": ["androidHeadlessRecovery374FixtureMain", "androidHeadlessCanonicalRecoveryMain"],
    "service": ["ProductionDeletedBatchRecovery(", ".commitAndSchedule { generation ->"],
    "seam": ["store.recordDeletion { generation ->", "enqueueDeletedBatch"],
}
sources = {"receiver": receiver, "fixture": fixture, "main": main, "service": service, "seam": seam}
for owner, needles in required.items():
    for needle in needles:
        if needle not in sources[owner]:
            raise SystemExit(f"Plan-374 source contract missing {owner}: {needle}")
if ".recordDeletion" in service:
    raise SystemExit("Firebase service bypasses ProductionDeletedBatchRecovery")
if "store.recordDeletion" in receiver or "WorkManager.getInstance" in receiver:
    raise SystemExit("debug receiver bypasses the production commit/schedule seam")
for forbidden in ("runApp(", "runApplicationBootstrap(", "ApplicationRoot"):
    if forbidden in fixture:
        raise SystemExit(f"Plan-374 fixture constructs a UI root: {forbidden}")
PY

shasum -a 256 \
  "$REPO_ROOT/lib/main.dart" \
  "$REPO_ROOT/lib/core/debug/android_headless_recovery_374_fixture.dart" \
  "$REPO_ROOT/lib/app/bootstrap/production_headless_canonical_recovery.dart" \
  "$REPO_ROOT/lib/app/bootstrap/production_canonical_direct_projection_composition.dart" \
  "$REPO_ROOT/lib/features/conversation/application/direct_notification_projection_owner.dart" \
  "$REPO_ROOT/android/app/src/debug/kotlin/com/mknoon/app/CanonicalRuntimeH0ProbeReceiver.kt" \
  "$REPO_ROOT/android/app/src/main/kotlin/com/mknoon/app/ProductionDeletedBatchRecovery.kt" \
  "$REPO_ROOT/android/app/src/main/kotlin/com/mknoon/app/HeadlessCanonicalRecoveryWorker.kt" \
  "$REPO_ROOT/scripts/run_android_headless_recovery_374.sh" \
  >"$OUTPUT_DIR/source.sha256"
shasum -a 256 "$APK_PATH" >"$OUTPUT_DIR/apk.sha256"
printf '%s\n' "$DEVICE_ID" >"$OUTPUT_DIR/device-id.txt"
printf '%s\n' "$RUN_NONCE" >"$OUTPUT_DIR/run-nonce.txt"

adb -s "$DEVICE_ID" uninstall "$APP_ID" >/dev/null 2>&1 || true
adb -s "$DEVICE_ID" install -t "$APK_PATH" >"$OUTPUT_DIR/install.txt"
PACKAGE_INSTALLED=true
# The disposable proof package has no foreground launch by design. Explicitly
# keep that package in the active app-standby bucket so WorkManager's CONNECTED
# constraint is tested against network availability, not a stale emulator UID
# standby denial inherited from an earlier disposable install.
adb -s "$DEVICE_ID" shell am set-standby-bucket "$APP_ID" active
adb -s "$DEVICE_ID" shell am get-standby-bucket "$APP_ID" \
  >"$OUTPUT_DIR/app-standby-bucket.txt"
SDK_INT=$(adb -s "$DEVICE_ID" shell getprop ro.build.version.sdk | tr -d '\r')
if [[ "$SDK_INT" =~ ^[0-9]+$ && "$SDK_INT" -ge 33 ]]; then
  adb -s "$DEVICE_ID" shell pm grant "$APP_ID" \
    android.permission.POST_NOTIFICATIONS
fi
adb -s "$DEVICE_ID" logcat -c

run_phase() {
  local phase=$1
  local artifact="$OUTPUT_DIR/$phase.json"
  adb -s "$DEVICE_ID" shell run-as "$APP_ID" rm -f \
    "$REMOTE_DIRECTORY/$phase-latest.json" >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" shell am broadcast -W --receiver-foreground \
    -a "$ACTION" \
    -n "$APP_ID/$RECEIVER_CLASS" \
    --es plan374Phase "$phase" \
    --es runNonce "$RUN_NONCE" \
    >"$RUN_TMP/$phase-broadcast.txt"
  local attempt
  for attempt in $(seq 1 240); do
    if adb -s "$DEVICE_ID" exec-out run-as "$APP_ID" cat \
      "$REMOTE_DIRECTORY/$phase-latest.json" >"$artifact" 2>/dev/null && \
      python3 - "$artifact" "$phase" "$RUN_NONCE" <<'PY'
import json
import sys

try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if payload.get("phase") == sys.argv[2] and payload.get("runNonce") == sys.argv[3] else 1)
PY
    then
      cp "$RUN_TMP/$phase-broadcast.txt" "$OUTPUT_DIR/$phase-broadcast.txt"
      return 0
    fi
    sleep 0.25
  done
  echo "Plan-374 phase did not produce an artifact: $phase" >&2
  return 1
}

jobscheduler_dump() {
  adb -s "$DEVICE_ID" shell dumpsys jobscheduler "$APP_ID"
}

# Print only registered JobScheduler IDs whose block proves all three anchors:
# the production package's SystemJobService, WorkManager's exact namespace, and
# HeadlessCanonicalRecoveryWorker's debug tag. Pending/active/recent-history
# copies are deliberately outside the registered-jobs section parsed here. The
# section header carries a job count on current images ("Registered 217 jobs:")
# and was bare "Registered jobs:" on older ones; both are accepted.
registered_namespaced_recovery_job_ids() {
  local dump_path=$1
  python3 - "$dump_path" "$APP_ID" "$WORK_MANAGER_JOB_NAMESPACE" \
    "$WORKER_JOB_TAG" <<'PY'
import pathlib
import re
import sys

dump_path = pathlib.Path(sys.argv[1])
app_id, namespace, worker_tag = sys.argv[2:5]
text = dump_path.read_text(encoding="utf-8", errors="replace").replace("\r", "")
section_match = re.search(r"(?m)^Registered(?:\s+\d+)?\s+jobs:", text)
if section_match is None:
    raise SystemExit("JobScheduler dump has no Registered jobs section")
section = text[section_match.end():]
section_end_markers = (
    "\nPending queue:",
    "\nActive jobs:",
    "\nRecently completed jobs:",
    "\nConcurrency:",
)
ends = [section.find(marker) for marker in section_end_markers]
ends = [position for position in ends if position >= 0]
if ends:
    section = section[:min(ends)]

# Accepted header forms across images: "JOB #u0a333/45:", the explicit
# "JOB #u0a333/45 from namespace <ns>:" variant, and the current namespaced
# token "JOB <ns>:u0a333/45: <hash> <tag>".
header = re.compile(
    r"(?m)^\s*JOB\s+#?[^\s/]+/(?P<job_id>\d+)"
    r"(?::|\s+from\s+namespace\b[^\n]*:)",
)
matches = list(header.finditer(section))
service = f"{app_id}/androidx.work.impl.background.systemjob.SystemJobService"
job_ids = set()
for index, match in enumerate(matches):
    end = matches[index + 1].start() if index + 1 < len(matches) else len(section)
    block = section[match.start():end]
    if service not in block or worker_tag not in block:
        continue
    if re.search(rf"(?<![A-Za-z0-9_.]){re.escape(namespace)}(?![A-Za-z0-9_.])", block) is None:
        continue
    job_ids.add(int(match.group("job_id")))

for job_id in sorted(job_ids):
    print(job_id)
PY
}

run_phase seed
python3 - "$OUTPUT_DIR/seed.json" <<'PY'
import json
import sys

p = json.load(open(sys.argv[1], encoding="utf-8"))
d = p.get("dart") or {}
custody = d.get("custodyBefore") or {}
passed = (
    p.get("status") == "PASS" and
    p.get("mainActivityLaunchCount") == 0 and
    p.get("applicationRootConstructed") is False and
    p.get("finalLeaseState") == "RELEASED" and
    p.get("finalGoState") == "RELEASED" and
    p.get("headlessRecoveryEngineRetained") is False and
    p.get("recoveryWorkEnabled") is True and
    d.get("databaseExistingBeforeRecovery") is True and
    d.get("databaseUserVersion") == 116 and
    d.get("databaseClosed") is True and
    bool(d.get("cipherVersion")) and
    d.get("ledgerRecordsBefore") == 0 and
    set(custody) == {"directDisplay", "directReconciliation", "groupDisplay", "groupReconciliation"} and
    all(isinstance(value, int) and value > 0 for value in custody.values())
)
raise SystemExit(0 if passed else "seed artifact failed Plan-374 invariants")
PY

# Freeze the exact recovery-worker IDs that predate the production deleted-batch
# seam. A later force may target only one registered, namespaced, worker-tagged
# ID absent from this baseline; it can never invent or directly schedule work.
jobscheduler_dump >"$OUTPUT_DIR/jobscheduler-baseline.txt"
registered_namespaced_recovery_job_ids \
  "$OUTPUT_DIR/jobscheduler-baseline.txt" \
  >"$OUTPUT_DIR/jobscheduler-baseline-worker-ids.txt"

run_phase deleted-batch
GENERATION=$(python3 - "$OUTPUT_DIR/deleted-batch.json" <<'PY'
import json
import sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
generation = p.get("committedGeneration")
passed = (
    p.get("status") == "PASS" and
    p.get("productionDeletedBatchSeam") is True and
    p.get("processDeathBarrierArmed") is True and
    p.get("recoveryWorkEnabledBefore") is True and
    isinstance(generation, int) and generation > 0 and
    p.get("pendingGenerationAfter") == generation and
    p.get("committedBinding") == p.get("pendingBindingAfter") and
    str(p.get("immediateUniqueWorkName", "")).startswith("mknoon-recovery-immediate-")
)
if not passed:
    raise SystemExit("deleted-batch artifact failed Plan-374 invariants")
print(generation)
PY
)

worker_log() {
  adb -s "$DEVICE_ID" logcat -d -v raw -s "$WORKER_LOG_TAG:I" '*:S'
}

FIRST_PID=
for attempt in $(seq 1 300); do
  worker_log >"$RUN_TMP/worker-before-death.txt"
  FIRST_PID=$(python3 - "$RUN_TMP/worker-before-death.txt" "$GENERATION" <<'PY'
import json
import sys
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        value = json.loads(line.strip())
    except json.JSONDecodeError:
        continue
    if value.get("event") == "plan374_headless_worker" and value.get("phase") == "process_death_barrier_consumed" and value.get("generation") == int(sys.argv[2]):
        print(value.get("pid", ""))
        break
PY
  )
  [[ -n "$FIRST_PID" ]] && break
  sleep 0.1
done
[[ -n "$FIRST_PID" ]] || {
  echo "WorkManager did not consume the first-attempt Plan-374 barrier" >&2
  exit 1
}
if python3 - "$RUN_TMP/worker-before-death.txt" "$GENERATION" <<'PY'
import json
import sys
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        value = json.loads(line.strip())
    except json.JSONDecodeError:
        continue
    if value.get("phase") == "completion" and value.get("generation") == int(sys.argv[2]):
        raise SystemExit(0)
raise SystemExit(1)
PY
then
  echo "First worker completed before the process-death cut" >&2
  exit 1
fi

if ! adb -s "$DEVICE_ID" shell run-as "$APP_ID" kill -9 "$FIRST_PID" \
  >"$OUTPUT_DIR/process-death-command.txt" 2>&1; then
  echo "The pinned package-UID kill command failed" >&2
  exit 1
fi

FIRST_PID_GONE=false
for attempt in $(seq 1 100); do
  CURRENT_PIDS=$(adb -s "$DEVICE_ID" shell pidof "$APP_ID" 2>/dev/null || true)
  CURRENT_PIDS=${CURRENT_PIDS//$'\r'/}
  if [[ " $CURRENT_PIDS " != *" $FIRST_PID "* ]]; then
    FIRST_PID_GONE=true
    break
  fi
  sleep 0.1
done
[[ "$FIRST_PID_GONE" == true ]] || {
  echo "The pinned package-UID kill did not terminate the barrier-held worker process" >&2
  exit 1
}
printf 'firstPid=%s\npidsAfterCut=%s\n' "$FIRST_PID" "$CURRENT_PIDS" \
  >"$OUTPUT_DIR/process-death-cut.txt"

# Android may batch an otherwise-ready namespaced WorkManager job, and every
# Result.retry() may replace it with a successor JobScheduler ID. Drive only the
# incumbent work already registered by production WorkManager. Completed worker
# attempts are deduplicated by runAttemptCount. Force keys combine the latest
# completed RETRY attempt with the incumbent ID: this prevents a still-visible
# JobStatus from being forced twice while allowing platforms that reuse an ID.
readonly RESUME_AUDIT="$OUTPUT_DIR/workmanager-resume.txt"
readonly FORCED_JOB_KEYS="$RUN_TMP/forced-job-keys.txt"
readonly COMPLETED_RUN_ATTEMPTS="$RUN_TMP/completed-run-attempts.txt"
: >"$FORCED_JOB_KEYS"
: >"$COMPLETED_RUN_ATTEMPTS"
printf 'event\tpoll\tjobId\trunAttemptCount\tpid\toutcomeOrState\tartifact\n' \
  >"$RESUME_AUDIT"
BASELINE_JOB_IDS=$(paste -sd, \
  "$OUTPUT_DIR/jobscheduler-baseline-worker-ids.txt")
printf 'baseline\t0\t%s\t\t\tregistered\tjobscheduler-baseline.txt\n' \
  "${BASELINE_JOB_IDS:-none}" >>"$RESUME_AUDIT"

SECOND_PID=
LATEST_RETRY_RUN_ATTEMPT=-1
for attempt in $(seq 1 2400); do
  worker_log >"$OUTPUT_DIR/worker-log.txt"
  python3 - "$OUTPUT_DIR/worker-log.txt" "$GENERATION" \
    >"$RUN_TMP/completions-current.tsv" <<'PY'
import json
import sys
completions = {}
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        value = json.loads(line.strip())
    except json.JSONDecodeError:
        continue
    if (
        value.get("event") == "plan374_headless_worker" and
        value.get("phase") == "completion" and
        value.get("generation") == int(sys.argv[2])
    ):
        run_attempt = value.get("runAttemptCount")
        pid = value.get("pid")
        outcome = value.get("outcome")
        if not isinstance(run_attempt, int) or run_attempt < 0:
            raise SystemExit("worker completion has invalid runAttemptCount")
        if not isinstance(pid, int) or outcome not in {"SUCCESS", "RETRY"}:
            raise SystemExit("worker completion has invalid PID/outcome")
        signature = (pid, outcome)
        previous = completions.setdefault(run_attempt, signature)
        if previous != signature:
            raise SystemExit("conflicting worker completions for one runAttemptCount")
for run_attempt, (pid, outcome) in sorted(completions.items()):
    print(f"{run_attempt}\t{pid}\t{outcome}")
PY

  while IFS=$'\t' read -r RUN_ATTEMPT COMPLETION_PID OUTCOME; do
    [[ -n "$RUN_ATTEMPT" ]] || continue
    if rg -Fxq -- "$RUN_ATTEMPT" "$COMPLETED_RUN_ATTEMPTS"; then
      continue
    fi
    printf '%s\n' "$RUN_ATTEMPT" >>"$COMPLETED_RUN_ATTEMPTS"
    printf 'completion\t%s\t\t%s\t%s\t%s\tworker-log.txt\n' \
      "$attempt" "$RUN_ATTEMPT" "$COMPLETION_PID" "$OUTCOME" \
      >>"$RESUME_AUDIT"
    if [[ "$COMPLETION_PID" == "$FIRST_PID" ]]; then
      echo "The killed first process emitted a post-cut completion" >&2
      exit 1
    fi
    if [[ "$OUTCOME" == SUCCESS ]]; then
      SECOND_PID=$COMPLETION_PID
    elif [[ "$RUN_ATTEMPT" -gt "$LATEST_RETRY_RUN_ATTEMPT" ]]; then
      LATEST_RETRY_RUN_ATTEMPT=$RUN_ATTEMPT
    fi
  done <"$RUN_TMP/completions-current.tsv"
  [[ -z "$SECOND_PID" ]] || break

  jobscheduler_dump >"$RUN_TMP/jobscheduler-current.txt"
  registered_namespaced_recovery_job_ids \
    "$RUN_TMP/jobscheduler-current.txt" \
    >"$RUN_TMP/jobscheduler-current-worker-ids.txt"
  : >"$RUN_TMP/jobscheduler-incumbent-ids.txt"
  while IFS= read -r JOB_ID; do
    [[ -n "$JOB_ID" ]] || continue
    if rg -Fxq -- "$JOB_ID" \
      "$OUTPUT_DIR/jobscheduler-baseline-worker-ids.txt"; then
      continue
    fi
    JOB_FORCE_KEY="$LATEST_RETRY_RUN_ATTEMPT:$JOB_ID"
    if rg -Fxq -- "$JOB_FORCE_KEY" "$FORCED_JOB_KEYS"; then
      continue
    fi
    printf '%s\n' "$JOB_ID" >>"$RUN_TMP/jobscheduler-incumbent-ids.txt"
  done <"$RUN_TMP/jobscheduler-current-worker-ids.txt"

  INCUMBENT_COUNT=$(wc -l <"$RUN_TMP/jobscheduler-incumbent-ids.txt" | tr -d ' ')
  if [[ "$INCUMBENT_COUNT" -gt 1 ]]; then
    cp "$RUN_TMP/jobscheduler-current.txt" \
      "$OUTPUT_DIR/jobscheduler-ambiguous-poll-$attempt.txt"
    echo "Multiple non-baseline registered recovery-worker jobs are ambiguous" >&2
    exit 1
  fi
  if [[ "$INCUMBENT_COUNT" -eq 1 ]]; then
    JOB_ID=$(tr -d '\r\n' <"$RUN_TMP/jobscheduler-incumbent-ids.txt")
    SNAPSHOT_ARTIFACT="jobscheduler-incumbent-poll-$attempt-job-$JOB_ID.txt"
    STATE_ARTIFACT="jobscheduler-state-poll-$attempt-job-$JOB_ID.txt"
    FORCE_ARTIFACT="jobscheduler-force-poll-$attempt-job-$JOB_ID.txt"
    cp "$RUN_TMP/jobscheduler-current.txt" "$OUTPUT_DIR/$SNAPSHOT_ARTIFACT"
    if adb -s "$DEVICE_ID" shell cmd jobscheduler get-job-state -n \
      "$WORK_MANAGER_JOB_NAMESPACE" "$APP_ID" "$JOB_ID" \
      >"$OUTPUT_DIR/$STATE_ARTIFACT" 2>&1 && \
      python3 - "$OUTPUT_DIR/$STATE_ARTIFACT" <<'PY'
import pathlib
import sys

tokens = pathlib.Path(sys.argv[1]).read_text(
    encoding="utf-8", errors="replace",
).replace("\r", " ").split()
known = {
    "pending", "active", "user-stopped", "backing-up", "no-component",
    "ready", "waiting",
}
raise SystemExit(0 if tokens and set(tokens) <= known else 1)
PY
    then
      JOB_STATE=$(tr '\r\n' '  ' <"$OUTPUT_DIR/$STATE_ARTIFACT" | xargs)
      printf 'state\t%s\t%s\t%s\t\t%s\t%s\n' \
        "$attempt" "$JOB_ID" "$LATEST_RETRY_RUN_ATTEMPT" \
        "$JOB_STATE" "$STATE_ARTIFACT" \
        >>"$RESUME_AUDIT"
      if [[ " $JOB_STATE " != *" active "* && \
            " $JOB_STATE " != *" user-stopped "* && \
            " $JOB_STATE " != *" backing-up "* && \
            " $JOB_STATE " != *" no-component "* ]]; then
        if adb -s "$DEVICE_ID" shell cmd jobscheduler run -f -n \
          "$WORK_MANAGER_JOB_NAMESPACE" "$APP_ID" "$JOB_ID" \
          >"$OUTPUT_DIR/$FORCE_ARTIFACT" 2>&1; then
          printf '%s\n' "$LATEST_RETRY_RUN_ATTEMPT:$JOB_ID" \
            >>"$FORCED_JOB_KEYS"
          printf 'force\t%s\t%s\t%s\t\t%s\t%s\n' \
            "$attempt" "$JOB_ID" "$LATEST_RETRY_RUN_ATTEMPT" \
            "$JOB_STATE" "$FORCE_ARTIFACT" \
            >>"$RESUME_AUDIT"
        else
          printf 'force-race\t%s\t%s\t%s\t\t%s\t%s\n' \
            "$attempt" "$JOB_ID" "$LATEST_RETRY_RUN_ATTEMPT" \
            "$JOB_STATE" "$FORCE_ARTIFACT" \
            >>"$RESUME_AUDIT"
        fi
      fi
    else
      printf 'state-race\t%s\t%s\t%s\t\tunregistered\t%s\n' \
        "$attempt" "$JOB_ID" "$LATEST_RETRY_RUN_ATTEMPT" \
        "$STATE_ARTIFACT" >>"$RESUME_AUDIT"
    fi
  fi

  sleep 0.25
done
[[ -n "$SECOND_PID" ]] || {
  jobscheduler_dump >"$OUTPUT_DIR/jobscheduler-resume-timeout.txt" 2>&1 || true
  echo "Resumed WorkManager attempts did not complete successfully" >&2
  exit 1
}
jobscheduler_dump >"$OUTPUT_DIR/jobscheduler-after-success.txt" 2>&1 || true

run_phase inspect
adb -s "$DEVICE_ID" shell dumpsys activity activities \
  >"$OUTPUT_DIR/dumpsys-activity-activities.txt"
adb -s "$DEVICE_ID" shell dumpsys jobscheduler "$APP_ID" \
  >"$OUTPUT_DIR/dumpsys-jobscheduler.txt" 2>&1 || true
ACTIVITY_COUNT=$(rg -c "$APP_ID/.MainActivity|$APP_ID/com\.mknoon\.app\.MainActivity" \
  "$OUTPUT_DIR/dumpsys-activity-activities.txt" || true)
ACTIVITY_COUNT=${ACTIVITY_COUNT:-0}

python3 - "$OUTPUT_DIR/inspect.json" "$ACTIVITY_COUNT" <<'PY'
import json
import sys

p = json.load(open(sys.argv[1], encoding="utf-8"))
d = p.get("dart") or {}
custody = d.get("custodyAfter") or {}
records = d.get("ledgerRecords") or []
kinds = {r.get("producerKind") for r in records if isinstance(r, dict)}
notification_ids = {
    r.get("notificationId") for r in records
    if isinstance(r, dict) and isinstance(r.get("notificationId"), int)
}
exact_records = all(
    isinstance(r, dict) and
    r.get("sourceCustody") == "SQL_READY" and
    r.get("presentationOwner") == "INBOX_RECONCILER" and
    r.get("presentationState") == "OS_POSTED" and
    r.get("effectPhase") == "SETTLED"
    for r in records
)
passed = (
    p.get("status") == "PASS" and
    int(sys.argv[2]) == 0 and
    p.get("mainActivityLaunchCount") == 0 and
    p.get("applicationRootConstructed") is False and
    p.get("finalLeaseState") == "RELEASED" and
    p.get("finalGoState") == "RELEASED" and
    p.get("headlessRecoveryEngineRetained") is False and
    p.get("pendingGeneration") is None and
    d.get("databaseUserVersion") == 116 and
    d.get("databaseClosed") is True and
    str(d.get("quickCheck", "")).lower() == "ok" and
    bool(d.get("cipherVersion")) and
    d.get("identityPresent") is True and
    set(custody) == {"directDisplay", "directReconciliation", "groupDisplay", "groupReconciliation"} and
    all(value == 0 for value in custody.values()) and
    d.get("ledgerRecordCount") == 2 and
    len(records) == 2 and
    d.get("settledSqlReadyInboxReconcilerCount") == 2 and
    kinds == {"direct_message", "group_message"} and
    len(notification_ids) == 2 and
    exact_records and
    p.get("exactSettledLedger") is True and
    p.get("matchingCardCount") == 2 and
    p.get("privateMessageCardCount") == 2 and
    # The OS may add its own autogroup summary over silent app cards (the
    # API 36+ Aggregate_SilentSection row). Exactness is owned by app-posted
    # cards: exactly the two expected IDs and zero app-posted extras, both as
    # reported by the receiver and recomputed from the raw notification list.
    p.get("appPostedCardCount") == 2 and
    p.get("unexpectedAppPostedCardCount") == 0 and
    sorted(
        n.get("id") for n in (p.get("activeNotifications") or [])
        if not n.get("systemAutogroupSummary")
    ) == sorted(p.get("expectedCardIds") or [])
)
raise SystemExit(0 if passed else "inspect artifact failed Plan-374 invariants")
PY

python3 - \
  "$OUTPUT_DIR/seed.json" \
  "$OUTPUT_DIR/deleted-batch.json" \
  "$OUTPUT_DIR/inspect.json" \
  "$OUTPUT_DIR/worker-log.txt" \
  "$OUTPUT_DIR/tc-374-08-result.json" \
  "$DEVICE_ID" "$RUN_NONCE" "$FIRST_PID" "$SECOND_PID" "$GENERATION" \
  "$ACTIVITY_COUNT" <<'PY'
import hashlib
import json
import pathlib
import sys

seed_path, deletion_path, inspect_path, worker_path, output_path = map(pathlib.Path, sys.argv[1:6])
device_id, nonce, first_pid, second_pid = sys.argv[6:10]
generation, activity_count = map(int, sys.argv[10:12])

def load(path):
    return json.loads(path.read_text(encoding="utf-8"))

worker_events = []
for line in worker_path.read_text(encoding="utf-8", errors="replace").splitlines():
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    if value.get("event") == "plan374_headless_worker":
        worker_events.append(value)

successful_resumes = [
    event for event in worker_events
    if event.get("phase") == "completion"
    and event.get("generation") == generation
    and str(event.get("pid")) == second_pid
    and event.get("outcome") == "SUCCESS"
    and isinstance(event.get("runAttemptCount"), int)
    and event.get("runAttemptCount") >= 1
]
if first_pid == second_pid or len(successful_resumes) != 1:
    raise SystemExit("final resumed WorkManager success identity is not exact")

result = {
    "schemaVersion": 1,
    "testId": "TC-374-08",
    "status": "PASS",
    "deviceId": device_id,
    "runNonce": nonce,
    "scenarioCount": 1,
    "productionDeletedBatchSeam": True,
    "workManagerProductionEntrypoint": "androidHeadlessCanonicalRecoveryMain",
    "existingSqlCipherVersion": 116,
    "processDeath": {
        "firstPid": int(first_pid),
        "resumedPid": int(second_pid),
        "generation": generation,
        "distinctProcess": first_pid != second_pid,
        "firstAttemptBarrierConsumed": any(
            event.get("phase") == "process_death_barrier_consumed" and
            str(event.get("pid")) == first_pid and
            event.get("generation") == generation
            for event in worker_events
        ),
        "cutCommand": "run-as kill -9",
    },
    "activityLaunchCount": activity_count,
    "manualTapCount": 0,
    "skipCount": 0,
    "seed": load(seed_path),
    "deletedBatch": load(deletion_path),
    "inspection": load(inspect_path),
    "workerEvents": worker_events,
}
output_path.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
print(hashlib.sha256(output_path.read_bytes()).hexdigest(), output_path.name)
PY

printf '%s\n' \
  'TC-374-08 PASS: production deleted-batch seam -> WorkManager -> process-death retry -> production headless recovery; Activity launches=0, manual taps=0, skips=0'
