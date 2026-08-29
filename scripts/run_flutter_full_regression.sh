#!/usr/bin/env bash

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

android_device=""
ios_simulator=""
run_dir=""
dry_run=false
resume=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_flutter_full_regression.sh \
    --android-device <explicit-physical-android-id> \
    --ios-simulator <explicit-available-ios-simulator-id> \
    [--output <run-directory> | --resume <run-directory>] [--dry-run]

The runner executes the fixed 95-case full-regression inventory. It keeps
per-case status files and logs, so --resume skips only cases already recorded
as PASS and reruns every failed or unfinished case.
EOF
}

while (($# > 0)); do
  case "$1" in
    --android-device)
      android_device="${2:-}"
      shift 2
      ;;
    --ios-simulator)
      ios_simulator="${2:-}"
      shift 2
      ;;
    --output)
      run_dir="${2:-}"
      shift 2
      ;;
    --resume)
      run_dir="${2:-}"
      resume=true
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$dry_run" == true ]]; then
  android_device="${android_device:-ANDROID_DEVICE_ID}"
  ios_simulator="${ios_simulator:-IOS_SIMULATOR_ID}"
else
  if [[ -z "$android_device" || -z "$ios_simulator" ]]; then
    printf 'Both explicit device IDs are required.\n' >&2
    usage >&2
    exit 2
  fi
fi

if [[ -z "$run_dir" ]]; then
  run_dir=".full_regression_logs/$(date -u +%Y%m%d_%H%M%S)"
fi
if [[ "$resume" == true && ! -d "$run_dir" ]]; then
  printf 'Resume directory does not exist: %s\n' "$run_dir" >&2
  exit 2
fi

if [[ "$dry_run" != true ]]; then
  for command_name in adb dart flutter jq xcrun; do
    command -v "$command_name" >/dev/null 2>&1 || {
      printf 'Required command is unavailable: %s\n' "$command_name" >&2
      exit 1
    }
  done
  if [[ "$(adb -s "$android_device" get-state 2>/dev/null || true)" != "device" ]]; then
    printf 'Physical Android target is unavailable: %s\n' "$android_device" >&2
    exit 1
  fi
  if [[ "$(adb -s "$android_device" shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]]; then
    printf 'The primary Android target must be physical, not an emulator.\n' >&2
    exit 1
  fi
  if ! xcrun simctl list devices available -j | \
      jq -e --arg id "$ios_simulator" \
        '[.devices[][] | select(.udid == $id)] | length == 1' >/dev/null; then
    printf 'iOS simulator is unavailable: %s\n' "$ios_simulator" >&2
    exit 1
  fi
  if ! flutter devices --machine | \
      jq -e --arg android "$android_device" --arg ios "$ios_simulator" \
        'any(.[]; .id == $android) and any(.[]; .id == $ios)' >/dev/null; then
    printf 'Flutter did not expose both pinned targets.\n' >&2
    exit 1
  fi
fi

mkdir -p "$run_dir/logs" "$run_dir/status" "$run_dir/aux"
summary_file="$run_dir/summary.tsv"
case_number=0
passed_count=0
failed_count=0

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | \
    sed -E 's/[^a-z0-9._-]+/_/g; s/^_+//; s/_+$//'
}

rebuild_summary() {
  : >"$summary_file"
  local status_path
  for status_path in "$run_dir"/status/*.tsv; do
    [[ -e "$status_path" ]] || continue
    cat "$status_path" >>"$summary_file"
  done
}

run_case() {
  local label="$1"
  shift
  case_number=$((case_number + 1))
  local slug
  slug="$(slugify "$label")"
  local log_file="$run_dir/logs/$(printf '%03d' "$case_number")_${slug}.log"
  local status_file="$run_dir/status/$(printf '%03d' "$case_number").tsv"

  if [[ "$resume" == true && -f "$status_file" ]] && \
      awk -F '\t' '$1 == "PASS" { found = 1 } END { exit !found }' "$status_file"; then
    passed_count=$((passed_count + 1))
    printf 'RESUME PASS %03d/095 %s\n' "$case_number" "$label"
    return 0
  fi

  printf 'RUN %03d/095 %s\n' "$case_number" "$label"
  if [[ "$dry_run" == true ]]; then
    printf '  route:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
  } >"$log_file"
  local started_at
  started_at="$(date +%s)"
  local command_status
  if "$@" >>"$log_file" 2>&1; then
    command_status=0
  else
    command_status=$?
  fi
  local elapsed=$(( $(date +%s) - started_at ))

  if [[ "$command_status" -eq 0 ]]; then
    printf 'PASS\t%s\t%s\t%ss\n' "$label" "$log_file" "$elapsed" >"$status_file"
    passed_count=$((passed_count + 1))
    printf 'PASS %03d/095 %s (%ss)\n' "$case_number" "$label" "$elapsed"
  else
    printf 'FAIL\t%s\t%s\t%ss exit=%s\n' \
      "$label" "$log_file" "$elapsed" "$command_status" >"$status_file"
    failed_count=$((failed_count + 1))
    printf 'FAIL %03d/095 %s (%ss, exit=%s)\n' \
      "$case_number" "$label" "$elapsed" "$command_status" >&2
    tail -n 30 "$log_file" >&2 || true
  fi
  rebuild_summary
  return 0
}

run_sims_capability() {
  local capability="$1"
  printf 'ROUTE sims capability=%s android=%s\n' "$capability" "$android_device"
  local prepare_output
  if ! prepare_output="$(dart tool/sims/sims.dart major \
      --only "$capability" --prepare-builds --format text 2>&1)"; then
    printf '%s\n' "$prepare_output"
    return 1
  fi
  printf '%s\n' "$prepare_output"

  local proof_output
  if ! proof_output="$(dart tool/sims/sims.dart major \
      --only "$capability" --format text 2>&1)"; then
    printf '%s\n' "$proof_output"
    return 1
  fi
  printf '%s\n' "$proof_output"
  grep -Fq $'PASS\t'"$capability"$'\t' <<<"$proof_output"
}

run_android_notification_recovery_completion() {
  printf 'ROUTE Android notification recovery disposable fixture\n'
  dart run \
    integration_test/scripts/run_android_notification_recovery_completion_sims.dart \
    --mode major \
    --scenario notifications.android_recovery_completion
}

run_group_lifecycle_scenario() {
  local scenario="$1"
  printf 'ROUTE group-lifecycle scenario=%s device=%s\n' \
    "$scenario" "$android_device"
  flutter test --no-pub -d "$android_device" --reporter expanded \
    --dart-define="GROUP_SIM_SCENARIO=$scenario" \
    integration_test/group_lifecycle_simulator_harness.dart
}

run_identity_progress_performance() {
  printf 'ROUTE performance target=IDENTITY_PROGRESS device=%s\n' "$android_device"
  flutter test --no-pub -d "$android_device" --reporter expanded \
    --dart-define=PERF_TARGET=IDENTITY_PROGRESS \
    integration_test/performance_harness.dart
}

run_playback_continuity_proof() {
  printf 'ROUTE media-notification-playback device=%s\n' "$android_device"
  ./scripts/run_media_notification_playback_continuity_proof.sh \
    --device "$android_device" \
    --output "$run_dir/aux/media-notification-playback"
}

run_picture_in_picture_matrix() {
  local scenario
  local attempt_id
  attempt_id="$(date -u +%Y%m%dT%H%M%SZ)-${$}"
  for scenario in return close process-recreation completion engine-detach interruption; do
    printf 'ROUTE received-video-pip scenario=%s device=%s\n' \
      "$scenario" "$android_device"
    ./scripts/run_received_video_picture_in_picture_proof.sh \
      --platform android \
      --scenario "$scenario" \
      --device "$android_device" \
      --output "$run_dir/aux/pip-$scenario-$attempt_id" || return $?
  done
}

run_integration_test() {
  local path="$1"
  local filename="${path##*/}"
  case "$filename" in
    android_notification_recovery_completion_proof_test.dart)
      run_android_notification_recovery_completion
      ;;
    app_group_path_simulator_test.dart|conversation_swipe_back_proof_test.dart|group_terminal_send_failed_proof_test.dart)
      printf 'ROUTE iOS-simulator device=%s\n' "$ios_simulator"
      flutter test --no-pub -d "$ios_simulator" --reporter expanded "$path"
      ;;
    group_admin_metadata_convergence_simulator_test.dart)
      run_group_lifecycle_scenario ADMIN_METADATA
      ;;
    group_announcement_reaction_notification_proof_test.dart|group_reaction_notification_sqlcipher_probe_test.dart)
      run_sims_capability groups.reaction_notification_campaign
      ;;
    group_delete_preserves_friends_simulator_test.dart)
      run_group_lifecycle_scenario DELETE_PRESERVES_FRIENDS
      ;;
    group_exit_release_diagnostics_sqlcipher_proof_test.dart)
      printf 'ROUTE Android non-debug profile device=%s\n' "$android_device"
      flutter drive --no-pub --profile -d "$android_device" \
        --driver=test_driver/integration_test.dart --target="$path"
      ;;
    group_invite_accept_spinner_simulator_test.dart)
      run_group_lifecycle_scenario INVITE_ACCEPT_SPINNER
      ;;
    group_muted_notification_proof_test.dart)
      run_sims_capability groups.muted_notification_campaign
      ;;
    group_new_member_media_simulator_proof_test.dart)
      run_group_lifecycle_scenario NEW_MEMBER_MEDIA
      ;;
    group_notification_projection_android_proof_test.dart)
      run_sims_capability groups.notification_projection_durability
      ;;
    group_strict_notification_proof_test.dart)
      run_sims_capability groups.strict_notification_closure
      ;;
    identity_progress_performance_test.dart)
      run_identity_progress_performance
      ;;
    intro_accept_notification_android_proof_test.dart)
      run_sims_capability intro.accept_notification_campaign
      ;;
    media_notification_playback_continuity_test.dart)
      run_playback_continuity_proof
      ;;
    notification_tap_message_visible_proof_test.dart)
      run_sims_capability notifications.android_payload_campaign
      ;;
    one_to_one_reaction_notification_proof_test.dart)
      run_sims_capability notifications.android_typed_reaction_smoke
      ;;
    received_video_picture_in_picture_proof_test.dart)
      run_picture_in_picture_matrix
      ;;
    voice_message_e2e_test.dart)
      run_sims_capability android.voice_recorder_native_smoke
      ;;
    *)
      printf 'ROUTE Android integration device=%s\n' "$android_device"
      flutter test --no-pub -d "$android_device" --reporter expanded "$path"
      ;;
  esac
}

integration_tests=(
  account_migration_group_media_durability_simulator_test.dart
  account_migration_local_transfer_timeout_simulator_test.dart
  account_migration_scale_benchmark_test.dart
  android_notification_recovery_completion_proof_test.dart
  announcement_private_media_platform_proof_test.dart
  app_group_path_simulator_test.dart
  background_reconnect_test.dart
  bidi_text_smoke_test.dart
  cold_start_message_render_simulator_test.dart
  cold_start_sendable_no_user_action_test.dart
  conversation_bridge_test.dart
  conversation_swipe_back_proof_test.dart
  db_raw_key_migration_proof_test.dart
  direct_forwarded_marker_sqlcipher_proof_test.dart
  direct_inbox_custody_outbox_sqlcipher_proof_test.dart
  direct_notification_durability_sqlcipher_proof_test.dart
  direct_private_media_lifecycle_sqlcipher_proof_test.dart
  direct_private_media_platform_protection_proof_test.dart
  direct_reaction_inbox_custody_outbox_sqlcipher_proof_test.dart
  feed_performance_test.dart
  foreground_group_push_drain_test.dart
  group_admin_metadata_convergence_simulator_test.dart
  group_announcement_reaction_notification_proof_test.dart
  group_conversation_polish_proof_test.dart
  group_delete_preserves_friends_simulator_test.dart
  group_exit_intents_sqlcipher_proof_test.dart
  group_exit_release_diagnostics_sqlcipher_proof_test.dart
  group_forwarded_marker_db_proof_test.dart
  group_invite_accept_spinner_simulator_test.dart
  group_invite_reliability_proof_test.dart
  group_media_deletion_journal_sqlcipher_proof_test.dart
  group_message_retry_backoff_db_proof_test.dart
  group_mute_notification_db_proof_test.dart
  group_muted_notification_proof_test.dart
  group_new_member_media_simulator_proof_test.dart
  group_notification_display_outbox_sqlcipher_proof_test.dart
  group_notification_projection_android_proof_test.dart
  group_private_media_lifecycle_db_proof_test.dart
  group_private_media_platform_proof_test.dart
  group_reaction_notification_sqlcipher_probe_test.dart
  group_reaction_reliability_db_proof_test.dart
  group_real_crypto_onboarding_test.dart
  group_recovery_cli_e2e_test.dart
  group_recovery_e2e_test.dart
  group_recovery_gate_serialization_proof_test.dart
  group_rejoin_state_db_proof_test.dart
  group_removal_rotation_keyless_converge_proof_test.dart
  group_removal_rotation_keyless_proof_test.dart
  group_self_removed_marker_sqlcipher_proof_test.dart
  group_strict_notification_proof_test.dart
  group_terminal_send_failed_proof_test.dart
  identity_progress_performance_test.dart
  intro_accept_notification_android_proof_test.dart
  loading_states_smoke_test.dart
  media_library_state_sqlcipher_proof_test.dart
  media_message_journey_e2e_test.dart
  media_notification_playback_continuity_test.dart
  media_stable_id_smoke_test.dart
  migration_database_sqlcipher_capability_test.dart
  notification_open_ui_smoke_test.dart
  notification_tap_message_visible_proof_test.dart
  one_to_one_reaction_notification_proof_test.dart
  outgoing_transport_settlement_sqlcipher_proof_test.dart
  posts_phase1_fake_test.dart
  posts_phase2_fake_test.dart
  posts_phase3_fake_test.dart
  posts_phase4_fake_test.dart
  posts_phase5_fake_test.dart
  protected_photo_thumbnail_secure_window_proof_test.dart
  received_media_native_egress_proof_test.dart
  received_video_picture_in_picture_proof_test.dart
  sender_media_unavailable_fallback_proof_test.dart
  settings_background_choice_smoke_test.dart
  smoke_test.dart
  soak_e2e_test.dart
  transport_e2e_test.dart
  voice_message_e2e_test.dart
  warm_peer_lan_aware_smoke_test.dart
  wifi_relay_fallback_smoke_test.dart
  wifi_transport_test.dart
)

run_case 'flutter version' flutter --version
run_case 'dart version' dart --version
run_case 'flutter pub get' flutter pub get
run_case 'flutter analyze baseline gate' ./scripts/check_flutter_analyze_baseline.sh
run_case 'gate completeness-check' ./scripts/run_test_gates.sh completeness-check
run_case 'gate all' env FLUTTER_DEVICE_ID="$android_device" ./scripts/run_test_gates.sh all
run_case 'gate benchmark' ./scripts/run_test_gates.sh benchmark
run_case 'gate benchmark-sim' env FLUTTER_DEVICE_ID="$android_device" ./scripts/run_test_gates.sh benchmark-sim
run_case 'all core tests' flutter test --no-pub test/core --reporter expanded
run_case 'all feature tests' flutter test --no-pub test/features --reporter expanded
run_case 'all shared tests' flutter test --no-pub test/shared --reporter expanded
run_case 'all security tests' flutter test --no-pub test/security --reporter expanded
run_case 'all unit tests' flutter test --no-pub test/unit --reporter expanded
run_case 'all repo integration tests under test/' flutter test --no-pub test/integration --reporter expanded
run_case 'all performance tests' flutter test --no-pub test/performance --reporter expanded

for integration_test_file in "${integration_tests[@]}"; do
  run_case "integration_test $integration_test_file" \
    run_integration_test "integration_test/$integration_test_file"
done

if [[ "$case_number" -ne 95 ]]; then
  printf 'Inventory error: planned %s cases instead of 95.\n' "$case_number" >&2
  exit 1
fi

if [[ "$dry_run" == true ]]; then
  printf 'DRY RUN COMPLETE: 95/95 routes planned.\n'
  exit 0
fi

rebuild_summary
printf 'FULL REGRESSION: %s passed, %s failed. Summary: %s\n' \
  "$passed_count" "$failed_count" "$summary_file"
if [[ "$failed_count" -ne 0 || "$passed_count" -ne 95 ]]; then
  exit 1
fi
