#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scope="host-all"
dry_run=0
continue_on_failure=0
start_at=1
only_selector=""
batch_flutter=0
dart_only=0
flutter_concurrency=""
flutter_reporter=""

readonly ONE_TO_ONE_HOST_TESTS=(
  "test/features/conversation/integration/two_user_message_exchange_test.dart"
  "test/features/conversation/integration/offline_inbox_roundtrip_test.dart"
  "test/features/conversation/integration/media_attachment_flow_test.dart"
  "test/features/conversation/integration/media_retry_smoke_test.dart"
  "test/features/conversation/integration/media_eviction_redownload_test.dart"
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
  "test/features/conversation/application/outgoing_live_deadline_test.dart"
  "test/features/conversation/application/send_chat_message_use_case_test.dart"
  # Plan 256: composed direct-reaction notification + unread-message boundary.
  "test/features/conversation/integration/reaction_notification_pipeline_test.dart"
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
  # 295 DTR-17: exact P2P facade/component ownership and callback boundaries.
  "test/core/services/p2p_service_impl_composition_contract_test.dart"
  "test/features/conversation/application/download_media_use_case_test.dart"
  "test/features/conversation/application/upload_media_use_case_test.dart"
  "test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart"
  "test/core/bridge/go_bridge_client_test.dart"
  "test/core/bridge/p2p_bridge_client_test.dart"
  "test/features/conversation/application/media_download_slow_transfer_simulator_test.dart"
  "test/features/contact_request/application/handle_incoming_message_use_case_test.dart"
  "test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart"
  # 217 CV-14 wake-token: send leg (A01) + the bridge attach/omit lock (A06).
  "test/features/contact_request/application/send_contact_request_use_case_test.dart"
  "test/core/bridge/p2p_bridge_client_wake_attach_test.dart"
  "test/features/conversation/application/post_restore_stale_key_recovery_test.dart"
  "test/features/contact_request/application/contact_request_listener_test.dart"
  # 171: one-scan mutual contact add — two-party convergence host lock.
  "test/features/contact_request/integration/contact_request_one_scan_mutual_test.dart"
  "test/features/identity/domain/repositories/identity_repository_impl_test.dart"
  # 189: degraded-relay drain starvation + restart-loop locks (drain on every
  # health-check tick, truthful phase=recovered, recovery backoff).
  "test/core/services/p2p_service_impl_health_drain_test.dart"
  # 216: cold-start connecting→online inbox-proof kick — send-proof store mirrors
  # the send→inbox readiness kick (inboxCapabilityReady flips off the store, not
  # the first 30s health-check tick). Auto-globs into core-host-all; pinned here
  # for the 1to1 host gate beside the 189 drain lock.
  "test/core/services/p2p_service_impl_inbox_proof_kick_test.dart"
  # 191: iOS foreground-push forwarding hardening — Dart half (FirebaseReadiness
  # retry latch + PushListenerArmer PUSH_LISTENERS_ARMED / readiness-driven third
  # arm point). Auto-glob into feature-host-all; pinned here for the 1to1 host gate.
  "test/features/push/application/firebase_readiness_test.dart"
  "test/features/push/application/push_listener_armer_test.dart"
  # 231: 1:1 received media core actions — bubble/viewer identity + Info/Reply
  # (screen), current-row egress controller, exact-callsite transport boundary,
  # and the wired viewer-delete/egress seams (conversation_wired_test).
  "test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart"
  "test/features/conversation/application/received_media_action_controller_test.dart"
  "test/features/conversation/application/received_media_action_transport_boundary_test.dart"
  "test/features/conversation/presentation/screens/conversation_wired_test.dart"
  # 294 DTR-15: shared compositional conversation-controller ownership,
  # lane-neutral mechanics, lifecycle, and exact facade/gate contracts.
  "test/features/conversation/presentation/controllers/conversation_controller_composition_contract_test.dart"
  "test/features/conversation/presentation/controllers/conversation_composer_controller_test.dart"
  "test/features/conversation/presentation/controllers/conversation_upload_activity_controller_test.dart"
  "test/features/conversation/presentation/controllers/conversation_voice_capture_controller_test.dart"
  "test/features/conversation/presentation/controllers/conversation_reaction_projection_controller_test.dart"
  # 232: direct received-media forwarding draft, picker launch, retry/provenance,
  # migration, and frozen Dart transport boundary.
  "test/features/conversation/application/build_received_media_forward_test.dart"
  "test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart"
  "test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart"
  "test/features/conversation/application/direct_media_forward_transport_boundary_test.dart"
  "test/core/database/migrations/097_direct_message_forwarded_test.dart"
  "test/features/share/application/share_batch_delivery_coordinator_test.dart"
  "test/features/share/presentation/share_target_picker_wired_test.dart"
  "test/features/share/integration/external_share_media_ux_test.dart"
  "test/features/share/integration/outgoing_share_media_owner_viewer_test.dart"
  "test/features/share/integration/direct_received_media_to_group_preservation_test.dart"
  "test/features/conversation/domain/models/message_payload_test.dart"
  # 234 Session 01: typed encrypted-inner policy plus direct-parent v100
  # durability. Dedicated host proofs are pinned in both 1:1 inventories.
  "test/features/conversation/domain/models/private_media_policy_test.dart"
  "test/features/conversation/domain/models/conversation_message_test.dart"
  "test/core/database/helpers/messages_db_helpers_test.dart"
  "test/core/database/migrations/100_direct_private_media_lifecycle_test.dart"
  "test/core/database/integration/full_migration_chain_test.dart"
  # 342: immutable direct-text relay-inbox custody schema, DB helpers, drain,
  # and lifecycle ownership are pinned in the curated 1:1 lane.
  "test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart"
  "test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart"
  "test/core/services/pending_message_retrier_direct_inbox_custody_test.dart"
  "test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart"
  # 343: immutable direct-reaction relay-inbox custody replays exact authored
  # event envelopes on the existing direct-custody lifecycle cadence.
  "test/core/database/migrations/109_direct_reaction_inbox_custody_outbox_test.dart"
  # 345: manifest-bound preparation authority for fresh ordinary direct media.
  "test/core/database/migrations/110_direct_media_custody_intent_test.dart"
  "test/core/database/migrations/111_direct_media_blob_custody_test.dart"
  "test/features/conversation/integration/android_direct_media_blob_custody_campaign_test.dart"
  "test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart"
  "test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart"
  "test/features/conversation/domain/repositories/reaction_repository_impl_test.dart"
  "test/features/conversation/application/send_reaction_use_case_test.dart"
  "test/features/conversation/application/remove_reaction_use_case_test.dart"
  # 234 Session 03: direct private-media SQL/CAS, reveal lease, monotonic
  # expiry scheduler, restart/cleanup convergence, and resume ordering.
  "test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart"
  "test/features/conversation/application/consume_private_media_use_case_test.dart"
  "test/features/conversation/application/private_media_expiry_scheduler_test.dart"
  "test/features/conversation/integration/private_media_restart_replay_test.dart"
  "test/features/conversation/application/private_media_cleanup_race_test.dart"
  "test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart"
  # 234 Session 04: central current-parent direct-media capability matrix and
  # stale/direct-call action boundary (egress, Forward, library, download, PiP).
  "test/features/conversation/application/private_media_action_eligibility_test.dart"
  "test/features/conversation/application/direct_private_media_boundary_test.dart"
  # 234 Session 05: direct private viewer/lifecycle protection host contracts.
  "test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart"
  "test/core/media/private_media_protection_coordinator_test.dart"
  # 234 Session 06: strict fail-closed evaluator for the fully automated,
  # availability-bounded physical-Android + emulator device-local artifact.
  "test/integration/direct_private_media_device_local_journey_criteria_test.dart"
  # 249 Session 01: hidden direct-library batch-forward source qualification,
  # canonical order, independent captions/tokens, and atomic revalidation.
  "test/features/conversation/application/build_direct_media_library_batch_forward_test.dart"
  # 249 Session 02: direct-only source/contact delivery matrix, strict ordinary
  # transport boundary, dedicated picker state, and Shared Media reconciliation.
  "test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart"
  "test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart"
  "test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart"
  "test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart"
  # 247 Session 03: announcement Message sender opens a blank real 1:1 route
  # and opening/cancelling remains delivery-free.
  "test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart"
  "test/features/conversation/presentation/widgets/letter_card_test.dart"
  "test/features/conversation/presentation/screens/conversation_screen_test.dart"
  # 233: 1:1 shared media library — strict direct-scoped paging/filters/
  # cursors, cross-message typed viewer + lazy continuation, scoped-page
  # bookmarks, batch save/share with the ten-item ceiling, confirmed
  # whole-message batch delete, Go to Message, and the frozen local/
  # transport-free boundary contract.
  "test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart"
  "test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart"
  "test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart"
  "test/features/conversation/application/direct_media_library_batch_actions_test.dart"
  "test/features/conversation/application/direct_media_library_batch_delete_test.dart"
  "test/features/conversation/application/direct_media_library_boundary_test.dart"
  # 262: headline sender pending-open application contract.
  "test/features/conversation/application/direct_private_media_sender_pending_open_test.dart"
  "test/features/conversation/application/retry_failed_messages_private_manual_retry_test.dart"
  "test/features/conversation/integration/private_cached_envelope_retry_delete_race_test.dart"
  "test/core/database/helpers/outgoing_direct_private_writer_guard_test.dart"
  "test/features/conversation/integration/private_media_committed_pending_cleanup_recovery_test.dart"
  "test/features/conversation/presentation/screens/conversation_wired_sender_finalize_canonical_path_test.dart"
  # 336: atomic ordinary outgoing attempt/transport settlement policy and
  # bounded application-writer census.
  "test/core/database/helpers/outgoing_transport_settlement_test.dart"
  "test/features/conversation/application/outgoing_transport_settlement_writers_test.dart"
)

readonly GO_BRIDGE_CONNECTED_PEER_TEST="go-mknoon/bridge/bridge_test.go"
# Finding 02 Slice 2 (UDM-E/F) closure gate: the held-key grace ring and the
# future-epoch Reject->Ignore split live in go-mknoon/node. The targeted -run
# below is the plan's mandatory regression catcher (Makefile `test: go test
# ./...` is manual + pulls vendored third_party, so it does not satisfy this).
readonly GO_NODE_KEYROTATION_TEST="go-mknoon/node"
# 190 (Android netlink SELinux addr-visibility): the go-multiaddr/anet fork
# suite runs in NO Flutter gate (run_test_gates.sh has zero Go). Pin it into
# host-all as a synthetic path, WITH the GOTOOLCHAIN pin the two Go targets
# above lack (Go 1.26.x quic-go panic — see go.mod). Fork-module unit tests
# (third_party/go-multiaddr/net) are a separate module, run via their own gate.
readonly GO_NODE_ADDR_VISIBILITY_TEST="go-mknoon/node/addr_visibility_denial_test.go"
# 219 (feature-flag decode-seam merge guard): B01/B02 pin the new
# MergeFeatureFlagsOverDefaults helper (partial map => omitted key keeps the Go
# default, never zero-value false). -run 'FeatureFlag' sweeps that superset plus
# the existing TestFeatureFlags_* fallback pins for free. GOTOOLCHAIN-pinned like
# the addr-visibility target above (Go 1.26.x quic-go panic — see go.mod).
readonly GO_NODE_FEATUREFLAGS_TEST="go-mknoon/node/feature_flags_merge_test.go"
readonly GO_NODE_FEATUREFLAGS_RUN='FeatureFlag'
# 219 B04 (the ONLY behavioural test on the real bridge.go decode seam): drives
# node:start with a PARTIAL featureFlags JSON and asserts an omitted graduated
# flag stays at its Go default. Separate package (./bridge) AND separate -run
# pattern from the ./node target above, so it registers as its OWN synthetic
# path (NOT folded into the ./node FeatureFlag branch). GOTOOLCHAIN-pinned.
readonly GO_BRIDGE_FEATUREFLAGS_TEST="go-mknoon/bridge/feature_flags_partial_map_test.go"
readonly GO_BRIDGE_FEATUREFLAGS_RUN='PartialFeatureFlags'
# 217 A11/A12 (CV-14 wake-token store frame): the send-side attach + NET-REL-07
# byte-identity locks + the new byte-equal round-trip. -run 'WakeToken' sweeps
# TestInboxStore_WakeTokenRoundTripsByteEqual, ...WithWakeToken_AttachesTokenToStoreFrame,
# and ...OmitsWakeTokenWhenAbsent. GOTOOLCHAIN-pinned like the targets above
# (Go 1.26.x quic-go panic — see go.mod).
readonly GO_NODE_WAKETOKEN_TEST="go-mknoon/node/inbox_wake_token_test.go"
readonly GO_NODE_WAKETOKEN_RUN='WakeToken'
# 220/337 (Go libp2p cleanup + authenticated committed ACK contracts):
# host-only source-shape, lifecycle/fan-out, semantic sender ACK parsing, and
# authenticated receiver identity/deferred-ordering proofs. GOTOOLCHAIN-pinned
# for the documented Go 1.26.x quic-go incompatibility.
readonly GO_NODE_LIBP2P_REFACTOR_TEST="go-mknoon/node/libp2p_refactor_contract_test.go"
readonly GO_NODE_LIBP2P_REFACTOR_RUN='TestGoLibp2pProductionShapeBudget|TestStartDoesNotHoldNodeLockAcrossHostCreation|TestStartRejectsConcurrentStartWhileHostCreationInProgress|TestStartHostCreationFailureRollsBackPublishedState|TestStartHostCreationPanicClearsInProgressAndAllowsRetry|TestStopDuringStartInProgressIsExplicitAndNonMutating|TestReconnectRelaysDuringStartInProgressFailsFast|TestGroupDialKnownMembersRunsBoundedParallel|TestDiscoverAndConnectGroupPeersRunsBoundedParallel|TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency|TestRelaySelectorFanOutRunsDistinctRelaysInParallel|TestRelaySelectorFanOutAllFailPreservesAggregateError|TestSendMessageWithTransport_AckFrameValidation|TestHandleIncomingMessage_BindsAuthenticatedRemotePeerAndClassifiedTransport|TestHandleIncomingMessage_DeferredDirectAck_WritesAckAfterConfirm|TestHandleIncomingMessage_DeferredDirectAck_FalseConfirmDoesNotAck|TestHandleIncomingMessage_DeferredDirectAck_TimesOutWithoutConfirm|TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce|TestShouldDeferDirectAck_ReactionAndDeletion|TestR3Deadline_|TestSendMessage_ReturnsUnackedWhenReceiverDoesNotConfirmDirectChat|TestTC34104BootstrapPublishSkipsOnlyPeerRefreshAndStillPublishes|TestTC34104BootstrapPublishPreservesAuthorizationBeforeCrypto'
readonly GO_BRIDGE_ENTRYPOINT_REFACTOR_TEST="go-mknoon/bridge/bridge_entrypoint_contract_test.go"
readonly GO_BRIDGE_ENTRYPOINT_REFACTOR_RUN='TestBridgeExportedHandlersUseSharedEntrypoint|TestBridgeGroupPublishContractsPreservedAfterHelperExtraction|TestTC34103GroupPublishMapsPeerRefreshControlOutsideMessageOpts'
# Exact Android build-boundary proof. Keep it as one synthetic core-host item:
# the auto-discovered Dart contract stays fast, while this leg performs the
# profile/release manifest preparation only once per core-host-all invocation.
readonly ANDROID_RENDERER_MANIFEST_CONTRACT="scripts/check_android_renderer_manifest_contract.sh"
readonly ANDROID_DROPPED_PUSH_MANIFEST_CONTRACT="scripts/check_dropped_push_recovery_manifest_contract.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_host_test_gates.sh [1to1|host-all|feature-host-all|core-host-all|performance-host|move-feature] [options]

Options:
  --list, --dry-run          Discover host tests and print the command plan only.
  --batch-flutter            Run the selected Dart paths in one exact-path
                             Flutter invocation; Go legs remain separate.
  --dart-only                Omit non-Dart plan items. For host-all this removes
                             the eight Go tails so a composed gate can run its
                             full Go lane exactly once.
  --concurrency <N>          Flutter batch process count from 1 through 64
                             (default: 1).
                             Requires --batch-flutter.
  --reporter <NAME>          Human-readable Flutter batch reporter: compact,
                             expanded, or failures-only.
                             Requires --batch-flutter.
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
  core-host-all              All test/core/**/*_test.dart and
                             test/unit/**/*_test.dart, plus the Android
                             renderer merged-manifest contract.
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
    --batch-flutter)
      batch_flutter=1
      shift
      ;;
    --dart-only)
      dart_only=1
      shift
      ;;
    --concurrency)
      if (($# < 2)); then
        printf 'Missing value for --concurrency.\n' >&2
        exit 2
      fi
      flutter_concurrency="$2"
      if ! [[ "$flutter_concurrency" =~ ^([1-9]|[1-5][0-9]|6[0-4])$ ]]; then
        printf 'Invalid --concurrency value: %s\n' "$flutter_concurrency" >&2
        exit 2
      fi
      shift 2
      ;;
    --reporter)
      if (($# < 2)); then
        printf 'Missing value for --reporter.\n' >&2
        exit 2
      fi
      flutter_reporter="$2"
      case "$flutter_reporter" in
        compact|expanded|failures-only)
          ;;
        *)
          printf 'Invalid --reporter value: %s\n' "$flutter_reporter" >&2
          exit 2
          ;;
      esac
      shift 2
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

if [ "$dart_only" -eq 1 ]; then
  case "$scope" in
    host-all|feature-host-all|core-host-all|performance-host|move-feature)
      ;;
    *)
      printf 'Dart-only mode is not supported for host scope: %s\n' "$scope" >&2
      exit 2
      ;;
  esac
fi

if [ "$batch_flutter" -ne 1 ] && {
  [ -n "$flutter_concurrency" ] || [ -n "$flutter_reporter" ];
}; then
  printf '%s\n' \
    'Using --concurrency or --reporter requires --batch-flutter.' >&2
  exit 2
fi

if [ "$batch_flutter" -eq 1 ]; then
  case "$scope" in
    host-all|feature-host-all|core-host-all|performance-host|move-feature)
      ;;
    *)
      printf 'Batch mode is not supported for host scope: %s\n' "$scope" >&2
      exit 2
      ;;
  esac
fi

if [ "$batch_flutter" -eq 1 ] && [ -z "$flutter_concurrency" ]; then
  flutter_concurrency=1
fi

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
      if [ "$dart_only" -ne 1 ]; then
        printf '%s\n' "$GO_BRIDGE_CONNECTED_PEER_TEST"
        printf '%s\n' "$GO_NODE_KEYROTATION_TEST"
        printf '%s\n' "$GO_NODE_ADDR_VISIBILITY_TEST"
        printf '%s\n' "$GO_NODE_FEATUREFLAGS_TEST"
        printf '%s\n' "$GO_BRIDGE_FEATUREFLAGS_TEST"
        printf '%s\n' "$GO_NODE_WAKETOKEN_TEST"
        printf '%s\n' "$GO_NODE_LIBP2P_REFACTOR_TEST"
        printf '%s\n' "$GO_BRIDGE_ENTRYPOINT_REFACTOR_TEST"
      fi
    } >"$plan_file"
    ;;
  feature-host-all)
    rg --files test/features -g '*_test.dart' | sort >"$plan_file"
    ;;
  core-host-all)
    {
      rg --files test/core -g '*_test.dart'
      rg --files test/unit -g '*_test.dart'
      if [ "$dart_only" -ne 1 ]; then
        printf '%s\n' "$ANDROID_RENDERER_MANIFEST_CONTRACT"
        printf '%s\n' "$ANDROID_DROPPED_PUSH_MANIFEST_CONTRACT"
      fi
    } | sort -u >"$plan_file"
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
        test/features/identity/presentation/screens/startup_router_recovery_test.dart \
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

is_go_node_addr_visibility_test() {
  [ "$1" = "$GO_NODE_ADDR_VISIBILITY_TEST" ]
}

is_go_node_featureflags_test() {
  [ "$1" = "$GO_NODE_FEATUREFLAGS_TEST" ]
}

is_go_bridge_featureflags_test() {
  [ "$1" = "$GO_BRIDGE_FEATUREFLAGS_TEST" ]
}

is_go_node_waketoken_test() {
  [ "$1" = "$GO_NODE_WAKETOKEN_TEST" ]
}

is_go_node_libp2p_refactor_test() {
  [ "$1" = "$GO_NODE_LIBP2P_REFACTOR_TEST" ]
}

is_go_bridge_entrypoint_refactor_test() {
  [ "$1" = "$GO_BRIDGE_ENTRYPOINT_REFACTOR_TEST" ]
}

is_android_renderer_manifest_contract() {
  [ "$1" = "$ANDROID_RENDERER_MANIFEST_CONTRACT" ]
}

is_android_dropped_push_manifest_contract() {
  [ "$1" = "$ANDROID_DROPPED_PUSH_MANIFEST_CONTRACT" ]
}

# Both Android manifest contracts shell out to `./android/gradlew`. Unlike
# `flutter`, gradlew is invoked path-qualified and is therefore NOT satisfied by
# the host shims on PATH, so inside the Claude container these two members are
# the only ones that execute locally for real -- with no /Users, no Flutter SDK,
# and no Android SDK. Gradle then cannot resolve android/local.properties'
# (correct) macOS `flutter.sdk` path and the build fails for an environment
# reason rather than a code one. When the host bridge is mounted, run them on
# the host instead. A native macOS run has no /claude-host-bin, so its command
# plan and execution are unchanged.
readonly HOST_RUN_BRIDGE="/claude-host-bin/host-run"

android_contract_is_bridged() {
  [ -x "$HOST_RUN_BRIDGE" ]
}

print_android_contract_command() {
  if android_contract_is_bridged; then
    printf '%s bash ./%s' "$HOST_RUN_BRIDGE" "$1"
  else
    printf './%s' "$1"
  fi
}

run_android_contract() {
  if android_contract_is_bridged; then
    "$HOST_RUN_BRIDGE" bash "./$1"
  else
    "./$1"
  fi
}

readonly GO_NODE_ADDR_VISIBILITY_RUN='AnnouncedAddrsSurvive|SignedPeerRecord|IdentifyLearnedAddr|InterfaceChangeUpdates|Fdc11PortMining|NoEnumerationErrorSpam|NotSuppressed|HolePunchInputAddrs|DoesNotLeakNonRoutable'

print_command_for_path() {
  local path="$1"
  if is_go_bridge_connected_peer_test "$path"; then
    printf '(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run TestGroupSendReliable_ReportsConnectedTopicPeerCount -count=1)'
    return
  fi
  if is_go_node_keyrotation_test "$path"; then
    printf "(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'UDME|EmitGroupDecryptionFailed|GroupTopicValidator|HandleGroupSubscription|GroupKey|DecryptGroupEnvelopePayload|KeyRotation' -count=1)"
    return
  fi
  if is_go_node_addr_visibility_test "$path"; then
    printf "(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run '%s' -count=1)" "$GO_NODE_ADDR_VISIBILITY_RUN"
    return
  fi
  if is_go_node_featureflags_test "$path"; then
    printf "(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '%s' -count=1)" "$GO_NODE_FEATUREFLAGS_RUN"
    return
  fi
  if is_go_bridge_featureflags_test "$path"; then
    printf "(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '%s' -count=1)" "$GO_BRIDGE_FEATUREFLAGS_RUN"
    return
  fi
  if is_go_node_waketoken_test "$path"; then
    printf "(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '%s' -count=1)" "$GO_NODE_WAKETOKEN_RUN"
    return
  fi
  if is_go_node_libp2p_refactor_test "$path"; then
    printf "(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '%s' -count=1)" "$GO_NODE_LIBP2P_REFACTOR_RUN"
    return
  fi
  if is_go_bridge_entrypoint_refactor_test "$path"; then
    printf "(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '%s' -count=1)" "$GO_BRIDGE_ENTRYPOINT_REFACTOR_RUN"
    return
  fi
  if is_android_renderer_manifest_contract "$path"; then
    print_android_contract_command "$ANDROID_RENDERER_MANIFEST_CONTRACT"
    return
  fi
  if is_android_dropped_push_manifest_contract "$path"; then
    print_android_contract_command "$ANDROID_DROPPED_PUSH_MANIFEST_CONTRACT"
    return
  fi
  printf 'flutter test %s' "$(quote_for_display "$path")"
}

run_path() {
  local path="$1"
  if is_go_bridge_connected_peer_test "$path"; then
    (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run TestGroupSendReliable_ReportsConnectedTopicPeerCount -count=1)
    return
  fi
  if is_go_node_keyrotation_test "$path"; then
    (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'UDME|EmitGroupDecryptionFailed|GroupTopicValidator|HandleGroupSubscription|GroupKey|DecryptGroupEnvelopePayload|KeyRotation' -count=1)
    return
  fi
  if is_go_node_addr_visibility_test "$path"; then
    (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run "$GO_NODE_ADDR_VISIBILITY_RUN" -count=1)
    return
  fi
  if is_go_node_featureflags_test "$path"; then
    (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run "$GO_NODE_FEATUREFLAGS_RUN" -count=1)
    return
  fi
  if is_go_bridge_featureflags_test "$path"; then
    (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run "$GO_BRIDGE_FEATUREFLAGS_RUN" -count=1)
    return
  fi
  if is_go_node_waketoken_test "$path"; then
    (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run "$GO_NODE_WAKETOKEN_RUN" -count=1)
    return
  fi
  if is_go_node_libp2p_refactor_test "$path"; then
    (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run "$GO_NODE_LIBP2P_REFACTOR_RUN" -count=1)
    return
  fi
  if is_go_bridge_entrypoint_refactor_test "$path"; then
    (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run "$GO_BRIDGE_ENTRYPOINT_REFACTOR_RUN" -count=1)
    return
  fi
  if is_android_renderer_manifest_contract "$path"; then
    run_android_contract "$ANDROID_RENDERER_MANIFEST_CONTRACT"
    return
  fi
  if is_android_dropped_push_manifest_contract "$path"; then
    run_android_contract "$ANDROID_DROPPED_PUSH_MANIFEST_CONTRACT"
    return
  fi
  flutter test "$path"
}

if [ "$batch_flutter" -eq 1 ]; then
  printf '\nHost test planned-item inventory: %s\n' "$scope"
else
  printf '\nHost test command plan: %s\n' "$scope"
fi
if [ "$dart_only" -eq 1 ]; then
  printf 'Dart-only plan: non-Dart items omitted.\n'
fi
if [ "$start_at" -ne 1 ]; then
  printf 'Resume filter: starting at planned item #%s\n' "$start_at"
fi
if [ -n "$only_selector" ]; then
  printf 'Resume filter: only %s\n' "$only_selector"
fi

command_count=0
batch_plan_dart_count=0
batch_plan_other_count=0
while IFS=$'\t' read -r index path; do
  [ -n "$path" ] || continue
  command_count=$((command_count + 1))
  printf '  %3d. ' "$index"
  if [ "$batch_flutter" -eq 1 ] && [[ "$path" == test/*_test.dart ]]; then
    batch_plan_dart_count=$((batch_plan_dart_count + 1))
    printf 'Flutter batch path %s' "$(quote_for_display "$path")"
  else
    if [ "$batch_flutter" -eq 1 ]; then
      batch_plan_other_count=$((batch_plan_other_count + 1))
    fi
    print_command_for_path "$path"
  fi
  printf '\n'
done <"$active_plan_file"

if [ "$batch_flutter" -eq 1 ]; then
  batch_plan_flutter_invocations=0
  if [ "$batch_plan_dart_count" -gt 0 ]; then
    batch_plan_flutter_invocations=1
  fi
  printf '\nBatch execution shape: %s Flutter invocation for %s exact Dart path(s)' \
    "$batch_plan_flutter_invocations" "$batch_plan_dart_count"
  printf ', concurrency=%s' "$flutter_concurrency"
  if [ -n "$flutter_reporter" ]; then
    printf ', reporter=%s' "$flutter_reporter"
  fi
  printf '; %s separate non-Flutter invocation(s).\n' \
    "$batch_plan_other_count"
  printf 'Indexed rows above are planned items, not serial execution commands.\n'
fi

if [ "$dry_run" -eq 1 ]; then
  printf '\nDry run only. Host test discovery passed and no commands were executed.\n'
  exit 0
fi

if [ "$batch_flutter" -eq 1 ]; then
  printf '\nRunning %s planned item(s) using the batch execution shape...\n' \
    "$command_count"
  batch_dart_paths=()
  batch_other_indices=()
  batch_other_paths=()

  while IFS=$'\t' read -r index path; do
    [ -n "$path" ] || continue
    if [[ "$path" == test/*_test.dart ]]; then
      batch_dart_paths+=("$path")
    else
      batch_other_indices+=("$index")
      batch_other_paths+=("$path")
    fi
  done <"$active_plan_file"

  if ((${#batch_dart_paths[@]} > 0)); then
    batch_flutter_args=("--concurrency=$flutter_concurrency")
    if [ -n "$flutter_reporter" ]; then
      batch_flutter_args+=("--reporter=$flutter_reporter")
    fi
    batch_flutter_args+=("${batch_dart_paths[@]}")

    printf '\n==> Flutter batch: %s exact planned test path(s), concurrency=%s' \
      "${#batch_dart_paths[@]}" "$flutter_concurrency"
    if [ -n "$flutter_reporter" ]; then
      printf ', reporter=%s' "$flutter_reporter"
    fi
    printf '\n'

    if flutter test "${batch_flutter_args[@]}"; then
      printf 'PASS: Flutter batch (%s test paths)\n' "${#batch_dart_paths[@]}"
    else
      status=$?
      printf 'FAIL: Flutter batch exited with %s\n' "$status" >&2
      printf '%s\t%s\t%s\n' \
        batch 'Flutter batch' "$status" >>"$failures_file"
      if [ "$continue_on_failure" -ne 1 ]; then
        exit "$status"
      fi
    fi
  fi

  for ((i = 0; i < ${#batch_other_paths[@]}; i++)); do
    index="${batch_other_indices[$i]}"
    path="${batch_other_paths[$i]}"
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
  done
else
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
fi

failure_count="$(awk 'END { print NR + 0 }' "$failures_file")"
if [ "$failure_count" -gt 0 ]; then
  printf '\nHost tests failed (%s):\n' "$failure_count" >&2
  awk -F '\t' '{ printf "  - #%s %s exited with %s\n", $1, $2, $3 }' "$failures_file" >&2
  exit 1
fi

printf '\nPASS: host tests completed for scope: %s\n' "$scope"
