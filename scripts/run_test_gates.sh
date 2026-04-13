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
)

readonly FEED_TESTS=(
  "test/features/feed/integration/feed_card_flow_test.dart"
  "test/features/feed/integration/expanded_collapsed_card_test.dart"
  "test/features/feed/integration/feed_color_smoke_test.dart"
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
  "test/features/introduction/integration/introduction_multi_node_test.dart"
  "test/features/introduction/integration/introduction_smoke_test.dart"
  "test/features/introduction/presentation/screens/friend_picker_wired_test.dart"
  "test/features/introduction/regression/introduction_regression_test.dart"
)

readonly GROUP_TESTS=(
  "test/features/groups/integration/group_messaging_smoke_test.dart"
  "test/features/groups/integration/group_resume_recovery_test.dart"
  "test/features/groups/integration/group_edge_cases_smoke_test.dart"
  "test/features/groups/integration/invite_round_trip_test.dart"
  "test/features/groups/integration/group_membership_smoke_test.dart"
  "test/features/groups/integration/group_startup_rejoin_smoke_test.dart"
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

readonly NIGHTLY_ONLY_TESTS=(
  "integration_test/smoke_test.dart"
  "integration_test/conversation_bridge_test.dart"
  "integration_test/wifi_transport_test.dart"
  "integration_test/voice_message_e2e_test.dart"
  "integration_test/group_recovery_e2e_test.dart"
  "integration_test/group_recovery_cli_e2e_test.dart"
  "integration_test/multi_relay_failover_test.dart"
  "integration_test/relay_chaos_soak_test.dart"
  "integration_test/soak_e2e_test.dart"
  "integration_test/bidi_text_smoke_test.dart"
)

readonly OPTIONAL_MANUAL_TESTS=(
  "test/features/groups/integration/announcement_happy_path_test.dart"
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
  "integration_test/media_message_journey_e2e_test.dart"
  "integration_test/notification_open_ui_smoke_test.dart"
  "test/performance/conversation_wired_performance_test.dart"
  "test/performance/conversation_wired_subscription_performance_test.dart"
  "integration_test/feed_performance_test.dart"
  "test/performance/feed_wired_init_performance_test.dart"
  "integration_test/identity_progress_performance_test.dart"
  "test/performance/orbit_performance_test.dart"
)

readonly OUT_OF_GATE_TESTS=(
  "test/features/loading_states_smoke_test.dart"
)

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_test_gates.sh baseline
  ./scripts/run_test_gates.sh 1to1
  ./scripts/run_test_gates.sh feed
  ./scripts/run_test_gates.sh intro
  ./scripts/run_test_gates.sh groups
  ./scripts/run_test_gates.sh posts
  ./scripts/run_test_gates.sh transport
  ./scripts/run_test_gates.sh all
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

  if [[ "$path" =~ ^test/core/(bridge|constants|database|device|inbox|local_discovery|media|secure_storage|theme|utils)/.*_test\.dart$ ]]; then
    printf 'core component direct suite'
    return 0
  fi

  if [[ "$path" =~ ^test/shared/widgets/.*_test\.dart$ ]]; then
    printf 'shared widget direct suite'
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

  case "$gate" in
    baseline)
      run_gate_command "Baseline Gate" "${BASELINE_TESTS[@]}"
      ;;
    1to1)
      run_gate_command "1:1 Reliability Gate" "${ONE_TO_ONE_TESTS[@]}"
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
    all)
      run_gate_command "Baseline Gate" "${BASELINE_TESTS[@]}"
      run_gate_command "1:1 Reliability Gate" "${ONE_TO_ONE_TESTS[@]}"
      run_gate_command "Feed / Surface Gate" "${FEED_TESTS[@]}"
      run_gate_command "Intro / Reintroduction Gate" "${INTRO_TESTS[@]}"
      run_gate_command "Group Messaging Gate" "${GROUP_TESTS[@]}"
      run_gate_command "Posts / Privacy Gate" "${POSTS_TESTS[@]}"
      run_transport_gate
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
