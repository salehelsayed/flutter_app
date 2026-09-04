#!/usr/bin/env bash
# Runs the Android call-package JVM unit tests (Telecom lifecycle, native
# bridge, notification factory, pending store, headless admission worker).
# Host-only: the Gradle wrapper needs the Mac toolchain. Run via host-run.
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GRADLEW="$REPO_ROOT/android/gradlew"
readonly LOG_DIR="${CALL_NATIVE_UNIT_LOG_DIR:-$REPO_ROOT/build/call-native-unit}"
readonly LOG="$LOG_DIR/android-call-jvm.log"

[[ -x "$GRADLEW" ]] || { echo "Gradle wrapper is not executable: $GRADLEW" >&2; exit 2; }
mkdir -p "$LOG_DIR"

echo "log: $LOG"
set +e
"$GRADLEW" -p "$REPO_ROOT/android" --console=plain \
  :app:testDebugUnitTest \
  --tests 'com.mknoon.app.call.*' \
  --tests 'com.mknoon.app.MknoonFirebaseMessagingServiceTest' \
  >"$LOG" 2>&1
status=$?
set -e

grep -E "^(> Task :app:testDebugUnitTest|BUILD |.*FAILED|.*tests completed)" "$LOG" | tail -20 || true
grep -E "^e: " "$LOG" | head -20 || true
echo "gradle exit: $status"
exit "$status"
