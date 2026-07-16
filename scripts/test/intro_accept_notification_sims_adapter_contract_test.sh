#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_one_typed_result() {
  local output="$1"
  local expected_status="$2"
  [ "$(printf '%s\n' "$output" | grep -c '^SIMS_RESULT_JSON=' || true)" -eq 1 ] ||
    fail 'adapter did not emit exactly one result sentinel'
  [ "$(printf '%s\n' "$output" | awk 'NF { count++ } END { print count + 0 }')" -eq 1 ] ||
    fail 'adapter wrote child diagnostics to stdout'
  printf '%s\n' "$output" | grep -q "\"status\":\"$expected_status\"" ||
    fail "adapter did not emit $expected_status: $output"
  printf '%s\n' "$output" | grep -q '"assertionsAttempted":' ||
    fail 'typed result omitted assertionsAttempted'
  printf '%s\n' "$output" | grep -q '"artifactPresent":' ||
    fail 'typed result omitted artifactPresent'
  printf '%s\n' "$output" | grep -q '"printOnly":false' ||
    fail 'typed result omitted printOnly=false'
}

campaign='integration_test/scripts/run_intro_accept_notification_android.dart'
python3 - "$campaign" <<'PY'
import sys
import re

source = open(sys.argv[1], encoding='utf-8').read()
start = source.index('Future<void> _launchAll()')
end = source.index('Future<void> _collectIdentities()', start)
launch = source[start:end]
assert "'am'" in launch and "'start'" in launch and "'-W'" in launch
assert "'-n'" in launch and "'$_appPackage/.MainActivity'" in launch
assert 'final output = await _adbShell' in launch
assert r"r'^Status:[ \t]+ok[ \t]*\r?$'" in launch
assert 'monkey' not in launch

start = source.index('Future<void> _installPreparedArtifactIfPresent(')
end = source.index('// ---- Phase 1:', start)
install = source[start:end]
assert "'auto_setup.json'" in install
assert "'username': 'SimsIntro${party.role}'" in install
assert source.index("'auto_setup.json'", start, end) < source.index(
    'Future<void> _launchAll()'
)

start = source.index('Future<void> _writeAppDocumentsFile(')
end = source.index('// ---- Artifacts', start)
writer = source[start:end]
assert "'run-as'" in writer and "'cp'" in writer
assert 'remoteTmp' in writer and "'app_flutter/$name'" in writer
assert "'mkdir'" in writer and "'-p'" in writer and "'app_flutter'" in writer
assert writer.index("'mkdir'") < writer.index("'cp'")
assert "'sh'" not in writer and "'-c'" not in writer

start = source.index('Future<void> _acceptanceLeg(')
end = source.index('Future<void> _terminateIntroducer()', start)
acceptance = source[start:end]
action = acceptance.index("'introduction_action': 'accept_all'")
custody_request = acceptance.index(
    "'require_introducer_acceptance_custody': true"
)
custody_confirmation = acceptance.index(
    "custody['status'] != 'confirmed'"
)
card = acceptance.index("'$legLabel acceptance card on A'")
headless_kill = acceptance.index('await _terminateIntroducer();', card)
pid_empty = acceptance.index("await _requirePidofEmpty(", headless_kill)
assert action < custody_request < custody_confirmation < card
assert card < headless_kill < pid_empty
assert "'force-stop'" not in acceptance

start = source.index('Future<void> _terminateIntroducer()')
end = source.index('Future<bool> _pidofEmptyWithin(', start)
termination = source[start:end]
home = termination.index("'KEYCODE_HOME'")
kill = termination.index("'kill'", home)
pid_checks = [match.start() for match in re.finditer(r'_pidofEmptyWithin\(', termination)]
stop_app = termination.index("'stop-app'")
assert len(pid_checks) == 2
assert termination.count('if (!await _pidofEmptyWithin(') == 2
assert termination.count('const Duration(seconds: 5)') == 1
assert termination.count('const Duration(seconds: 20)') == 1
assert home < kill < pid_checks[0] < stop_app < pid_checks[1]
assert "['am', 'kill', _appPackage]" in termination
assert "'cmd'" in termination and "'activity'" in termination
assert "'force-stop'" not in termination

helper_start = end
helper_end = source.index('Future<void> _requirePidofEmpty(', helper_start)
pid_helper = source[helper_start:helper_end]
assert 'DateTime.now().add(timeout)' in pid_helper
assert "(await _pidofA()).isEmpty" in pid_helper
assert 'const Duration(milliseconds: 250)' in pid_helper
assert "['am', 'force-stop'" not in source

start = source.index('Future<String> _logcatMark()')
end = source.index('Future<({String finalPeer', start)
logcat_mark = source[start:end]
assert "['date', '+%s.%3N']" in logcat_mark
assert r"r'^\d{10,}\.\d{3}$'" in logcat_mark
assert '+%m-%d %H:%M:%S.000' not in logcat_mark
PY

DART_BIN="$(command -v dart)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SHIM_DIR="$TMP_DIR/shims"
CHILD_LOG="$TMP_DIR/child.log"
STDERR_LOG="$TMP_DIR/adapter.stderr"
PROOF_DIR="$TMP_DIR/proofs"
APK="$TMP_DIR/production-fcm.apk"
CREDENTIAL="$TMP_DIR/service-account.json"
mkdir -p "$SHIM_DIR"
: >"$APK"
printf '%s\n' '{"project_id":"contract-project"}' >"$CREDENTIAL"

cp scripts/test/fixtures/intro_accept_notification_sims_dart_shim.sh \
  "$SHIM_DIR/dart"
chmod +x "$SHIM_DIR/dart"

cat >"$SHIM_DIR/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = -s ]; then
  serial="$2"
  shift 2
  state="$SIMS_TEST_APP_STATE_DIR/${serial//[^A-Za-z0-9_.-]/_}.installed"
  case "${1:-}" in
    install)
      [ "${2:-}" = -r ] && [ "${3:-}" = -d ] && [ "${4:-}" = -t ]
      [ -f "${5:-}" ]
      : >"$state"
      printf 'Success\n'
      ;;
    uninstall)
      rm -f "$state"
      printf 'Success\n'
      ;;
    shell)
      shift
      case "$*" in
        'pm path com.mknoon.app')
          [ ! -f "$state" ] || printf 'package:/data/app/base.apk\n'
          ;;
        'pidof com.mknoon.app'|'dumpsys activity activities'|\
        'am force-stop com.mknoon.app'|\
        'run-as com.mknoon.app ls -1 -A .')
          ;;
        *) exit 91 ;;
      esac
      ;;
    *) exit 92 ;;
  esac
else
  exit 93
fi
EOF
chmod +x "$SHIM_DIR/adb"

PHYSICAL='PHYSICAL123'
EMULATOR_A='emulator-5554'
EMULATOR_B='emulator-5556'
ADAPTER='integration_test/scripts/run_intro_accept_notification_sims.dart'

run_adapter() {
  env \
    PATH="$SHIM_DIR:$PATH" \
    SIMS_TEST_CHILD_LOG="$CHILD_LOG" \
    SIMS_TEST_APP_STATE_DIR="$TMP_DIR" \
    SIMS_PROOF_DIRECTORY="$PROOF_DIR" \
    MKNOON_RELAY_ADDRESSES='127.0.0.1:4001' \
    SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$APK" \
    SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$CREDENTIAL" \
    FIREBASE_SERVICE_ACCOUNT="$CREDENTIAL" \
    SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PHYSICAL" \
    SIMS_ANDROID_EMULATOR_DEVICE_ID="$EMULATOR_A" \
    SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID="$EMULATOR_B" \
    "$@"
}

: >"$CHILD_LOG"
output="$(run_adapter "$DART_BIN" "$ADAPTER" 2>"$STDERR_LOG")"
assert_one_typed_result "$output" PASS
printf '%s\n' "$output" | grep -q '"assertionsAttempted":2' ||
  fail 'PASS did not account for both intro scenarios'
printf '%s\n' "$output" | grep -q '"artifactEvidence":' ||
  fail 'PASS omitted durable artifact evidence'
printf '%s\n' "$output" | grep -Fq '"validatorIds":["integration_test/intro_accept_notification_android_proof_test.dart"]' ||
  fail 'PASS omitted the exact manifest validator binding'
[ "$(wc -l <"$CHILD_LOG" | tr -d ' ')" -eq 2 ] ||
  fail 'adapter did not launch exactly two scenarios'
grep -q -- '--scenario physical_introducer' "$CHILD_LOG" ||
  fail 'physical-introducer scenario was not launched'
grep -q -- '--scenario emulator_introducer' "$CHILD_LOG" ||
  fail 'emulator-introducer scenario was not launched'
[ "$(grep -c -- "--artifact $APK" "$CHILD_LOG")" -eq 2 ] ||
  fail 'both scenarios did not reuse the same central APK'
grep -Eq '(^| )build( |$)' "$CHILD_LOG" &&
  fail 'adapter launched a child build'
grep -q 'child diagnostic' "$STDERR_LOG" ||
  fail 'child diagnostics were not preserved on stderr'
proof_path="$(printf '%s\n' "$output" | sed -n 's/.*"artifactEvidence":{"path":"\([^"]*\)".*/\1/p')"
[ -f "$proof_path" ] || fail 'durable proof path does not exist'
grep -q '"childBuildCount":0' "$proof_path" ||
  fail 'durable proof did not record zero child builds'

assert_blocked_without_child() {
  local expected_blocker="$1"
  shift
  : >"$CHILD_LOG"
  set +e
  local blocked_output
  blocked_output="$(run_adapter "$@" 2>"$STDERR_LOG")"
  local status=$?
  set -e
  [ "$status" -eq 78 ] || fail "$expected_blocker exited $status, expected 78"
  assert_one_typed_result "$blocked_output" BLOCKED
  printf '%s\n' "$blocked_output" | grep -q "\"blocker\":\"$expected_blocker\"" ||
    fail "BLOCKED result omitted blocker=$expected_blocker"
  [ ! -s "$CHILD_LOG" ] || fail "$expected_blocker launched a child"
}

assert_blocked_without_child environment \
  env -u MKNOON_RELAY_ADDRESSES "$DART_BIN" "$ADAPTER"
assert_blocked_without_child missingArtifact \
  env -u SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM "$DART_BIN" "$ADAPTER"
assert_blocked_without_child credentials \
  env -u SIMS_PROVIDER_FCM_CREDENTIAL_PATH -u FIREBASE_SERVICE_ACCOUNT \
    "$DART_BIN" "$ADAPTER"
assert_blocked_without_child targetUnavailable \
  env -u SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID "$DART_BIN" "$ADAPTER"

: >"$CHILD_LOG"
set +e
failed_output="$(
  run_adapter env SIMS_TEST_CHILD_EXIT=9 "$DART_BIN" "$ADAPTER" \
    2>"$STDERR_LOG"
)"
failed_status=$?
set -e
[ "$failed_status" -eq 9 ] || fail 'child failure exit code was not propagated'
assert_one_typed_result "$failed_output" FAIL
[ "$(wc -l <"$CHILD_LOG" | tr -d ' ')" -eq 1 ] ||
  fail 'adapter continued after a failed scenario'

printf 'PASS: intro acceptance notification Sims adapter contract\n'
