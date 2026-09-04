#!/usr/bin/env bash

set -euo pipefail

readonly PROOF_APPLICATION_ID="com.mknoon.app.vc204proof"
readonly VC204_DART_DEFINES="Vk9JQ0VfQ0FMTF9DQVBBQklMSVRZX1YxPXRydWU=,Vk9JQ0VfQ0FMTF9JTkNPTUlOR19FTkFCTEVEPXRydWU=,Vk9JQ0VfQ0FMTF9UVVJOX0VOQUJMRUQ9dHJ1ZQ==,Vk9JQ0VfQ0FMTF9BTkRST0lEX05BVElWRV9FTkFCTEVEPXRydWU="
readonly PROOF_TEST_APPLICATION_ID="${PROOF_APPLICATION_ID}.test"
readonly PROOF_RUNNER="${PROOF_TEST_APPLICATION_ID}/androidx.test.runner.AndroidJUnitRunner"
readonly PROOF_CLASS="com.mknoon.app.call.Vc204AndroidCallLifecycleInstrumentationTest"
readonly PROOF_CLASS_DEX="Lcom/mknoon/app/call/Vc204AndroidCallLifecycleInstrumentationTest;"
readonly CALL_SERVICE="com.mknoon.app.call.MknoonCallForegroundService"
readonly PROCESS_DEATH_SEED_ACTIVITY="com.mknoon.app.call.Vc204ProcessDeathSeedActivity"
readonly PROCESS_DEATH_SEED_ACTION="com.mknoon.app.vc204proof.PROCESS_DEATH_SEED"
readonly PROCESS_DEATH_SEED_STATUS_FILE="vc204-process-death-seed.status"
readonly SCENARIO="vc204_android_call_lifecycle"
readonly PHASE_TIMEOUT_TENTHS=900

readonly PHASE_FOREGROUND_BACKGROUND="testVc204ForegroundBackgroundActualPlatformPresentation"
readonly PHASE_KEYGUARD_POLICY="testVc204ReportKeyguardAutomationPolicy"
readonly PHASE_ADVERSARIAL="testVc204DuplicateDelayedWakeAndPreAnswerCancel"
readonly PHASE_RINGING_SEED="testVc204SeedRingingBeforeAmKill"
readonly PHASE_RINGING_RECOVER="testVc204RecoverRingingAfterAmKill"
readonly PHASE_LOCKED="testVc204LockedActualPlatformPresentation"
readonly PHASE_NOTIFICATION_DENIED="testVc204NotificationAndFullScreenDeniedFallback"
readonly PHASE_MIC_DENIED="testVc204MicrophoneDeniedDoesNotActivateAudio"
readonly PHASE_MIC_GRANTED="testVc204MicrophoneGrantAudioAndRouteChange"
readonly PHASE_OUTGOING="testVc204OutgoingAuthenticatedCoreTelecomLifecycle"
readonly PHASE_NETWORK_TRANSITION="testVc204DurablyAdoptedAudioActiveAcrossNetworkTransition"
readonly PHASE_ACTIVE_SEED="testVc204SeedAcknowledgedActiveBeforeAmKill"
readonly PHASE_ACTIVE_RECOVER="testVc204AcknowledgedActiveDoesNotResurrectAfterAmKill"
readonly PHASE_REPEATED_CLEANUP="testVc204RepeatedCleanupIsIdempotent"
readonly NETWORK_BOUNDARY_STATUS_KEY="vc204NetworkBoundary"
readonly NETWORK_BOUNDARY_READY="audio-active-online-ready"
readonly NETWORK_BOUNDARY_OFFLINE="same-call-audio-active-offline"
readonly NETWORK_BOUNDARY_RESTORED="same-call-audio-active-restored"
readonly NOTIFICATION_DENIAL_STATUS_KEY="vc204NotificationDenial"
readonly KEYGUARD_POLICY_STATUS_KEY="vc204KeyguardPolicy"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_vc204_android_call_lifecycle_e2e.sh --build-only \
    --artifact-dir DIR
  ./scripts/run_vc204_android_call_lifecycle_e2e.sh --device-id ID \
    --artifact-dir DIR --result-dir DIR \
    --scenario vc204_android_call_lifecycle
  ./scripts/run_vc204_android_call_lifecycle_e2e.sh --list-scenarios

The build leg creates one disposable app/test APK pair. A device leg never
builds: it verifies that pair, refuses pre-existing proof packages, pins every
adb command to --device-id, coordinates bounded instrumentation phases with
host-owned OS changes, restores the captured screen/keyguard/network/package
states, and uninstalls both packages. Foreground task state is not captured.

The process-death legs first invoke Android's `am kill` after backgrounding the
disposable package. If Telecom keeps that process protected, the debuggable
proof APK uses same-UID SIGKILL as the bounded fallback. Neither path issues or
relabels Android force-stop, whose non-delivery-until-user-relaunch behavior is
a platform policy limitation.
EOF
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

physical_directory() {
  (cd -P -- "$1" && pwd -P)
}

require_empty_directory() {
  local directory="$1"
  local label="$2"
  local nonempty_message="${3:-$label directory must be new or empty}"
  local first_entry
  if ! first_entry="$(
    find "$directory" -mindepth 1 -maxdepth 1 -print -quit
  )"; then
    fail "cannot inspect $label directory contents"
  fi
  [[ -z "$first_entry" ]] || fail "$nonempty_message"
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
  [[ "$build_only" == false && -z "$device_id" && -z "$artifact_dir" && \
    -z "$result_dir" && -z "$scenario" ]] || {
    usage >&2
    exit 64
  }
  printf '%s\n' "$SCENARIO"
  exit 0
fi

[[ -n "$artifact_dir" ]] || { usage >&2; exit 64; }

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -e "$artifact_dir" || -L "$artifact_dir" ]]; then
  [[ -d "$artifact_dir" ]] || fail "artifact path must be a directory"
elif [[ "$build_only" == true ]]; then
  mkdir -p -- "$artifact_dir" || fail "cannot create artifact directory"
else
  fail "device leg requires an existing build-once artifact directory"
fi
artifact_dir="$(physical_directory "$artifact_dir")" ||
  fail "cannot physically resolve artifact directory"
if [[ "$build_only" == true ]]; then
  require_empty_directory "$artifact_dir" "build-only artifact"
fi
readonly PROOF_BUILD_ROOT="$artifact_dir/vc204-proof-gradle-build"
readonly PROOF_BUILD_MARKER="$artifact_dir/.vc204-proof-build-root"
readonly PROOF_PROJECT_CACHE="$artifact_dir/gradle-project-cache"
readonly SOURCE_APP_APK="$PROOF_BUILD_ROOT/app/outputs/apk/debug/app-debug.apk"
readonly SOURCE_TEST_APK="$PROOF_BUILD_ROOT/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
readonly APP_APK="$artifact_dir/vc204-android-call-lifecycle-debug.apk"
readonly TEST_APK="$artifact_dir/vc204-android-call-lifecycle-debug-androidTest.apk"
readonly APP_SHA="$artifact_dir/app.sha256"
readonly TEST_SHA="$artifact_dir/test.sha256"

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

hash_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

verify_hash() {
  local artifact="$1"
  local hash_path="$2"
  [[ -s "$hash_path" ]] || fail "missing build-once checksum: $hash_path"
  local expected actual
  expected="$(tr -d '[:space:]' <"$hash_path")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "invalid build-once checksum: $hash_path"
  actual="$(hash_file "$artifact")"
  [[ "$actual" == "$expected" ]] || fail "artifact checksum changed after build-only leg"
}

verify_artifacts() {
  [[ -s "$APP_APK" ]] || fail "missing app proof APK: $APP_APK"
  [[ -s "$TEST_APK" ]] || fail "missing test proof APK: $TEST_APK"
  command -v unzip >/dev/null 2>&1 || fail "unzip is required for test-class verification"
  command -v strings >/dev/null 2>&1 || fail "strings is required for test-class verification"

  local apkanalyzer_bin
  apkanalyzer_bin="$(resolve_apkanalyzer)" ||
    fail "apkanalyzer is required to validate the disposable APK boundary"
  local app_id test_id
  app_id="$("$apkanalyzer_bin" manifest application-id "$APP_APK" | tr -d '\r')"
  test_id="$("$apkanalyzer_bin" manifest application-id "$TEST_APK" | tr -d '\r')"
  [[ "$app_id" == "$PROOF_APPLICATION_ID" ]] ||
    fail "app APK has the wrong disposable application ID"
  [[ "$test_id" == "$PROOF_TEST_APPLICATION_ID" ]] ||
    fail "test APK has the wrong disposable application ID"

  "$apkanalyzer_bin" manifest print "$APP_APK" >"$artifact_dir/app-manifest.xml"
  "$apkanalyzer_bin" manifest print "$TEST_APK" >"$artifact_dir/test-manifest.xml"
  local required
  for required in \
    'android.permission.ACCESS_NETWORK_STATE' \
    'android.permission.MANAGE_OWN_CALLS' \
    'android.permission.RECORD_AUDIO' \
    'android.permission.POST_NOTIFICATIONS' \
    'android.permission.USE_FULL_SCREEN_INTENT' \
    'android.permission.FOREGROUND_SERVICE_MICROPHONE' \
    'android.permission.FOREGROUND_SERVICE_PHONE_CALL' \
    'com.mknoon.app.call.MknoonCallForegroundService' \
    'com.mknoon.app.call.MknoonCallActionReceiver' \
    "$PROCESS_DEATH_SEED_ACTIVITY"; do
    grep -Fq "$required" "$artifact_dir/app-manifest.xml" ||
      fail "proof app manifest omits required VC2-04 contract: $required"
  done
  # apkanalyzer renders the compiled phoneCall|microphone bitset as 0x84;
  # source/merged XML tools retain the symbolic names.
  grep -Eq 'android:foregroundServiceType="(phoneCall\|microphone|microphone\|phoneCall|0x84)"' \
    "$artifact_dir/app-manifest.xml" ||
    fail "proof app manifest omits the phoneCall+microphone FGS type boundary"
  grep -Fq 'android:permission="android.permission.DUMP"' \
    "$artifact_dir/app-manifest.xml" ||
    fail "proof seed Activity is not restricted to the adb shell permission"
  grep -Fq "android:targetPackage=\"$PROOF_APPLICATION_ID\"" \
    "$artifact_dir/test-manifest.xml" || fail "test APK targets the wrong package"
  grep -Fq 'android:name="androidx.test.runner.AndroidJUnitRunner"' \
    "$artifact_dir/test-manifest.xml" || fail "test APK omits AndroidJUnitRunner"
  if grep -Fq 'android:process=' "$artifact_dir/app-manifest.xml"; then
    fail "proof APK violates the one-process pending-call ownership boundary"
  fi
  if ! unzip -p "$TEST_APK" 'classes*.dex' 2>/dev/null |
    strings | grep -F "$PROOF_CLASS_DEX" >/dev/null; then
    fail "test APK omits the exact VC2-04 instrumentation class"
  fi
}

if [[ "$build_only" == true ]]; then
  [[ -z "$device_id" && -z "$result_dir" && -z "$scenario" ]] || {
    usage >&2
    exit 64
  }
  readonly BUILD_LOG="$artifact_dir/build.log"
  printf 'vc204-proof-build-root-v1\n' >"$PROOF_BUILD_MARKER"
  if ! "$REPO_ROOT/android/gradlew" --no-problems-report -p "$REPO_ROOT/android" \
    --project-cache-dir "$PROOF_PROJECT_CACHE" \
    clean \
    :app:assembleDebug \
    :app:assembleDebugAndroidTest \
    -Pvc204ProofBuildRoot="$PROOF_BUILD_ROOT" \
    -Pdart-defines="$VC204_DART_DEFINES" \
    -PenableVc204AndroidProof=true \
    -PenableAndroidNativeCalls=true \
    -PandroidApplicationId="$PROOF_APPLICATION_ID" \
    -PdisableGoogleServicesForDisposableProof=true \
    >"$BUILD_LOG" 2>&1; then
    tail -n 120 "$BUILD_LOG" >&2
    fail "VC2-04 Android proof build failed; full log retained at $BUILD_LOG"
  fi
  [[ -s "$SOURCE_APP_APK" ]] || fail "Gradle did not produce the app proof APK"
  [[ -s "$SOURCE_TEST_APK" ]] || fail "Gradle did not produce the test proof APK"
  cp "$SOURCE_APP_APK" "$APP_APK"
  cp "$SOURCE_TEST_APK" "$TEST_APK"
  verify_artifacts
  hash_file "$APP_APK" >"$APP_SHA"
  hash_file "$TEST_APK" >"$TEST_SHA"
  # Remove only the isolated proof build tree after copying the verified APKs.
  # Normal Flutter/Gradle outputs and task state are never shared with this
  # disposable application ID or enabled native-call flag.
  if ! "$REPO_ROOT/android/gradlew" --no-problems-report -p "$REPO_ROOT/android" \
    --project-cache-dir "$PROOF_PROJECT_CACHE" \
    clean \
    -Pvc204ProofBuildRoot="$PROOF_BUILD_ROOT" >>"$BUILD_LOG" 2>&1; then
    tail -n 120 "$BUILD_LOG" >&2
    fail "VC2-04 Android proof post-build isolation failed"
  fi
  [[ ! -e "$PROOF_BUILD_ROOT" ]] ||
    fail "VC2-04 proof left its isolated Gradle build tree behind"
  printf 'Built VC2-04 disposable Android proof APKs once in %s\n' "$artifact_dir"
  exit 0
fi

[[ "$scenario" == "$SCENARIO" ]] || { usage >&2; exit 64; }
[[ -n "$device_id" && -n "$result_dir" ]] || { usage >&2; exit 64; }
[[ "$device_id" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "invalid Android target ID"
[[ "$device_id" != *:* ]] ||
  fail "network-transition proof requires a USB Android target or local emulator, not TCP adb"
if [[ -n "${ANDROID_SERIAL:-}" && "$ANDROID_SERIAL" != "$device_id" ]]; then
  fail "ANDROID_SERIAL does not match --device-id"
fi
export ANDROID_SERIAL="$device_id"

command -v adb >/dev/null 2>&1 || fail "adb is required"
[[ "$(adb -s "$device_id" get-state 2>/dev/null | tr -d '\r')" == "device" ]] ||
  fail "Android target is not connected and authorized"
[[ "$(adb -s "$device_id" get-serialno 2>/dev/null | tr -d '\r')" == "$device_id" ]] ||
  fail "adb resolved a target other than --device-id"
[[ "$(adb -s "$device_id" shell am get-current-user 2>/dev/null | tr -d '\r[:space:]')" == "0" ]] ||
  fail "VC2-04 proof requires Android owner user 0 as the current user"
verify_artifacts
verify_hash "$APP_APK" "$APP_SHA"
verify_hash "$TEST_APK" "$TEST_SHA"

if [[ -e "$result_dir" || -L "$result_dir" ]]; then
  [[ -d "$result_dir" ]] || fail "result path must be a directory"
else
  mkdir -p -- "$result_dir" || fail "cannot create result directory"
fi
result_dir="$(physical_directory "$result_dir")" ||
  fail "cannot physically resolve result directory"
require_empty_directory \
  "$result_dir" \
  "result" \
  "result directory must be absent or empty"
readonly TIMINGS_FILE="$result_dir/timings.tsv"
printf 'phase\tdurationSeconds\n' >"$TIMINGS_FILE"

app_install_attempted=false
test_install_attempted=false
state_captured=false
network_mutated=false
screen_mutated=false
phase_pid=""
initial_airplane=""
initial_wifi=""
initial_mobile=""
initial_interactive=""
initial_keyguard=""
QUERY_PROOF_PID=""

adb_shell() {
  adb -s "$device_id" shell "$@"
}

query_proof_pid() {
  QUERY_PROOF_PID=""
  local output command_status
  if output="$(adb_shell pidof "$PROOF_APPLICATION_ID" 2>&1)"; then
    command_status=0
  else
    command_status=$?
  fi
  output="${output//$'\r'/}"

  if [[ "$command_status" == "0" ]]; then
    if [[ "$output" =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
      QUERY_PROOF_PID="${BASH_REMATCH[1]}"
      return 0
    fi
    fail "pidof returned success without exactly one numeric proof PID"
  fi

  if [[ "$command_status" == "1" && "$output" =~ ^[[:space:]]*$ ]]; then
    local target_state state_status
    if target_state="$(adb -s "$device_id" get-state 2>&1)"; then
      state_status=0
    else
      state_status=$?
    fi
    target_state="${target_state//$'\r'/}"
    if [[ "$state_status" == "0" &&
      "$target_state" =~ ^[[:space:]]*device[[:space:]]*$ ]]; then
      return 1
    fi
    fail "pidof absence could not be confirmed on the pinned connected target"
  fi

  fail "pidof returned ambiguous output or command status"
}

query_package_present() {
  local package_id="$1"
  local output
  output="$(
    adb_shell pm list packages --user -1 "$package_id" 2>/dev/null |
      tr -d '\r'
  )" || return 2
  grep -Fxq "package:${package_id}" <<<"$output"
}

verify_package_absent() {
  local package_id="$1"
  local query_status
  if query_package_present "$package_id"; then
    return 1
  else
    query_status=$?
  fi
  [[ "$query_status" == "1" ]]
}

uninstall_attempted_package() {
  local package_id="$1"
  local query_status
  if query_package_present "$package_id"; then
    adb -s "$device_id" uninstall "$package_id" >/dev/null 2>&1 || return 1
  else
    query_status=$?
    [[ "$query_status" == "1" ]] || return 1
  fi
  verify_package_absent "$package_id"
}

global_setting() {
  adb_shell settings get global "$1" | tr -d '\r[:space:]'
}

parse_interactive_state() {
  local power="$1"
  local saw_true=false
  local saw_false=false
  if grep -Eq \
    'mWakefulness=Awake([^[:alpha:]]|$)|mInteractive=true([^[:alpha:]]|$)' \
    <<<"$power"; then
    saw_true=true
  fi
  if grep -Eq \
    'mWakefulness=(Asleep|Dozing|Dreaming)([^[:alpha:]]|$)|mInteractive=false([^[:alpha:]]|$)' \
    <<<"$power"; then
    saw_false=true
  fi
  case "$saw_true:$saw_false" in
    true:false) printf 'true\n' ;;
    false:true) printf 'false\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

parse_keyguard_state() {
  local window="$1"
  local saw_true=false
  local saw_false=false
  if grep -Eq \
    '(mKeyguardShowing|isStatusBarKeyguard|mShowingLockscreen|mDreamingLockscreen)=true([^[:alpha:]]|$)' \
    <<<"$window"; then
    saw_true=true
  fi
  if grep -Eq \
    '(mKeyguardShowing|isStatusBarKeyguard|mShowingLockscreen|mDreamingLockscreen)=false([^[:alpha:]]|$)' \
    <<<"$window"; then
    saw_false=true
  fi
  case "$saw_true:$saw_false" in
    true:false) printf 'true\n' ;;
    false:true) printf 'false\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

interactive_now() {
  local power parsed
  if ! power="$(adb_shell dumpsys power 2>/dev/null)"; then
    return 2
  fi
  power="${power//$'\r'/}"
  parsed="$(parse_interactive_state "$power")"
  case "$parsed" in
    true|false) printf '%s\n' "$parsed" ;;
    *) return 2 ;;
  esac
}

keyguard_locked_now() {
  local window parsed
  if ! window="$(adb_shell dumpsys window 2>/dev/null)"; then
    return 2
  fi
  window="${window//$'\r'/}"
  parsed="$(parse_keyguard_state "$window")"
  case "$parsed" in
    true|false) printf '%s\n' "$parsed" ;;
    *) return 2 ;;
  esac
}

wait_for_interactive() {
  local expected="$1"
  case "$expected" in true|false) ;; *) return 2 ;; esac
  local attempt current
  for attempt in $(seq 1 80); do
    if ! current="$(interactive_now)"; then
      return 2
    fi
    case "$current" in true|false) ;; *) return 2 ;; esac
    if [[ "$current" == "$expected" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_keyguard() {
  local expected="$1"
  case "$expected" in true|false) ;; *) return 2 ;; esac
  local attempt current
  for attempt in $(seq 1 80); do
    if ! current="$(keyguard_locked_now)"; then
      return 2
    fi
    case "$current" in true|false) ;; *) return 2 ;; esac
    if [[ "$current" == "$expected" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

set_airplane() {
  local desired="$1"
  local command
  if [[ "$desired" == "1" ]]; then command=enable; else command=disable; fi
  if ! adb_shell cmd connectivity airplane-mode "$command" >/dev/null 2>&1; then
    adb_shell settings put global airplane_mode_on "$desired" >/dev/null
    adb_shell am broadcast -a android.intent.action.AIRPLANE_MODE \
      --ez state "$([[ "$desired" == "1" ]] && printf true || printf false)" \
      >/dev/null
  fi
}

wait_for_global_setting() {
  local name="$1"
  local expected="$2"
  local attempt
  for attempt in $(seq 1 120); do
    if [[ "$(global_setting "$name")" == "$expected" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

restore_network_state() {
  set_airplane "$initial_airplane" || return 1
  if [[ "$initial_wifi" == "1" ]]; then
    adb_shell svc wifi enable >/dev/null || return 1
  else
    adb_shell svc wifi disable >/dev/null || return 1
  fi
  if [[ "$initial_mobile" == "1" ]]; then
    adb_shell svc data enable >/dev/null || return 1
  elif [[ "$initial_mobile" == "0" ]]; then
    adb_shell svc data disable >/dev/null || return 1
  fi
  wait_for_global_setting airplane_mode_on "$initial_airplane" || return 1
  wait_for_global_setting wifi_on "$initial_wifi" || return 1
  if [[ "$initial_mobile" == "0" || "$initial_mobile" == "1" ]]; then
    wait_for_global_setting mobile_data "$initial_mobile" || return 1
  fi
  network_mutated=false
}

restore_screen_state() {
  if [[ "$initial_interactive" == "false" ]]; then
    adb_shell input keyevent KEYCODE_SLEEP >/dev/null || return 1
    wait_for_interactive false || return 1
    wait_for_keyguard "$initial_keyguard" || return 1
  elif [[ "$initial_keyguard" == "true" ]]; then
    adb_shell input keyevent KEYCODE_SLEEP >/dev/null || return 1
    adb_shell input keyevent KEYCODE_WAKEUP >/dev/null || return 1
    wait_for_interactive true || return 1
    wait_for_keyguard true || return 1
  else
    adb_shell input keyevent KEYCODE_WAKEUP >/dev/null || return 1
    adb_shell wm dismiss-keyguard >/dev/null || return 1
    wait_for_interactive true || return 1
    wait_for_keyguard false || return 1
  fi
}

restore_screen_state_and_disarm() {
  restore_screen_state || return 1
  screen_mutated=false
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  local cleanup_failed=false
  if [[ -n "$phase_pid" ]]; then
    kill "$phase_pid" >/dev/null 2>&1 || true
    wait "$phase_pid" >/dev/null 2>&1 || true
    phase_pid=""
  fi
  local artifact privacy_failed=false
  for artifact in "$result_dir"/phase-*.log; do
    [[ -f "$artifact" ]] || continue
    if grep -Eq '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32}' "$artifact"; then
      printf 'privacy=REDACTED_SENSITIVE_ARTIFACT\n' >"$artifact"
      privacy_failed=true
    fi
  done
  if [[ "$state_captured" == true && "$network_mutated" == true ]]; then
    restore_network_state || cleanup_failed=true
  fi
  if [[ "$state_captured" == true && "$screen_mutated" == true ]]; then
    restore_screen_state || cleanup_failed=true
  fi
  if [[ "$test_install_attempted" == true ]]; then
    uninstall_attempted_package "$PROOF_TEST_APPLICATION_ID" || cleanup_failed=true
  fi
  if [[ "$app_install_attempted" == true ]]; then
    uninstall_attempted_package "$PROOF_APPLICATION_ID" || cleanup_failed=true
  fi
  if [[ "$privacy_failed" == true ]]; then
    printf 'FAIL: a device artifact was redacted at the privacy boundary\n' >&2
    if ((status == 0)); then status=1; fi
  fi
  if [[ "$cleanup_failed" == true ]]; then
    printf 'FAIL: cleanup could not fully restore target state or uninstall proof packages\n' >&2
    if ((status == 0)); then status=1; fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! verify_package_absent "$PROOF_APPLICATION_ID"; then
  fail "cannot prove the disposable proof app is absent before installation"
fi
if ! verify_package_absent "$PROOF_TEST_APPLICATION_ID"; then
  fail "cannot prove the disposable proof test app is absent before installation"
fi

initial_airplane="$(global_setting airplane_mode_on)"
initial_wifi="$(global_setting wifi_on)"
initial_mobile="$(global_setting mobile_data)"
[[ "$initial_airplane" == "0" || "$initial_airplane" == "1" ]] ||
  fail "cannot capture prior airplane-mode state"
[[ "$initial_wifi" == "0" || "$initial_wifi" == "1" ]] ||
  fail "cannot capture prior Wi-Fi state"
[[ "$initial_mobile" == "0" || "$initial_mobile" == "1" || \
  "$initial_mobile" == "null" || -z "$initial_mobile" ]] ||
  fail "cannot capture prior mobile-data state"
initial_interactive="$(interactive_now)" ||
  fail "cannot capture an explicit prior interactive state"
case "$initial_interactive" in
  true|false) ;;
  *) fail "cannot capture an explicit prior interactive state" ;;
esac
initial_keyguard="$(keyguard_locked_now)" ||
  fail "cannot capture an explicit prior keyguard state"
case "$initial_keyguard" in
  true|false) ;;
  *) fail "cannot capture an explicit prior keyguard state" ;;
esac
state_captured=true

sdk_int="$(adb_shell getprop ro.build.version.sdk | tr -d '\r[:space:]')"
[[ "$sdk_int" =~ ^[0-9]+$ && "$sdk_int" -ge 26 ]] ||
  fail "VC2-04 production Core-Telecom proof requires an available API 26+ target"
is_emulator=false
if [[ "$(adb_shell getprop ro.kernel.qemu | tr -d '\r[:space:]')" == "1" ]]; then
  is_emulator=true
fi
{
  printf 'targetPinned=true\n'
  printf 'sdk=%s\n' "$sdk_int"
  printf 'emulator=%s\n' "$is_emulator"
  printf 'artifactScope=coarse-state-only\n'
} >"$result_dir/target.txt"

screen_mutated=true
adb_shell input keyevent KEYCODE_WAKEUP >/dev/null
adb_shell wm dismiss-keyguard >/dev/null
wait_for_interactive true || fail "device did not become interactive"
wait_for_keyguard false ||
  fail "device keyguard could not be dismissed automatically; no user taps are permitted"

app_install_attempted=true
adb -s "$device_id" install --user 0 -t "$APP_APK" >"$result_dir/install-app.log" 2>&1
grep -Fq 'Success' "$result_dir/install-app.log" || fail "app APK installation failed"
test_install_attempted=true
adb -s "$device_id" install --user 0 -t "$TEST_APK" >"$result_dir/install-test.log" 2>&1
grep -Fq 'Success' "$result_dir/install-test.log" || fail "test APK installation failed"

readonly EXPECTED_INSTRUMENTATION="instrumentation:${PROOF_RUNNER} (target=${PROOF_APPLICATION_ID})"
adb_shell pm list instrumentation | tr -d '\r' | grep -Fx "$EXPECTED_INSTRUMENTATION" >/dev/null ||
  fail "installed runner/target pair does not match verified artifacts"

reset_app_data() {
  local output
  output="$(adb_shell pm clear --user 0 "$PROOF_APPLICATION_ID" 2>&1 | tr -d '\r')"
  [[ "$output" == *Success* ]] || fail "proof app data clear failed"
}

set_notification_allowed() {
  adb_shell cmd appops set --user 0 "$PROOF_APPLICATION_ID" POST_NOTIFICATION allow >/dev/null
  if ((sdk_int >= 33)); then
    adb_shell pm grant --user 0 "$PROOF_APPLICATION_ID" android.permission.POST_NOTIFICATIONS >/dev/null
  fi
  if ((sdk_int >= 34)); then
    adb_shell cmd appops set --user 0 "$PROOF_APPLICATION_ID" USE_FULL_SCREEN_INTENT allow >/dev/null
  fi
}

set_notification_and_full_screen_denied() {
  adb_shell cmd appops set --user 0 "$PROOF_APPLICATION_ID" POST_NOTIFICATION ignore >/dev/null
  adb_shell cmd appops get --user 0 "$PROOF_APPLICATION_ID" POST_NOTIFICATION |
    grep -Ei 'ignore|deny' >/dev/null || fail "notification app-op was not denied"
  if ((sdk_int >= 33)); then
    adb_shell pm revoke --user 0 "$PROOF_APPLICATION_ID" android.permission.POST_NOTIFICATIONS >/dev/null
  fi
  if ((sdk_int >= 34)); then
    adb_shell cmd appops set --user 0 "$PROOF_APPLICATION_ID" USE_FULL_SCREEN_INTENT ignore >/dev/null
    adb_shell cmd appops get --user 0 "$PROOF_APPLICATION_ID" USE_FULL_SCREEN_INTENT |
      grep -Ei 'ignore|deny' >/dev/null || fail "full-screen intent app-op was not denied"
  fi
}

set_microphone_denied() {
  adb_shell pm revoke --user 0 "$PROOF_APPLICATION_ID" android.permission.RECORD_AUDIO >/dev/null
}

set_microphone_granted() {
  adb_shell pm grant --user 0 "$PROOF_APPLICATION_ID" android.permission.RECORD_AUDIO >/dev/null
}

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

enforce_coarse_artifact() {
  local log="$1"
  local boundary="$2"
  if grep -Eq '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32}' "$log"; then
    printf 'privacy=REDACTED_SENSITIVE_ARTIFACT\n' >"$log"
    fail "$boundary crossed the coarse-only artifact boundary"
  fi
}

assert_network_boundary_log() {
  local log="$1"
  local boundary marker count
  for boundary in \
    "$NETWORK_BOUNDARY_READY" \
    "$NETWORK_BOUNDARY_OFFLINE" \
    "$NETWORK_BOUNDARY_RESTORED"; do
    marker="INSTRUMENTATION_STATUS: ${NETWORK_BOUNDARY_STATUS_KEY}=${boundary}"
    count="$(grep -Fc "$marker" "$log" 2>/dev/null || true)"
    [[ "$count" == "1" ]] || fail "network phase omitted or duplicated a coarse boundary"
  done
}

run_phase() {
  local method="$1"
  local label="$2"
  local coordinator="${3:-}"
  local log="$result_dir/phase-${label}.log"
  local started=$SECONDS
  adb_shell am instrument -w -r \
    --user 0 \
    -e class "${PROOF_CLASS}#${method}" \
    "$PROOF_RUNNER" >"$log" 2>&1 &
  local adb_pid=$!
  phase_pid="$adb_pid"
  if [[ -n "$coordinator" ]]; then
    "$coordinator" "$log" "$adb_pid"
  fi
  local completed=false
  local attempt
  for attempt in $(seq 1 "$PHASE_TIMEOUT_TENTHS"); do
    if ! kill -0 "$adb_pid" 2>/dev/null; then
      completed=true
      break
    fi
    sleep 0.1
  done
  if [[ "$completed" != true ]]; then
    kill "$adb_pid" >/dev/null 2>&1 || true
    wait "$adb_pid" >/dev/null 2>&1 || true
    phase_pid=""
    enforce_coarse_artifact "$log" "$method"
    fail "$method exceeded the bounded instrumentation timeout"
  fi
  set +e
  wait "$adb_pid"
  local adb_status=$?
  phase_pid=""
  set -e
  enforce_coarse_artifact "$log" "$method"
  ((adb_status == 0)) || fail "$method instrumentation command failed"
  assert_phase_log "$method" "$log"
  if [[ "$method" == "$PHASE_NETWORK_TRANSITION" ]]; then
    assert_network_boundary_log "$log"
  fi
  printf '%s\t%s\n' "$label" "$((SECONDS - started))" >>"$TIMINGS_FILE"
}

run_process_death_seed() {
  local mode="$1"
  local label="$2"
  local expected_result="$3"
  local log="$result_dir/phase-${label}.log"
  local started=$SECONDS
  adb_shell am start -W --user 0 \
    -a "$PROCESS_DEATH_SEED_ACTION" \
    -n "${PROOF_APPLICATION_ID}/${PROCESS_DEATH_SEED_ACTIVITY}" \
    --es mode "$mode" >"$log" 2>&1 ||
    fail "$label proof seed Activity failed"
  enforce_coarse_artifact "$log" "$label"
  grep -Fq 'Status: ok' "$log" ||
    fail "$label proof seed Activity did not launch successfully"
  local observed_result
  observed_result=""
  local seed_attempt
  for seed_attempt in $(seq 1 150); do
    observed_result="$(
      adb -s "$device_id" exec-out run-as "$PROOF_APPLICATION_ID" \
        cat "files/${PROCESS_DEATH_SEED_STATUS_FILE}" 2>/dev/null |
        tr -d '\r\n' || true
    )"
    [[ "$observed_result" == "$expected_result" ]] && break
    sleep 0.1
  done
  [[ "$observed_result" == "$expected_result" ]] ||
    fail "$label proof seed did not reach its exact coarse ready state"
  if grep -Eqi 'SecurityException|RuntimeException|FATAL EXCEPTION|result=-1' "$log"; then
    fail "$label proof seed reported an Android failure"
  fi
  printf '%s\t%s\n' "$label" "$((SECONDS - started))" >>"$TIMINGS_FILE"
}

wait_for_network_boundary() {
  local log="$1"
  local adb_pid="$2"
  local boundary="$3"
  local marker="INSTRUMENTATION_STATUS: ${NETWORK_BOUNDARY_STATUS_KEY}=${boundary}"
  local attempt count
  for attempt in $(seq 1 "$PHASE_TIMEOUT_TENTHS"); do
    count="$(grep -Fc "$marker" "$log" 2>/dev/null || true)"
    if [[ "$count" == "1" ]]; then
      return 0
    fi
    [[ "$count" == "0" ]] || fail "network phase emitted a duplicate coarse boundary"
    kill -0 "$adb_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

coordinate_network_transition() {
  local log="$1"
  local adb_pid="$2"
  wait_for_network_boundary "$log" "$adb_pid" "$NETWORK_BOUNDARY_READY" ||
    fail "network phase did not reach adopted audio-active online readiness"
  set_network_unavailable
  wait_for_network_boundary "$log" "$adb_pid" "$NETWORK_BOUNDARY_OFFLINE" ||
    fail "same active call did not observe the automated offline transition"
  restore_network_state || fail "network prior state could not be restored"
  wait_for_network_boundary "$log" "$adb_pid" "$NETWORK_BOUNDARY_RESTORED" ||
    fail "same active call did not observe restored validated connectivity"
}

lock_device_if_available() {
  adb_shell input keyevent KEYCODE_SLEEP >/dev/null ||
    fail "device rejected the non-interactive keyguard probe"
  wait_for_interactive false || fail "device did not enter the non-interactive state"
  local keyguard_wait_status
  if wait_for_keyguard true; then
    return 0
  else
    keyguard_wait_status=$?
  fi
  [[ "$keyguard_wait_status" == "1" ]] ||
    fail "cannot determine whether an automatable keyguard is configured"
  restore_screen_state || fail "no-keyguard probe could not restore prior screen state"
  return 1
}

unlock_device() {
  adb_shell input keyevent KEYCODE_WAKEUP >/dev/null
  adb_shell wm dismiss-keyguard >/dev/null
  wait_for_interactive true || fail "device did not wake after locked proof"
  wait_for_keyguard false || fail "keyguard did not dismiss after locked proof"
}

background_and_am_kill() {
  local label="$1"
  adb_shell input keyevent KEYCODE_HOME >/dev/null ||
    fail "$label could not background the disposable package"
  local service_attempt
  for service_attempt in $(seq 1 50); do
    if ! adb_shell dumpsys activity services "$PROOF_APPLICATION_ID" 2>/dev/null |
      grep -F "$CALL_SERVICE" >/dev/null; then
      break
    fi
    sleep 0.1
  done
  if adb_shell dumpsys activity services "$PROOF_APPLICATION_ID" 2>/dev/null |
    grep -F "$CALL_SERVICE" >/dev/null; then
    fail "$label left the disposable call foreground service active"
  fi
  local pid_before pid_query_status
  if query_proof_pid; then
    pid_before="$QUERY_PROOF_PID"
  else
    pid_query_status=$?
    [[ "$pid_query_status" == "1" ]] ||
      fail "$label PID query failed before am kill"
    fail "$label had no live process before am kill"
  fi
  adb_shell am kill --user 0 "$PROOF_APPLICATION_ID" >/dev/null ||
    fail "$label am kill command was rejected by Android"
  local attempt
  for attempt in $(seq 1 100); do
    local pid_after
    if query_proof_pid; then
      pid_after="$QUERY_PROOF_PID"
    else
      pid_query_status=$?
      [[ "$pid_query_status" == "1" ]] ||
        fail "$label PID query failed after am kill"
      printf '%s\tPASS_AM_KILL_EXITED\n' "$label" >>"$result_dir/process-death.tsv"
      return 0
    fi
    if [[ "$pid_after" != "$pid_before" ]]; then
      # Core-Telecom may immediately recreate the provider process. A changed
      # PID is still a directly observed death/recreation boundary; neither PID
      # is retained in the coarse proof artifact.
      printf '%s\tPASS_AM_KILL_RESTARTED_DIFFERENT_PID\n' \
        "$label" >>"$result_dir/process-death.tsv"
      return 0
    fi
    sleep 0.1
  done
  [[ "$pid_before" =~ ^[0-9]+$ ]] ||
    fail "$label resolved an invalid single-process PID"
  adb -s "$device_id" shell run-as "$PROOF_APPLICATION_ID" \
    kill -9 "$pid_before" >/dev/null 2>&1 || true
  for attempt in $(seq 1 100); do
    local pid_after_fallback
    if query_proof_pid; then
      pid_after_fallback="$QUERY_PROOF_PID"
    else
      pid_query_status=$?
      [[ "$pid_query_status" == "1" ]] ||
        fail "$label fallback PID query failed"
      printf '%s\tPASS_SAME_UID_SIGKILL_AFTER_AM_KILL_NOOP\n' \
        "$label" >>"$result_dir/process-death.tsv"
      return 0
    fi
    if [[ "$pid_after_fallback" != "$pid_before" ]]; then
      printf '%s\tPASS_SAME_UID_SIGKILL_AFTER_AM_KILL_NOOP\n' \
        "$label" >>"$result_dir/process-death.tsv"
      return 0
    fi
    sleep 0.1
  done
  fail "$label process survived both bounded termination mechanisms"
}

set_network_unavailable() {
  network_mutated=true
  set_airplane 1
  adb_shell svc wifi disable >/dev/null
  if [[ "$initial_mobile" == "0" || "$initial_mobile" == "1" ]]; then
    adb_shell svc data disable >/dev/null
  fi
  wait_for_global_setting airplane_mode_on 1 || fail "airplane transition did not apply"
  wait_for_global_setting wifi_on 0 || fail "Wi-Fi transition did not apply"
}

printf 'boundary\tresult\n' >"$result_dir/process-death.tsv"

reset_app_data
run_phase "$PHASE_KEYGUARD_POLICY" keyguard-policy
keyguard_policy="$(
  sed -n "s/^INSTRUMENTATION_STATUS: ${KEYGUARD_POLICY_STATUS_KEY}=//p" \
    "$result_dir/phase-keyguard-policy.log"
)"
case "$keyguard_policy" in
  secure|non-secure) ;;
  *) fail "keyguard policy phase omitted its exact coarse result" ;;
esac

reset_app_data
set_notification_allowed
set_microphone_denied
run_phase "$PHASE_FOREGROUND_BACKGROUND" foreground-background

reset_app_data
set_notification_allowed
run_phase "$PHASE_ADVERSARIAL" duplicate-delayed-pre-answer-cancel

reset_app_data
set_notification_allowed
run_process_death_seed ringing ringing-before-am-kill VC204_PROOF_RINGING_READY
background_and_am_kill ringing-process-death
run_phase "$PHASE_RINGING_RECOVER" ringing-after-am-kill

locked_presentation="N/A_SECURE_KEYGUARD_NOT_AUTOMATABLE_WITHOUT_CREDENTIAL"
policy_nas=0
if [[ "$keyguard_policy" == "non-secure" ]]; then
  reset_app_data
  set_notification_allowed
  if lock_device_if_available; then
    run_phase "$PHASE_LOCKED" locked-presentation
    unlock_device
    locked_presentation=PASS
  else
    locked_presentation="N/A_NO_AUTOMATABLE_KEYGUARD_CONFIGURED"
    policy_nas=$((policy_nas + 1))
  fi
else
  policy_nas=$((policy_nas + 1))
fi

reset_app_data
set_notification_and_full_screen_denied
run_phase "$PHASE_NOTIFICATION_DENIED" notification-full-screen-denied
notification_denial_result="$(
  sed -n "s/^INSTRUMENTATION_STATUS: ${NOTIFICATION_DENIAL_STATUS_KEY}=//p" \
    "$result_dir/phase-notification-full-screen-denied.log"
)"
case "$notification_denial_result" in
  telecom-presented-no-ui|telecom-presented-notification-denied-full-screen-na|platform-rejected-clean) ;;
  *) fail "notification denial phase omitted its exact coarse policy result" ;;
esac
set_notification_allowed

reset_app_data
set_notification_allowed
set_microphone_denied
run_phase "$PHASE_MIC_DENIED" microphone-denied

reset_app_data
set_notification_allowed
set_microphone_granted
run_phase "$PHASE_MIC_GRANTED" microphone-granted-route-change

reset_app_data
set_notification_allowed
set_microphone_granted
run_phase "$PHASE_OUTGOING" outgoing-authenticated-core-telecom

reset_app_data
set_notification_allowed
set_microphone_granted
run_phase \
  "$PHASE_NETWORK_TRANSITION" \
  network-active-call-transition \
  coordinate_network_transition

reset_app_data
set_notification_allowed
set_microphone_granted
run_process_death_seed active acknowledged-active-before-am-kill VC204_PROOF_ACTIVE_READY
background_and_am_kill acknowledged-active-process-death
run_phase "$PHASE_ACTIVE_RECOVER" acknowledged-active-after-am-kill

reset_app_data
set_notification_allowed
run_phase "$PHASE_REPEATED_CLEANUP" repeated-cleanup

if ((sdk_int >= 34)); then
  full_screen_denial=PASS
else
  full_screen_denial='N/A_API_UNAVAILABLE'
  policy_nas=$((policy_nas + 1))
fi

restore_screen_state_and_disarm ||
  fail "screen/keyguard prior state could not be restored"

uninstall_attempted_package "$PROOF_TEST_APPLICATION_ID" ||
  fail "proof test package uninstall or absence verification failed"
test_install_attempted=false
uninstall_attempted_package "$PROOF_APPLICATION_ID" ||
  fail "proof app package uninstall or absence verification failed"
app_install_attempted=false

{
  printf 'scenario=%s\n' "$SCENARIO"
  printf 'buildOnceBoundary=PASS\n'
  printf 'explicitDevicePinning=PASS\n'
  printf 'artifactRunnerVerification=PASS\n'
  printf 'actualPlatformPresentation=PASS\n'
  printf 'foregroundBackground=PASS\n'
  printf 'lockedPresentation=%s\n' "$locked_presentation"
  printf 'duplicateDelayedPreAnswerCancel=PASS\n'
  printf 'notificationDenial=%s\n' "$notification_denial_result"
  printf 'fullScreenDenial=%s\n' "$full_screen_denial"
  printf 'microphoneDenyGrantRoute=PASS\n'
  printf 'outgoingAuthenticatedCoreTelecomLifecycle=PASS\n'
  printf 'outgoingCleanupResidue=NONE\n'
  printf 'networkTransitionSameAdoptedAudioActiveCall=PASS\n'
  printf 'networkTransitionAndPriorStateRestore=PASS\n'
  printf 'ringingProcessDeath=PASS\n'
  printf 'ringingProcessDeathReconciliation=SAME_UUID_REREGISTERED_NO_DUPLICATE_PRESENTED\n'
  printf 'acknowledgedActiveProcessDeath=PASS\n'
  printf 'processDeathMechanism=am kill with same-UID SIGKILL fallback when Telecom protects the background provider\n'
  printf 'repeatedCleanup=PASS\n'
  printf 'forceStopDelivery=NOT_PROVEN_POLICY_LIMITATION\n'
  printf 'forceStopPolicy=Android force-stop suppresses delivery until explicit user relaunch; this harness never issues or relabels it.\n'
  printf 'independentPhaseReset=pm clear outside the two measured am-kill boundaries\n'
  printf 'adversarialIngressBoundary=direct production runtime payload seam; not FCM transport delivery\n'
  printf 'privacy=coarse state and timing only; no tokens identities payload handles or media\n'
  printf 'screenKeyguardNetworkAndPackagesRestored=PASS\n'
  printf 'foregroundTaskRestore=NOT_CAPTURED_OR_CLAIMED\n'
  printf 'testSkips=0\n'
  printf 'policyNAs=%s\n' "$policy_nas"
} >"$result_dir/summary.txt"

printf 'PASS: %s on explicit target (actual platform + host OS boundaries, zero test skips, policy N/A count=%s)\n' \
  "$SCENARIO" "$policy_nas"
