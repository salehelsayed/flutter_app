#!/bin/bash
# Call-enabled debug APK as build_android_calls_debug.sh, plus the coordinated
# reply-once repair rollout flag. For the two disposable emulators only.
#   host-run bash docker-ws/build_android_calls_debug_repair_rollout.sh <log-file-in-repo>
set -uo pipefail
cd "$(dirname "$0")/.."
LOG="${1:?log file}"
flutter build apk --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --dart-define=CONTACT_REPAIR_ROLLOUT=true \
  --android-project-arg=enableAndroidNativeCalls=true > "$LOG" 2>&1
rc=$?
echo "exit=$rc" >> "$LOG"
exit "$rc"
