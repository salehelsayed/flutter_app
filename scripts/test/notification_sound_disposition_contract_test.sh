#!/usr/bin/env bash

# Plan 378 — notification sound-disposition process contract.
#
# The sound-smoke orchestrator owns ONE machine-readable scenario -> disposition
# table (S1..S16). This contract pins that table byte-exactly, pins the offline
# OS-capture decision function that the live device path reuses, and pins that
# every scenario is actually visible to the reliability-simulation discovery
# gate. Without these three cases a card can land on the wrong notification
# channel — or a whole scenario family can go unregistered — while every gate
# stays green.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

orchestrator=integration_test/scripts/run_notification_sound_smoke.dart
runner=(dart "$orchestrator")

# The orchestrator resolves the Android application id from the environment
# first; pin it so the offline dumpsys fixtures below are package-deterministic
# on any checkout.
export ANDROID_APP_PACKAGE=com.mknoon.app

# ---------------------------------------------------------------------------
# case1_print_disposition_contract
#
# `--print-disposition-contract` must emit the pinned S1..S16 table WITHOUT a
# device pair. NOTE: never pass `-d` to this orchestrator from a contract test —
# with two live devices attached it would start a real two-device run.
# ---------------------------------------------------------------------------
case1_print_disposition_contract() {
  local actual="$tmp_dir/disposition.actual"
  local expected="$tmp_dir/disposition.expected"
  local status=0

  set +e
  "${runner[@]}" --print-disposition-contract >"$actual" 2>"$tmp_dir/disposition.err"
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    printf 'observed exit=%s stdout:\n' "$status" >&2
    cat "$actual" >&2
    printf 'stderr:\n' >&2
    cat "$tmp_dir/disposition.err" >&2
    fail '--print-disposition-contract did not exit 0 without a device pair'
  fi

  printf '%s\n' \
    '# notification-sound-smoke disposition contract v1' \
    '# scenario|disposition|lane|expectedChannel' \
    'S1|audibleStrict|direct|mknoon_messages' \
    'S2|audibleStrict|group|mknoon_messages' \
    'S3|audibleStrict|announcement|mknoon_messages' \
    'S4|suppressed|direct|none' \
    'S5|consistency|direct|mknoon_messages' \
    'S6|consistency|direct|mknoon_messages' \
    'S7|consistency|direct|mknoon_messages' \
    'S8|consistency|group|mknoon_messages' \
    'S9|consistency|group|mknoon_messages' \
    'S10|consistency|group|mknoon_messages' \
    'S11|consistency|announcement|mknoon_messages' \
    'S12|consistency|announcement|mknoon_messages' \
    'S13|consistency|announcement|mknoon_messages' \
    'S14|toneDebounce|direct|mknoon_messages' \
    'S15|suppressed|group|none' \
    'S16|audibleStrict|direct|mknoon_messages' >"$expected"

  if ! cmp -s "$expected" "$actual"; then
    diff -u "$expected" "$actual" >&2 || true
    fail 'scenario disposition table drifted from the pinned S1..S16 contract'
  fi
}

# ---------------------------------------------------------------------------
# case2_verify_os_capture_fixtures
#
# `--verify-os-capture <scenario> <dumpsys-file> <verdict-json>` runs the SAME
# pure decision function the live device path uses, offline. Three canned dumps
# are enough to pin the contradiction that HEAD's either-channel predicate
# silently accepted.
# ---------------------------------------------------------------------------
write_dump_fixture() {
  # $1 = destination file, $2 = channel
  local destination="$1"
  local channel="$2"
  cat >"$destination" <<EOF
Current Notification List:
  NotificationRecord(0x1a2b3c: pkg=com.mknoon.app user=UserHandle{0} id=1701 tag=null importance=4 key=0|com.mknoon.app|1701|null|10123: Notification(channel=$channel shortcut=null contentView=null vibrate=null sound=null defaults=0x0 flags=0x8 color=0x00000000 category=msg vis=PRIVATE)
      groupKey=0|com.mknoon.app|g:mknoon|10123
      android.title=String (AliceNotif)
      android.text=String (S1: notification sound 1:1)

Ranking Config:
  Ranking:
EOF
}

write_empty_dump_fixture() {
  cat >"$1" <<'EOF'
Current Notification List:

Ranking Config:
  Ranking:
EOF
}

run_verify() {
  # $1 = scenario, $2 = dump file, $3 = verdict file; echoes "<status>|<line>"
  local status=0
  local out="$tmp_dir/verify.out"
  set +e
  "${runner[@]}" --verify-os-capture "$1" "$2" "$3" >"$out" 2>"$tmp_dir/verify.err"
  status=$?
  set -e
  printf '%s|%s\n' "$status" "$(grep -F 'os-capture-verdict' "$out" || true)"
}

case2_verify_os_capture_fixtures() {
  local audible_dump="$tmp_dir/dump.audible"
  local silent_dump="$tmp_dir/dump.silent"
  local empty_dump="$tmp_dir/dump.empty"
  write_dump_fixture "$audible_dump" mknoon_messages
  write_dump_fixture "$silent_dump" mknoon_messages_silent
  write_empty_dump_fixture "$empty_dump"

  local shown_false="$tmp_dir/verdict.shown_false.json"
  printf '%s\n' '{"shownCalls":[{"silent":false}]}' >"$shown_false"
  local shown_none="$tmp_dir/verdict.shown_none.json"
  printf '%s\n' '{"shownCalls":[]}' >"$shown_none"
  local shown_debounce="$tmp_dir/verdict.shown_debounce.json"
  printf '%s\n' \
    '{"shownCalls":[{"silent":false},{"silent":true}],"priorRecordIds":[1701]}' \
    >"$shown_debounce"

  # 2a: audible-expected scenario + audible record -> pass.
  local result
  result="$(run_verify S1 "$audible_dump" "$shown_false")"
  [ "${result%%|*}" = 0 ] ||
    fail "audible fixture did not pass the OS-capture decision (got: $result)"
  case "$result" in
    *"result=pass"*"reason=ok"*) ;;
    *) fail "audible fixture emitted no passing verdict line (got: $result)" ;;
  esac

  # 2b: audible-expected scenario + SILENT-channel record -> typed failure.
  # This is the contradiction HEAD's either-channel predicate accepted.
  result="$(run_verify S1 "$silent_dump" "$shown_false")"
  [ "${result%%|*}" != 0 ] ||
    fail 'audible-expected scenario accepted a silent-channel record'
  case "$result" in
    *"result=fail"*"reason=channel_contradiction"*) ;;
    *) fail "channel contradiction was not typed (got: $result)" ;;
  esac

  # 2c: suppressed-expected scenario + any record -> typed failure.
  result="$(run_verify S4 "$audible_dump" "$shown_none")"
  [ "${result%%|*}" != 0 ] ||
    fail 'suppressed-expected scenario accepted an OS notification record'
  case "$result" in
    *"result=fail"*"reason=unexpected_notification"*) ;;
    *) fail "suppressed violation was not typed (got: $result)" ;;
  esac

  # Sanity: the suppressed scenario still passes on an empty shade, so 2c is a
  # contradiction assertion and not an always-fail.
  result="$(run_verify S4 "$empty_dump" "$shown_none")"
  [ "${result%%|*}" = 0 ] ||
    fail "suppressed scenario failed on an empty shade (got: $result)"

  # 2d: tone debounce keeps the original primary-channel card while the
  # second same-ID update is explicitly silent.
  result="$(run_verify S14 "$audible_dump" "$shown_debounce")"
  [ "${result%%|*}" = 0 ] ||
    fail "tone-debounce primary-card fixture did not pass (got: $result)"

  # 2e: the same two call flags cannot excuse a settled channel demotion.
  result="$(run_verify S14 "$silent_dump" "$shown_debounce")"
  [ "${result%%|*}" != 0 ] ||
    fail 'tone-debounce scenario accepted a demoted silent-channel survivor'
  case "$result" in
    *"result=fail"*"reason=channel_contradiction"*) ;;
    *) fail "tone-debounce channel demotion was not typed (got: $result)" ;;
  esac
}

# ---------------------------------------------------------------------------
# case3_discovery_rows
#
# Every S1..S16 row must be visible to the reliability-simulation discovery
# gate under the correct family. HEAD registers only S1..S4 (the S5..S13
# map-loop emission is unparseable by the discovery awk) and still exits 0 —
# invisible-but-green.
# ---------------------------------------------------------------------------
case3_discovery_rows() {
  local tsv="$tmp_dir/discovery.tsv"
  ./scripts/check_reliability_simulation_discovery.sh --checks-tsv >"$tsv"

  local actual="$tmp_dir/discovery.actual"
  local expected="$tmp_dir/discovery.expected"
  awk -F'\t' \
    '$2 == "integration_test/scripts/run_notification_sound_smoke.dart" {
       print $1 "\t" $3
     }' "$tsv" |
    LC_ALL=C sort >"$actual"

  printf '%s\t%s\n' \
    1to1 S1 \
    1to1 S14 \
    1to1 S16 \
    1to1 S4 \
    1to1 S5 \
    1to1 S6 \
    1to1 S7 \
    group S10 \
    group S11 \
    group S12 \
    group S13 \
    group S15 \
    group S2 \
    group S3 \
    group S8 \
    group S9 >"$expected"

  if ! cmp -s "$expected" "$actual"; then
    printf 'observed %s sound-smoke discovery rows:\n' "$(wc -l <"$actual" | tr -d ' ')" >&2
    diff -u "$expected" "$actual" >&2 || true
    fail 'sound-smoke scenarios are not all registered under the correct discovery families'
  fi
}

# ---------------------------------------------------------------------------
# case4_absent_package_state_boundary
#
# Flutter integration-test cleanup can uninstall its package. The guarded
# Android pair is therefore accepted only when BOTH packages are absent before
# any child or mutating adb command. That read-only refusal path is executable
# here with fake adb; source ordering pins the accepted absent-baseline path.
# ---------------------------------------------------------------------------
case4_absent_package_state_boundary() {
  grep -Fq 'final androidStateBoundary = await _captureAndroidSoundStateBoundary(' \
    "$orchestrator" ||
    fail 'sound runner lacks its read-only Android package/state preflight'
  grep -Fq 'AndroidAppStateGuard.capture(' "$orchestrator" ||
    fail 'sound runner does not own the absent Android pair with one state guard'
  grep -Fq 'await androidStateBoundary.restoreAndVerify()' "$orchestrator" ||
    fail 'sound runner does not restore and re-read the exact baseline'

  python3 - "$orchestrator" <<'PY'
import sys

source = open(sys.argv[1], encoding="utf-8").read()
main = source[source.index("Future<void> main(List<String> args) async {"):]
capture = main.index("_captureAndroidSoundStateBoundary(")
launch = main.index("_launchHarness(", capture)
restore = main.index("androidStateBoundary.restoreAndVerify()", launch)
summary = main.index("final summary = <String, dynamic>{", restore)
exit_call = main.index("exit(failed ? 1 : 0)", summary)
assert capture < launch < restore < summary < exit_call

method_start = source.index("Future<_AndroidSoundStateBoundary?> _captureAndroidSoundStateBoundary(")
method_end = source.index("Future<Process> _launchHarness", method_start)
method = source[method_start:method_end]
both_checks = method.index("Future.wait")
installed_block = method.index("package_installed_before_sound_smoke", both_checks)
snapshot = method.index("_readAndroidSoundNotificationSnapshot", installed_block)
guard = method.index("AndroidAppStateGuard.capture", snapshot)
assert both_checks < installed_block < snapshot < guard

boundary_start = source.index("final class _AndroidSoundStateBoundary")
boundary_end = source.index("Future<_AndroidSoundStateBoundary?>", boundary_start)
boundary = source[boundary_start:boundary_end]
assert "restoreAll()" in boundary
assert "_readAndroidSoundNotificationSnapshot" in boundary
assert "packagePresent" in boundary
assert "notificationCardsSha256" in boundary
assert "notificationChannelsSha256" in boundary
assert "restorationVerified" in boundary
PY

  local fake_bin="$tmp_dir/state-boundary-bin"
  local command_log="$tmp_dir/state-boundary.commands"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "adb %s\\n" "$*" >>"${SOUND_STATE_COMMAND_LOG:?}"' \
    'case "$*" in' \
    '  "-s physical-1 get-state"|"-s emulator-5554 get-state") printf "device\\n" ;;' \
    '  "-s physical-1 shell pm path com.mknoon.app") printf "package:/data/app/com.mknoon.app/base.apk\\n" ;;' \
    '  "-s emulator-5554 shell pm path com.mknoon.app") exit 1 ;;' \
    '  *) exit 23 ;;' \
    'esac' >"$fake_bin/adb"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "flutter %s\\n" "$*" >>"${SOUND_STATE_COMMAND_LOG:?}"' \
    'exit 99' >"$fake_bin/flutter"
  chmod +x "$fake_bin/adb" "$fake_bin/flutter"

  local blocked_out="$tmp_dir/state-boundary.out"
  local blocked_err="$tmp_dir/state-boundary.err"
  local blocked_status=0
  set +e
  PATH="$fake_bin:$PATH" SOUND_STATE_COMMAND_LOG="$command_log" \
    dart "$orchestrator" -d physical-1,emulator-5554 --non-interactive \
      >"$blocked_out" 2>"$blocked_err"
  blocked_status=$?
  set -e
  [ "$blocked_status" -eq 78 ] ||
    fail "installed-package preflight exited $blocked_status instead of 78"
  grep -Fq 'package_installed_before_sound_smoke' "$blocked_err" ||
    fail 'installed-package preflight omitted its typed blocker'
  grep -Fq 'adb -s physical-1 shell pm path com.mknoon.app' "$command_log" ||
    fail 'physical package presence was not checked read-only'
  grep -Fq 'adb -s emulator-5554 shell pm path com.mknoon.app' "$command_log" ||
    fail 'emulator package presence was not checked read-only'
  if grep -Eq 'flutter | install| uninstall| pm grant| pm revoke| am | cmd ' \
      "$command_log"; then
    fail 'installed-package blocker launched a child or mutated a target'
  fi
}

# ---------------------------------------------------------------------------
# case5_direct_send_custody_capability
#
# S1/S4/S5-S7/S14/S16 use the production direct-text sender. Its repository
# must expose the complete custody capability, including the unique owner
# lookup added to the production contract. Omitting that one callback compiles
# but makes every direct row fail before transport.
# ---------------------------------------------------------------------------
case5_direct_send_custody_capability() {
  python3 - \
    integration_test/notification_sound_smoke_harness.dart \
    integration_test/_support/direct_inbox_custody_db_bindings.dart <<'PY'
import re
import sys

harness = re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8").read())
bindings = re.sub(r"\s+", " ", open(sys.argv[2], encoding="utf-8").read())

assert (
    "dbLoadDirectInboxCustodyOutboxOwnerForMessageId: "
    "custodyDb.loadOwnerForMessageId" in harness
), "sound sender omits the direct custody owner lookup"
assert "loadOwnerForMessageId({ required String messageId" in bindings, (
    "shared direct custody bindings omit the owner lookup"
)
assert re.search(
    r"dbLoadDirectInboxCustodyOutboxOwnerForMessageId\(\s*db,",
    bindings,
), (
    "owner lookup is not bound to the production DB helper"
)
assert harness.count("dbApplyIncomingOrdinaryTextMutation:") == 2, (
    "both sound peers must wire the atomic incoming ordinary-text apply"
)
assert "dbApplyIncomingOrdinaryTextMutation( stack.db," in harness, (
    "sound peers do not bind the production incoming ordinary-text apply"
)
factory = re.search(
    r"MediaAttachment _mediaAttachmentForScenario\(.*?return MediaAttachment\((.*?)\n  \);",
    open(sys.argv[1], encoding="utf-8").read(),
    re.S,
)
assert factory is not None, "sound media descriptor factory is missing"
assert re.search(r"\blocalPath\s*:\s*[^,]+,", factory.group(1)), (
    "sound media descriptor omits the local path required by direct custody preflight"
)
PY
}

# ---------------------------------------------------------------------------
# case6_android_completion_signal_handshake
#
# Android signal files live in app-private storage and are mirrored to the
# host. A role must remain alive until the host acknowledges its final signal;
# otherwise `flutter test` can tear the package down before the 500ms mirror
# loop observes the file, producing a false timeout after all rows pass.
# ---------------------------------------------------------------------------
case6_android_completion_signal_handshake() {
  python3 - \
    integration_test/notification_sound_smoke_harness.dart \
    integration_test/scripts/run_notification_sound_smoke.dart <<'PY'
import re
import sys

harness = re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8").read())
runner = re.sub(r"\s+", " ", open(sys.argv[2], encoding="utf-8").read())

for role in ("alice", "bob"):
    assert f"writeSignal('{role}_done', content: 'ok')" in harness, (
        f"{role} completion signal is missing"
    )
    assert f"waitForSignal( '{role}_done_ack'" in harness, (
        f"{role} can exit before its final Android signal is mirrored"
    )
    assert f"waitForSignal( '{role}_done'" in runner, (
        f"orchestrator does not await {role} completion"
    )
    assert f"writeSignal('{role}_done_ack')" in runner, (
        f"orchestrator does not acknowledge {role} completion"
    )
    assert f"_awaitHarnessSuccess({role}, '{role}')" in runner, (
        f"orchestrator can kill {role} before the completion ack is consumed"
    )
assert "Future<void> _awaitHarnessSuccess(" in runner, (
    "sound runner does not require a clean Flutter child exit"
)
PY
}

# ---------------------------------------------------------------------------
# case7_notification_shade_retry_order
#
# A killed first uiautomator dump must not turn the progressive-scroll retries
# into upward swipes against the app. On a short one-card shade that gesture can
# collapse SystemUI, so every retry must capture and identify the shade before
# it is allowed to scroll.
# ---------------------------------------------------------------------------
case7_notification_shade_retry_order() {
  python3 - integration_test/scripts/run_notification_sound_smoke.dart <<'PY'
import sys

source = open(sys.argv[1], encoding="utf-8").read()
method_start = source.index("Future<Map<String, dynamic>> _captureAndroidNotificationState({")
method_end = source.index("Map<String, dynamic> _redactedVerdict(", method_start)
method = source[method_start:method_end]

loop = method[method.index("for (var attempt = 1; attempt <= 3; attempt++)"):]
first_dump = loop.index("'uiautomator',")
first_swipe = loop.index("'swipe',")
assert first_dump < first_swipe, (
    "notification retry scrolls before proving the shade is open"
)
assert "package=\"com.android.systemui\"" in loop, (
    "notification retry does not distinguish SystemUI from the foreground app"
)
shade_guard = loop.index("shadeHierarchyVisible")
assert first_dump < shade_guard < first_swipe, (
    "notification retry does not gate scrolling on a captured SystemUI hierarchy"
)
PY
}

case1_print_disposition_contract
case2_verify_os_capture_fixtures
case3_discovery_rows
case4_absent_package_state_boundary
case5_direct_send_custody_capability
case6_android_completion_signal_handshake
case7_notification_shade_retry_order

printf 'PASS: notification sound disposition contract\n'
