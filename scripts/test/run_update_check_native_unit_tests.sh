#!/usr/bin/env bash
# SE-41 T4a: runs the Android JVM unit tests for the background update check
# (worker routing, scheduler, budget abort, notification poster) plus the
# MainActivity tests, because MainActivity registers the main-engine bridge,
# and (T4b) the FCM service tests for the check-now push match.
# Host-only: the Gradle wrapper needs the Mac toolchain. Run via host-run.
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GRADLEW="$REPO_ROOT/android/gradlew"
readonly LOG_DIR="${UPDATE_CHECK_NATIVE_UNIT_LOG_DIR:-$REPO_ROOT/build/update-check-native-unit}"
readonly LOG="$LOG_DIR/android-update-check-jvm.log"

[[ -x "$GRADLEW" ]] || { echo "Gradle wrapper is not executable: $GRADLEW" >&2; exit 2; }
mkdir -p "$LOG_DIR"

echo "log: $LOG"
set +e
"$GRADLEW" -p "$REPO_ROOT/android" --console=plain \
  :app:testDebugUnitTest \
  --tests 'com.mknoon.app.UpdateCheckBackgroundWorkTest' \
  --tests 'com.mknoon.app.UpdateCheckNotificationPosterTest' \
  --tests 'com.mknoon.app.MknoonFirebaseMessagingServiceTest' \
  --tests 'com.mknoon.app.MainActivityOnNewIntentTest' \
  --tests 'com.mknoon.app.MainActivityAppVisibilityTest' \
  --tests 'com.mknoon.app.CanonicalRuntimeLeaseTest' \
  >"$LOG" 2>&1
status=$?
set -e

grep -E "^(> Task :app:testDebugUnitTest|BUILD |.*FAILED|.*tests completed)" "$LOG" | tail -20 || true
grep -E "^e: " "$LOG" | head -20 || true
echo "gradle exit: $status"
exit "$status"
