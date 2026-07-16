#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

runner="integration_test/scripts/run_group_reaction_notification_device.dart"
expected="$({
  printf '%s\n' android_group_message_unread_lifecycle
  printf '%s\n' android_announcement_message_unread_lifecycle
  printf '%s\n' android_group_reaction_recipient
  printf '%s\n' android_announcement_reaction_recipient
  printf '%s\n' ios_announcement_reaction_recipient
})"

actual="$(
  dart run "$runner" --list-scenarios |
    awk '/^[[:alnum:]_]+$/ { print }'
)"
[ "$actual" = "$expected" ] || {
  printf 'FAIL: Plan 257 scenario listing differs from the five-row contract\n' >&2
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
  "'copy'" \
  'appDataContainer' \
  'idevicesyslog' \
  "'xcodebuild'"; do
  grep -Eq "$required_seam" "$capture_driver" || {
    printf 'FAIL: real capture driver is missing seam: %s\n' "$required_seam" >&2
    exit 1
  }
done

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
