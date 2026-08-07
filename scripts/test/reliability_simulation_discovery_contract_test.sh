#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

records="$tmp_dir/records.tsv"
checks="$tmp_dir/checks.tsv"
./scripts/check_reliability_simulation_discovery.sh --records-tsv >"$records"
./scripts/check_reliability_simulation_discovery.sh --checks-tsv >"$checks"

record_count() {
  local category="$1"
  local kind="$2"
  local path="$3"
  awk -F '\t' -v category="$category" -v kind="$kind" -v path="$path" '
    $1 == category && $2 == kind && $3 == path { count++ }
    END { print count + 0 }
  ' "$records"
}

assert_record_once() {
  local category="$1"
  local kind="$2"
  local path="$3"
  local count
  count="$(record_count "$category" "$kind" "$path")"
  [ "$count" -eq 1 ] ||
    fail "$path expected one $category/$kind record, found $count"
}

assert_not_executable() {
  local path="$1"
  if awk -F '\t' -v path="$path" '
    $3 == path &&
    ($1 == "1to1" || $1 == "group" || $1 == "intro" || $1 == "move-feature") &&
    ($2 == "runner" || $2 == "test") { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$records"; then
    fail "$path remains an executable reliability record"
  fi
  if awk -F '\t' -v path="$path" '$2 == path { found = 1 } END { exit found ? 0 : 1 }' \
    "$checks"; then
    fail "$path still expands into a runnable reliability check"
  fi
}

assert_capability() {
  local lifecycle="$1"
  local path="$2"
  local id="$3"
  local required="$4"
  local profile="$5"
  local target="$6"
  local count
  count="$(awk -F '\t' \
    -v lifecycle="$lifecycle" \
    -v path="$path" \
    -v id="$id" \
    -v required="$required" \
    -v profile="$profile" \
    -v target="$target" '
      $1 == lifecycle && $2 == "capability" && $3 == path &&
      index($4, "id=" id " ") == 1 &&
      index($4, " required=" required " ") > 0 &&
      index($4, " profile=" profile " ") > 0 &&
      index($4, " target=" target " ") > 0 { count++ }
      END { print count + 0 }
    ' "$records")"
  [ "$count" -eq 1 ] ||
    fail "$id expected one complete $lifecycle capability record, found $count"
}

# Executable placeholder bodies are deleted. The non-executable registry keeps
# current automated requirements and inactive VC-02 requirements discoverable.
registry=Test-Flight-Improv/sims-manual-proof-registry.md
assert_capability \
  implemented \
  "$registry" \
  android.connectivity_restore_inbox_drain \
  major \
  android.e2e.main \
  android-physical+android-emulator
assert_capability \
  implemented \
  "$registry" \
  android.keepalive_drop_skip_direct \
  major \
  android.e2e.main \
  android-physical+android-emulator
assert_capability \
  implemented \
  "$registry" \
  android.wake_token_directionality \
  major \
  android.e2e.wake_token \
  android-physical+android-emulator

for path in \
  integration_test/connectivity_restore_inbox_drain_proof_test.dart \
  integration_test/keepalive_drop_skip_direct_proof_test.dart \
  integration_test/wake_token_distribution_proof_test.dart \
  integration_test/dcutr_upgrade_proof_test.dart; do
  [ ! -e "$path" ] || fail "$path placeholder must be deleted"
  assert_not_executable "$path"
done

# VC-02 is a future product capability, not a waived/deleted requirement and
# not a current-major blocker before VC-01/VC-02 production exists.
assert_capability \
  inactive \
  "$registry" \
  vc02.dcutr_upgrade \
  future \
  android.e2e.standard \
  android-physical+android-emulator
assert_capability \
  inactive \
  "$registry" \
  vc02.dcutr_symmetric_cgnat_negative \
  future \
  android.e2e.standard \
  network-symmetric-cgnat
assert_not_executable "$registry"

# Manifest-owned adapters/drivers and capture-owned artifact validators are
# support. A zero exit from a catalog or validator can therefore never become
# a second device PASS row.
support_paths=(
  integration_test/scripts/run_1to1_device_real.dart
  integration_test/scripts/run_group_multi_party_sims.dart
  integration_test/scripts/run_group_notification_projection_android.dart
  integration_test/scripts/group_notification_projection_android_criteria.dart
  integration_test/scripts/run_notification_tap_device_real.dart
  integration_test/scripts/notification_ios_payload_campaign.dart
  integration_test/scripts/ios_notification_payload_xcui_driver.dart
  integration_test/scripts/run_ios_notification_payload_sims.dart
  integration_test/scripts/android_group_media_reliability_controller.dart
  integration_test/scripts/group_media_ios_background_recovery.dart
  integration_test/scripts/group_media_ios_background_recovery_evidence.dart
  integration_test/scripts/group_media_ios_fixture_driver.dart
  integration_test/scripts/group_media_prepared_artifact_custody.dart
  integration_test/scripts/group_media_reliability_criteria.dart
  integration_test/scripts/group_media_reliability_runner_contract.dart
  integration_test/support/group_media_android_disposable_app.dart
  lib/core/debug/group_media_ios_background_e2e.dart
  lib/core/debug/group_media_ios_background_e2e_contract.dart
  lib/core/debug/group_media_ios_background_e2e_main_actions.dart
  lib/core/debug/group_media_ios_background_e2e_overlay.dart
  lib/core/debug/group_media_ios_disposable_profile.dart
  lib/core/debug/group_media_ios_disposable_reset.dart
  lib/core/debug/group_media_reliability_e2e.dart
  lib/core/debug/group_media_reliability_e2e_main_actions.dart
  integration_test/scripts/validate_group_reaction_notification_artifacts.dart
  integration_test/group_notification_projection_android_proof_test.dart
  integration_test/inbox_replay_before_ack_custody_harness.dart
  integration_test/intro_accept_notification_android_proof_test.dart
  integration_test/notif_push_payload_persist_harness.dart
  integration_test/notification_tap_message_visible_proof_test.dart
)
for path in "${support_paths[@]}"; do
  assert_record_once support support "$path"
  assert_not_executable "$path"
done

jq -e '
  [.capabilities[] | select(.id == "groups.notification_projection_durability")] == [{
    "id": "groups.notification_projection_durability",
    "owner": "groups",
    "proofBoundary": "android.group-notification-projection-durability",
    "assertions": [
      "groups.two_group_read_zero_exact_cancel",
      "groups.group_reaction_photo_semantic_kind",
      "groups.group_reaction_video_semantic_kind",
      "groups.group_reaction_voice_message_semantic_kind",
      "groups.group_projection_stable_single_card"
    ],
    "lane": "reliability",
    "modes": ["major", "full"],
    "families": ["group", "notifications"],
    "required": true,
    "command": ["dart", "run", "integration_test/scripts/run_group_notification_projection_android.dart"],
    "buildProfile": "android.production_fcm",
    "dependencies": ["build.android.production_fcm"],
    "resources": [
      {"name": "build:android.production_fcm", "access": "read"},
      {"name": "device:android-physical", "access": "exclusive"},
      {"name": "device:android-emulator", "access": "exclusive"},
      {"name": "relay-mutation:staging", "access": "exclusive"},
      {"name": "artifact:group-notification-projection", "access": "write"}
    ],
    "targetCapabilities": ["android.physical", "android.emulator", "credentials.fcm", "relay.staging"],
    "allowedNaReason": "target_unavailable_by_project_policy",
    "artifactRequired": true,
    "artifactValidator": "integration_test/group_notification_projection_android_proof_test.dart",
    "automationReady": true,
    "active": true,
    "declaredBuildException": false
  }]
' tool/sims/critical_features.json >/dev/null ||
  fail 'Plan 330 notification projection capability is incomplete or duplicated'

# Plan 269 keeps one discoverable prepared-artifact runner with exactly two
# independently listable target-bounded scenarios. The manifest owns only the
# Android production-critical row; discovery must not create a second PASS
# owner for either criteria/support helper.
group_media_runner=integration_test/scripts/run_group_media_send_reliability.dart
assert_record_once group runner "$group_media_runner"
for scenario in \
  group_media_foreground_retry_acl_roundtrip \
  group_media_ios_receiver_background_recovery; do
  count="$(awk -F '\t' -v path="$group_media_runner" -v scenario="$scenario" '
    $1 == "group" && $2 == path && $3 == scenario { count++ }
    END { print count + 0 }
  ' "$checks")"
  [ "$count" -eq 1 ] ||
    fail "$group_media_runner:$scenario expected one discovery check, found $count"
done

group_media_list="$tmp_dir/group-media-scenarios.list"
dart "$group_media_runner" --list-scenarios | awk 'NF { print }' >"$group_media_list" ||
  fail 'Plan 269 runner metadata listing failed'
printf '%s\n' \
  group_media_foreground_retry_acl_roundtrip \
  group_media_ios_receiver_background_recovery \
  >"$tmp_dir/group-media-scenarios.expected"
cmp -s "$tmp_dir/group-media-scenarios.expected" "$group_media_list" ||
  fail 'Plan 269 runner did not list exactly the two declared scenarios'

assert_group_media_scenario_selectable() {
  local scenario="$1"
  local devices="$2"
  local output="$tmp_dir/group-media-$scenario.list"
  RELIABILITY_MULTI_DEVICE_IDS="$devices" \
    ./scripts/run_test_gates.sh reliability-sim group --list \
      --only "$group_media_runner:$scenario" >"$output" ||
    fail "$group_media_runner:$scenario was not independently selectable"
  grep -Fq \
    "dart run $group_media_runner --scenario '$scenario' -d '$devices'" \
    "$output" ||
    fail "$group_media_runner:$scenario lost exact scenario/device arguments"
  count="$(grep -Ec '^[[:space:]]+[0-9]+\. ' "$output" || true)"
  [ "$count" -eq 1 ] ||
    fail "$group_media_runner:$scenario selected $count commands instead of one"
}

assert_group_media_scenario_selectable \
  group_media_foreground_retry_acl_roundtrip \
  pixel-usb,emulator-5554
assert_group_media_scenario_selectable \
  group_media_ios_receiver_background_recovery \
  pixel-usb,00008030-001A6D2801BB802E

jq -e '
  [.capabilities[] | select(.id == "groups.media_send_reliability")] |
  length == 1 and
  .[0].automationReady == true and
  .[0].buildProfile == "android.e2e.group_media_269" and
  .[0].dependencies == ["build.android.e2e.group_media_269"] and
  .[0].families == ["group", "media", "transport"] and
  .[0].command == ["dart", "run", "integration_test/scripts/run_group_media_send_reliability.dart", "--scenario", "group_media_foreground_retry_acl_roundtrip"] and
  any(.[0].resources[]; .name == "build:android.e2e.group_media_269" and .access == "read") and
  any(.[0].resources[]; .name == "device:android-physical" and .access == "exclusive") and
  any(.[0].resources[]; .name == "device:android-emulator" and .access == "exclusive") and
  any(.[0].resources[]; .name == "relay-mutation:staging" and .access == "exclusive") and
  any(.[0].resources[]; .name == "artifact:group-media-reliability" and .access == "write") and
  .[0].artifactValidator == "validateGroupMediaReliabilityArtifact"
' tool/sims/critical_features.json >/dev/null ||
  fail 'Plan 269 manifest capability is incomplete or duplicated'

grep -Fq $'support\tsupport\tintegration_test/scripts/run_ios_notification_payload_sims.dart\ttyped notification facade/campaign: Android and prebuilt physical-iOS APNs/NSE campaigns are automation-ready; live iOS credentials and dedicated-device teardown remain typed BLOCKED prerequisites; manifest owns execution' \
  "$records" || fail 'iOS notification discovery note is stale or loses typed credential blocking'

for catalog in \
  integration_test/scripts/run_1to1_device_real.dart \
  integration_test/scripts/run_notification_tap_device_real.dart; do
  dart "$catalog" --list-scenarios >/dev/null ||
    fail "$catalog metadata listing must remain available"
  set +e
  dart "$catalog" >/dev/null 2>&1
  catalog_status=$?
  set -e
  [ "$catalog_status" -eq 78 ] ||
    fail "$catalog normal mode exited $catalog_status instead of BLOCKED (78)"
done

# Plan 267 owns two explicit rows on one runner. Each row must remain directly
# selectable; a generic path-only discovery row cannot satisfy this contract.
invite_runner=integration_test/scripts/run_invite_reliability_multi_device.dart
assert_invite_scenario_selectable() {
  local scenario="$1"
  local mode="${2:-}"
  local devices="${3:-}"
  local output="$tmp_dir/invite-$scenario.list"
  local command_count
  local expected_command="dart run $invite_runner --scenario '$scenario'"

  if [ -n "$devices" ]; then
    RELIABILITY_MULTI_DEVICE_IDS="$devices" \
      ./scripts/run_test_gates.sh reliability-sim group --list \
        --only "$invite_runner:$scenario" >"$output" ||
      fail "$invite_runner:$scenario was not independently selectable"
  else
    ./scripts/run_test_gates.sh reliability-sim group --list \
      --only "$invite_runner:$scenario" >"$output" ||
      fail "$invite_runner:$scenario was not independently selectable"
  fi

  if [ -n "$mode" ]; then
    expected_command="$expected_command --mode '$mode'"
  fi
  if [ -n "$devices" ]; then
    expected_command="$expected_command -d '$devices'"
  fi
  grep -Fq "$expected_command" "$output" ||
    fail "$invite_runner:$scenario did not preserve its explicit scenario/mode/device arguments"
  command_count="$(grep -Ec '^[[:space:]]+[0-9]+\. ' "$output" || true)"
  [ "$command_count" -eq 1 ] ||
    fail "$invite_runner:$scenario selected $command_count commands instead of exactly one"
}

assert_invite_scenario_selectable invite_reliability
assert_invite_scenario_selectable \
  invite_send_latency \
  closure \
  android-physical,android-emulator

unset RELIABILITY_MULTI_DEVICE_IDS FLUTTER_MULTI_DEVICE_IDS FLUTTER_DEVICE_ID
missing_invite_devices_list="$tmp_dir/invite-send-latency-missing-devices.list"
./scripts/run_test_gates.sh reliability-sim group --list \
  --only "$invite_runner:invite_send_latency" \
  >"$missing_invite_devices_list" ||
  fail "$invite_runner:invite_send_latency list must remain available without device env"
grep -Fq -- \
  "--mode 'closure' -d '<required:RELIABILITY_MULTI_DEVICE_IDS>'" \
  "$missing_invite_devices_list" ||
  fail 'invite_send_latency list did not expose its required explicit device pair'

missing_invite_devices_run="$tmp_dir/invite-send-latency-missing-devices.run"
set +e
./scripts/run_test_gates.sh reliability-sim group \
  --only "$invite_runner:invite_send_latency" \
  >"$missing_invite_devices_run" 2>&1
missing_invite_devices_status=$?
set -e
[ "$missing_invite_devices_status" -eq 64 ] ||
  fail "invite_send_latency without device env exited $missing_invite_devices_status instead of 64"
grep -Fq 'Missing explicit two-device IDs' "$missing_invite_devices_run" ||
  fail 'invite_send_latency without device env did not fail with the explicit-pair diagnostic'
if grep -Fq '==>' "$missing_invite_devices_run"; then
  fail 'invite_send_latency without device env reached Dart/device execution'
fi

# Plan 342 has exactly one device-proof discovery row; it is not a host test.
custody_path=integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart
assert_record_once 1to1 test "$custody_path"
grep -Fq $'1to1\ttest\t'$custody_path$'\t342 TC-342-11 Android v107-to-v108 direct-text custody SQLCipher durability device proof' \
  "$records" || fail 'TC-342-11 discovery record lost its exact Android proof label'

unset RELIABILITY_SINGLE_DEVICE_ID FLUTTER_DEVICE_ID
missing_custody_device_list="$tmp_dir/tc342-missing-device.list"
./scripts/run_test_gates.sh reliability-sim 1to1 --list \
  --only "$custody_path" \
  >"$missing_custody_device_list" ||
  fail 'TC-342-11 list must remain available without a device env'
grep -Fq -- "-d '<required:RELIABILITY_SINGLE_DEVICE_ID>'" \
  "$missing_custody_device_list" ||
  fail 'TC-342-11 list did not expose its required explicit Android target'

missing_custody_device_run="$tmp_dir/tc342-missing-device.run"
set +e
./scripts/run_test_gates.sh reliability-sim 1to1 \
  --only "$custody_path" \
  >"$missing_custody_device_run" 2>&1
missing_custody_device_status=$?
set -e
[ "$missing_custody_device_status" -eq 64 ] ||
  fail "TC-342-11 without device env exited $missing_custody_device_status instead of 64"
grep -Fq 'Missing explicit single-device ID' "$missing_custody_device_run" ||
  fail 'TC-342-11 without device env did not fail with the explicit-ID diagnostic'
if grep -Fq '==>' "$missing_custody_device_run"; then
  fail 'TC-342-11 without device env reached Flutter/device execution'
fi
grep -Fq 'Platform.isAndroid' "$custody_path" ||
  fail 'TC-342-11 does not reject a non-Android explicit target'

# The recorder proof remains executable, but is honest about its one native
# boundary and has no compile-time skip escape hatch.
voice_path=integration_test/voice_message_e2e_test.dart
voice_support_path=integration_test/support/android_voice_recorder_smoke.dart
assert_record_once 1to1 test "$voice_path"
grep -Fq $'1to1\t'$voice_path$'\tphysical Android records a nonempty AAC/M4A file with valid duration\t' \
  "$checks" || fail 'Android native recorder test did not expand exactly'
grep -Fq 'Platform.isAndroid' "$voice_support_path" ||
  fail 'recorder proof does not reject a non-Android target'
grep -Fq 'RECORD_AUDIO must be pregranted' "$voice_support_path" ||
  fail 'recorder proof does not fail closed on missing permission/plugin'
grep -Fq "'ftyp'" "$voice_support_path" ||
  fail 'recorder proof does not validate the native M4A container'
if rg -q 'RUN_REAL_VOICE_MESSAGE_E2E|markTestSkipped|^[[:space:]]*skip:' \
  "$voice_path" "$voice_support_path"; then
  fail 'recorder proof still has a skip/define false-green path'
fi

printf 'PASS: reliability simulation discovery disposition contract\n'
