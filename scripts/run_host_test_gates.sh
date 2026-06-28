#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scope="host-all"
dry_run=0
continue_on_failure=0
start_at=1
only_selector=""

readonly ONE_TO_ONE_HOST_TESTS=(
  "test/features/conversation/integration/two_user_message_exchange_test.dart"
  "test/features/conversation/integration/offline_inbox_roundtrip_test.dart"
  "test/features/conversation/integration/media_attachment_flow_test.dart"
  "test/features/conversation/integration/media_retry_smoke_test.dart"
  "test/features/conversation/integration/voice_message_exchange_test.dart"
  "test/features/conversation/integration/incomplete_upload_recovery_test.dart"
  "test/features/conversation/integration/send_then_lock_delivery_test.dart"
  "test/features/conversation/integration/stuck_sending_recovery_test.dart"
  "test/features/conversation/integration/quote_reply_thread_test.dart"
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
  "test/features/conversation/application/delete_message_use_case_test.dart"
  "test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart"
  "test/features/conversation/application/handle_delivery_receipt_use_case_test.dart"
  "test/features/conversation/application/send_delivery_receipt_use_case_test.dart"
  "test/features/conversation/application/verify_inbox_custody_use_case_test.dart"
  "test/core/database/helpers/inbox_staging_db_helpers_test.dart"
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
  # 171: one-scan mutual contact add — two-party convergence host lock.
  "test/features/contact_request/integration/contact_request_one_scan_mutual_test.dart"
  "test/features/identity/domain/repositories/identity_repository_impl_test.dart"
)

readonly GO_BRIDGE_CONNECTED_PEER_TEST="go-mknoon/bridge/bridge_test.go"
# Finding 02 Slice 2 (UDM-E/F) closure gate: the held-key grace ring and the
# future-epoch Reject->Ignore split live in go-mknoon/node. The targeted -run
# below is the plan's mandatory regression catcher (Makefile `test: go test
# ./...` is manual + pulls vendored third_party, so it does not satisfy this).
readonly GO_NODE_KEYROTATION_TEST="go-mknoon/node"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_host_test_gates.sh [1to1|host-all|feature-host-all|core-host-all|performance-host|move-feature] [options]

Options:
  --list, --dry-run          Discover host tests and print the command plan only.
  --continue-on-failure      Run the remaining commands after a failure.
  --start-at <N>             Run the planned command list starting at item N.
  --only <N|path>            Run only planned item N or the exact planned path.
  -h, --help                 Show this help.

Scopes:
  1to1                      Focused host-side 1:1 message reliability suites,
                             including the P0 silent-message-loss inventory.
  host-all                   All test/**/*_test.dart except test/performance/**,
                             plus host-side Go bridge reliability contracts.
  feature-host-all           All test/features/**/*_test.dart.
  core-host-all              All test/core/**/*_test.dart.
  performance-host           All test/performance/**/*_test.dart.
  move-feature               Move Account dedicated host tests plus shared
                             lifecycle/push/discovery/startup/P2P move guards.
EOF
}

while (($# > 0)); do
  case "$1" in
    1to1|one-to-one|one_to_one)
      scope="1to1"
      shift
      ;;
    host-all|all)
      scope="host-all"
      shift
      ;;
    feature-host-all|features)
      scope="feature-host-all"
      shift
      ;;
    core-host-all|core)
      scope="core-host-all"
      shift
      ;;
    performance-host|performance)
      scope="performance-host"
      shift
      ;;
    move-feature|move|moves|account-migration|account_migration)
      scope="move-feature"
      shift
      ;;
    --list|--dry-run)
      dry_run=1
      shift
      ;;
    --continue-on-failure)
      continue_on_failure=1
      shift
      ;;
    --start-at)
      start_at="${2:?missing --start-at value}"
      if ! [[ "$start_at" =~ ^[0-9]+$ ]] || [ "$start_at" -lt 1 ]; then
        printf 'Invalid --start-at value: %s\n' "$start_at" >&2
        exit 2
      fi
      shift 2
      ;;
    --only)
      only_selector="${2:?missing --only value}"
      shift 2
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

if ! command -v rg >/dev/null 2>&1; then
  printf 'ripgrep (rg) is required for host test discovery.\n' >&2
  exit 1
fi

plan_file="$(mktemp)"
indexed_plan_file="$(mktemp)"
active_plan_file="$(mktemp)"
failures_file="$(mktemp)"
trap 'rm -f "$plan_file" "$indexed_plan_file" "$active_plan_file" "$failures_file"' EXIT

case "$scope" in
  1to1)
    printf '%s\n' "${ONE_TO_ONE_HOST_TESTS[@]}" | sort -u >"$plan_file"
    ;;
  host-all)
    {
      rg --files test -g '*_test.dart' | awk '$0 !~ /^test\/performance\//' | sort
      printf '%s\n' "$GO_BRIDGE_CONNECTED_PEER_TEST"
      printf '%s\n' "$GO_NODE_KEYROTATION_TEST"
    } >"$plan_file"
    ;;
  feature-host-all)
    rg --files test/features -g '*_test.dart' | sort >"$plan_file"
    ;;
  core-host-all)
    rg --files test/core -g '*_test.dart' | sort >"$plan_file"
    ;;
  performance-host)
    rg --files test/performance -g '*_test.dart' | sort >"$plan_file"
    ;;
  move-feature)
    {
      rg --files test/features/account_migration -g '*_test.dart'
      printf '%s\n' \
        test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart \
        test/features/push/application/push_registration_post_cutover_test.dart \
        test/core/local_discovery/bonsoir_discovery_service_contract_test.dart \
        test/features/identity/application/startup_decision_test.dart \
        test/core/services/p2p_service_impl_test.dart
    } | sort -u >"$plan_file"
    ;;
esac

if [ ! -s "$plan_file" ]; then
  printf 'No host test files matched scope: %s\n' "$scope" >&2
  exit 1
fi

awk '{ print NR "\t" $0 }' "$plan_file" >"$indexed_plan_file"

awk -F '\t' -v start_at="$start_at" -v only_selector="$only_selector" '
  function is_number(value) {
    return value ~ /^[0-9]+$/
  }
  {
    plan_index = $1
    path = $2

    if (only_selector != "") {
      if (is_number(only_selector)) {
        if (plan_index == only_selector) {
          print
        }
      } else if (path == only_selector) {
        print
      }
      next
    }

    if (plan_index >= start_at) {
      print
    }
  }
' "$indexed_plan_file" >"$active_plan_file"

if [ ! -s "$active_plan_file" ]; then
  printf 'No host test commands matched the requested resume filter.\n' >&2
  exit 1
fi

quote_for_display() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

is_go_bridge_connected_peer_test() {
  [ "$1" = "$GO_BRIDGE_CONNECTED_PEER_TEST" ]
}

is_go_node_keyrotation_test() {
  [ "$1" = "$GO_NODE_KEYROTATION_TEST" ]
}

print_command_for_path() {
  local path="$1"
  if is_go_bridge_connected_peer_test "$path"; then
    printf '(cd go-mknoon && go test ./bridge -run TestGroupSendReliable_ReportsConnectedTopicPeerCount -count=1)'
    return
  fi
  if is_go_node_keyrotation_test "$path"; then
    printf "(cd go-mknoon && go test ./node -run 'UDME|EmitGroupDecryptionFailed|GroupTopicValidator|HandleGroupSubscription|GroupKey|DecryptGroupEnvelopePayload|KeyRotation' -count=1)"
    return
  fi
  printf 'flutter test %s' "$(quote_for_display "$path")"
}

run_path() {
  local path="$1"
  if is_go_bridge_connected_peer_test "$path"; then
    (cd go-mknoon && go test ./bridge -run TestGroupSendReliable_ReportsConnectedTopicPeerCount -count=1)
    return
  fi
  if is_go_node_keyrotation_test "$path"; then
    (cd go-mknoon && go test ./node -run 'UDME|EmitGroupDecryptionFailed|GroupTopicValidator|HandleGroupSubscription|GroupKey|DecryptGroupEnvelopePayload|KeyRotation' -count=1)
    return
  fi
  flutter test "$path"
}

printf '\nHost test command plan: %s\n' "$scope"
if [ "$start_at" -ne 1 ]; then
  printf 'Resume filter: starting at planned item #%s\n' "$start_at"
fi
if [ -n "$only_selector" ]; then
  printf 'Resume filter: only %s\n' "$only_selector"
fi

command_count=0
while IFS=$'\t' read -r index path; do
  [ -n "$path" ] || continue
  command_count=$((command_count + 1))
  printf '  %3d. ' "$index"
  print_command_for_path "$path"
  printf '\n'
done <"$active_plan_file"

if [ "$dry_run" -eq 1 ]; then
  printf '\nDry run only. Host test discovery passed and no commands were executed.\n'
  exit 0
fi

printf '\nRunning %s host test command(s)...\n' "$command_count"
while IFS=$'\t' read -r index path; do
  [ -n "$path" ] || continue
  printf '\n==> #%s ' "$index"
  print_command_for_path "$path"
  printf '\n'

  if run_path "$path"; then
    printf 'PASS: #%s %s\n' "$index" "$path"
  else
    status=$?
    printf 'FAIL: #%s %s exited with %s\n' "$index" "$path" "$status" >&2
    printf '%s\t%s\t%s\n' "$index" "$path" "$status" >>"$failures_file"
    if [ "$continue_on_failure" -ne 1 ]; then
      exit "$status"
    fi
  fi
done <"$active_plan_file"

failure_count="$(awk 'END { print NR + 0 }' "$failures_file")"
if [ "$failure_count" -gt 0 ]; then
  printf '\nHost tests failed (%s):\n' "$failure_count" >&2
  awk -F '\t' '{ printf "  - #%s %s exited with %s\n", $1, $2, $3 }' "$failures_file" >&2
  exit 1
fi

printf '\nPASS: host tests completed for scope: %s\n' "$scope"
