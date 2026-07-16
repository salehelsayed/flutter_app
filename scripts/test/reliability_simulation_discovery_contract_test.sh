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
  integration_test/scripts/run_notification_tap_device_real.dart
  integration_test/scripts/notification_ios_payload_campaign.dart
  integration_test/scripts/ios_notification_payload_xcui_driver.dart
  integration_test/scripts/run_ios_notification_payload_sims.dart
  integration_test/scripts/validate_group_reaction_notification_artifacts.dart
  integration_test/inbox_replay_before_ack_custody_harness.dart
  integration_test/intro_accept_notification_android_proof_test.dart
  integration_test/notif_push_payload_persist_harness.dart
  integration_test/notification_tap_message_visible_proof_test.dart
)
for path in "${support_paths[@]}"; do
  assert_record_once support support "$path"
  assert_not_executable "$path"
done

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
