#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

runner="integration_test/scripts/run_group_reaction_notification_device.dart"
# Ordered census of every scenario `groupReactionNotificationScenarios` exposes.
# Plan 315 added the backgrounded-but-connected row without repinning this
# contract, which left the gate red; keep this list in declaration order.
expected="$({
  printf '%s\n' android_group_message_unread_lifecycle
  printf '%s\n' android_announcement_message_unread_lifecycle
  printf '%s\n' android_group_reaction_recipient
  printf '%s\n' android_announcement_reaction_recipient
  printf '%s\n' android_group_reaction_recipient_background_connected
  printf '%s\n' ios_announcement_reaction_recipient
  printf '%s\n' ios_chat_group_message_and_reaction_recipient
})"

actual="$(
  dart run "$runner" --list-scenarios |
    awk '/^[[:alnum:]_]+$/ { print }'
)"
[ "$actual" = "$expected" ] || {
  printf 'FAIL: Plan 257 scenario listing differs from the pinned scenario census\n' >&2
  exit 1
}

single="$(
  dart run "$runner" \
    --scenario ios_announcement_reaction_recipient \
    --list-scenarios |
    awk '/^[[:alnum:]_]+$/ { print }'
)"
[ "$single" = "ios_announcement_reaction_recipient" ] || {
  printf 'FAIL: --scenario did not isolate the iOS announcement row\n' >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# A stale same-name JSON must never bypass explicit capture mode. Historical
# artifacts are accepted only through --validate-artifacts.
mkdir -p "$tmp_dir/run"
printf '%s\n' '{"status":"passed","generatedBy":"marker-only"}' \
  >"$tmp_dir/run/android_group_reaction_recipient.json"

set +e
env -u MKNOON_257_STAGING_MANIFEST dart run "$runner" \
  --scenario android_group_reaction_recipient \
  --sender emulator-5554 \
  --recipient ANDROIDPHYSICAL123 \
  --artifact-dir "$tmp_dir/run" \
  >"$tmp_dir/run.stdout" 2>"$tmp_dir/run.stderr"
run_status=$?
set -e

[ "$run_status" -ne 0 ] || {
  printf 'FAIL: unconfigured device runner reported success\n' >&2
  exit 1
}
run_verdict="$tmp_dir/run/android_group_reaction_recipient_orchestrator_verdict.json"
[ -f "$run_verdict" ] || {
  printf 'FAIL: unconfigured runner did not persist a failure verdict\n' >&2
  exit 1
}
grep -q '"ok":false' "$run_verdict" || {
  printf 'FAIL: unconfigured runner verdict was not failed\n' >&2
  exit 1
}
grep -q '"status":"configuration_blocked"' "$run_verdict" || {
  printf 'FAIL: missing staging config was not classified honestly\n' >&2
  exit 1
}
grep -q 'staging_manifest_required' "$run_verdict" || {
  printf 'FAIL: missing staging configuration blocker was not explicit\n' >&2
  exit 1
}
[ ! -f "$tmp_dir/run/android_group_reaction_recipient.json" ] || {
  printf 'FAIL: stale artifact survived fresh capture preflight\n' >&2
  exit 1
}

capture_driver="integration_test/scripts/capture_group_reaction_notification_device.dart"
[ -f "$capture_driver" ] || {
  printf 'FAIL: Plan 257 capture driver is missing\n' >&2
  exit 1
}
! grep -Eq 'capture_driver_.*implemented' "$runner" "$capture_driver" || {
  printf 'FAIL: placeholder capture-driver blocker remains\n' >&2
  exit 1
}
! grep -Fq 'physical_ios_announcement_fixture_staging_seam_missing' \
  "$capture_driver" || {
  printf 'FAIL: unconditional physical-iOS fixture blocker remains\n' >&2
  exit 1
}
for required_seam in \
  "'build'" \
  'candidate_install_failed' \
  'recipient process absent before provider delivery' \
  "'uiautomator'" \
  "'journalctl'" \
  'GROUP_REACTION_PUSH_ENABLED' \
  'group_reaction_notification_sqlcipher_probe_test.dart' \
  'testCreateAnnouncementReactionFixture' \
  'testAuthorAnnouncementReactionTarget' \
  'testPrepareWarmNotificationTap' \
  'testAnnouncementReactionNotificationTap' \
  'testCreateChatGroupNotificationFixture' \
  'testAuthorChatGroupReactionTarget' \
  'testChatGroupNotificationTap' \
  "'copy'" \
  'appDataContainer' \
  'idevicesyslog' \
  "'xcodebuild'"; do
  grep -Eq "$required_seam" "$capture_driver" || {
    printf 'FAIL: real capture driver is missing seam: %s\n' "$required_seam" >&2
    exit 1
  }
done

# ---------------------------------------------------------------------------
# Plan 386 TC-386-05 - every GRADED capture read comes from a live stream with
# byte-offset cursors, never a post-hoc `logcat -d` window.
#
# Deliberately SCOPED rather than the tap-campaign's file-wide seam
# (`notification_tap_campaign_adapter_contract_test.sh:239-252`). Ported
# verbatim that seam is UNSATISFIABLE here: it bans `['logcat', '-c']` outright
# and tests `'logcat',` x `'-d',` co-occurrence across the whole file, while
# this capture legitimately keeps ten `logcat -c` clears and two
# process-scoped `logcat -d --pid=<pid>` readiness polls. A permanent red is
# not a causal red, so the assertions below name the exact graded shapes.
python3 - "$capture_driver" <<'STREAM_SEAM'
import re
import sys

source = open(sys.argv[1], encoding='utf-8').read()


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    sys.exit(1)


for required in (
    '_startDeviceLogStream',
    '_deviceLogcatCursor',
    '_deviceLogSince',
):
    if required not in source:
        fail('capture driver lacks the live log stream seam ' + required)

# The exact 4-element post-hoc reads the graded paths used before Plan 386.
# Compared whitespace-insensitively so a reformat cannot smuggle one back.
compact = re.sub(r'\s+', '', source)
for banned in ("'logcat','-d','-v','threadtime'", "'logcat','-d','-v','brief'"):
    if banned in compact:
        fail('a graded capture read still uses a post-hoc logcat -d window')

# The two surviving `logcat -d` reads are process-scoped setup polls: they must
# observe only the CURRENT pid, which a whole-device stream cannot express, and
# they gate fixture readiness rather than producing artifact evidence.
for read in re.findall(r"'logcat',\s*'-d',(.*?)\]", source, re.S):
    if '--pid=' not in read:
        fail('an ungated post-hoc logcat -d read remains on a graded path')

# The clears stay. The stream turns each one into a floor instead of destroying
# evidence, so the destructive-action ban stays green.
#
# Repinned 8 -> 9 by Plan 389 for the reaction kill, then 9 -> 10 by Plan 393
# for the distinct killed-photo message window. Each clear is intercepted by
# the live-stream floor and cannot destroy captured evidence.
if source.count("const <String>['logcat', '-c']") != 10:
    fail('the ten non-destructive log clear sites changed without repinning')

killed_cursor = source.find(
    'final killedPhotoCursor = await _deviceLogcatCursor(recipientId);'
)
killed_send = source.find("phase: 'send_killed_jpeg'", killed_cursor)
killed_flow = source.find(
    'await _deviceLogSince(recipientId, killedPhotoCursor)', killed_send
)
killed_terminal = source.find(
    "flow.contains('PUSH_BACKGROUND_NOTIFICATION_SHOWN')", killed_flow
)
if not (0 <= killed_cursor < killed_send < killed_flow < killed_terminal):
    fail('the killed-photo proof no longer waits on its exact live-stream window')
STREAM_SEAM

set +e
dart run "$runner" \
  --scenario android_group_reaction_recipient \
  --validate-artifacts "$tmp_dir/validation" \
  >"$tmp_dir/validation.stdout" 2>"$tmp_dir/validation.stderr"
validation_status=$?
set -e

[ "$validation_status" -ne 0 ] || {
  printf 'FAIL: missing device artifacts unexpectedly validated\n' >&2
  exit 1
}
validation_verdict="$tmp_dir/validation/android_group_reaction_recipient/android_group_reaction_recipient_orchestrator_verdict.json"
[ -f "$validation_verdict" ] || {
  printf 'FAIL: missing-artifact validation did not persist a verdict\n' >&2
  exit 1
}
grep -q '"ok":false' "$validation_verdict" || {
  printf 'FAIL: missing-artifact validation verdict was not failed\n' >&2
  exit 1
}

printf 'PASS: Plan 257 device runner is discoverable, staged, and fail-closed\n'
