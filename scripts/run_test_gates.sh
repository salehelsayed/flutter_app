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
  # 214: Orbit-as-home landing locks (post-accept, cold start, full journey).
  "test/features/home/presentation/screens/first_time_experience_wired_test.dart"
  "test/features/identity/presentation/screens/startup_router_home_surface_test.dart"
  "test/features/home/integration/onboarding_landing_surface_test.dart"
)

readonly ONE_TO_ONE_TESTS=(
  "test/features/conversation/integration/two_user_message_exchange_test.dart"
  "test/features/conversation/integration/offline_inbox_roundtrip_test.dart"
  # FDC-02: staggered relay-penalty ranked race — e2e dedup-masking discriminator
  # (sender relayLiveSendCount) across sender+receiver fakes.
  "test/features/conversation/integration/ranked_race_relay_penalty_test.dart"
  "test/features/conversation/integration/media_attachment_flow_test.dart"
  "test/features/conversation/integration/media_retry_smoke_test.dart"
  "test/features/conversation/integration/media_eviction_redownload_test.dart"
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
  "test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart"
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
  # FDC-07: cold-start early mDNS discovery hoist + idempotent/move-gated seam.
  "test/core/services/p2p_service_early_discovery_ordering_test.dart"
  # FDC-13: relay->direct 'upgraded' badge — the _inferTransportForPeer flip is
  # a 1:1 headline lock (DCUTR-002/013 + T4 census/data asserts).
  "test/core/services/p2p_service_inbound_transport_test.dart"
  "test/features/conversation/application/download_media_use_case_test.dart"
  "test/features/conversation/application/upload_media_use_case_test.dart"
  "test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart"
  "test/core/bridge/go_bridge_client_test.dart"
  "test/core/bridge/p2p_bridge_client_test.dart"
  "test/features/conversation/application/media_download_slow_transfer_simulator_test.dart"
  "test/features/contact_request/application/handle_incoming_message_use_case_test.dart"
  "test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart"
  # 217 CV-14 wake-token send leg (A01) — curated into the 1to1 gate alongside
  # the receive (handle) + backfill (retry) files already listed above.
  "test/features/contact_request/application/send_contact_request_use_case_test.dart"
  "test/features/conversation/application/post_restore_stale_key_recovery_test.dart"
  "test/features/contact_request/application/contact_request_listener_test.dart"
  # 171: one-scan mutual contact add (auto-add v2 + deferred-ack + staged inbox
  # replay). Two-party convergence lock (INV-4: A issues zero reciprocals).
  "test/features/contact_request/integration/contact_request_one_scan_mutual_test.dart"
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
  # 170 send button frozen + failure SnackBar overlap (offline-send UX).
  "test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart"
  # FDC-04 LAN-aware eager warmPeer: resume warm-peer lock + notif-tap warm
  # forward-wiring lock.
  "test/core/lifecycle/handle_app_resumed_warm_peer_test.dart"
  "test/features/push/application/prepare_notification_route_target_use_case_test.dart"
  # FDC-18: 1:1 reaction add+remove send reliability — concurrent durable inbox
  # (mirror of FDC-01+FDC-03 onto sendReaction/removeReaction). These already
  # auto-glob into feature-host-all; appended here so the headline reaction
  # locks also run in the curated 1to1 gate. (emoji_reaction_exchange stays in
  # OPTIONAL_MANUAL_TESTS; group reaction files are out of scope.)
  "test/features/conversation/application/send_reaction_use_case_test.dart"
  "test/features/conversation/application/remove_reaction_use_case_test.dart"
  "test/features/conversation/application/handle_incoming_reaction_use_case_test.dart"
  "test/features/conversation/integration/reaction_roundtrip_test.dart"
  # Plan 256: composed actor-copy, stable conversation-card identity, and
  # message-unread non-increment contract through the real local plugin seam.
  "test/features/conversation/integration/reaction_notification_pipeline_test.dart"
  # FDC-08: 1:1 presence-emphasis send locks (C5/C6/C7). Auto-globs into
  # feature-host-all; appended here so the load-bearing "presence is never a
  # delivery gate" locks also run in the curated 1to1 gate.
  "test/features/conversation/application/send_presence_emphasis_test.dart"
  # FDC-12: DCUtR relay->direct upgrade — Dart sticky/badge handling (TC-12-09/09b)
  # and the default-off flag plumb (TC-12-10). test/core/** is NOT auto-globbed
  # into the curated 1to1 gate, so these are appended explicitly.
  "test/core/services/p2p_service_transport_upgrade_test.dart"
  "test/core/services/p2p_service_dcutr_flag_test.dart"
  # FDC-15: 1:1 media over a libp2p LAN stream — send leg + hasNonCircuitDirectConn
  # predicate (TD1-7) and the go_bridge media:lan_received routing (TD8, which
  # guards the unknown-event regression). test/core/** is NOT auto-globbed into
  # the curated 1to1 gate, so these are appended explicitly.
  "test/core/services/p2p_service_impl_lan_media_test.dart"
  "test/core/bridge/go_bridge_client_lan_media_test.dart"
  # 179: CV-34 Pixel→iPhone LAN-media forward-chain self-heal + observability
  # (TC-179-01..03/05 — resolved-but-empty skip diagnostic, dedup-clear-on-lost,
  # bounded re-resolve, advert port-derivation lock). test/core/** is NOT auto-
  # globbed into the curated 1to1 gate, so it is appended explicitly. (TC-179-04
  # lives in local_p2p_service_test.dart, which auto-globs into core-host-all.)
  "test/core/services/p2p_service_lan_forward_test.dart"
  # 190 (Android netlink addr-visibility, TC-190-05 Dart parity): the advert-port
  # derivation is IP-agnostic, so the empty(0.0.0.0-mined)→real address rollout
  # derives identical advert ports (no bonsoir re-advert churn). Standalone file
  # (kept off the dirty p2p_service_impl_test.dart); auto-globs into core-host-all,
  # pinned here so the 1to1 gate lists it too.
  "test/core/services/p2p_service_addr_shape_parity_test.dart"
  # 181: presence lifecycle wiring lock — _MyAppState constructs SetPresenceUseCase
  # and dispatches onForegrounded/onBackgrounded/dispose on resume/pause/teardown
  # (the producer that activates the committed unreachable short-circuit). Source-
  # assertion lock under test/core/**, which is NOT auto-globbed into the curated
  # 1to1 gate, so it is appended explicitly (it also auto-globs into core-host-all).
  "test/core/lifecycle/main_presence_lifecycle_wiring_test.dart"
  # 183: active-chat keepalive wiring lock — _MyAppState constructs
  # ActivePeerKeepAliveUseCase from the concrete P2PServiceImpl (PeerLivenessProbe)
  # + the active 1:1 peer, REUSING warmPeer + drainOfflineInbox, and arms/cancels/
  # disposes it on resume/pause/teardown. Source-assertion lock under test/core/**,
  # NOT auto-globbed into the curated 1to1 gate, so appended explicitly (it also
  # auto-globs into core-host-all).
  "test/core/lifecycle/main_keepalive_wiring_test.dart"
  # 189: degraded-relay drain starvation + restart-loop locks — every health-check
  # tick drains (recovery/failed/throwing ticks included), phase=recovered is
  # truthful (bridge 'success'), failed recoveries back off while drains never do.
  # Receive-side 1:1 delivery latency (field: store→ack 86s→10+min). test/core/**
  # is NOT auto-globbed into the curated 1to1 gate, so appended explicitly (it
  # also auto-globs into core-host-all).
  "test/core/services/p2p_service_impl_health_drain_test.dart"
  # 216: cold-start connecting→online inbox-proof kick — the send-proof store
  # mirrors the send→inbox readiness kick so inboxCapabilityReady flips off the
  # store instead of waiting for the first 30s health-check tick (badge ~30s→~1.5s
  # on device). Locks the store-seam kick + its once-per-window / re-arm guard.
  # Auto-globs into core-host-all; pinned here for the curated 1to1 gate.
  "test/core/services/p2p_service_impl_inbox_proof_kick_test.dart"
  # 191: iOS foreground-push forwarding hardening — Dart half. FirebaseReadiness
  # (latch-on-success retry, no more one-failure permanent push deafness) +
  # PushListenerArmer (observable PUSH_LISTENERS_ARMED, readiness-driven third
  # arm point). Both auto-glob into feature-host-all; appended here so the
  # curated 1to1 gate also runs the receive-path (push→drain) arm locks.
  "test/features/push/application/firebase_readiness_test.dart"
  "test/features/push/application/push_listener_armer_test.dart"
  # 225: notif-tap last-message lag — replay-before-ack and 1:1 push-envelope
  # staging fast-path host locks. test/core/** and selected feature integration
  # files are pinned here so the headline 1:1 gate includes them.
  "test/core/services/p2p_service_inbox_ack_ordering_test.dart"
  "test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart"
  "test/features/push/application/background_message_handler_staging_test.dart"
  "test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart"
  "test/features/conversation/integration/notif_tap_payload_fast_path_test.dart"
  "test/features/push/integration/push_ingest_persistence_test.dart"
  # 231: 1:1 received media core actions — attachment-targeted bubble/viewer
  # identity + Info/Reply (screen tests auto-glob but are pinned for the
  # curated 1to1 gate), the current-row egress controller, and the exact
  # egress-callsite / frozen wired-transport boundary contract.
  "test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart"
  "test/features/conversation/application/received_media_action_controller_test.dart"
  "test/features/conversation/application/received_media_action_transport_boundary_test.dart"
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
  # 234 Session 05: dedicated private route/lifecycle/native-protection host
  # contract. Native and device proofs stay exact manual commands.
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
  # 247 Session 03: the real direct-route boundary must remain blank and
  # delivery-free when entered from eligible announcement media.
  "test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart"
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
  "test/features/feed/presentation/widgets/letter_card_system_signal_test.dart"
  "test/features/feed/presentation/widgets/feed_tokens_tone_test.dart"
  # Screen behaviors: focus/compose, swipe-dismiss, caught-up, reduced-motion.
  "test/features/feed/presentation/screens/feed_focus_test.dart"
  "test/features/feed/presentation/screens/feed_swipe_test.dart"
  "test/features/feed/presentation/screens/feed_caught_up_test.dart"
  "test/features/feed/presentation/screens/feed_reduced_motion_test.dart"
  "test/features/feed/presentation/screens/feed_screen_test.dart"
  "test/features/feed/presentation/screens/feed_wired_test.dart"
  # 206 avatar removal + 211 connection dot migrated to Orbit top-right
  # (header keeps only the username editor).
  "test/features/feed/presentation/widgets/feed_header_test.dart"
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
  # 252: intro-accept notification copy + A->B chat routing (fallback copy,
  # anchored route target, canonical envelope-ID parse, resolver, shared open
  # coordinator, main.dart source-wiring lock).
  "test/features/push/application/background_push_notification_fallback_test.dart"
  "test/core/notifications/notification_route_target_test.dart"
  "test/core/notifications/intro_accept_open_coordinator_wiring_test.dart"
  "test/features/introduction/application/introduction_payload_test.dart"
  "test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart"
  "test/features/push/application/intro_accept_notification_open_flow_test.dart"
)

readonly GROUP_TESTS=(
  "test/features/groups/integration/group_messaging_smoke_test.dart"
  "test/features/conversation/integration/media_eviction_redownload_test.dart"
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
  # 206: Orbit center self-avatar → Settings entry (full-chain + gating + latch).
  "test/features/orbit/presentation/screens/orbit_settings_entry_test.dart"
  "test/features/groups/presentation/widgets/pending_group_invite_card_test.dart"
  # 156 QW-4: group avatar cacheWidth/cacheHeight.
  "test/features/groups/presentation/widgets/group_avatar_test.dart"
  # 159 group display-items memo (hoisted to wired State) + window cap.
  "test/features/groups/presentation/group_display_items_memo_test.dart"
  "test/features/groups/presentation/group_window_cap_test.dart"
  # FDC-15: group-media scope lock (TD6) — group uploads stay relay-CDN-only and
  # must NEVER touch the 1:1 libp2p-LAN leg. Added here so the groups gate
  # actually exercises TD6 (the file is otherwise only in the 1to1/transport arrays).
  "test/core/services/p2p_service_impl_lan_media_test.dart"
  # 193 orbit view split: new view-split widget tests + the orbit l10n parity
  # test (test/l10n is OUTSIDE feature-host-all's glob, so it must be curated
  # here to be reachable from the groups gate + completeness-check).
  "test/features/orbit/presentation/screens/orbit_view_split_test.dart"
  # 194 orbit per-node unread "messenger orbit" indicator: wired-host tier
  # (live-appear + per-surface clear-on-read + surface-scoping regression).
  # Auto-globs into feature-host-all, but pinned here so it also runs in the
  # curated groups gate + completeness-check alongside the other orbit tests.
  "test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart"
  # 196 orbit QR-chrome migration: wired-host tier (PROD-CRITICAL tap→route
  # push through _onMyQR/_onScanQR). Auto-globs into feature-host-all, pinned
  # here so it also runs in the curated groups gate + completeness-check.
  "test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart"
  # 198 orbit Sculpt & Summon: the headline wired surface suite (edit session,
  # geometry handles, find, labels, persistence, reset seam). Auto-globs into
  # feature-host-all, pinned here so it also runs in the curated groups gate.
  "test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart"
  # 212 orbit search-trigger placement: floated bottom-right band (INV-212-1
  # one band across both surfaces, RTL physical-right, standalone freeze).
  # Auto-globs into feature-host-all, pinned here so the curated groups gate
  # also locks the placement contract.
  "test/features/orbit/presentation/screens/orbit_search_trigger_placement_test.dart"
  # 211 orbit connection indicator: the pill migrated from the Feed header to
  # the Orbit top-right chrome (Layer 4b before the FAB scrim, both views,
  # edit-hide, seed/telemetry-once). Auto-globs into feature-host-all, pinned
  # here so the curated groups gate also locks the placement contract.
  "test/features/orbit/presentation/screens/orbit_connection_indicator_test.dart"
  "test/l10n/orbit_strings_parity_test.dart"
  # 210 group offline-send: the real-SQLCipher recovery-predicate test (the
  # 'queued_offline' re-drive anchor). Auto-globs into feature-host-all, pinned
  # here so the curated groups gate also exercises the recovery change.
  "test/features/groups/domain/repositories/group_message_repository_impl_test.dart"
  # 210b: the repush lane is the LIVE-app self-heal for 'queued_offline' rows
  # (clock→tick on reconnect). Auto-globs into feature-host-all, pinned here so
  # the curated groups gate exercises the queued_offline promote.
  "test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart"
  # 207 orbit intro dock: inner-circle top-row review entry (placement, count
  # gate, edit-hide, RTL, scrim/identity). Auto-globs into feature-host-all,
  # pinned here so the curated groups gate also locks the dock chrome.
  "test/features/orbit/presentation/screens/orbit_intro_dock_test.dart"
  # 235 group received-media core actions: pure capability policy (chat-only,
  # incoming-only, group-lane-only; verified gates Save/Share, canWrite gates
  # Reply) + the requalifying egress adapter (exact parent/owner reload before
  # every ReceivedMediaEgressService call; refusals make zero egress calls).
  "test/features/groups/application/group_received_media_action_policy_test.dart"
  "test/features/groups/application/group_received_media_actions_test.dart"
  # 247 Session 02: minimum local request, fresh fail-closed announcement
  # sender/contact qualification, and the read-only transport boundary.
  "test/features/groups/application/announcement_private_reply_request_test.dart"
  "test/features/groups/application/announcement_private_reply_policy_test.dart"
  "test/features/groups/application/announcement_private_reply_transport_boundary_test.dart"
  # 247 Session 03: distinct bubble/viewer action, exact five-owner opener
  # census, blank direct route, current-item dispatch, and localized feedback.
  "test/features/groups/presentation/announcement_private_reply_routing_test.dart"
  "test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart"
  "test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart"
  # 257: compatible payload/send/remove/roundtrip coverage, composed
  # reaction-notification/unread policy, routed Orbit refresh, and the strict
  # five-row device-evidence contract. The device proof itself remains in the
  # manual reliability-sim lane and cannot pass without captured artifacts.
  "test/features/groups/domain/models/group_reaction_payload_test.dart"
  "test/features/groups/application/send_group_reaction_use_case_test.dart"
  "test/features/groups/application/remove_group_reaction_use_case_test.dart"
  "test/features/groups/integration/group_reaction_roundtrip_test.dart"
  "test/features/groups/integration/group_reaction_notification_pipeline_test.dart"
  "test/features/orbit/presentation/screens/orbit_group_unread_notification_wired_test.dart"
  "test/integration/group_reaction_notification_device_criteria_test.dart"
  # 235 persistence slice: v98 deletion journal (atomic delete-prepare +
  # exact reaction cleanup), the file->key->DB cleanup saga with restart
  # convergence, the guarded incoming final write / journal-aware download
  # CAS, the tombstone reaction discard, and the cold-start/resume wiring.
  "test/features/groups/application/delete_group_media_for_me_use_case_test.dart"
  "test/features/groups/application/handle_incoming_group_message_use_case_test.dart"
  "test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart"
  "test/features/groups/integration/group_received_media_delete_replay_test.dart"
  "test/core/database/migrations/098_group_media_deletion_journal_test.dart"
  "test/core/lifecycle/group_media_deletion_reconciler_wiring_test.dart"
  "test/core/lifecycle/handle_app_resumed_group_media_cleanup_test.dart"
  # 236 group received-media forwarding: Forward-offer policy + dispatch-time
  # source gate, explicit-forward-only provenance, forward-mode picker
  # filtering/revalidation/caption, coordinator re-encryption + per-target
  # isolation + owner sentinel, failed-only picker retry, marker through
  # send/reliable/publish/wire/replay + BOTH durable re-drive callers, live
  # listener + durable membership buffer, ordinary drain + history-gap
  # repair, bubble label, and the transport-boundary source contract.
  "test/features/groups/application/group_media_forward_policy_test.dart"
  # P1 media-forwarding regression: preview and dispatch share the same locked,
  # canonical JPEG/MP4 qualification and fail closed on lifecycle/file drift.
  "test/features/groups/application/group_media_forward_preview_gate_test.dart"
  "test/features/groups/application/group_media_forward_intent_test.dart"
  "test/features/groups/presentation/group_media_forward_flow_test.dart"
  "test/features/share/application/share_batch_delivery_coordinator_test.dart"
  "test/features/share/presentation/share_target_picker_wired_test.dart"
  "test/features/groups/application/send_group_message_use_case_test.dart"
  "test/features/groups/application/retry_failed_group_messages_use_case_test.dart"
  "test/features/groups/integration/external_share_group_media_liveness_test.dart"
  "test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart"
  "test/features/groups/application/group_message_listener_test.dart"
  "test/features/groups/application/drain_group_offline_inbox_use_case_test.dart"
  "test/features/groups/integration/group_forwarding_transport_boundary_test.dart"
  # 240 announcement received-media forwarding: announcement source adapter,
  # caption modes, target policy/revalidation, per-target provenance, marker,
  # owner boundary, and failed-only retry discrimination.
  "test/features/groups/application/announcement_media_forward_request_test.dart"
  "test/features/groups/presentation/announcement_received_media_forwarding_test.dart"
  "test/features/groups/integration/announcement_received_media_forwarding_test.dart"
  "test/features/groups/integration/announcement_media_forward_marker_test.dart"
  "test/features/share/presentation/announcement_forward_target_policy_test.dart"
  "test/features/share/application/announcement_forward_batch_delivery_test.dart"
  "test/features/share/application/announcement_forward_contact_marker_test.dart"
  "test/features/share/application/announcement_forward_media_owner_contract_test.dart"
  # 237 discussion-group shared media: guarded entry, strict group scope,
  # lazy typed viewer, bounded selection/actions, durable local state,
  # bounded Go-to-message, refresh, and transport isolation.
  "test/features/groups/presentation/group_shared_media_entry_test.dart"
  "test/features/groups/application/group_shared_media_repository_contract_test.dart"
  "test/features/groups/presentation/group_shared_media_screen_test.dart"
  "test/features/groups/presentation/group_shared_media_wired_test.dart"
  "test/features/groups/presentation/group_shared_media_go_to_message_test.dart"
  "test/features/groups/application/group_media_batch_actions_test.dart"
  "test/features/groups/integration/group_shared_media_bookmark_test.dart"
  "test/features/groups/integration/group_shared_media_eviction_test.dart"
  "test/features/groups/integration/group_shared_media_transport_boundary_test.dart"
  # 241 announcement received-only shared media composition.
  "test/features/groups/integration/announcement_media_library_repository_test.dart"
  "test/features/groups/presentation/announcement_media_library_entry_test.dart"
  "test/features/groups/presentation/announcement_media_library_paging_test.dart"
  "test/features/groups/presentation/announcement_media_library_viewer_test.dart"
  "test/features/groups/presentation/announcement_media_go_to_message_test.dart"
  "test/features/groups/presentation/announcement_media_library_actions_test.dart"
  "test/features/groups/application/announcement_media_library_batch_actions_test.dart"
  "test/features/groups/application/announcement_media_library_batch_delete_test.dart"
  # 238 group-private foundation: sequential v101 policy persistence, strict
  # encrypted-inner four-field roundtrip, current-role retry/pre-upload
  # qualification, and fail-closed action/library/announcement shields.
  "test/core/database/migrations/101_group_private_media_lifecycle_test.dart"
  "test/features/groups/domain/models/group_private_media_policy_test.dart"
  "test/features/groups/integration/group_private_media_payload_roundtrip_test.dart"
  "test/features/groups/application/group_private_media_safe_disabled_boundary_test.dart"
  "test/features/groups/application/group_private_media_retry_qualification_test.dart"
  "test/features/groups/application/group_private_media_preupload_boundary_test.dart"
  "test/features/groups/application/group_private_media_stale_library_boundary_test.dart"
  "test/features/groups/integration/group_private_media_transport_boundary_test.dart"
  "test/features/groups/presentation/group_private_media_announcement_sentinel_test.dart"
  # 238 group lifecycle closure: first-frame CAS, restart recovery,
  # monotonic expiry, exact cleanup, and guarded explicit download replay.
  "test/features/groups/application/group_private_media_lifecycle_test.dart"
  "test/features/groups/integration/group_private_media_crash_recovery_test.dart"
  "test/features/groups/application/group_private_media_expiry_test.dart"
  "test/features/groups/integration/group_private_media_cleanup_replay_test.dart"
  "test/features/groups/presentation/group_private_media_capabilities_test.dart"
  "test/features/groups/application/group_private_media_notification_test.dart"
  "test/features/push/application/push_decrypt_preview_test.dart"
  "test/features/groups/presentation/group_private_media_viewer_test.dart"
  # 242 announcement-private lifecycle: exact current-admin author/receive
  # authority, encrypted-inner policy, shared durable lifecycle/capabilities,
  # minimized moderation metadata, and generic notification privacy.
  "test/features/groups/domain/models/announcement_private_media_policy_test.dart"
  "test/features/groups/application/announcement_private_media_authorization_test.dart"
  "test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart"
  "test/features/groups/integration/announcement_private_media_lifecycle_test.dart"
  "test/features/groups/presentation/announcement_private_media_capabilities_test.dart"
  "test/features/groups/application/announcement_private_media_notification_test.dart"
  "test/features/groups/application/announcement_private_media_moderation_test.dart"
  # Receive-side current-admin authorization completes Plan 242's exact eight
  # dedicated host suites across live and offline persistence paths.
  "test/features/groups/application/announcement_incoming_message_authorization_test.dart"
  # 250/251 shared Plan-249-derived batch foundation: owner-scoped draft,
  # bounded preflight, current target authorization, one-statement SQLite
  # authorization snapshot, and source-target-cell delivery/retry truth.
  "test/features/groups/application/group_media_batch_forward_draft_test.dart"
  "test/features/groups/application/group_media_batch_forward_preflight_test.dart"
  "test/features/groups/application/group_media_batch_forward_authorization_test.dart"
  "test/core/database/helpers/group_forward_authorization_db_helpers_test.dart"
  "test/features/groups/application/group_media_batch_forward_delivery_test.dart"
  # 250 discussion-library opt-in batch surface and scope preservation.
  "test/features/groups/presentation/group_shared_media_batch_forward_test.dart"
  # 251 announcement-library batch surface, exact target policy, and opaque
  # target-unit provenance / durable retry without source mutation.
  "test/features/groups/presentation/announcement_media_batch_forward_test.dart"
  "test/features/share/presentation/announcement_batch_forward_target_policy_test.dart"
  "test/features/share/application/announcement_batch_forward_provenance_test.dart"
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
  # FDC-04 LAN-aware warm-peer overlap smoke (host-green proves label wiring;
  # the real LAN win is device-proof).
  "integration_test/warm_peer_lan_aware_smoke_test.dart"
  # FDC-15: 1:1 media over a libp2p LAN stream — host-side send-leg/predicate/
  # routing locks (the live two-phone media transfer is device-only, D1). A
  # test/** path runs host-side here via run_gate_command's flutter-test split.
  "test/core/services/p2p_service_impl_lan_media_test.dart"
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

# 236/238: exact non-vacuous Go legs for group-media forwarding and private
# policy — bridge option mapping plus unchanged-node encrypted-extra delivery
# sentinels. Wired into BOTH the `groups` and `all` gates.
run_group_forwarding_go_bridge_gate() {
  echo "=== Group Forwarding / Private Media Go Bridge Gate ==="
  (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '^TestGMF11ForwardedMarkerMapsToPublishOptions$' -count=1)
  (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge ./node -run 'GPL12|GK030' -count=1)
}

# Notification relay closure: curated 1:1 and group gates run only the focused
# provider-routing sentinels. The wave/all gate runs the complete relay module
# once, matching the repository's full-Go cadence.
run_relay_toolchain_contract_gate() {
  echo "=== Relay Go Toolchain Contract Gate ==="
  bash scripts/test/relay_go_toolchain_contract_test.sh
}

run_relay_notification_go_gate() {
  echo "=== Relay Notification Go Gate ==="
  run_relay_toolchain_contract_gate
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_' -count=1)
}

run_relay_all_go_gate() {
  echo "=== Relay Full Go Gate ==="
  run_relay_toolchain_contract_gate
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)
}

classify_path() {
  local path="$1"

  # Plan 257 device campaign controller/validator/capture sources are expanded
  # by reliability discovery, not executed as host tests. Keep them explicitly
  # classified here so manual completeness queries cannot mistake them for an
  # unowned integration path.
  case "$path" in
    integration_test/scripts/run_group_reaction_notification_device.dart|\
    integration_test/scripts/capture_group_reaction_notification_device.dart|\
    integration_test/scripts/validate_group_reaction_notification_artifacts.dart|\
    integration_test/scripts/group_reaction_notification_device_criteria.dart)
      printf 'Plan 257 device-capture runner'
      return 0
      ;;
  esac

  # Plan 257 driver-owned SQLCipher observer. It is launched on the explicit
  # recipient only after the OS notification/tap journey; running it in a host
  # array would be both impossible and misleading.
  if [[ "$path" == "integration_test/group_reaction_notification_sqlcipher_probe_test.dart" ]]; then
    printf 'Plan 257 device-capture support'
    return 0
  fi

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

  if [[ "$path" =~ ^test/core/(bridge|constants|database|device|inbox|l10n|local_discovery|media|permissions|secure_storage|theme|utils)/.*_test\.dart$ ]]; then
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

  if [[ "$path" =~ ^test/features/[^/]+/(application|domain|infrastructure|presentation|improvement|phase[1-5]|regression)/.*_test\.dart$ ]]; then
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

has_host_batch_control() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --batch-flutter|--batch-flutter=*|\
        --concurrency|--concurrency=*|\
        --reporter|--reporter=*)
        return 0
        ;;
    esac
  done
  return 1
}

main() {
  local gate="${1:-}"
  local -a gate_args=("${@:2}")

  case "$gate" in
    move-feature|host-all|feature-host-all|core-host-all|performance-host)
      ;;
    *)
      if ((${#gate_args[@]} > 0)) &&
        has_host_batch_control "${gate_args[@]}"; then
        printf 'Host batch options are not supported for gate: %s\n' \
          "${gate:-<missing>}" >&2
        return 2
      fi
      ;;
  esac

  case "$gate" in
    baseline)
      run_gate_command "Baseline Gate" "${BASELINE_TESTS[@]}"
      ;;
    1to1)
      if ((${#gate_args[@]} == 0)); then
        run_gate_command "1:1 Reliability Gate" "${ONE_TO_ONE_TESTS[@]}"
        run_relay_notification_go_gate
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
      run_group_forwarding_go_bridge_gate
      run_relay_notification_go_gate
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
      run_group_forwarding_go_bridge_gate
      run_relay_all_go_gate
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
