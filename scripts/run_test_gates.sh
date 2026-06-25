#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

readonly BASELINE_TESTS=(
  "test/features/identity/presentation/screens/startup_router_recovery_test.dart"
  "test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart"
  "test/features/conversation/integration/offline_inbox_roundtrip_test.dart"
  "integration_test/loading_states_smoke_test.dart"
  "integration_test/posts_phase1_fake_test.dart"
  "test/features/groups/integration/group_messaging_smoke_test.dart"
)

readonly ONE_TO_ONE_TESTS=(
  "test/features/conversation/integration/two_user_message_exchange_test.dart"
  "test/features/conversation/integration/offline_inbox_roundtrip_test.dart"
  "test/features/conversation/integration/media_attachment_flow_test.dart"
  "test/features/conversation/integration/media_retry_smoke_test.dart"
  "test/features/conversation/integration/voice_message_exchange_test.dart"
  "test/features/conversation/integration/incomplete_upload_recovery_test.dart"
  "test/features/conversation/integration/send_then_lock_delivery_test.dart"
  "test/features/conversation/integration/stuck_sending_recovery_test.dart"
  "test/features/conversation/integration/quote_reply_thread_test.dart"
  "test/features/conversation/integration/edit_retry_round_trip_test.dart"
  "test/features/conversation/presentation/navigation/conversation_route_transition_test.dart"
  "test/core/database/migrations/077_message_relay_custody_test.dart"
  "test/core/inbox/inbox_round_trip_test.dart"
  "test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart"
  "test/core/services/incoming_message_router_test.dart"
  "test/core/services/pending_message_retrier_upload_ordering_test.dart"
  "test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart"
  "test/features/conversation/application/chat_message_listener_test.dart"
  "test/features/conversation/application/send_chat_message_use_case_test.dart"
  "test/features/conversation/application/retry_unacked_messages_use_case_test.dart"
  "test/features/conversation/application/recovered_inbox_chat_disposition_test.dart"
  "test/features/conversation/application/delivered_status_minting_sites_test.dart"
  "test/features/conversation/application/retry_failed_messages_delivered_truthfulness_test.dart"
  "test/features/conversation/application/delete_message_use_case_test.dart"
  "test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart"
  "test/features/conversation/application/handle_delivery_receipt_use_case_test.dart"
  "test/features/conversation/application/send_delivery_receipt_use_case_test.dart"
  "test/features/conversation/application/verify_inbox_custody_use_case_test.dart"
  "test/core/database/helpers/inbox_staging_db_helpers_test.dart"
  "test/core/inbox/inbox_staging_repository_impl_test.dart"
  "test/core/services/p2p_service_impl_test.dart"
  "test/features/conversation/application/download_media_use_case_test.dart"
  "test/features/conversation/application/upload_media_use_case_test.dart"
  "test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart"
  "test/core/bridge/go_bridge_client_test.dart"
  "test/core/bridge/p2p_bridge_client_test.dart"
  "test/features/conversation/application/media_download_slow_transfer_simulator_test.dart"
  "test/features/contact_request/application/handle_incoming_message_use_case_test.dart"
  "test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart"
  "test/features/conversation/application/post_restore_stale_key_recovery_test.dart"
  "test/features/contact_request/application/contact_request_listener_test.dart"
  "test/features/identity/domain/repositories/identity_repository_impl_test.dart"
  "test/features/conversation/domain/utils/message_run_grouping_test.dart"
  "test/features/conversation/presentation/widgets/letter_card_test.dart"
  "test/features/conversation/presentation/screens/conversation_screen_test.dart"
  "test/features/conversation/presentation/screens/conversation_wired_test.dart"
  "test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart"
  "test/features/conversation/domain/models/media_rejection_test.dart"
  "test/features/push/application/prepare_notification_open_use_case_test.dart"
  # 159 conversation memoize / coalesce / window-cap / cached-DateTime.
  "test/features/conversation/domain/models/conversation_message_parsed_timestamp_test.dart"
  "test/features/conversation/presentation/screens/conversation_display_items_memo_test.dart"
  "test/features/conversation/presentation/screens/conversation_wired_change_coalesce_test.dart"
  "test/features/conversation/domain/conversation_window_cap_test.dart"
)

readonly FEED_TESTS=(
  # 134 feed redesign — curated surface gate. Old per-card integration tests
  # were deleted; this is the letter-card / pending-reply-inbox suite.
  # Domain + projection + store + repo + migration.
  "test/features/feed/domain/feed_letter_model_test.dart"
  "test/features/feed/domain/group_sender_runs_test.dart"
  "test/features/feed/domain/models/feed_item_test.dart"
  "test/features/feed/domain/models/session_reply_test.dart"
  "test/features/feed/application/feed_pending_projection_test.dart"
  "test/features/feed/application/feed_projection_test.dart"
  "test/features/feed/application/feed_store_test.dart"
  "test/features/feed/application/load_feed_use_case_test.dart"
  "test/features/feed/application/load_contact_feed_snapshot_use_case_test.dart"
  "test/features/feed/data/feed_cleared_repository_test.dart"
  "test/core/database/migrations/092_feed_cleared_threads_test.dart"
  "test/core/theme/feed_tokens_test.dart"
  # Letter cards / bubble widgets.
  "test/features/feed/presentation/widgets/letter_bubble_test.dart"
  "test/features/feed/presentation/widgets/letter_card_group_test.dart"
  "test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart"
  "test/features/feed/presentation/widgets/letter_card_system_test.dart"
  # Screen behaviors: focus/compose, swipe-dismiss, caught-up, reduced-motion.
  "test/features/feed/presentation/screens/feed_focus_test.dart"
  "test/features/feed/presentation/screens/feed_swipe_test.dart"
  "test/features/feed/presentation/screens/feed_caught_up_test.dart"
  "test/features/feed/presentation/screens/feed_reduced_motion_test.dart"
  "test/features/feed/presentation/screens/feed_screen_test.dart"
  "test/features/feed/presentation/screens/feed_wired_test.dart"
  # 134-P8 additive guards: l10n parity, shared-widget survival, contract.
  "test/l10n/feed_strings_parity_test.dart"
  "test/features/feed/presentation/widgets/feed_shared_widget_survival_test.dart"
  "test/features/feed/presentation/screens/feed_contract_preservation_test.dart"
  # 156 QW-3: reduce-motion gating on the default ambient surface.
  "test/features/identity/presentation/widgets/ambient_background_test.dart"
  # 163: AppShellController tab-vs-background change-kind discrimination.
  "test/features/feed/application/app_shell_controller_test.dart"
)

readonly INTRO_TESTS=(
  "test/features/introduction/application/accept_introduction_test.dart"
  "test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart"
  "test/features/introduction/application/handle_incoming_introduction_test.dart"
  "test/features/introduction/application/introduction_listener_test.dart"
  "test/features/introduction/application/mutual_acceptance_test.dart"
  "test/features/introduction/application/pass_introduction_test.dart"
  "test/features/introduction/application/send_introduction_test.dart"
  "test/features/introduction/integration/intro_wiring_smoke_test.dart"
  "test/features/introduction/integration/introduction_b_to_a_c_precondition_test.dart"
  "test/features/introduction/integration/introduction_multi_node_test.dart"
  "test/features/introduction/integration/introduction_smoke_test.dart"
  "test/features/introduction/presentation/screens/friend_picker_wired_test.dart"
  "test/features/introduction/regression/introduction_regression_test.dart"
)

readonly GROUP_TESTS=(
  "test/features/groups/integration/group_messaging_smoke_test.dart"
  "test/features/groups/integration/group_admin_metadata_convergence_test.dart"
  "test/features/groups/integration/group_resume_recovery_test.dart"
  "test/features/groups/integration/group_edge_cases_smoke_test.dart"
  "test/features/groups/integration/invite_round_trip_test.dart"
  "test/features/groups/integration/group_membership_smoke_test.dart"
  "test/features/groups/integration/group_startup_rejoin_smoke_test.dart"
  "test/features/groups/integration/group_key_repair_pull_roundtrip_test.dart"
  "test/features/groups/application/group_key_repair_request_sender_test.dart"
  "test/features/groups/application/group_key_repair_responder_listener_test.dart"
  "test/features/groups/application/group_key_repair_wiring_test.dart"
  "test/features/conversation/domain/utils/message_run_grouping_test.dart"
  "test/features/conversation/presentation/widgets/letter_card_test.dart"
  "test/features/groups/presentation/group_conversation_screen_test.dart"
  "test/features/groups/presentation/group_conversation_wired_test.dart"
  "test/features/groups/presentation/group_list_wired_test.dart"
  "test/features/groups/presentation/group_info_wired_test.dart"
  "test/features/orbit/presentation/screens/orbit_wired_test.dart"
  "test/features/groups/presentation/widgets/pending_group_invite_card_test.dart"
  # 156 QW-4: group avatar cacheWidth/cacheHeight.
  "test/features/groups/presentation/widgets/group_avatar_test.dart"
  # 159 group display-items memo (hoisted to wired State) + window cap.
  "test/features/groups/presentation/group_display_items_memo_test.dart"
  "test/features/groups/presentation/group_window_cap_test.dart"
)

readonly POSTS_TESTS=(
  "integration_test/posts_phase1_fake_test.dart"
  "integration_test/posts_phase2_fake_test.dart"
  "integration_test/posts_phase3_fake_test.dart"
  "integration_test/posts_phase4_fake_test.dart"
  "integration_test/posts_phase5_fake_test.dart"
  "test/features/posts/phase3/post_presence_listener_test.dart"
)

readonly TRANSPORT_TESTS=(
  "integration_test/background_reconnect_test.dart"
  "integration_test/wifi_relay_fallback_smoke_test.dart"
  "integration_test/transport_e2e_test.dart"
  "integration_test/media_stable_id_smoke_test.dart"
)

readonly RUNTIME_TELEMETRY_TESTS=(
  "test/features/push/application/push_preview_telemetry_gate_test.dart"
)

readonly NIGHTLY_ONLY_TESTS=(
  "integration_test/smoke_test.dart"
  "integration_test/conversation_bridge_test.dart"
  "integration_test/wifi_transport_test.dart"
  "integration_test/voice_message_e2e_test.dart"
  "integration_test/group_real_crypto_onboarding_test.dart"
  "integration_test/group_recovery_e2e_test.dart"
  "integration_test/group_recovery_cli_e2e_test.dart"
  "integration_test/soak_e2e_test.dart"
  "integration_test/bidi_text_smoke_test.dart"
)

readonly APP_DEFAULT_RELAY_ADDRESSES="/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

readonly OPTIONAL_MANUAL_TESTS=(
  "test/features/groups/integration/announcement_happy_path_test.dart"
  "test/features/groups/integration/announcement_new_reader_onboarding_test.dart"
  "test/features/groups/integration/group_media_fanout_test.dart"
  "test/features/groups/integration/group_multi_device_convergence_test.dart"
  "test/features/groups/integration/group_new_member_onboarding_test.dart"
  "test/features/conversation/integration/emoji_reaction_exchange_test.dart"
  "test/features/contact_request/integration/contact_request_flow_test.dart"
  "test/features/contact_request/integration/key_exchange_retry_flow_test.dart"
  "test/features/introduction/integration/intro_wiring_smoke_test.dart"
  "test/features/introduction/integration/introduction_multi_node_test.dart"
  "test/features/introduction/integration/introduction_smoke_test.dart"
  "test/features/settings/integration/profile_picture_flow_test.dart"
  "test/features/share/integration/share_to_contact_smoke_test.dart"
  "test/integration/onboarding_golden_path_test.dart"
  "test/integration/notification_deeplink_integration_test.dart"
  "test/integration/rapid_lock_unlock_integration_test.dart"
  "test/integration/relay_down_degradation_integration_test.dart"
  "test/integration/routing_smoke_group_criteria_test.dart"
  "integration_test/cold_start_sendable_no_user_action_test.dart"
  "integration_test/cold_start_message_render_simulator_test.dart"
  "integration_test/account_migration_scale_benchmark_test.dart"
  "integration_test/account_migration_group_media_durability_simulator_test.dart"
  "integration_test/account_migration_local_transfer_timeout_simulator_test.dart"
  "integration_test/foreground_group_push_drain_test.dart"
  # Single dispatched group-lifecycle simulator entrypoint (124 Phase 5). The
  # four former per-suite group simulator files
  # (group_admin_metadata_convergence_simulator_test.dart,
  # group_delete_preserves_friends_simulator_test.dart,
  # group_invite_accept_spinner_simulator_test.dart,
  # group_new_member_media_simulator_proof_test.dart) are now pure libraries
  # dispatched via --dart-define=GROUP_SIM_SCENARIO=<key> against this one file
  # (see the `group-lifecycle-sim` gate below).
  "integration_test/group_lifecycle_simulator_harness.dart"
  "integration_test/media_message_journey_e2e_test.dart"
  "integration_test/migration_database_sqlcipher_capability_test.dart"
  "integration_test/notification_open_ui_smoke_test.dart"
  "integration_test/settings_background_choice_smoke_test.dart"
  # Single dispatched performance entrypoint (124 Phase 5). The six former
  # per-harness perf suites are now run via `performance` / `performance-sim`
  # below with --dart-define=PERF_TARGET=<key> against this one file.
  "integration_test/performance_harness.dart"
)

readonly OUT_OF_GATE_TESTS=(
  "test/features/loading_states_smoke_test.dart"
  "test/features/push/infrastructure/push_token_store_impl_test.dart"
)

# Single dispatched performance entrypoint (124 Phase 5). Each key selects one
# refactored run<X>Perf harness via --dart-define=PERF_TARGET=<key> against
# integration_test/performance_harness.dart (build once, re-run per target).
readonly PERFORMANCE_HARNESS="integration_test/performance_harness.dart"
readonly PERFORMANCE_TARGETS=(
  CONVERSATION
  CONVERSATION_SUB
  FEED_INIT
  FEED
  ORBIT
  IDENTITY_PROGRESS
)

# Single dispatched group-lifecycle simulator entrypoint (124 Phase 5). Each key
# selects one refactored run<X>Sim harness via --dart-define=GROUP_SIM_SCENARIO=<key>
# against integration_test/group_lifecycle_simulator_harness.dart (build once,
# re-run per scenario).
readonly GROUP_LIFECYCLE_SIM_HARNESS="integration_test/group_lifecycle_simulator_harness.dart"
readonly GROUP_LIFECYCLE_SIM_SCENARIOS=(
  ADMIN_METADATA
  DELETE_PRESERVES_FRIENDS
  INVITE_ACCEPT_SPINNER
  NEW_MEMBER_MEDIA
)

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_test_gates.sh baseline
  ./scripts/run_test_gates.sh 1to1 [options]
  ./scripts/run_test_gates.sh feed
  ./scripts/run_test_gates.sh intro
  ./scripts/run_test_gates.sh groups
  ./scripts/run_test_gates.sh posts
  ./scripts/run_test_gates.sh transport
  ./scripts/run_test_gates.sh runtime-telemetry
  ./scripts/run_test_gates.sh move-feature
  ./scripts/run_test_gates.sh group-real-network-nightly
  ./scripts/run_test_gates.sh reliability-sim [all|1to1|group|intro|move-feature] [options]
  ./scripts/run_test_gates.sh host-all [options]
  ./scripts/run_test_gates.sh feature-host-all [options]
  ./scripts/run_test_gates.sh core-host-all [options]
  ./scripts/run_test_gates.sh performance-host [options]
  ./scripts/run_test_gates.sh all
  ./scripts/run_test_gates.sh benchmark
  ./scripts/run_test_gates.sh benchmark-sim
  ./scripts/run_test_gates.sh performance
  ./scripts/run_test_gates.sh performance-sim
  ./scripts/run_test_gates.sh group-lifecycle-sim
  ./scripts/run_test_gates.sh group-lifecycle-sim-host
  ./scripts/run_test_gates.sh completeness-check

Notes:
  - The script is the canonical source of truth for the named gates.
  - Export FLUTTER_DEVICE_ID=<device-id> when you want transport-gate runs to
    force a specific simulator or device.
EOF
}

run_flutter_test() {
  local label="$1"
  shift

  printf 'Running %s\n' "$label"
  flutter test "$@"
}

integration_test_args() {
  if [[ -n "${FLUTTER_DEVICE_ID:-}" ]]; then
    printf '%s\n' "-d" "$FLUTTER_DEVICE_ID"
  fi
}

run_gate_command() {
  local label="$1"
  shift
  local -a host_tests=()
  local -a integration_tests=()
  local path

  for path in "$@"; do
    if [[ "$path" == integration_test/* ]]; then
      integration_tests+=("$path")
    else
      host_tests+=("$path")
    fi
  done

  printf 'Running %s\n' "$label"

  if ((${#host_tests[@]} > 0)); then
    flutter test "${host_tests[@]}"
  fi

  if ((${#integration_tests[@]} > 0)); then
    local -a args=()
    local integration_path

    while IFS= read -r path; do
      args+=("$path")
    done < <(integration_test_args)

    for integration_path in "${integration_tests[@]}"; do
      if ((${#args[@]} > 0)); then
        flutter test "${args[@]}" "$integration_path"
      else
        flutter test "$integration_path"
      fi
    done
  fi
}

run_transport_gate() {
  # Run transport integration suites one file at a time. The combined macOS
  # invocation can fail later files with app-start/log-reader flake even when
  # the same suites pass in isolated runs.
  run_gate_command "Startup / Transport Gate" "${TRANSPORT_TESTS[@]}"
}

run_performance_gate() {
  # Single dispatched entrypoint: re-run the one performance harness per
  # PERF_TARGET key via --dart-define (no per-harness rebuild). When the first
  # argument is "sim", pass FLUTTER_DEVICE_ID through so the run targets a
  # simulator/device; otherwise run on the default (host) device.
  local mode="${1:-host}"
  local -a device_args=()
  if [[ "$mode" == "sim" ]]; then
    while IFS= read -r path; do
      device_args+=("$path")
    done < <(integration_test_args)
  fi

  printf 'Running Performance Gate (%s)\n' "$mode"

  local perf_target
  for perf_target in "${PERFORMANCE_TARGETS[@]}"; do
    printf -- '--- Performance: %s ---\n' "$perf_target"
    if ((${#device_args[@]} > 0)); then
      flutter test "${device_args[@]}" \
        --dart-define="PERF_TARGET=$perf_target" \
        "$PERFORMANCE_HARNESS"
    else
      flutter test \
        --dart-define="PERF_TARGET=$perf_target" \
        "$PERFORMANCE_HARNESS"
    fi
  done
}

run_group_lifecycle_sim_gate() {
  # Single dispatched entrypoint: re-run the one group-lifecycle simulator
  # harness per GROUP_SIM_SCENARIO key via --dart-define (no per-suite rebuild).
  # When the first argument is "sim", pass FLUTTER_DEVICE_ID through so the run
  # targets a simulator/device; otherwise run on the default (host) device.
  local mode="${1:-sim}"
  local -a device_args=()
  if [[ "$mode" == "sim" ]]; then
    while IFS= read -r path; do
      device_args+=("$path")
    done < <(integration_test_args)
  fi

  printf 'Running Group Lifecycle Simulator Gate (%s)\n' "$mode"

  local scenario
  for scenario in "${GROUP_LIFECYCLE_SIM_SCENARIOS[@]}"; do
    printf -- '--- Group sim: %s ---\n' "$scenario"
    if ((${#device_args[@]} > 0)); then
      flutter test "${device_args[@]}" \
        --dart-define="GROUP_SIM_SCENARIO=$scenario" \
        "$GROUP_LIFECYCLE_SIM_HARNESS"
    else
      flutter test \
        --dart-define="GROUP_SIM_SCENARIO=$scenario" \
        "$GROUP_LIFECYCLE_SIM_HARNESS"
    fi
  done
}

run_group_real_network_nightly_gate() {
  if [[ -z "${FLUTTER_DEVICE_ID:-}" ]]; then
    printf 'FLUTTER_DEVICE_ID is required for Group Real-Network Nightly Gate.\n' >&2
    return 1
  fi

  local relay_addresses="${MKNOON_RELAY_ADDRESSES:-$APP_DEFAULT_RELAY_ADDRESSES}"

  printf 'Running Group Real-Network Nightly Gate\n'
  printf 'Using MKNOON_RELAY_ADDRESSES=%s\n' "$relay_addresses"

  # The deleted multi_relay_failover_test.dart wrapper re-ran transport_e2e_test
  # (and group_recovery_cli_e2e_test when a CLI peer fixture was present) only
  # when >=2 relays were configured. The multi-relay gate now lives inside the
  # source tests via --dart-define=MKNOON_REQUIRE_MULTI_RELAY=true, so run the
  # source files directly with the same defines for identical coverage.
  flutter test \
    -d "$FLUTTER_DEVICE_ID" \
    --dart-define=MKNOON_REQUIRE_MULTI_RELAY=true \
    --dart-define=MKNOON_RELAY_ADDRESSES="$relay_addresses" \
    integration_test/transport_e2e_test.dart

  # group_recovery_cli_e2e_test only had effect under the wrapper when a CLI peer
  # fixture was configured; mirror that conditional so behavior is preserved.
  if [[ -n "${CLI_PEER_FIXTURE:-}" ]]; then
    flutter test \
      -d "$FLUTTER_DEVICE_ID" \
      --dart-define=MKNOON_REQUIRE_MULTI_RELAY=true \
      --dart-define=MKNOON_RELAY_ADDRESSES="$relay_addresses" \
      --dart-define=CLI_PEER_FIXTURE="$CLI_PEER_FIXTURE" \
      integration_test/group_recovery_cli_e2e_test.dart
  else
    printf 'Skipping group_recovery_cli_e2e_test: CLI_PEER_FIXTURE not set.\n'
  fi
}

array_contains() {
  local needle="$1"
  shift

  local entry
  for entry in "$@"; do
    if [[ "$entry" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

classify_path() {
  local path="$1"

  if array_contains "$path" "${BASELINE_TESTS[@]}"; then
    printf 'baseline gate'
    return 0
  fi

  if array_contains "$path" "${ONE_TO_ONE_TESTS[@]}"; then
    printf '1:1 reliability gate'
    return 0
  fi

  if array_contains "$path" "${FEED_TESTS[@]}"; then
    printf 'feed / surface gate'
    return 0
  fi

  if array_contains "$path" "${INTRO_TESTS[@]}"; then
    printf 'intro / reintroduction gate'
    return 0
  fi

  if array_contains "$path" "${GROUP_TESTS[@]}"; then
    printf 'group messaging gate'
    return 0
  fi

  if array_contains "$path" "${POSTS_TESTS[@]}"; then
    printf 'posts / privacy gate'
    return 0
  fi

  if array_contains "$path" "${TRANSPORT_TESTS[@]}"; then
    printf 'startup / transport gate'
    return 0
  fi

  if array_contains "$path" "${RUNTIME_TELEMETRY_TESTS[@]}"; then
    printf 'runtime telemetry gate'
    return 0
  fi

  if array_contains "$path" "${NIGHTLY_ONLY_TESTS[@]}"; then
    printf 'nightly / release pool'
    return 0
  fi

  if array_contains "$path" "${OPTIONAL_MANUAL_TESTS[@]}"; then
    printf 'optional / manual direct suite'
    return 0
  fi

  if array_contains "$path" "${OUT_OF_GATE_TESTS[@]}"; then
    printf 'explicit out-of-gate'
    return 0
  fi

  if [[ "$path" =~ ^test/core/services/.*_test\.dart$ ]]; then
    printf 'core services direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/core/lifecycle/.*_test\.dart$ ]]; then
    printf 'core lifecycle direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/core/resilience/.*_test\.dart$ ]]; then
    printf 'core resilience direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/core/notifications/.*_test\.dart$ ]]; then
    printf 'core notifications direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/core/debug/.*_test\.dart$ ]]; then
    printf 'core debug direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/core/(bridge|constants|database|device|inbox|local_discovery|media|permissions|secure_storage|theme|utils)/.*_test\.dart$ ]]; then
    printf 'core component direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/l10n/.*_test\.dart$ ]]; then
    printf 'localization integrity direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/shared/fakes/.*_test\.dart$ ]]; then
    printf 'shared fake harness direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/security/.*_test\.dart$ ]]; then
    printf 'security invariant direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/shared/widgets/.*_test\.dart$ ]]; then
    printf 'shared widget direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/performance/.*_test\.dart$ ]]; then
    printf 'benchmark / performance suite'
    return 0
  fi

  if [[ "$path" =~ ^integration_test/.*_performance_test\.dart$ ]]; then
    printf 'benchmark / performance suite'
    return 0
  fi

  if [[ "$path" =~ ^test/unit/.*_test\.dart$ ]]; then
    printf 'unit direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/features/[^/]+/integration/.*_test\.dart$ ]]; then
    printf 'feature integration direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/integration/.*_test\.dart$ ]]; then
    printf 'repo integration direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/features/[^/]+/(application|domain|presentation|improvement|phase[1-5]|regression)/.*_test\.dart$ ]]; then
    printf 'feature-local direct suite'
    return 0
  fi

  # G-D: manual device/sim proofs under integration_test/ are NOT host-gated
  # (they require a device or simulator and carry @Tags(['device'])); they run
  # via `flutter test integration_test/<proof>` on the device matrix. Recognize
  # them as an explicit manual category so the completeness gate stops reporting
  # them as un-classified (they are intentionally outside the automated host
  # sweep, not silently dropped).
  if [[ "$path" =~ ^integration_test/.*_proof_test\.dart$ ]]; then
    printf 'manual device-proof suite'
    return 0
  fi

  # G-D: group lifecycle simulator stubs under integration_test/ are pure
  # libraries dispatched via --dart-define=GROUP_SIM_SCENARIO=<key>, not the
  # default test runner.
  if [[ "$path" =~ ^integration_test/.*_simulator_test\.dart$ ]]; then
    printf 'group lifecycle simulator (GROUP_SIM_SCENARIO dispatch)'
    return 0
  fi

  # G-D: feature-root and core-root tests (placed directly under
  # test/features/<feature>/ or test/core/, not in a recognized subdir) are
  # swept by the host-all / feature-host-all gates. Classify them so the
  # completeness gate accounts for every host-run file. Placed last so the more
  # specific subdir patterns above always win.
  if [[ "$path" =~ ^test/features/[^/]+/[^/]+_test\.dart$ ]]; then
    printf 'feature-root direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/core/[^/]+_test\.dart$ ]]; then
    printf 'core-root direct suite'
    return 0
  fi

  return 1
}

run_completeness_check() {
  local -a all_tests=()
  local -a unmatched=()
  local path
  local matched_count=0

  while IFS= read -r path; do
    all_tests+=("$path")
  done < <(rg --files test integration_test -g '*_test.dart' | sort)

  for path in "${all_tests[@]}"; do
    if classify_path "$path" >/dev/null; then
      matched_count=$((matched_count + 1))
    else
      unmatched+=("$path")
    fi
  done

  printf 'Completeness check: %d/%d test files classified.\n' \
    "$matched_count" "${#all_tests[@]}"

  if ((${#unmatched[@]} > 0)); then
    printf 'Unmatched test files:\n'
    printf '  %s\n' "${unmatched[@]}"
    return 1
  fi

  printf 'Completeness check PASS.\n'
}

main() {
  local gate="${1:-}"
  local -a gate_args=("${@:2}")

  case "$gate" in
    baseline)
      run_gate_command "Baseline Gate" "${BASELINE_TESTS[@]}"
      ;;
    1to1)
      if ((${#gate_args[@]} == 0)); then
        run_gate_command "1:1 Reliability Gate" "${ONE_TO_ONE_TESTS[@]}"
      else
        ./scripts/run_host_test_gates.sh 1to1 "${gate_args[@]}"
      fi
      ;;
    feed)
      run_gate_command "Feed / Surface Gate" "${FEED_TESTS[@]}"
      ;;
    intro)
      run_gate_command "Intro / Reintroduction Gate" "${INTRO_TESTS[@]}"
      ;;
    groups)
      run_gate_command "Group Messaging Gate" "${GROUP_TESTS[@]}"
      ;;
    posts)
      run_gate_command "Posts / Privacy Gate" "${POSTS_TESTS[@]}"
      ;;
    transport)
      run_transport_gate
      ;;
    runtime-telemetry)
      run_gate_command "Runtime Telemetry Gate" "${RUNTIME_TELEMETRY_TESTS[@]}"
      ;;
    group-real-network-nightly)
      run_group_real_network_nightly_gate
      ;;
    reliability-sim)
      if ((${#gate_args[@]} == 0)); then
        gate_args=(all)
      fi
      ./scripts/run_reliability_simulations.sh "${gate_args[@]}"
      ;;
    move-feature|host-all|feature-host-all|core-host-all|performance-host)
      if ((${#gate_args[@]} == 0)); then
        ./scripts/run_host_test_gates.sh "$gate"
      else
        ./scripts/run_host_test_gates.sh "$gate" "${gate_args[@]}"
      fi
      ;;
    all)
      run_gate_command "Baseline Gate" "${BASELINE_TESTS[@]}"
      run_gate_command "1:1 Reliability Gate" "${ONE_TO_ONE_TESTS[@]}"
      run_gate_command "Feed / Surface Gate" "${FEED_TESTS[@]}"
      run_gate_command "Intro / Reintroduction Gate" "${INTRO_TESTS[@]}"
      run_gate_command "Group Messaging Gate" "${GROUP_TESTS[@]}"
      run_gate_command "Posts / Privacy Gate" "${POSTS_TESTS[@]}"
      run_transport_gate
      run_gate_command "Runtime Telemetry Gate" "${RUNTIME_TELEMETRY_TESTS[@]}"
      ;;
    benchmark)
      echo "=== Benchmark Tests ==="
      flutter test test/performance/ --reporter expanded
      ;;
    benchmark-sim)
      echo "=== Simulator Benchmark Tests ==="
      local -a sim_args=()
      while IFS= read -r path; do
        sim_args+=("$path")
      done < <(integration_test_args)
      # Single dispatched entrypoint: build the app once and re-run per
      # BENCHMARK key via --dart-define (no per-harness rebuild).
      local -a benchmark_keys=(
        ROUTING_PATHS
        BACKGROUND_RESUME
        RELAY_RECOVERY
        TIME_TO_ONLINE
        NOTIFICATION_TAP
        GROUP_PUBLISH
        MEDIA
        ONE_TO_ONE_SEND
        TIMEOUT_ACCURACY
        ENCRYPTION
        NODE_STARTUP
        CONNECTION_REUSE
        INBOX
        ACK
        BRIDGE_CROSSING
        EVENT_QUEUE
        VOICE
      )
      local benchmark_key
      for benchmark_key in "${benchmark_keys[@]}"; do
        echo "--- Benchmark: $benchmark_key ---"
        if ((${#sim_args[@]} > 0)); then
          flutter test "${sim_args[@]}" \
            --dart-define="BENCHMARK=$benchmark_key" \
            integration_test/benchmark_harness.dart
        else
          flutter test \
            --dart-define="BENCHMARK=$benchmark_key" \
            integration_test/benchmark_harness.dart
        fi
      done
      ;;
    performance)
      run_performance_gate host
      ;;
    performance-sim)
      run_performance_gate sim
      ;;
    group-lifecycle-sim)
      run_group_lifecycle_sim_gate sim
      ;;
    group-lifecycle-sim-host)
      run_group_lifecycle_sim_gate host
      ;;
    completeness-check)
      run_completeness_check
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
