#!/usr/bin/env bash
# Build-time parity between Gradle enableAndroidNativeCalls and the Dart
# VOICE_CALL_ANDROID_NATIVE_ENABLED define. Configures :app with each case and
# checks which ones Gradle refuses. Host-only (Gradle wrapper): run via host-run.
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GRADLEW="$REPO_ROOT/android/gradlew"
readonly LOG_DIR="${PARITY_LOG_DIR:-$REPO_ROOT/build/native-call-flag-parity}"
mkdir -p "$LOG_DIR"

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
readonly ON="$(b64 VOICE_CALL_ANDROID_NATIVE_ENABLED=true)"
readonly OFF="$(b64 VOICE_CALL_ANDROID_NATIVE_ENABLED=false)"
readonly OTHER="$(b64 VOICE_CALL_OUTGOING_ENABLED=true)"
readonly TARGET="-Ptarget=$REPO_ROOT/lib/main.dart"

failures=0
run_case() {
  local name="$1" expect="$2"; shift 2
  local log="$LOG_DIR/$name.log"
  "$GRADLEW" -p "$REPO_ROOT/android" --console=plain -q :app:help "$@" >"$log" 2>&1
  local status=$?
  local refused=no
  grep -q "Android native calls and the Dart VOICE_CALL_ANDROID_NATIVE_ENABLED define disagree" "$log" && refused=yes
  if [[ "$expect" == refuse && "$refused" == yes && $status -ne 0 ]] || [[ "$expect" == accept && $status -eq 0 ]]; then
    echo "PASS $name (expect $expect, exit $status)"
  else
    echo "FAIL $name (expect $expect, exit $status, refused=$refused, log $log)"
    failures=$((failures + 1))
  fi
}

run_case gradle_on_dart_on accept -PenableAndroidNativeCalls=true "-Pdart-defines=$OTHER,$ON" "$TARGET"
run_case gradle_off_dart_off accept -PenableAndroidNativeCalls=false "-Pdart-defines=$OFF" "$TARGET"
run_case gradle_off_no_defines accept "$TARGET"
run_case gradle_on_dart_off refuse -PenableAndroidNativeCalls=true "-Pdart-defines=$OFF" "$TARGET"
run_case gradle_on_define_missing refuse -PenableAndroidNativeCalls=true "-Pdart-defines=$OTHER" "$TARGET"
run_case gradle_on_no_defines_flutter_build refuse -PenableAndroidNativeCalls=true "$TARGET"
run_case gradle_off_dart_on refuse "-Pdart-defines=$ON" "$TARGET"
# Plain Gradle runs (JVM unit tests) carry no Flutter target or defines.
run_case gradle_on_plain_gradle_run accept -PenableAndroidNativeCalls=true

echo "failures: $failures"
[[ $failures -eq 0 ]]
