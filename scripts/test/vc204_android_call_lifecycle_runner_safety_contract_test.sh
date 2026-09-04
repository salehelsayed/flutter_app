#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT_DIR/scripts/run_vc204_android_call_lifecycle_e2e.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

stage_runner() {
  local staged_repo="$1"
  mkdir -p "$staged_repo/scripts" "$staged_repo/android"
  cp "$RUNNER" "$staged_repo/scripts/run_vc204_android_call_lifecycle_e2e.sh"
  chmod +x "$staged_repo/scripts/run_vc204_android_call_lifecycle_e2e.sh"
  cat >"$staged_repo/android/gradlew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: >"$GRADLE_CALLED"
exit 97
EOF
  chmod +x "$staged_repo/android/gradlew"
}

run_expect_failure() {
  local output="$1"
  shift
  local exit_code
  set +e
  "$@" >"$output" 2>&1
  exit_code=$?
  set -e
  [[ "$exit_code" -ne 0 ]] || fail "command unexpectedly passed: $*"
}

assert_only_canary() {
  local directory="$1"
  local expected="$2"
  [[ "$(<"$directory/canary.txt")" == "$expected" ]] ||
    fail "canary content changed in $directory"
  local entry_count
  entry_count="$(find "$directory" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d '[:space:]')"
  [[ "$entry_count" == "1" ]] ||
    fail "refused directory gained files before the safety check"
}

# A symlink operand is not traversed by the default find policy. The runner
# must resolve it physically before deciding whether the target is empty.
build_repo="$tmp_dir/build-repo"
stage_runner "$build_repo"
build_target="$tmp_dir/build-target"
mkdir -p "$build_target"
printf 'build-canary\n' >"$build_target/canary.txt"
ln -s "$build_target" "$tmp_dir/build-link"
build_output="$tmp_dir/build-symlink.out"
run_expect_failure "$build_output" \
  env GRADLE_CALLED="$tmp_dir/build-gradle-called" \
  "$build_repo/scripts/run_vc204_android_call_lifecycle_e2e.sh" \
  --build-only --artifact-dir "$tmp_dir/build-link"
grep -Fq 'build-only artifact directory must be new or empty' "$build_output" ||
  fail "non-empty physical artifact target did not fail at the emptiness boundary"
[[ ! -e "$tmp_dir/build-gradle-called" ]] ||
  fail "artifact symlink refusal reached Gradle"
assert_only_canary "$build_target" 'build-canary'

# Directory listing failure is uncertainty, not evidence that a directory is
# empty. It must fail before the build marker or any build command is written.
find_fail_bin="$tmp_dir/find-fail-bin"
mkdir -p "$find_fail_bin"
cat >"$find_fail_bin/find" <<'EOF'
#!/usr/bin/env bash
exit 74
EOF
chmod +x "$find_fail_bin/find"
empty_artifact="$tmp_dir/empty-artifact"
mkdir -p "$empty_artifact"
find_output="$tmp_dir/artifact-find-error.out"
run_expect_failure "$find_output" \
  env PATH="$find_fail_bin:$PATH" \
  GRADLE_CALLED="$tmp_dir/find-error-gradle-called" \
  "$build_repo/scripts/run_vc204_android_call_lifecycle_e2e.sh" \
  --build-only --artifact-dir "$empty_artifact"
grep -Fq 'cannot inspect build-only artifact directory contents' "$find_output" ||
  fail "artifact find error was not reported as an inspection failure"
[[ ! -e "$empty_artifact/.vc204-proof-build-root" ]] ||
  fail "artifact find error wrote the build marker"
[[ ! -e "$tmp_dir/find-error-gradle-called" ]] ||
  fail "artifact find error reached Gradle"

device_repo="$tmp_dir/device-repo"
stage_runner "$device_repo"
device_artifact="$tmp_dir/device-artifact"
mkdir -p "$device_artifact"
printf 'app fixture\n' >"$device_artifact/vc204-android-call-lifecycle-debug.apk"
printf 'test fixture\n' >"$device_artifact/vc204-android-call-lifecycle-debug-androidTest.apk"
shasum -a 256 "$device_artifact/vc204-android-call-lifecycle-debug.apk" |
  awk '{print $1}' >"$device_artifact/app.sha256"
shasum -a 256 "$device_artifact/vc204-android-call-lifecycle-debug-androidTest.apk" |
  awk '{print $1}' >"$device_artifact/test.sha256"

device_bin="$tmp_dir/device-bin"
mkdir -p "$device_bin"
cat >"$device_bin/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == -s && "${2:-}" == fixture-serial ]] || exit 91
shift 2
case "${1:-}" in
  get-state)
    printf 'device\n'
    ;;
  get-serialno)
    printf 'fixture-serial\n'
    ;;
  shell)
    shift
    case "$*" in
      'am get-current-user') printf '0\n' ;;
      'pm list packages --user -1 com.mknoon.app.vc204proof'|\
      'pm list packages --user -1 com.mknoon.app.vc204proof.test') exit 74 ;;
      *) exit 92 ;;
    esac
    ;;
  *) exit 93 ;;
esac
EOF
chmod +x "$device_bin/adb"

cat >"$device_bin/apkanalyzer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == manifest ]] || exit 81
case "${2:-}" in
  application-id)
    case "${3:-}" in
      *androidTest.apk) printf 'com.mknoon.app.vc204proof.test\n' ;;
      *) printf 'com.mknoon.app.vc204proof\n' ;;
    esac
    ;;
  print)
    cat <<'MANIFEST'
android.permission.ACCESS_NETWORK_STATE
android.permission.MANAGE_OWN_CALLS
android.permission.RECORD_AUDIO
android.permission.POST_NOTIFICATIONS
android.permission.USE_FULL_SCREEN_INTENT
android.permission.FOREGROUND_SERVICE_MICROPHONE
android.permission.FOREGROUND_SERVICE_PHONE_CALL
com.mknoon.app.call.MknoonCallForegroundService
com.mknoon.app.call.MknoonCallActionReceiver
com.mknoon.app.call.Vc204ProcessDeathSeedActivity
android:foregroundServiceType="phoneCall|microphone"
android:permission="android.permission.DUMP"
android:targetPackage="com.mknoon.app.vc204proof"
android:name="androidx.test.runner.AndroidJUnitRunner"
MANIFEST
    ;;
  *) exit 82 ;;
esac
EOF
chmod +x "$device_bin/apkanalyzer"

cat >"$device_bin/unzip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'Lcom/mknoon/app/call/Vc204AndroidCallLifecycleInstrumentationTest;\n'
EOF
chmod +x "$device_bin/unzip"

cat >"$device_bin/strings" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat
EOF
chmod +x "$device_bin/strings"

run_device_refusal() {
  local output="$1"
  local result_path="$2"
  local path_value="$device_bin:$PATH"
  if [[ -n "${FIND_OVERRIDE_DIR:-}" ]]; then
    path_value="$FIND_OVERRIDE_DIR:$path_value"
  fi
  run_expect_failure "$output" \
    env PATH="$path_value" \
    "$device_repo/scripts/run_vc204_android_call_lifecycle_e2e.sh" \
    --device-id fixture-serial \
    --artifact-dir "$device_artifact" \
    --result-dir "$result_path" \
    --scenario vc204_android_call_lifecycle
}

result_target="$tmp_dir/result-target"
mkdir -p "$result_target"
printf 'result-canary\n' >"$result_target/canary.txt"
ln -s "$result_target" "$tmp_dir/result-link"
result_output="$tmp_dir/result-symlink.out"
run_device_refusal "$result_output" "$tmp_dir/result-link"
grep -Fq 'result directory must be absent or empty' "$result_output" ||
  fail "non-empty physical result target did not fail at the emptiness boundary"
assert_only_canary "$result_target" 'result-canary'

empty_result="$tmp_dir/empty-result"
mkdir -p "$empty_result"
result_find_output="$tmp_dir/result-find-error.out"
FIND_OVERRIDE_DIR="$find_fail_bin" run_device_refusal \
  "$result_find_output" "$empty_result"
grep -Fq 'cannot inspect result directory contents' "$result_find_output" ||
  fail "result find error was not reported as an inspection failure"
[[ ! -e "$empty_result/timings.tsv" ]] ||
  fail "result find error wrote a timing artifact"

extract_function() {
  local function_name="$1"
  awk -v signature="^${function_name}\\(\\)" '
    $0 ~ signature { copying = 1 }
    copying { print }
    copying && $0 == "}" { found = 1; exit }
    END { if (!found) exit 1 }
  ' "$RUNNER"
}

# One fail-closed helper owns pidof interpretation. The three process-death
# probes must call it rather than reinterpreting command output independently.
pidof_count="$(grep -Fc 'pidof "$PROOF_APPLICATION_ID"' "$RUNNER")"
[[ "$pidof_count" == "1" ]] ||
  fail "pidof is not centralized in one proof-PID query helper"
query_pid_count="$(grep -Ec '(^|[^[:alnum:]_])query_proof_pid([^[:alnum:]_]|$)' "$RUNNER")"
[[ "$query_pid_count" == "4" ]] ||
  fail "the helper definition plus all three PID probes were not found"

pid_probe="$tmp_dir/pid-probe.sh"
cat >"$pid_probe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}
device_id=fixture-serial
readonly PROOF_APPLICATION_ID=com.mknoon.app.vc204proof
QUERY_PROOF_PID=""
adb_shell() {
  adb -s "$device_id" shell "$@"
}
EOF
extract_function query_proof_pid >>"$pid_probe"
cat >>"$pid_probe" <<'EOF'
if query_proof_pid; then
  printf 'present:%s\n' "$QUERY_PROOF_PID"
  exit 0
else
  query_status=$?
fi
if [[ "$query_status" == "1" ]]; then
  printf 'absent\n'
  exit 0
fi
exit "$query_status"
EOF
chmod +x "$pid_probe"

pid_bin="$tmp_dir/pid-bin"
mkdir -p "$pid_bin"
cat >"$pid_bin/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PID_COMMAND_LOG"
[[ "${1:-}" == -s && "${2:-}" == fixture-serial ]] || exit 91
shift 2
case "${1:-}" in
  shell)
    shift
    [[ "$*" == 'pidof com.mknoon.app.vc204proof' ]] || exit 92
    case "$PID_MODE" in
      one) printf ' 1234\r\n' ;;
      absent-connected|absent-offline|absent-state-error) exit 1 ;;
      zero-empty) exit 0 ;;
      multiple) printf '1234 5678\n' ;;
      one-output) printf 'pidof: unavailable\n'; exit 1 ;;
      two-empty) exit 2 ;;
      *) exit 93 ;;
    esac
    ;;
  get-state)
    case "$PID_MODE" in
      absent-connected) printf 'device\n' ;;
      absent-offline) printf 'offline\n' ;;
      absent-state-error) exit 4 ;;
      *) exit 94 ;;
    esac
    ;;
  *) exit 95 ;;
esac
EOF
chmod +x "$pid_bin/adb"

run_pid_probe() {
  local mode="$1"
  local output="$2"
  : >"$tmp_dir/pid-commands.log"
  set +e
  env PATH="$pid_bin:$PATH" \
    PID_MODE="$mode" \
    PID_COMMAND_LOG="$tmp_dir/pid-commands.log" \
    "$pid_probe" >"$output" 2>&1
  PID_PROBE_STATUS=$?
  set -e
}

run_pid_probe one "$tmp_dir/pid-one.out"
[[ "$PID_PROBE_STATUS" == "0" ]] || fail "one numeric PID was rejected"
grep -Fxq 'present:1234' "$tmp_dir/pid-one.out" ||
  fail "one numeric PID was not normalized exactly"

run_pid_probe absent-connected "$tmp_dir/pid-absent.out"
[[ "$PID_PROBE_STATUS" == "0" ]] ||
  fail "status 1 plus empty output on a connected target was not absence"
grep -Fxq 'absent' "$tmp_dir/pid-absent.out" ||
  fail "connected status-1 PID query did not report absence"
[[ "$(wc -l <"$tmp_dir/pid-commands.log" | tr -d '[:space:]')" == "2" ]] ||
  fail "absence proof issued commands between pidof and get-state"
[[ "$(sed -n '1p' "$tmp_dir/pid-commands.log")" == \
  '-s fixture-serial shell pidof com.mknoon.app.vc204proof' ]] ||
  fail "pidof was not pinned to the exact target"
[[ "$(sed -n '2p' "$tmp_dir/pid-commands.log")" == \
  '-s fixture-serial get-state' ]] ||
  fail "absence was not followed immediately by pinned get-state"

for invalid_mode in \
  zero-empty multiple one-output two-empty absent-offline absent-state-error; do
  run_pid_probe "$invalid_mode" "$tmp_dir/pid-${invalid_mode}.out"
  [[ "$PID_PROBE_STATUS" -ne 0 ]] ||
    fail "invalid PID evidence passed: $invalid_mode"
done

# Exercise the parsers and the keyguard caller separately. Unknown/error is a
# third state: it must fail, never be converted to explicit false and then N/A.
state_probe="$tmp_dir/state-probe.sh"
cat >"$state_probe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}
device_id=fixture-serial
restore_called=false
adb_shell() {
  case "$*" in
    'dumpsys power')
      printf '%b' "${POWER_DUMP:-}"
      return "${POWER_STATUS:-0}"
      ;;
    'dumpsys window')
      printf '%b' "${KEYGUARD_DUMP:-}"
      return "${KEYGUARD_STATUS:-0}"
      ;;
    'input keyevent KEYCODE_SLEEP') return 0 ;;
    *) return 97 ;;
  esac
}
seq() { printf '1\n'; }
sleep() { :; }
restore_screen_state() {
  restore_called=true
  return "${RESTORE_STATUS:-0}"
}
EOF
for function_name in \
  parse_interactive_state \
  parse_keyguard_state \
  interactive_now \
  keyguard_locked_now \
  wait_for_interactive \
  wait_for_keyguard \
  lock_device_if_available \
  restore_screen_state_and_disarm; do
  extract_function "$function_name" >>"$state_probe"
done
cat >>"$state_probe" <<'EOF'
case "${1:-}" in
  parse-power) parse_interactive_state "$2" ;;
  parse-keyguard) parse_keyguard_state "$2" ;;
  query-power) interactive_now ;;
  query-keyguard) keyguard_locked_now ;;
  lock)
    if lock_device_if_available; then
      printf 'locked\n'
    else
      lock_status=$?
      printf 'not-locked:%s:restored=%s\n' "$lock_status" "$restore_called"
    fi
    ;;
  restore-disarm)
    screen_mutated=true
    if restore_screen_state_and_disarm; then
      printf 'restored:armed=%s\n' "$screen_mutated"
    else
      printf 'restore-failed:armed=%s\n' "$screen_mutated"
      exit 1
    fi
    ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$state_probe"

assert_state() {
  local expected="$1"
  shift
  local actual
  actual="$("$state_probe" "$@")"
  [[ "$actual" == "$expected" ]] ||
    fail "state parser expected $expected but observed $actual"
}

assert_state true parse-power $'mWakefulness=Awake\nmInteractive=true'
assert_state false parse-power $'mWakefulness=Asleep\nmInteractive=false'
assert_state unknown parse-power 'no recognized power facts'
assert_state unknown parse-power $'mWakefulness=Awake\nmInteractive=false'
assert_state true parse-keyguard 'mKeyguardShowing=true'
assert_state false parse-keyguard 'mKeyguardShowing=false'
assert_state unknown parse-keyguard 'no recognized keyguard facts'
assert_state unknown parse-keyguard $'mKeyguardShowing=true\nmKeyguardShowing=false'

query_power_error="$tmp_dir/query-power-error.out"
run_expect_failure "$query_power_error" \
  env POWER_STATUS=7 "$state_probe" query-power
query_keyguard_error="$tmp_dir/query-keyguard-error.out"
run_expect_failure "$query_keyguard_error" \
  env KEYGUARD_STATUS=7 "$state_probe" query-keyguard

unknown_lock="$tmp_dir/unknown-lock.out"
run_expect_failure "$unknown_lock" \
  env \
    POWER_DUMP='mWakefulness=Asleep\n' \
    KEYGUARD_DUMP='unparseable keyguard output\n' \
    "$state_probe" lock
if grep -Fq 'not-locked:' "$unknown_lock"; then
  fail "unknown keyguard evidence was converted to the no-keyguard path"
fi

explicit_no_keyguard="$tmp_dir/explicit-no-keyguard.out"
env \
  POWER_DUMP='mWakefulness=Asleep\n' \
  KEYGUARD_DUMP='mKeyguardShowing=false\n' \
  "$state_probe" lock >"$explicit_no_keyguard"
grep -Fxq 'not-locked:1:restored=true' "$explicit_no_keyguard" ||
  fail "explicit false keyguard state did not take the restorable N/A path"

restore_failure="$tmp_dir/restore-failure.out"
run_expect_failure "$restore_failure" \
  env RESTORE_STATUS=1 "$state_probe" restore-disarm
grep -Fxq 'restore-failed:armed=true' "$restore_failure" ||
  fail "failed restoration disarmed screen cleanup"

restore_success="$tmp_dir/restore-success.out"
env RESTORE_STATUS=0 "$state_probe" restore-disarm >"$restore_success"
grep -Fxq 'restored:armed=false' "$restore_success" ||
  fail "verified restoration did not disarm screen cleanup"

bash -n "$RUNNER"
bash -n "$0"

printf 'PASS: VC2-04 Android lifecycle harness fails closed for paths, PID, and device-state evidence\n'
