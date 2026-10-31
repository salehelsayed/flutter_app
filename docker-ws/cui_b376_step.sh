#!/bin/bash
# Run one Codex-UI b376 request step in the isolated worktree with the request's env. Output goes to <log>.
#   host-run bash docker-ws/cui_b376_step.sh <log-relative-to-worktree> <sender-id|-> <receiver-id|-> -- <command...>
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-b376; M=/Volumes/CrucialX9/flutter_app
PK=$M/build/kayan-safe/codex-ui/plan407-20261021T1507Z
LOG="$1"; SND="$2"; RCV="$3"; shift 3; [ "$1" = "--" ] && shift
cd "$W" || exit 3
mkdir -p "$(dirname "$LOG")"
eval "$(python3 - "$PK/private/campaign-environment.private.json" <<'PY'
import json,shlex,sys
d=json.load(open(sys.argv[1]))
for k in ("SIMS_NOTIFICATION_RELAY_TARGET","SIMS_NOTIFICATION_RELAY_KEY","MKNOON_RELAY_ADDRESSES","SIMS_CANDIDATE_RELAY_REVISION","SIMS_CANDIDATE_RELAY_SHA256"):
    if k in d: print("export %s=%s" % (k, shlex.quote(str(d[k]))))
PY
)"
export FIREBASE_SERVICE_ACCOUNT="$M/mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json"
export SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$FIREBASE_SERVICE_ACCOUNT"
case "$SND" in emulator-*) export SIMS_DISPOSABLE_ANDROID_JOURNEYS=1 ;; esac
export ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=false
export ORG_GRADLE_PROJECT_androidApplicationId=com.mknoon.sims.notifications
export ANDROID_APP_PACKAGE=com.mknoon.sims.notifications
export SIMS_APP_ID=com.mknoon.sims.notifications
export MKNOON_PLAN393_FIXED_WAKE_FIXTURE=false
export GOTOOLCHAIN=go1.27.1
export SIMS_MAX_PARALLEL=1 SIMS_HOST_CONCURRENCY=1
[ "$SND" != "-" ] && export SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID="$SND"
[ "$RCV" != "-" ] && export SIMS_ANDROID_EMULATOR_DEVICE_ID="$RCV"
[ -n "${CUI_APK:-}" ] && export SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$CUI_APK"
export PATH="$HOME/development/flutter-3.47.2/bin:$PATH"
echo "start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD) cmd=$*" > "$LOG"
env "ORG_GRADLE_PROJECT_android.builder.sdkDownload=false" "$@" >> "$LOG" 2>&1
rc=$?
echo "exit=$rc end=$(date -u +%FT%TZ)" >> "$LOG"
exit $rc
