#!/usr/bin/env bash

set -euo pipefail

readonly PROOF_APPLICATION_ID="com.mknoon.app.visibilityproof"
readonly PROOF_TEST_APPLICATION_ID="${PROOF_APPLICATION_ID}.test"
readonly PROOF_RUNNER="${PROOF_TEST_APPLICATION_ID}/androidx.test.runner.AndroidJUnitRunner"
readonly PROOF_CLASS="com.mknoon.app.AppVisibilityLifecycleInstrumentationTest"
readonly PHASE_A_METHOD="testTC37108aSeedLifecycleAndDurableRecord"
readonly PHASE_B_METHOD="testTC37108bReopenDiskAndRejectStaleRoute"
readonly SCENARIO="app_visibility_lifecycle"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_app_visibility_android_e2e.sh --build-only --artifact-dir DIR
  ./scripts/run_app_visibility_android_e2e.sh --device-id ID --artifact-dir DIR \
    --result-dir DIR --scenario app_visibility_lifecycle
  ./scripts/run_app_visibility_android_e2e.sh --list-scenarios

The build-only leg creates one disposable debug app/test APK pair. Each device
leg installs that pair once, executes phase A, force-stops the exact disposable
package, and executes phase B against the reopened durable record.
EOF
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

build_only=false
list_scenarios=false
device_id=""
artifact_dir=""
result_dir=""
scenario=""

while (($# > 0)); do
  case "$1" in
    --build-only)
      build_only=true
      shift
      ;;
    --list-scenarios)
      list_scenarios=true
      shift
      ;;
    --device-id)
      (($# >= 2)) || { usage >&2; exit 64; }
      device_id="$2"
      shift 2
      ;;
    --artifact-dir)
      (($# >= 2)) || { usage >&2; exit 64; }
      artifact_dir="$2"
      shift 2
      ;;
    --result-dir)
      (($# >= 2)) || { usage >&2; exit 64; }
      result_dir="$2"
      shift 2
      ;;
    --scenario)
      (($# >= 2)) || { usage >&2; exit 64; }
      scenario="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

if [[ "$list_scenarios" == true ]]; then
  printf '%s\n' "$SCENARIO"
  exit 0
fi

[[ -n "$artifact_dir" ]] || { usage >&2; exit 64; }

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SOURCE_APP_APK="$REPO_ROOT/build/app/outputs/apk/debug/app-debug.apk"
readonly SOURCE_TEST_APK="$REPO_ROOT/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
mkdir -p "$artifact_dir"
artifact_dir="$(cd "$artifact_dir" && pwd)"
readonly APP_APK="$artifact_dir/app-visibility-371-debug.apk"
readonly TEST_APK="$artifact_dir/app-visibility-371-debug-androidTest.apk"

resolve_apkanalyzer() {
  local candidate
  if command -v apkanalyzer >/dev/null 2>&1; then
    command -v apkanalyzer
    return
  fi
  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -z "$sdk_root" && -f "$REPO_ROOT/android/local.properties" ]]; then
    sdk_root="$(sed -n 's/^sdk\.dir=//p' "$REPO_ROOT/android/local.properties" | head -n 1)"
  fi
  if [[ -n "$sdk_root" ]]; then
    candidate="$sdk_root/cmdline-tools/latest/bin/apkanalyzer"
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
    candidate="$(find "$sdk_root/cmdline-tools" -type f -name apkanalyzer 2>/dev/null | sort | tail -n 1)"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  fi
  return 1
}

verify_artifacts() {
  [[ -s "$APP_APK" ]] || fail "missing app proof APK: $APP_APK"
  [[ -s "$TEST_APK" ]] || fail "missing test proof APK: $TEST_APK"

  local apkanalyzer_bin
  apkanalyzer_bin="$(resolve_apkanalyzer)" ||
    fail "apkanalyzer is required to validate the disposable APK boundary"
  local app_id test_id
  app_id="$("$apkanalyzer_bin" manifest application-id "$APP_APK" | tr -d '\r')"
  test_id="$("$apkanalyzer_bin" manifest application-id "$TEST_APK" | tr -d '\r')"
  [[ "$app_id" == "$PROOF_APPLICATION_ID" ]] ||
    fail "app APK application ID is $app_id, expected $PROOF_APPLICATION_ID"
  [[ "$test_id" == "$PROOF_TEST_APPLICATION_ID" ]] ||
    fail "test APK application ID is $test_id, expected $PROOF_TEST_APPLICATION_ID"

  "$apkanalyzer_bin" manifest print "$APP_APK" >"$artifact_dir/app-manifest.xml"
  "$apkanalyzer_bin" manifest print "$TEST_APK" >"$artifact_dir/test-manifest.xml"
  grep -Fq 'android:name="com.mknoon.app.MainActivity"' \
    "$artifact_dir/app-manifest.xml" || fail "proof APK omits MainActivity"
  grep -Fq 'android:name="com.mknoon.app.MknoonFirebaseMessagingService"' \
    "$artifact_dir/app-manifest.xml" || fail "proof APK omits the app-owned FCM service"
  grep -Fq 'android:name="androidx.work.impl.foreground.SystemForegroundService"' \
    "$artifact_dir/app-manifest.xml" || fail "proof APK omits WorkManager foreground service"
  if grep -Fq 'android:process=' "$artifact_dir/app-manifest.xml"; then
    fail "proof APK violates the one-process app-visibility store assumption"
  fi
  grep -Fq "android:targetPackage=\"$PROOF_APPLICATION_ID\"" \
    "$artifact_dir/test-manifest.xml" || fail "test APK targets the wrong package"
  grep -Fq 'android:name="androidx.test.runner.AndroidJUnitRunner"' \
    "$artifact_dir/test-manifest.xml" || fail "test APK omits AndroidJUnitRunner"
}

if [[ "$build_only" == true ]]; then
  [[ -z "$device_id" && -z "$result_dir" && -z "$scenario" ]] || {
    usage >&2
    exit 64
  }
  readonly BUILD_LOG="$artifact_dir/build.log"
  if ! "$REPO_ROOT/android/gradlew" -p "$REPO_ROOT/android" \
    :app:assembleDebug \
    :app:assembleDebugAndroidTest \
    -PenableAppVisibility371Proof=true \
    -PandroidApplicationId="$PROOF_APPLICATION_ID" \
    -PdisableGoogleServicesForDisposableProof=true \
    >"$BUILD_LOG" 2>&1; then
    tail -n 120 "$BUILD_LOG" >&2
    fail "Plan 371 Android proof build failed; full log retained at $BUILD_LOG"
  fi
  [[ -s "$SOURCE_APP_APK" ]] || fail "Gradle did not produce $SOURCE_APP_APK"
  [[ -s "$SOURCE_TEST_APK" ]] || fail "Gradle did not produce $SOURCE_TEST_APK"
  cp "$SOURCE_APP_APK" "$APP_APK"
  cp "$SOURCE_TEST_APK" "$TEST_APK"
  verify_artifacts
  shasum -a 256 "$APP_APK" "$TEST_APK" >"$artifact_dir/checksums.sha256"
  printf 'Built Plan 371 Android proof APKs once in %s\n' "$artifact_dir"
  exit 0
fi

[[ "$scenario" == "$SCENARIO" ]] || { usage >&2; exit 64; }
[[ -n "$device_id" && -n "$result_dir" ]] || { usage >&2; exit 64; }
[[ "$device_id" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "invalid Android target ID"
verify_artifacts

mkdir -p "$result_dir"
result_dir="$(cd "$result_dir" && pwd)"
export ANDROID_SERIAL="$device_id"
[[ "$ANDROID_SERIAL" == "$device_id" ]] || fail "ANDROID_SERIAL target mismatch"
[[ "$(adb -s "$device_id" get-state 2>/dev/null | tr -d '\r')" == "device" ]] ||
  fail "Android target is not connected and authorized: $device_id"
[[ "$(adb -s "$device_id" get-serialno 2>/dev/null | tr -d '\r')" == "$device_id" ]] ||
  fail "adb resolved a target other than --device-id $device_id"

cleanup() {
  adb -s "$device_id" shell am force-stop "$PROOF_APPLICATION_ID" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

{
  printf 'deviceId=%s\n' "$device_id"
  printf 'state=%s\n' "$(adb -s "$device_id" get-state | tr -d '\r')"
  printf 'model=%s\n' "$(adb -s "$device_id" shell getprop ro.product.model | tr -d '\r')"
  printf 'sdk=%s\n' "$(adb -s "$device_id" shell getprop ro.build.version.sdk | tr -d '\r')"
  printf 'fingerprint=%s\n' "$(adb -s "$device_id" shell getprop ro.build.fingerprint | tr -d '\r')"
} >"$result_dir/target.txt"

adb -s "$device_id" install -r -t "$APP_APK" \
  >"$result_dir/install-app.log" 2>&1
grep -Fq 'Success' "$result_dir/install-app.log" || fail "app APK installation failed"
adb -s "$device_id" install -r -t "$TEST_APK" \
  >"$result_dir/install-test.log" 2>&1
grep -Fq 'Success' "$result_dir/install-test.log" || fail "test APK installation failed"
adb -s "$device_id" shell pm clear "$PROOF_APPLICATION_ID" \
  >"$result_dir/clear-app-data.log" 2>&1
grep -Fq 'Success' "$result_dir/clear-app-data.log" || fail "proof app data clear failed"

assert_phase_log() {
  local method="$1"
  local log="$2"
  grep -Fq "INSTRUMENTATION_STATUS: test=$method" "$log" ||
    fail "instrumentation did not execute exact method $method"
  grep -Fq 'OK (1 test)' "$log" || fail "$method did not pass exactly one test"
  grep -Fq 'INSTRUMENTATION_CODE: -1' "$log" ||
    fail "$method did not terminate successfully"
  if grep -Eqi 'INSTRUMENTATION_FAILED|FAILURES!!!|(^|[^a-z])(skipped|ignored)([^a-z]|$)' "$log" ||
    grep -Fq 'INSTRUMENTATION_STATUS_CODE: -3' "$log"; then
    fail "$method reported a failure or skip"
  fi
}

run_phase() {
  local method="$1"
  local log="$2"
  set +e
  adb -s "$device_id" shell am instrument -w -r \
    -e class "${PROOF_CLASS}#${method}" \
    "$PROOF_RUNNER" 2>&1 | tee "$log"
  local adb_status="${PIPESTATUS[0]}"
  set -e
  [[ "$adb_status" == "0" ]] || fail "$method instrumentation command failed"
  assert_phase_log "$method" "$log"
}

run_phase "$PHASE_A_METHOD" "$result_dir/phase-a.log"
adb -s "$device_id" shell am force-stop "$PROOF_APPLICATION_ID" \
  >"$result_dir/force-stop.log" 2>&1
if [[ -n "$(adb -s "$device_id" shell pidof "$PROOF_APPLICATION_ID" 2>/dev/null | tr -d '\r')" ]]; then
  fail "host force-stop left the disposable app process alive"
fi
run_phase "$PHASE_B_METHOD" "$result_dir/phase-b.log"
adb -s "$device_id" logcat -d -v threadtime >"$result_dir/logcat.txt" 2>&1 || true

printf 'scenario=%s\ndeviceId=%s\nphaseA=PASS\nforceStop=PASS\nphaseB=PASS\nskips=0\n' \
  "$SCENARIO" "$device_id" >"$result_dir/summary.txt"
printf 'PASS: %s on %s (two phases, host force-stop, zero skips)\n' \
  "$SCENARIO" "$device_id"
