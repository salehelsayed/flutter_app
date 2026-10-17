#!/bin/bash
# Build the call-enabled debug APK (same flags as the SE-42 campaign build), logging to a file so a
# lingering Gradle daemon cannot hold the host bridge's output pipe open.
#   host-run bash docker-ws/build_android_calls_debug.sh <log-file-in-repo>
set -uo pipefail
cd "$(dirname "$0")/.."
LOG="${1:?log file}"
flutter build apk --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --android-project-arg=enableAndroidNativeCalls=true > "$LOG" 2>&1
rc=$?
echo "exit=$rc" >> "$LOG"
exit "$rc"
