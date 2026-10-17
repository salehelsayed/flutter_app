#!/bin/bash
# Real Flutter build with Gradle native calls on and NO Dart defines. The parity
# guard must refuse it during Gradle configuration.
#   host-run bash docker-ws/native_call_flag_parity_real_build.sh <log-file-in-repo>
set -uo pipefail
cd "$(dirname "$0")/.."
LOG="${1:?log file}"
flutter build apk --debug --no-pub \
  --android-project-arg=enableAndroidNativeCalls=true > "$LOG" 2>&1
rc=$?
echo "exit=$rc" >> "$LOG"
if [ "$rc" -ne 0 ] && grep -q "define disagree" "$LOG"; then
  echo "PASS: mismatched build refused by the parity guard"
  exit 0
fi
echo "FAIL: build exit $rc without the parity refusal"
exit 1
