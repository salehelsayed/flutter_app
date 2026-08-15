#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_mode="human"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/check_reliability_simulation_discovery.sh
  ./scripts/check_reliability_simulation_discovery.sh --records-tsv
  ./scripts/check_reliability_simulation_discovery.sh --checks-tsv

Options:
  --records-tsv   Emit classified candidates as category/kind/path/note TSV.
  --checks-tsv    Emit expanded checks/scenarios as category/path/id/note TSV.
EOF
}

while (($# > 0)); do
  case "$1" in
    --records-tsv)
      output_mode="records-tsv"
      shift
      ;;
    --checks-tsv)
      output_mode="checks-tsv"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

records_file="$(mktemp)"
checks_file="$(mktemp)"
expansion_errors_file="$(mktemp)"
trap 'rm -f "$records_file" "$checks_file" "$expansion_errors_file"' EXIT

record() {
  local category="$1"
  local path="$2"
  local kind="$3"
  local note="$4"
  printf '%s\t%s\t%s\t%s\n' "$category" "$kind" "$path" "$note" >>"$records_file"
}

record_check() {
  local category="$1"
  local path="$2"
  local check_id="$3"
  local note="$4"
  printf '%s\t%s\t%s\t%s\n' "$category" "$path" "$check_id" "$note" >>"$checks_file"
}

record_expansion_error() {
  local path="$1"
  local note="$2"
  printf '%s\t%s\n' "$path" "$note" >>"$expansion_errors_file"
}

# Capability records keep required proof boundaries visible without pretending
# that a placeholder, recipe catalog, or artifact binding is executable. The
# Plan 258 manifest is the release-gate source of truth; these structured notes
# are the compatibility discovery inventory used to reconcile that manifest.
record_capability() {
  local lifecycle="$1"
  local path="$2"
  local capability_id="$3"
  local requiredness="$4"
  local family="$5"
  local boundary="$6"
  local profile="$7"
  local target="$8"
  local reason="$9"

  record "$lifecycle" "$path" "capability" \
    "id=$capability_id required=$requiredness family=$family boundary=$boundary profile=$profile target=$target reason=$reason"
}

record_archived_proof_requirements() {
  local registry="Test-Flight-Improv/sims-manual-proof-registry.md"
  record_capability "implemented" "$registry" \
    "android.connectivity_restore_inbox_drain" "major" "1to1" \
    "android-os-network+relay" "android.e2e.main" \
    "android-physical+android-emulator" \
    "manifest_owned_ADB_driver_three_message_drain_no_resume_and_fdc04_network_change_rewarm"
  record_capability "implemented" "$registry" \
    "android.connectivity_restore_media_outbox" "major" "1to1" \
    "android.os-network.private-media-outbox.relay-delivery" \
    "android.e2e.main" "android-physical+android-emulator" \
    "manifest_owned_production_private_media_offline_restore_exactly_once_delivery"
  record_capability "implemented" "$registry" \
    "android.keepalive_drop_skip_direct" "major" "1to1" \
    "android-process-lifecycle+bridge+relay" "android.e2e.main" \
    "android-physical+android-emulator" \
    "manifest_owned_main_app_driver_natural_drop_no_dial_bounded_custody_recovery_delivery_and_rearm"
  record_capability "implemented" "$registry" \
    "android.wake_token_directionality" "major" "1to1" \
    "android-native-bridge-relay" "android.e2e.wake_token" \
    "android-physical+android-emulator" \
    "manifest_owned_hash_only_registered_stored_attached_directionality_driver"
  record_capability "implemented" "$registry" \
    "android.direct_media_blob_custody" "major" "1to1" \
    "android.two-peer.direct-media-blob-custody" \
    "android.e2e.direct_media_custody" \
    "android-physical+android-emulator" \
    "manifest_owned_disposable_relay_restart_exact_bytes_source_pinned_ack_driver"
  record_capability "inactive" "$registry" \
    "vc02.dcutr_upgrade" "future" "voice-video-1to1" \
    "android-nat-relay" "android.e2e.standard" \
    "android-physical+android-emulator" \
    "INACTIVE_until_VC01_circuit_hold_and_VC02_default_on_upgrade_are_implemented"
  record_capability "inactive" "$registry" \
    "vc02.dcutr_symmetric_cgnat_negative" "future" \
    "voice-video-1to1" "android-symmetric-cgnat-relay" \
    "android.e2e.standard" "network-symmetric-cgnat" \
    "INACTIVE_until_VC01_VC02_implemented_then_NA_only_when_topology_unavailable"
}

classify_path() {
  local path="$1"

  case "$path" in
    smoke_test_friends.sh)
      record "intro" "$path" "runner" "intro three/four-simulator scenario harness"
      return
      ;;
    reset_simulators.sh)
      record "support" "$path" "support" "intro simulator reset helper"
      return
      ;;
    lib/core/debug/intro_e2e_runner.dart)
      record "support" "$path" "support" "intro E2E app-side runner"
      return
      ;;
    lib/core/debug/e2e_test_mode.dart|\
    lib/core/debug/connectivity_restore_e2e_contract.dart|\
    lib/core/debug/keepalive_drop_e2e.dart|\
    lib/core/debug/keepalive_drop_e2e_contract.dart|\
    lib/core/debug/group_reaction_e2e_probe.dart|\
    lib/core/debug/group_notification_projection_e2e.dart|\
    lib/debug/group_notification_projection_e2e_action.dart|\
    lib/core/debug/android_notification_payload_e2e.dart|\
    lib/core/debug/android_notification_payload_e2e_protocol.dart|\
    lib/core/debug/private_media_outbox_e2e.dart|\
    lib/core/debug/private_media_outbox_e2e_conversation.dart|\
    lib/core/debug/private_media_outbox_e2e_protocol.dart|\
    lib/core/debug/wake_token_directionality_e2e.dart|\
    lib/core/debug/wake_token_directionality_e2e_protocol.dart)
      record "support" "$path" "support" "debug-only E2E mode, campaign contract, or production-database probe wiring"
      return
      ;;
    lib/core/debug/smoke_test_runner.dart)
      record "support" "$path" "support" "smoke-test app-side automation runner"
      return
      ;;
    scripts/push_fixture_to_simulator.sh|scripts/push_fixture_to_android_emulator.sh)
      record "support" "$path" "support" "push fixture injection helper"
      return
      ;;
    scripts/smoke_test_push_decrypt_simulator.sh)
      record "1to1" "$path" "runner" "1:1 push-decrypt simulator smoke rows"
      record "group" "$path" "runner" "group push-decrypt simulator smoke rows"
      return
      ;;
    scripts/run_ios_notification_tap_ui_smoke.sh)
      record "1to1" "$path" "runner" "iOS notification tap smoke includes 1:1 rows"
      record "group" "$path" "runner" "iOS notification tap smoke includes group rows"
      return
      ;;
    scripts/run_app_visibility_android_e2e.sh)
      record "1to1" "$path" "runner" "Plan 371 app-visibility lifecycle scenario"
      record "group" "$path" "runner" "Plan 371 app-visibility lifecycle scenario"
      return
      ;;
  esac

  case "$path" in
    integration_test/scripts/select_android_picture_in_picture_pixel6_api36_geometry.dart|\
    integration_test/scripts/select_android_picture_in_picture_system_ui_control.dart)
      record "support" "$path" "support" "243 Android received-video PiP SystemUI control selector"
      return
      ;;
    integration_test/received_video_picture_in_picture_proof_test.dart)
      record "ignored" "$path" "ignored" "manual Android received-video Picture-in-Picture proof outside default reliability-sim"
      return
      ;;
    integration_test/received_media_native_egress_proof_test.dart)
      record "ignored" "$path" "ignored" "manual Android/iOS received-media native egress proof outside default reliability-sim"
      return
      ;;
    integration_test/media_library_state_sqlcipher_proof_test.dart)
      record "ignored" "$path" "ignored" "manual Android/iOS media-library-state SQLCipher migration proof outside reliability-sim"
      return
      ;;
    integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart)
      record "ignored" "$path" "ignored" "manual Android/iOS direct-forwarded v97 SQLCipher migration proof outside reliability-sim"
      return
      ;;
    integration_test/group_media_deletion_journal_sqlcipher_proof_test.dart)
      record "ignored" "$path" "ignored" "manual Android/iOS group-media-deletion-journal v98 SQLCipher migration proof outside reliability-sim"
      return
      ;;
    integration_test/group_forwarded_marker_db_proof_test.dart)
      record "group" "$path" "test" "236 group forwarded-marker v99 SQLCipher migration proof (upgrade/wrong-password/downgrade/reopen)"
      return
      ;;
    integration_test/android_background_crypto_preflight_app.dart)
      record "support" "$path" "support" "256 TC-07 real-FCM headless crypto preflight app target"
      return
      ;;
    integration_test/scripts/capture_1to1_reaction_head_provenance.dart|\
    integration_test/scripts/capture_android_background_crypto_preflight.dart|\
    integration_test/scripts/capture_1to1_reaction_notification_closure.dart)
      record "support" "$path" "support" "256 bounded reaction-notification device proof capture driver"
      return
      ;;
    integration_test/scripts/capture_android_push_relay_registration.dart)
      record "support" "$path" "support" "256 Android production push-relay registration capture driver"
      return
      ;;
    integration_test/scripts/reaction_notification_proof_support.dart)
      record "support" "$path" "support" "256 reaction-notification proof parsing and attribution helper"
      return
      ;;
    integration_test/scripts/group_reaction_notification_device_criteria.dart|\
    integration_test/scripts/capture_group_reaction_notification_device.dart|\
    integration_test/group_reaction_notification_sqlcipher_probe_test.dart)
      record "support" "$path" "support" "257 staged group/announcement reaction-notification capture, SQLCipher observer, and strict evidence criteria"
      return
      ;;
    integration_test/scripts/group_notification_projection_android_criteria.dart)
      record "support" "$path" "support" "330 strict Android group notification projection raw-evidence criteria"
      return
      ;;
    integration_test/scripts/direct_private_media_device_local_journey_criteria.dart|\
    integration_test/direct_private_media_device_local_journey_harness.dart)
      record "support" "$path" "support" "234 deterministic device-local private-media proof support"
      return
      ;;
    integration_test/scripts/android_group_media_reliability_controller.dart|\
    integration_test/scripts/group_media_ios_background_recovery.dart|\
    integration_test/scripts/group_media_ios_background_recovery_evidence.dart|\
    integration_test/scripts/group_media_ios_fixture_driver.dart|\
    integration_test/scripts/group_media_prepared_artifact_custody.dart|\
    integration_test/scripts/group_media_reliability_criteria.dart|\
    integration_test/scripts/group_media_reliability_runner_contract.dart|\
    integration_test/support/group_media_android_disposable_app.dart|\
    lib/core/debug/group_media_ios_background_e2e.dart|\
    lib/core/debug/group_media_ios_background_e2e_contract.dart|\
    lib/core/debug/group_media_ios_background_e2e_main_actions.dart|\
    lib/core/debug/group_media_ios_background_e2e_overlay.dart|\
    lib/core/debug/group_media_ios_disposable_profile.dart|\
    lib/core/debug/group_media_ios_disposable_reset.dart|\
    lib/core/debug/group_media_reliability_e2e.dart|\
    lib/core/debug/group_media_reliability_e2e_main_actions.dart)
      record "support" "$path" "support" "269 strict group-media app hooks, host controllers, artifact criteria, and prepared-runner contract"
      return
      ;;
    integration_test/scripts/_android_app_package.dart|\
    integration_test/scripts/routing_smoke_group_criteria.dart|\
    integration_test/sims_dispatcher.dart|\
    integration_test/setup_device.dart|\
    integration_test/benchmark_helpers.dart)
      record "support" "$path" "support" "shared integration-test helper or prebuilt runtime dispatcher"
      return
      ;;
    integration_test/scripts/posts_phase*_smoke.sh|\
    integration_test/posts_phase*_fake_test.dart)
      record "ignored" "$path" "ignored" "posts simulator/fake smoke outside 1:1/group/intro reliability"
      return
      ;;
    integration_test/scripts/run_transport_census_cli.dart)
      record "ignored" "$path" "ignored" "manual NET-REL-04 1:1 transport census harvest outside default reliability-sim gates"
      return
      ;;
    integration_test/apns_provider_probe_app.dart|\
    integration_test/apns_provider_probe_harness.dart)
      record "ignored" "$path" "ignored" "physical iOS APNs provider probe outside default simulator reliability gates"
      return
      ;;
    integration_test/migration_database_sqlcipher_capability_test.dart)
      record "move-feature" "$path" "test" "Move Account SQLCipher migration capability companion"
      return
      ;;
    integration_test/db_raw_key_migration_proof_test.dart)
      record "move-feature" "$path" "test" "218 SQLCipher raw-key cold-start migration device proof (SC-8/R/1-9/B/F1)"
      return
      ;;
    integration_test/app_group_path_simulator_test.dart)
      record "1to1" "$path" "test" "iOS app-group notification dedupe simulator proof"
      return
      ;;
    integration_test/benchmark_harness.dart|\
    integration_test/performance_harness.dart)
      record "ignored" "$path" "ignored" "single dispatched benchmark/performance entrypoint (BENCHMARK/PERF_TARGET=<key>) outside reliability simulation discovery"
      return
      ;;
    integration_test/scripts/run_benchmark_suite.dart|\
    integration_test/scripts/run_group_publish_benchmark.dart|\
    integration_test/scripts/run_timeout_accuracy_benchmark.dart|\
    integration_test/benchmark_*_harness.dart|\
    integration_test/*_performance_test.dart|\
    integration_test/*_performance_harness.dart)
      record "ignored" "$path" "ignored" "benchmark/performance coverage outside reliability simulation discovery"
      return
      ;;
    integration_test/transport_census_harness.dart)
      record "support" "$path" "support" "NET-REL-04 transport census role harness launched by census orchestrators"
      return
      ;;
  esac

  case "$path" in
    integration_test/scripts/run_routing_smoke_e2e.dart)
      record "1to1" "$path" "runner" "two-simulator 1:1 routing smoke"
      record "group" "$path" "runner" "two-simulator group routing smoke"
      return
      ;;
    integration_test/routing_smoke_harness.dart)
      record "support" "$path" "support" "1:1 routing smoke harness"
      return
      ;;
    integration_test/group_smoke_harness.dart)
      record "support" "$path" "support" "group routing smoke harness"
      return
      ;;
  esac

  case "$path" in
    integration_test/scripts/run_transport_e2e.dart|\
    integration_test/scripts/run_wifi_relay_fallback_smoke.dart|\
    integration_test/scripts/run_soak_e2e.dart|\
    integration_test/scripts/run_media_message_journey_e2e.dart|\
    integration_test/scripts/run_notification_open_during_other_chat.dart)
      record "1to1" "$path" "runner" "1:1 simulator/E2E orchestrator"
      return
      ;;
    integration_test/scripts/run_1to1_device_real.dart)
      record "support" "$path" "support" "mixed typed 1:1 facade: manifest owns prebuilt Android recorder and two-peer campaigns; unimplemented legacy recipes remain BLOCKED"
      return
      ;;
    integration_test/scripts/run_connectivity_restore_sims.dart)
      record "support" "$path" "support" "manifest-owned build-free physical-Android plus emulator connectivity restore campaign"
      return
      ;;
    integration_test/scripts/run_connectivity_restore_media_outbox_sims.dart)
      record "support" "$path" "support" "manifest-owned production private-media outbox restore campaign"
      return
      ;;
    integration_test/scripts/android_keepalive_drop_campaign.dart)
      record "support" "$path" "support" "manifest-owned build-free physical-Android plus emulator keepalive drop campaign"
      return
      ;;
    integration_test/scripts/android_wake_token_directionality_campaign.dart)
      record "support" "$path" "support" "manifest-owned build-free physical-Android plus emulator hash-only wake-token directionality campaign"
      return
      ;;
    integration_test/scripts/run_direct_media_blob_custody_sims.dart|\
    integration_test/scripts/android_direct_media_blob_custody_campaign.dart|\
    integration_test/scripts/android_direct_media_blob_custody_device_action.dart|\
    integration_test/support/android_direct_media_blob_custody_campaign_contract.dart|\
    integration_test/support/android_direct_media_blob_custody_evidence.dart)
      record "support" "$path" "support" "347 manifest-owned disposable-relay adapter, concrete Android action campaign, or hash-only evidence contract"
      return
      ;;
    integration_test/scripts/run_voice_message_sims.dart|\
    integration_test/scripts/android_voice_message_device_campaign.dart)
      record "support" "$path" "support" "manifest-owned prebuilt main-app physical-Android plus emulator voice-message campaign"
      return
      ;;
    integration_test/scripts/run_notification_tap_device_real.dart|\
    integration_test/scripts/notification_android_payload_campaign.dart|\
    integration_test/scripts/notification_ios_payload_campaign.dart|\
    integration_test/scripts/ios_notification_payload_xcui_driver.dart|\
    integration_test/scripts/run_ios_notification_payload_sims.dart)
      record "support" "$path" "support" "typed notification facade/campaign: Android and prebuilt physical-iOS APNs/NSE campaigns are automation-ready; live iOS credentials and dedicated-device teardown remain typed BLOCKED prerequisites; manifest owns execution"
      return
      ;;
    integration_test/scripts/ios_notification_provider_adapter.md|\
    integration_test/scripts/ios_notification_provider_adapter.py|\
    integration_test/scripts/ios_notification_relay_fixture.md|\
    integration_test/scripts/ios_notification_relay_fixture_driver.py|\
    integration_test/scripts/ios_notification_relay_remote_helper.py|\
    integration_test/scripts/ios_receiver_bootstrap.md|\
    integration_test/scripts/ios_receiver_bootstrap.py)
      record "support" "$path" "support" "physical-iOS APNs provider, relay-fixture, and receiver-bootstrap automation support"
      return
      ;;
    lib/core/debug/android_voice_message_e2e.dart|\
    lib/core/debug/android_voice_message_e2e_protocol.dart)
      record "support" "$path" "support" "debug-only main-app voice-message endpoint and pure host protocol"
      return
      ;;
    lib/debug/android_direct_media_blob_custody_e2e.dart|\
    lib/core/debug/android_direct_media_blob_custody_e2e_protocol.dart)
      record "support" "$path" "support" "347 profile-gated direct-media custody endpoint and pure host protocol"
      return
      ;;
    integration_test/scripts/run_1to1_reaction_notification_device.dart)
      record "1to1" "$path" "runner" "256 reaction-notification device/relay proof campaign orchestrator (--list-scenarios)"
      return
      ;;
    integration_test/scripts/run_direct_private_media_device_local_journey.dart)
      record "1to1" "$path" "runner" "234 fully automated physical-Android plus emulator device-local private-media proof"
      return
      ;;
    integration_test/one_to_one_reaction_notification_proof_test.dart)
      record "1to1" "$path" "test" "256 TC-00/07/13/14/16 reaction-notification device proof artifact validation"
      return
      ;;
    integration_test/scripts/run_group_reaction_notification_device.dart)
      record "group" "$path" "runner" "257 config-gated automated group/announcement reaction-notification device campaign"
      return
      ;;
    integration_test/scripts/validate_group_reaction_notification_artifacts.dart)
      record "support" "$path" "support" "257 capture-owned authoritative artifact validator; invoked only after its owning capture"
      return
      ;;
    integration_test/group_announcement_reaction_notification_proof_test.dart)
      record "group" "$path" "test" "257 TC-13/14/15/16 group/announcement notification proof binding"
      return
      ;;
    integration_test/scripts/run_intro_accept_notification_android.dart)
      record "intro" "$path" "runner" "252 intro-accept notification copy/tap three-party Android device proof campaign orchestrator (--list-scenarios)"
      return
      ;;
    integration_test/scripts/run_intro_accept_notification_sims.dart)
      record "support" "$path" "support" "typed sims adapter for the intro notification campaign; manifest owns the executable proof row"
      return
      ;;
    integration_test/intro_accept_notification_android_proof_test.dart)
      record "support" "$path" "support" "252 capture-owned TC-12/TC-13 intro-accept artifact binding; not a device execution row"
      return
      ;;
    integration_test/group_notification_projection_android_proof_test.dart)
      record "support" "$path" "support" "330 capture-owned Android projection artifact binding; manifest owns execution"
      return
      ;;
    integration_test/android_notification_recovery_completion_proof_test.dart)
      record "support" "$path" "support" "331 capture-owned paired Android recovery artifact binding; manifest owns execution"
      return
      ;;
    integration_test/scripts/run_media_stable_id_smoke.dart|\
    integration_test/scripts/run_media_delivery_ui_smoke.dart)
      record "1to1" "$path" "runner" "1:1 media simulator smoke"
      record "group" "$path" "runner" "group media simulator smoke"
      return
      ;;
    integration_test/scripts/run_notification_open_ui_smoke.dart)
      record "1to1" "$path" "runner" "notification-open smoke includes 1:1 rows"
      record "group" "$path" "runner" "notification-open smoke includes group rows"
      record "intro" "$path" "runner" "notification-open smoke includes intro routing rows"
      return
      ;;
    integration_test/scripts/run_notification_sound_smoke.dart)
      record "1to1" "$path" "runner" "notification sound smoke includes 1:1 rows"
      record "group" "$path" "runner" "notification sound smoke includes group rows"
      return
      ;;
    integration_test/notification_open_during_other_chat_harness.dart)
      record "support" "$path" "support" "1:1 notification-open two-simulator harness"
      return
      ;;
    integration_test/inbox_replay_before_ack_custody_harness.dart)
      record "support" "$path" "support" "225 capture-owned TC-A6 replay-before-ack artifact binding; not a device execution row"
      return
      ;;
    integration_test/notif_push_payload_persist_harness.dart)
      record "support" "$path" "support" "225 capture-owned TC-B11 payload-persist artifact binding; not a device execution row"
      return
      ;;
    integration_test/notification_tap_message_visible_proof_test.dart)
      record "support" "$path" "support" "225 capture-owned TC-B12 payload-fast-path artifact binding; not a device execution row"
      return
      ;;
    integration_test/notification_sound_smoke_harness.dart)
      record "support" "$path" "support" "1:1/group notification sound harness"
      return
      ;;
  esac

  case "$path" in
    integration_test/scripts/run_group_recovery_e2e.dart|\
    integration_test/scripts/run_group_multi_device_real.dart|\
    integration_test/scripts/run_b1b_sibling_device_convergence.dart|\
    integration_test/scripts/run_invite_reliability_multi_device.dart|\
    integration_test/scripts/run_group_invite_status_matrix_sim.dart|\
    integration_test/scripts/run_group_multi_party_device_real.dart|\
    integration_test/scripts/run_foreground_group_push_simulator_smoke.dart)
      record "group" "$path" "runner" "group simulator/E2E orchestrator"
      return
      ;;
    integration_test/foreground_group_push_simulator_harness.dart|\
    integration_test/group_invite_status_matrix_harness.dart|\
    integration_test/group_multi_party_device_real_android_harness.dart|\
    integration_test/group_multi_party_device_real_harness.dart|\
    integration_test/group_multi_device_real_harness.dart)
      record "support" "$path" "support" "group simulator harness"
      return
      ;;
    integration_test/scripts/group_multi_party_device_criteria.dart)
      record "support" "$path" "support" "group multi-party device criteria helper"
      return
      ;;
    integration_test/scripts/group_multi_party_runtime_config.dart)
      record "support" "$path" "support" "group multi-party runtime config helper"
      return
      ;;
    integration_test/scripts/run_group_multi_party_sims.dart)
      record "support" "$path" "support" "typed sims adapter for the existing group multi-party runner; not a second executable proof row"
      return
      ;;
    integration_test/scripts/run_group_reaction_notification_sims.dart)
      record "support" "$path" "support" "typed sims adapter for the group reaction-notification campaign; manifest owns the executable proof row"
      return
      ;;
    integration_test/scripts/run_group_notification_projection_android.dart)
      record "support" "$path" "support" "typed Sims adapter for Android group notification projection durability; manifest owns execution"
      return
      ;;
    integration_test/scripts/run_android_notification_recovery_completion.dart)
      record "support" "$path" "support" "manifest-owned paired Android recovery runner; product debug seam remains activation-gated"
      return
      ;;
    integration_test/scripts/android_notification_recovery_completion_criteria.dart)
      record "support" "$path" "support" "331 strict content-addressed Android recovery evidence criteria"
      return
      ;;
    integration_test/scripts/run_group_media_send_reliability.dart)
      record "group" "$path" "runner" "269 prepared-artifact two-role group-media reliability runner (--list-scenarios)"
      return
      ;;
    integration_test/group_multi_party_phase0_runtime_channel_probe.dart)
      record "support" "$path" "support" "group multi-party Phase 0 runtime-channel probe target"
      return
      ;;
  esac

  case "$path" in
    integration_test/conversation_swipe_back_proof_test.dart)
      record "1to1" "$path" "test" "1:1 edge-swipe-back navigation device proof"
      return
      ;;
    integration_test/sender_media_unavailable_fallback_proof_test.dart)
      record "1to1" "$path" "test" "sender media-unavailable render fallback proof (1:1)"
      record "group" "$path" "test" "sender media-unavailable render fallback proof (group)"
      return
      ;;
    integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart)
      record "1to1" "$path" "test" "234 TC-234-03 direct private-media v100 SQLCipher lifecycle migration device proof"
      return
      ;;
    integration_test/direct_notification_durability_sqlcipher_proof_test.dart)
      record "1to1" "$path" "test" "331 TC-331-22 Android v106-to-v108/current direct notification SQLCipher durability device proof"
      return
      ;;
    integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart)
      record "1to1" "$path" "test" "342/345/347/361/362/365 TC-342-11 direct-text, TC-345-11 direct-media, TC-347-01 blob custody, TC-361-04a linked event fanout, TC-362-05a linked media fanout and TC-365-01a group-media custody Android SQLCipher durability device proofs"
      return
      ;;
    integration_test/direct_reaction_inbox_custody_outbox_sqlcipher_proof_test.dart)
      record "1to1" "$path" "test" "343 TC-343-10 Android v108-to-v109 direct-reaction custody SQLCipher durability device proof"
      return
      ;;
    integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart)
      record "1to1" "$path" "test" "336 TC-336-16 atomic outgoing transport settlement SQLCipher device proof"
      return
      ;;
    integration_test/direct_private_media_platform_protection_proof_test.dart)
      record "1to1" "$path" "test" "234 TC-234-11 direct private-media platform-protection device proof"
      return
      ;;
    integration_test/protected_photo_thumbnail_secure_window_proof_test.dart)
      record "1to1" "$path" "test" "protected thumbnail secure-window device proof"
      return
      ;;
    integration_test/group_private_media_lifecycle_db_proof_test.dart)
      record "group" "$path" "test" "238 GPL-01D group private-media v101 SQLCipher lifecycle migration device proof"
      return
      ;;
    integration_test/group_self_removed_marker_sqlcipher_proof_test.dart)
      record "group" "$path" "test" "263 GSR-102D removed-member shell v102 SQLCipher authority migration device proof"
      return
      ;;
    integration_test/group_exit_intents_sqlcipher_proof_test.dart)
      record "group" "$path" "test" "264 PB264-05 group-exit-intents v103 SQLCipher migration device proof"
      return
      ;;
    integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart)
      record "group" "$path" "test" "266 PB266-15 release SQLCipher diagnostic reopen and Settings remount proof"
      return
      ;;
    integration_test/group_notification_display_outbox_sqlcipher_proof_test.dart)
      record "group" "$path" "test" "330 Android SQLCipher v105-to-v106 group notification display-outbox proof"
      return
      ;;
    integration_test/group_private_media_platform_proof_test.dart)
      record "ignored" "$path" "ignored" "238 GPL-11 manual Android/iOS native group private-media capture proof outside reliability-sim"
      return
      ;;
    integration_test/announcement_private_media_platform_proof_test.dart)
      record "ignored" "$path" "ignored" "242 APL-08 manual Android wired announcement private-media capture proof outside reliability-sim"
      return
      ;;
    integration_test/transport_e2e_test.dart|\
    integration_test/wifi_relay_fallback_smoke_test.dart|\
    integration_test/wifi_transport_test.dart|\
    integration_test/background_reconnect_test.dart|\
    integration_test/soak_e2e_test.dart|\
    integration_test/conversation_bridge_test.dart|\
    integration_test/media_message_journey_e2e_test.dart|\
    integration_test/warm_peer_lan_aware_smoke_test.dart|\
    integration_test/cold_start_sendable_no_user_action_test.dart)
      record "1to1" "$path" "test" "1:1 transport/conversation simulator test"
      return
      ;;
    integration_test/voice_message_e2e_test.dart)
      record "1to1" "$path" "test" "Android native microphone recorder smoke; physical Android target required; permission/plugin failures are test failures"
      return
      ;;
    integration_test/media_stable_id_smoke_test.dart|\
    integration_test/cold_start_message_render_simulator_test.dart)
      record "1to1" "$path" "test" "1:1 simulator smoke test"
      record "group" "$path" "test" "group simulator smoke test"
      return
      ;;
    integration_test/notification_open_ui_smoke_test.dart)
      record "1to1" "$path" "test" "notification-open smoke includes 1:1 rows"
      record "group" "$path" "test" "notification-open smoke includes group rows"
      record "intro" "$path" "test" "notification-open smoke includes intro routing rows"
      return
      ;;
    integration_test/foreground_group_push_drain_test.dart)
      record "1to1" "$path" "test" "foreground push drain includes 1:1 control coverage"
      record "group" "$path" "test" "foreground group push drain test"
      return
      ;;
    integration_test/account_migration_scale_benchmark_test.dart|\
    integration_test/account_migration_group_media_durability_simulator_test.dart|\
    integration_test/account_migration_local_transfer_timeout_simulator_test.dart)
      record "move-feature" "$path" "test" "Move Account simulator/E2E test"
      return
      ;;
    integration_test/group_recovery_e2e_test.dart|\
    integration_test/group_recovery_cli_e2e_test.dart|\
    integration_test/group_real_crypto_onboarding_test.dart)
      record "group" "$path" "test" "group simulator/E2E test"
      return
      ;;
    integration_test/group_lifecycle_simulator_harness.dart)
      record "group" "$path" "test" "single dispatched group-lifecycle simulator entrypoint (GROUP_SIM_SCENARIO=<key>)"
      return
      ;;
    integration_test/group_invite_reliability_proof_test.dart|\
    integration_test/group_message_retry_backoff_db_proof_test.dart|\
    integration_test/group_mute_notification_db_proof_test.dart|\
    integration_test/group_reaction_reliability_db_proof_test.dart|\
    integration_test/group_recovery_gate_serialization_proof_test.dart|\
    integration_test/group_rejoin_state_db_proof_test.dart|\
    integration_test/group_removal_rotation_keyless_converge_proof_test.dart|\
    integration_test/group_removal_rotation_keyless_proof_test.dart)
      record "group" "$path" "test" "group reliability device proof"
      return
      ;;
    integration_test/group_admin_metadata_convergence_simulator_test.dart|\
    integration_test/group_delete_preserves_friends_simulator_test.dart|\
    integration_test/group_invite_accept_spinner_simulator_test.dart|\
    integration_test/group_new_member_media_simulator_proof_test.dart)
      record "support" "$path" "support" "group-lifecycle simulator scenario library dispatched via group_lifecycle_simulator_harness.dart"
      return
      ;;
  esac

  case "$path" in
    integration_test/bidi_text_smoke_test.dart|\
    integration_test/feed_performance_test.dart|\
    integration_test/feed_wired_init_performance_harness.dart|\
    integration_test/group_conversation_polish_proof_test.dart|\
    integration_test/group_terminal_send_failed_proof_test.dart|\
    integration_test/identity_progress_performance_test.dart|\
    integration_test/loading_states_smoke_test.dart|\
    integration_test/orbit_performance_harness.dart|\
    integration_test/settings_background_choice_smoke_test.dart|\
    integration_test/smoke_test.dart)
      record "ignored" "$path" "ignored" "general UI/performance smoke outside 1:1/group/intro reliability"
      return
      ;;
  esac

  record "unclassified" "$path" "unclassified" "candidate matched discovery but has no classification rule"
}

discover_candidates() {
  {
    find integration_test -maxdepth 1 -type f -name '*.dart' -print 2>/dev/null
    find integration_test/scripts -maxdepth 1 -type f -print 2>/dev/null
    [ ! -f integration_test/support/group_media_android_disposable_app.dart ] ||
      printf '%s\n' integration_test/support/group_media_android_disposable_app.dart
    [ ! -f integration_test/support/android_direct_media_blob_custody_evidence.dart ] ||
      printf '%s\n' integration_test/support/android_direct_media_blob_custody_evidence.dart
    [ ! -f integration_test/support/android_direct_media_blob_custody_campaign_contract.dart ] ||
      printf '%s\n' integration_test/support/android_direct_media_blob_custody_campaign_contract.dart
    find scripts -maxdepth 1 -type f \( \
      -name '*simulator*.sh' -o \
      -name '*emulator*.sh' -o \
      -name '*e2e*.sh' -o \
      -name '*smoke*.sh' \
    \) -print 2>/dev/null
    find lib/core/debug -maxdepth 1 -type f \( -name '*e2e*.dart' -o -name '*smoke*.dart' \) -print 2>/dev/null
    for path in \
      lib/core/debug/group_media_ios_disposable_profile.dart \
      lib/core/debug/group_media_ios_disposable_reset.dart \
      lib/debug/android_direct_media_blob_custody_e2e.dart \
      lib/debug/group_notification_projection_e2e_action.dart; do
      [ ! -f "$path" ] || printf '%s\n' "$path"
    done
    [ -f smoke_test_friends.sh ] && printf '%s\n' smoke_test_friends.sh
    [ -f reset_simulators.sh ] && printf '%s\n' reset_simulators.sh
  } | sed 's#^\./##' | sort -u
}

print_category() {
  local category="$1"
  local title="$2"
  local count
  count="$(awk -F '\t' -v cat="$category" '$1 == cat { count++ } END { print count + 0 }' "$records_file")"
  printf '\n%s (%s)\n' "$title" "$count"
  awk -F '\t' -v cat="$category" '$1 == cat { printf "  - [%s] %s - %s\n", $2, $3, $4 }' "$records_file" | sort
}

print_check_category() {
  local category="$1"
  local title="$2"
  local count
  count="$(awk -F '\t' -v cat="$category" '$1 == cat { count++ } END { print count + 0 }' "$checks_file")"
  printf '\n%s (%s)\n' "$title" "$count"
  awk -F '\t' -v cat="$category" '$1 == cat { printf "  - %s :: %s - %s\n", $2, $3, $4 }' "$checks_file" | sort
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

extract_dart_test_labels() {
  local path="$1"
  perl -0ne "while (/(?:^|\\n)\\s*(?:testWidgets|test)\\s*\\(\\s*((?:\\\"[^\\\"]*\\\"|'[^']*'|\\s)+)/sg) { my \$block = \$1; my \$name = ''; while (\$block =~ /\\\"([^\\\"]*)\\\"|'([^']*)'/g) { \$name .= defined \$1 ? \$1 : \$2; } \$name =~ s/\\s+/ /g; \$name =~ s/^\\s+|\\s+\$//g; print \"\$name\\n\" if \$name ne ''; }" "$path"
}

should_include_dart_label() {
  local category="$1"
  local source_path="$2"
  local label="$3"
  local lower
  lower="$(lowercase "$label")"

  case "$source_path" in
    integration_test/notification_open_ui_smoke_test.dart)
      case "$category" in
        1to1)
          case "$lower" in *group*|*intro*|*invite*|*post*) return 1 ;; *) return 0 ;; esac
          ;;
        group)
          case "$lower" in *group*) return 0 ;; *) return 1 ;; esac
          ;;
        intro)
          case "$lower" in *intro*|*invite*) return 0 ;; *) return 1 ;; esac
          ;;
      esac
      ;;
    integration_test/media_stable_id_smoke_test.dart)
      case "$category" in
        1to1)
          case "$lower" in *1:1*|*one-to-one*|*one\ to\ one*) return 0 ;; *) return 1 ;; esac
          ;;
        group)
          case "$lower" in *group*|*announcement*) return 0 ;; *) return 1 ;; esac
          ;;
      esac
      ;;
    integration_test/foreground_group_push_drain_test.dart)
      case "$category" in
        1to1)
          case "$lower" in *1:1*) return 0 ;; *) return 1 ;; esac
          ;;
        group)
          case "$lower" in *group*|*announcement*) return 0 ;; *) return 1 ;; esac
          ;;
      esac
      ;;
  esac

  return 0
}

expand_dart_test_declarations() {
  local category="$1"
  local output_path="$2"
  local source_path="$3"
  local note="$4"
  local count=0
  local label
  local detail

  detail="$note"
  if [ "$output_path" != "$source_path" ]; then
    detail="$note; target=$source_path"
  fi

  while IFS= read -r label; do
    [ -n "$label" ] || continue
    if should_include_dart_label "$category" "$source_path" "$label"; then
      record_check "$category" "$output_path" "$label" "$detail"
      count=$((count + 1))
    fi
  done < <(extract_dart_test_labels "$source_path")

  printf '%s\n' "$count"
}

extract_runner_targets() {
  local path="$1"
  awk '{
    line = $0
    while (match(line, /integration_test\/[A-Za-z0-9_\/.-]+_test\.dart/)) {
      print substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
    }
  }' "$path" | sort -u
}

expand_runner_target_tests() {
  local category="$1"
  local path="$2"
  local note="$3"
  local target
  local count
  local total=0
  local found=0

  while IFS= read -r target; do
    [ -n "$target" ] || continue
    found=1
    if [ ! -f "$target" ]; then
      record_expansion_error "$path" "references missing target test: $target"
      continue
    fi
    count="$(expand_dart_test_declarations "$category" "$path" "$target" "$note")"
    total=$((total + count))
  done < <(extract_runner_targets "$path")

  if [ "$total" -gt 0 ]; then
    return 0
  fi

  if [ "$found" -gt 0 ]; then
    record_expansion_error "$path" "target test(s) found but no $category checks matched"
  fi
  return 1
}

expand_intro_smoke() {
  local category="$1"
  local path="$2"
  local scenario
  local count=0

  while IFS= read -r scenario; do
    [ -n "$scenario" ] || continue
    record_check "$category" "$path" "$scenario" "INTRO_E2E_SCENARIO=all scenario"
    count=$((count + 1))
  done < <(
    awk '
      /^[[:space:]]*all\)/ { in_all = 1; next }
      in_all && /^[[:space:]]*;;/ { in_all = 0; next }
      in_all {
        line = $0
        while (match(line, /scenario_[A-Za-z0-9_]+/)) {
          print substr(line, RSTART, RLENGTH)
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract INTRO_E2E_SCENARIO=all scenarios"
  fi
}

expand_routing_smoke() {
  local category="$1"
  local path="$2"
  local scenario
  local count=0

  while IFS= read -r scenario; do
    [ -n "$scenario" ] || continue
    case "$category:$scenario" in
      1to1:S*|1to1:X*|group:G*)
        record_check "$category" "$path" "$scenario" "routing smoke scenario"
        count=$((count + 1))
        ;;
    esac
  done < <(
    awk '
      /_check\(/ { pending = 1 }
      pending {
        line = $0
        if (match(line, /\047[SGX][0-9]+\047/)) {
          print substr(line, RSTART + 1, RLENGTH - 2)
          pending = 0
        }
        if (/\);/) {
          pending = 0
        }
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract $category routing smoke scenarios"
  fi
}

expand_push_decrypt() {
  local category="$1"
  local path="$2"
  local id payload scope description lower
  local count=0

  while IFS='|' read -r id payload scope description; do
    [ -n "$id" ] || continue
    lower="$(lowercase "$payload $description")"
    case "$category" in
      1to1)
        case "$lower" in *one_to_one*|*1:1*) ;; *) continue ;; esac
        ;;
      group)
        case "$lower" in *group*) ;; *) continue ;; esac
        ;;
    esac
    record_check "$category" "$path" "$id" "push-decrypt scope=$scope $description"
    count=$((count + 1))
  done < <(
    awk '
      /^[[:space:]]*"S-/ {
        line = $0
        sub(/^[[:space:]]*"/, "", line)
        sub(/"[[:space:]]*,?[[:space:]]*$/, "", line)
        print line
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract $category push-decrypt scenarios"
  fi
}

expand_ios_notification_tap() {
  local category="$1"
  local path="$2"
  local mode case_id lower
  local count=0

  while IFS=':' read -r mode case_id; do
    [ -n "$mode" ] && [ -n "$case_id" ] || continue
    lower="$(lowercase "$case_id")"
    case "$category" in
      1to1)
        case "$lower" in direct_*) ;; *) continue ;; esac
        ;;
      group)
        case "$lower" in group_*|announcement_*) ;; *) continue ;; esac
        ;;
    esac
    record_check "$category" "$path" "$mode:$case_id" "notification tap case=$case_id mode=$mode"
    count=$((count + 1))
  done < <(
    "$path" --selection-only 2>/dev/null
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract $category iOS notification tap scenarios"
  fi
}

expand_notification_sound() {
  local category="$1"
  local path="$2"
  local id description lower
  local count=0

  while IFS='|' read -r id description; do
    [ -n "$id" ] || continue
    lower="$(lowercase "$description")"
    case "$category" in
      1to1)
        case "$lower" in *1:1*|*conversation*) ;; *) [ "$id" = "S4" ] || continue ;; esac
        ;;
      group)
        case "$lower" in *group*) ;; *) continue ;; esac
        ;;
    esac
    record_check "$category" "$path" "$id" "$description"
    count=$((count + 1))
  done < <(
    awk '
      /_runScenario\(/ { in_block = 1; id = ""; description = "" }
      in_block && index($0, "id: \047") {
        line = $0
        sub(/^.*id: \047/, "", line)
        sub(/\047.*/, "", line)
        id = line
      }
      in_block && index($0, "description: \047") {
        line = $0
        sub(/^.*description: \047/, "", line)
        sub(/\047.*/, "", line)
        description = line
      }
      in_block && /^[[:space:]]*\)[,;]?[[:space:]]*$/ {
        if (id != "") {
          print id "|" description
        }
        in_block = 0
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract $category notification sound scenarios"
  fi
}

expand_group_multi_party_device_real() {
  local category="$1"
  local path="$2"
  local note="$3"
  local scenario
  local count=0

  while IFS= read -r scenario; do
    [ -n "$scenario" ] || continue
    record_check "$category" "$path" "$scenario" "$note; scenario=$scenario"
    count=$((count + 1))
  done < <(
    dart "$path" --scenario all --list-scenarios 2>/dev/null |
      awk '/^[[:alnum:]_]+$/ { print }'
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not list group multi-party device scenarios"
  fi
}

expand_1to1_device_real() {
  local category="$1"
  local path="$2"
  local note="$3"
  local scenario
  local count=0

  while IFS= read -r scenario; do
    [ -n "$scenario" ] || continue
    record_check "$category" "$path" "$scenario" "$note; scenario=$scenario"
    count=$((count + 1))
  done < <(
    dart "$path" --scenario all --list-scenarios 2>/dev/null |
      awk '/^[[:alnum:]_]+$/ { print }'
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not list 1:1 device-real scenarios"
  fi
}

expand_group_reaction_notification_device() {
  local category="$1"
  local path="$2"
  local note="$3"
  local scenario
  local count=0

  while IFS= read -r scenario; do
    [ -n "$scenario" ] || continue
    record_check "$category" "$path" "$scenario" "$note; scenario=$scenario"
    count=$((count + 1))
  done < <(
    dart "$path" --scenario all --list-scenarios 2>/dev/null |
      awk '/^[[:alnum:]_]+$/ { print }'
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not list Plan 257 group reaction-notification scenarios"
  fi
}

expand_group_media_reliability() {
  local category="$1"
  local path="$2"
  local note="$3"
  local scenario
  local count=0

  while IFS= read -r scenario; do
    [ -n "$scenario" ] || continue
    record_check "$category" "$path" "$scenario" "$note; scenario=$scenario"
    count=$((count + 1))
  done < <(
    dart "$path" --list-scenarios 2>/dev/null |
      awk '/^[[:alnum:]_]+$/ { print }'
  )

  if [ "$count" -ne 2 ]; then
    record_expansion_error "$path" "expected exactly two Plan 269 group-media scenarios, found $count"
  fi
}

expand_record_to_checks() {
  local category="$1"
  local kind="$2"
  local path="$3"
  local note="$4"
  local count

  case "$category" in
    1to1|group|intro|move-feature) ;;
    *) return ;;
  esac

  case "$kind" in
    runner|test) ;;
    *) return ;;
  esac

  case "$path" in
    smoke_test_friends.sh)
      expand_intro_smoke "$category" "$path"
      return
      ;;
    integration_test/scripts/run_routing_smoke_e2e.dart)
      expand_routing_smoke "$category" "$path"
      return
      ;;
    scripts/smoke_test_push_decrypt_simulator.sh)
      expand_push_decrypt "$category" "$path"
      return
      ;;
    scripts/run_ios_notification_tap_ui_smoke.sh)
      expand_ios_notification_tap "$category" "$path"
      return
      ;;
    scripts/run_app_visibility_android_e2e.sh)
      record_check "$category" "$path" "app_visibility_lifecycle" \
        "Plan 371 target-pinned Android lifecycle and durable-reopen scenario"
      return
      ;;
    integration_test/scripts/run_notification_sound_smoke.dart)
      expand_notification_sound "$category" "$path"
      return
      ;;
    integration_test/scripts/run_group_multi_party_device_real.dart)
      expand_group_multi_party_device_real "$category" "$path" "$note"
      return
      ;;
    integration_test/scripts/run_1to1_reaction_notification_device.dart)
      expand_1to1_device_real "$category" "$path" "$note"
      return
      ;;
    integration_test/scripts/run_group_reaction_notification_device.dart)
      expand_group_reaction_notification_device "$category" "$path" "$note"
      return
      ;;
    integration_test/scripts/run_group_media_send_reliability.dart)
      expand_group_media_reliability "$category" "$path" "$note"
      return
      ;;
    integration_test/scripts/run_intro_accept_notification_android.dart)
      expand_1to1_device_real "$category" "$path" "$note"
      return
      ;;
  esac

  if [ "$kind" = "runner" ] && expand_runner_target_tests "$category" "$path" "$note"; then
    return
  fi

  if [ "$kind" = "test" ]; then
    count="$(expand_dart_test_declarations "$category" "$path" "$path" "$note")"
    if [ "$count" -gt 0 ]; then
      return
    fi
    record_expansion_error "$path" "no Dart test declarations found for $category classification"
    return
  fi

  record_check "$category" "$path" "$(basename "$path")" "$note"
}

emit_failures_if_any() {
  local unclassified_count="$1"
  local expansion_error_count="$2"

  if [ "$expansion_error_count" -gt 0 ]; then
    printf 'Expansion errors (%s)\n' "$expansion_error_count" >&2
    awk -F '\t' '{ printf "  - %s - %s\n", $1, $2 }' "$expansion_errors_file" | sort >&2
  fi

  if [ "$unclassified_count" -gt 0 ]; then
    printf 'FAIL: %s candidate(s) are unclassified.\n' "$unclassified_count" >&2
    printf 'Add a classification rule or narrow the discovery pattern.\n' >&2
    return 1
  fi

  if [ "$expansion_error_count" -gt 0 ]; then
    printf 'FAIL: %s classified candidate(s) could not be expanded into checks/scenarios.\n' "$expansion_error_count" >&2
    return 1
  fi

  return 0
}

while IFS= read -r path; do
  [ -n "$path" ] || continue
  classify_path "$path"
done < <(discover_candidates)

record_archived_proof_requirements

while IFS=$'\t' read -r category kind path note; do
  [ -n "$category" ] || continue
  expand_record_to_checks "$category" "$kind" "$path" "$note"
done <"$records_file"

unclassified_count="$(awk -F '\t' '$1 == "unclassified" { count++ } END { print count + 0 }' "$records_file")"
expansion_error_count="$(awk 'END { print NR + 0 }' "$expansion_errors_file")"

case "$output_mode" in
  records-tsv)
    emit_failures_if_any "$unclassified_count" "$expansion_error_count"
    cat "$records_file"
    exit 0
    ;;
  checks-tsv)
    emit_failures_if_any "$unclassified_count" "$expansion_error_count"
    cat "$checks_file"
    exit 0
    ;;
esac

printf 'Reliability simulation discovery\n'
printf 'Root: %s\n' "$ROOT_DIR"

print_category "1to1" "1:1 entrypoints/files"
print_category "group" "Group entrypoints/files"
print_category "intro" "Intro entrypoints/files"
print_category "move-feature" "Move Feature entrypoints/files"
print_category "support" "Support"
print_category "blocked" "Required blocked capabilities (manifest-enforced)"
print_category "inactive" "Inactive future capabilities"
print_category "ignored" "Ignored"
print_category "unclassified" "Unclassified"

printf '\nExpanded runnable checks/scenarios\n'
print_check_category "1to1" "1:1 checks/scenarios"
print_check_category "group" "Group checks/scenarios"
print_check_category "intro" "Intro checks/scenarios"
print_check_category "move-feature" "Move Feature checks/scenarios"

if [ "$expansion_error_count" -gt 0 ]; then
  printf '\nExpansion errors (%s)\n' "$expansion_error_count"
  awk -F '\t' '{ printf "  - %s - %s\n", $1, $2 }' "$expansion_errors_file" | sort
fi

emit_failures_if_any "$unclassified_count" "$expansion_error_count"

printf '\nPASS: all discovered simulator/E2E candidates are classified, capability gaps are inventoried, and executable tests/scenarios expanded.\n'
