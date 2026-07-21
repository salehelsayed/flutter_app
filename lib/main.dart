import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/share/application/handle_share_intent_use_case.dart';
import 'package:flutter_app/features/share/presentation/navigation/share_target_picker_route.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/device/disk_space.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_rejoin_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_forward_authorization_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_consumptions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_revocations_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_welcome_key_package_tombstones_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_invites_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/intro_review_seen_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_sibling_devices_db_helpers.dart';
import 'package:flutter_app/features/groups/application/manage_pending_sibling_device.dart';
import 'package:flutter_app/core/secure_storage/ml_kem_secret_ring.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_distributions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_membership_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_exit_intents_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_history_gap_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_sync_receipts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/self_removed_group_shell_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_comments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_comment_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_follow_on_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_location_presence_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_pin_dismissals_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_origin_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_passes_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_pins_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_privacy_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/feed_cleared_threads_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_upload_recovery_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_pending_child_events_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_repost_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/domain/repositories/intro_review_seen_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/resolve_introduction_notification_target_use_case.dart';
import 'package:flutter_app/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart';
import 'package:flutter_app/features/push/application/intro_accept_notification_open_flow.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/core/secure_storage/legacy_group_secret_storage_scrub.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_notification_materializer.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_bridge_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_segmented_transfer_service.dart';
import 'package:flutter_app/features/account_migration/application/migration_storage_preflight.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_checkpoint_store.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/private_media_expiry_scheduler.dart';
import 'package:flutter_app/features/conversation/application/delivery_receipt_listener.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart'
    show sendDeliveryReceipt;
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart'
    show predecryptStagedInboxChatEntry;
import 'package:flutter_app/features/conversation/application/handle_incoming_message_deletion_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_sibling_dispositions.dart';
import 'package:flutter_app/features/conversation/application/link_incoming_local_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/message_deletion_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_direct_private_committed_pending_cleanup.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/verify_inbox_custody_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/groups/application/recover_stuck_sending_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_distribution_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_membership_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository_impl.dart';
import 'package:flutter_app/core/database/helpers/group_message_local_deletions_db_helpers.dart';
import 'package:flutter_app/features/groups/application/delete_group_media_for_me_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_media_deletion_journal_reconciler.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_invite_identity_callbacks.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_repair_responder_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_backoff_timer.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_repush.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_dissolve_preflight_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository_impl.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/reconcile_missed_group_dissolves_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/settings/application/media_auto_download_decider.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';
import 'package:flutter_app/core/services/connectivity_signal.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/core/debug/e2e_test_mode.dart';
import 'package:flutter_app/core/debug/ios_receiver_bootstrap.dart';
import 'package:flutter_app/core/debug/ios_sender_projection_fixture.dart';
import 'package:flutter_app/core/debug/ios_sender_projection_fixture_contract.dart';
import 'package:flutter_app/core/debug/auto_setup_config.dart';
import 'package:flutter_app/core/debug/intro_e2e_runner.dart';
import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';
import 'package:flutter_app/core/debug/wake_token_directionality_e2e.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/disabled_local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/native_mdns_resolver.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/local_discovery/local_media_server.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/ios_apns_notification_open_bridge.dart';
import 'package:flutter_app/core/notifications/notification_open_dedupe_gate.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/initial_local_notification_route_diagnostics.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/app_shell_theme_binding.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/diagnostics/app_build_info.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'
    show
        ValueListenable,
        ValueNotifier,
        debugPrintSynchronously,
        kDebugMode,
        kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_app/core/notifications/recent_remote_gate_ios_wiring.dart';
import 'package:flutter_app/features/push/application/firebase_readiness.dart';
import 'package:flutter_app/features/push/application/group_missing_notification_feedback.dart';
import 'package:flutter_app/features/push/application/push_listener_armer.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/ingest_staged_push_envelopes_use_case.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/push_relay_registration_proof.dart';
import 'package:flutter_app/features/push/application/prepare_notification_route_target_use_case.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart'
    as push_registration;
import 'package:flutter_app/features/push/application/request_push_permission_use_case.dart';
import 'package:flutter_app/features/push/application/set_presence_use_case.dart';
import 'package:flutter_app/core/services/active_peer_keepalive_use_case.dart';
import 'package:flutter_app/features/push/infrastructure/push_token_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/wake_token_store_impl.dart';
import 'package:flutter_app/features/push/application/issue_wake_tokens_use_case.dart';
import 'package:flutter_app/features/push/application/wake_token_wiring.dart';
import 'package:flutter_app/features/push/application/wake_token_reissue_coalescer.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/download_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/publish_post_presence_update_use_case.dart';
import 'package:flutter_app/features/posts/application/post_presence_listener.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_notification_open_coordinator.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/groups/application/sweep_expired_group_invites_use_case.dart';
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository_impl.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository_impl.dart';

/// 164 (cold-start-3): retained reference to the launch-time shared-Keychain
/// mirror backfill so it runs off the pre-runApp critical path without the
/// analyzer/GC silently dropping it. Assigned (not awaited) in [main].
Future<void>? keychainMirrorBackfill;

Stream<void> _mergeVoidStreams(Iterable<Stream<void>> inputs) {
  return Stream<void>.multi((controller) {
    final subscriptions = inputs
        .map(
          (input) => input.listen(
            (_) => controller.addSync(null),
            onError: controller.addErrorSync,
          ),
        )
        .toList(growable: false);
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupTiming.instance.mark('app_start');
  // FDC-S1 measurement harness (observation-only, OFF by default): built with
  // --dart-define=FDC_FLOW_LOG=1 (or true/yes/on) this forces flow-event logging
  // on so cold-start `[FLOW]` timing events are visible in a realistic-timing
  // profile build (logging otherwise defaults to kDebugMode). No effect on a
  // normal build. Accepts any truthy spelling so the runbook is forgiving —
  // bool.fromEnvironment only honours the exact strings 'true'/'false'.
  const fdcFlowLog = String.fromEnvironment('FDC_FLOW_LOG');
  if (fdcFlowLog == '1' ||
      fdcFlowLog == 'true' ||
      fdcFlowLog == 'yes' ||
      fdcFlowLog == 'on') {
    flowEventLoggingEnabled = true;
    // The default debugPrint throttles to ~16KB/s and would drop bursty
    // cold-start [FLOW] lines; print synchronously so every timing event lands
    // in logcat/console for capture. Measurement build only.
    debugPrint = debugPrintSynchronously;
  }
  // Build-provenance milestone (B6): emit the source revision under test before
  // anything else, so device/harness logs can be matched to the exact build and
  // "fixed in tree, broken on device" build-skew is caught by a log grep.
  emitAppBuildInfo();
  final shareIntentService = ShareIntentService();
  StartupTiming.instance.mark('share_launch_probe_begin');
  // 164 (cold-start-5): the share-intent probe and the documents-directory probe
  // are independent — start both, then join with Future.wait so they overlap
  // instead of running serially on the pre-runApp critical path.
  final shareIntentProbe = shareIntentService.captureInitialIntent();
  final appDocDirProbe = getApplicationDocumentsDirectory();
  await Future.wait<Object?>([shareIntentProbe, appDocDirProbe]);
  final initialShareIntent = await shareIntentProbe;
  final appDocDir = await appDocDirProbe;
  final isShareLaunch = initialShareIntent != null;
  StartupTiming.instance.mark('share_launch_probe_complete');

  // Initialize Firebase (mobile only — not available on desktop)
  final bool isDesktop =
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
  // 191 (Fix D1): delegate Firebase init to FirebaseReadiness so the readiness
  // latch is consumed ONLY on a successful init. The pre-191 code latched
  // `firebaseInitialized = true` BEFORE the try, so ONE transient
  // Firebase.initializeApp() failure permanently marked Firebase "ready" — no
  // later call ever retried and the process stayed deaf to push for its whole
  // lifetime. The unit latches after success (retryable on failure) and, on the
  // first success, notifies its on-ready listeners once — the event the
  // push-listener arm rides (the third arm point in _MyAppState).
  final firebaseReadiness = FirebaseReadiness(
    initialize: () async {
      if (!isDesktop) {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: false,
              badge: false,
              sound: false,
            );
      }

      // 04-P0 / SI-5 (iOS): wire the recent-remote gate to also consume the NSE's
      // app-group sidecar dedupe markers, and persist the app-group container path
      // so the FCM background isolate can read it too.
      if (!kIsWeb && Platform.isIOS) {
        configureRecentRemoteNotificationGateForIos();
        unawaited(persistAppGroupContainerPathForGate());
      }
      StartupTiming.instance.mark('firebase_ready');
    },
    onError: (error, _) => debugPrint('Firebase init skipped: $error'),
  );
  Future<void> ensureFirebaseReady() => firebaseReadiness.ensureReady();

  // 164 (cold-start-1): Firebase is no longer initialized eagerly here. It is
  // initialized lazily inside the deferred startLiveServices, leaving the
  // pre-runApp critical path on a normal launch (matching the share-launch path
  // that already deferred Firebase). appDocDir was hoisted above to overlap with
  // the share-intent probe (cold-start-5).
  UserAvatar.setDocumentsDir(appDocDir.path);
  // 127 (round 3): seed the sync render-boundary resolver so MediaGridCell /
  // MediaThumbnailImage can turn a RELATIVE stored localPath into an absolute
  // one during build() — the durable fix for own-sent media "Media unavailable"
  // (the render gate, not just the send path, must resolve).
  MediaFileManager.cacheDocumentsDir(appDocDir.path);
  // 128 (round 4): build-identifying marker. Its PRESENCE in a device log proves
  // the installed binary contains the render-boundary fix + the cache is seeded;
  // its ABSENCE means a stale build (deploy gap), settling the 4-round ambiguity.
  emitFlowEvent(
    layer: 'FL',
    event: 'MEDIA_RENDER_RESOLVER_SEEDED',
    details: {'seeded': true},
  );
  StartupTiming.instance.mark('documents_dir_ready');

  // Initialize database based on platform
  if (isDesktop) {
    // Desktop platforms need FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 1. Create secure key store
  final secureKeyStore = FlutterSecureKeyStore();
  final SecureKeyStore? sharedPushKeyStore = !kIsWeb && Platform.isIOS
      ? FlutterSecureKeyStore(appleAccessGroup: mknoonSharedAppleAccessGroup)
      : null;
  final directReactionNotificationProjection = sharedPushKeyStore == null
      ? null
      : DirectReactionNotificationProjection(store: sharedPushKeyStore);
  final groupReactionNotificationProjection = sharedPushKeyStore == null
      ? null
      : GroupReactionNotificationProjection(store: sharedPushKeyStore);
  void Function()? notifyContactPushEligibilityChanged;
  // 229: install the process-wide auto-download policy so EVERY automatic
  // media transfer entry point (direct listener, direct visible-media
  // recovery, shared group loader) consults the user's persisted matrix +
  // current network class immediately before transferring.
  defaultMediaAutoDownloadDecider =
      PreferenceBackedMediaAutoDownloadDecider.fromSecureKeyStore(
        secureKeyStore: secureKeyStore,
      );
  final pushTokenStore = PushTokenStoreImpl(secureKeyStore: secureKeyStore);
  final pushRelayRegistrationProof = await loadPushRelayRegistrationProof();
  if (pushRelayRegistrationProof case final proof?) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_REGISTER_RELAY_PROOF_ARMED',
      details: proof.safeDetails(
        platform: Platform.isAndroid ? 'android' : 'ios',
      ),
    );
  }
  // FDC-09 §12 / CV-14: ONE shared sender-side received-wake-token store — the
  // receive leg (ContactRequestListener → handleIncomingMessage) writes it and
  // the send funnel (P2PServiceImpl.storeInInboxDetailed) reads it, so its
  // in-memory cache stays coherent across both.
  final receivedWakeTokenStore = ReceivedWakeTokenStoreImpl(
    secureKeyStore: secureKeyStore,
  );
  // FDC-09 §12 / CV-14 recipient leg: the {contact -> minted token} store this
  // node registers with the relay + distributes to contacts (send half).
  final wakeTokenStore = WakeTokenStoreImpl(secureKeyStore: secureKeyStore);
  final accountMigrationAuthorityRepository =
      SecureKeyStoreAccountMigrationAuthorityRepository(
        secureKeyStore: secureKeyStore,
      );
  final accountMigrationCutoverRepository =
      SecureKeyStoreMigrationCutoverRepository(secureKeyStore: secureKeyStore);
  final accountMigrationRuntimeNetworkGate = AccountMigrationRuntimeNetworkGate(
    authorityRepository: accountMigrationAuthorityRepository,
  );

  // 2. Open encrypted database (handles plaintext→encrypted migration)
  final db = await openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: 'identity.db',
    version: currentIdentityDatabaseVersion,
    // 228: both branches live in the shared, order-locked production registry
    // (production_migration_registry.dart) so tests and the SQLCipher device
    // proof run the LITERAL production sequences. Migration 005 stays deferred
    // to the post-open step below.
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
  );
  StartupTiming.instance.mark('database_ready');

  // 3. Run one-time secrets migration (DB → secure storage)
  //    Must run BEFORE migration 005 so CHECK constraints don't reject
  //    existing non-null secret values during the table rebuild.
  await migrateSecretsToSecureStorage(db: db, secureKeyStore: secureKeyStore);

  // 4. Apply CHECK constraints now that secret columns are guaranteed NULL
  await runSecretNullChecksMigration(db);
  await scrubLegacyGroupSecretsToSecureStorage(
    db: db,
    secureKeyStore: secureKeyStore,
  );
  StartupTiming.instance.mark('identity_store_ready');

  // 5. Create repository with database helpers + secure key store
  final repository = IdentityRepositoryImpl(
    dbLoadIdentityRow: () => dbLoadIdentityRow(db),
    dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
    secureKeyStore: secureKeyStore,
    pushSharedKeyStore: sharedPushKeyStore,
    directReactionProjection: directReactionNotificationProjection,
    groupReactionProjection: groupReactionNotificationProjection,
  );
  // Establish (or clear) projection ownership off the pre-runApp critical path.
  // Both group backfills and deferred Firebase/push eligibility await this
  // retained future below.
  final groupReactionProjectionIdentityReady = repository.loadIdentity();
  Future<bool> allowsAccountRuntimeNetworkSideEffects(String operation) async {
    final identity = await repository.loadIdentity();
    final allowed = await accountMigrationRuntimeNetworkGate
        .allowsAccountNetworkSideEffects(
          peerId: identity?.peerId,
          operation: operation,
        );
    if (!allowed) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_RUNTIME_NETWORK_ACTION_BLOCKED',
        details: {'operation': operation},
      );
    }
    return allowed;
  }

  Future<T> runAccountRuntimeNetworkAction<T>({
    required String operation,
    required T blockedValue,
    required Future<T> Function() action,
  }) async {
    if (!await allowsAccountRuntimeNetworkSideEffects(operation)) {
      return blockedValue;
    }
    return action();
  }

  Future<void> runAccountRuntimeNetworkVoidAction({
    required String operation,
    required Future<void> Function() action,
  }) async {
    if (!await allowsAccountRuntimeNetworkSideEffects(operation)) {
      return;
    }
    await action();
  }

  // Create contact repository
  final contactRepository = ContactRepositoryImpl(
    dbLoadAllContacts: () => dbLoadAllContacts(db),
    dbLoadContact: (peerId) => dbLoadContact(db, peerId),
    dbUpsertContact: (row) => dbUpsertContact(db, row),
    dbDeleteContact: (peerId) => dbDeleteContact(db, peerId),
    dbGetContactCount: () => dbGetContactCount(db),
    dbContactExists: (peerId) => dbContactExists(db, peerId),
    dbArchiveContact: (peerId) => dbArchiveContact(db, peerId),
    dbUnarchiveContact: (peerId) => dbUnarchiveContact(db, peerId),
    dbLoadActiveContacts: () => dbLoadActiveContacts(db),
    dbLoadArchivedContacts: () => dbLoadArchivedContacts(db),
    dbBlockContact: (peerId) => dbBlockContact(db, peerId),
    dbUnblockContact: (peerId) => dbUnblockContact(db, peerId),
    dbDismissIntroBanner: (peerId) => dbDismissIntroBanner(db, peerId),
    dbSetIntrosSentAt: (peerId, timestamp) =>
        dbSetIntrosSentAt(db, peerId, timestamp),
    directReactionProjection: directReactionNotificationProjection,
    onPushEligibilityChanged: () => notifyContactPushEligibilityChanged?.call(),
  );

  // Create contact request repository
  final contactRequestRepository = ContactRequestRepositoryImpl(
    dbLoadPendingRequests: () => dbLoadPendingRequests(db),
    dbLoadRequest: (peerId) => dbLoadRequest(db, peerId),
    dbUpsertRequest: (row) => dbUpsertRequest(db, row),
    dbUpdateRequestStatus: (peerId, status) =>
        dbUpdateRequestStatus(db, peerId, status),
    dbDeleteRequest: (peerId) => dbDeleteRequest(db, peerId),
    dbRequestExists: (peerId) => dbRequestExists(db, peerId),
  );

  // Create message repository
  final messageRepository = MessageRepositoryImpl(
    dbInsertMessage: (row) => dbInsertMessage(db, row),
    dbLoadMessagesForContact: (contactPeerId) =>
        dbLoadMessagesForContact(db, contactPeerId),
    dbLoadLatestMessageForContact: (contactPeerId) =>
        dbLoadLatestMessageForContact(db, contactPeerId),
    dbUpdateMessageStatus: (id, status) =>
        dbUpdateMessageStatus(db, id, status),
    dbLoadMessage: (id) => dbLoadMessage(db, id),
    dbCountMessagesForContact: (contactPeerId) =>
        dbCountMessagesForContact(db, contactPeerId),
    dbMarkConversationAsRead: (contactPeerId) =>
        dbMarkConversationAsRead(db, contactPeerId),
    dbCountUnreadForContact: (contactPeerId) =>
        dbCountUnreadForContact(db, contactPeerId),
    dbCountTotalUnread: () => dbCountTotalUnread(db),
    dbCountTotalUnreadExcludingArchived: () =>
        dbCountTotalUnreadExcludingArchived(db),
    dbDeleteMessagesForContact: (contactPeerId) =>
        dbDeleteMessagesForContact(db, contactPeerId),
    dbDeleteMessage: (id) => dbDeleteMessage(db, id),
    dbExistsMessageByContent: (contactPeerId, senderPeerId, text, timestamp) =>
        dbExistsMessageByContent(
          db,
          contactPeerId,
          senderPeerId,
          text,
          timestamp,
        ),
    dbExistsMessageByDedupKey: (contactPeerId, senderPeerId, dedupKey) =>
        dbExistsMessageByDedupKey(db, contactPeerId, senderPeerId, dedupKey),
    dbLoadMessagesPage: (contactPeerId, {limit = 50, beforeTimestamp}) =>
        dbLoadMessagesPage(
          db,
          contactPeerId,
          limit: limit,
          beforeTimestamp: beforeTimestamp,
        ),
    dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
    dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
        dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
    dbLoadInboxCustodyOutgoingMessages:
        ({required recheckOlderThan, limit = 50}) =>
            dbLoadInboxCustodyOutgoingMessages(
              db,
              recheckOlderThan: recheckOlderThan,
              limit: limit,
            ),
    dbMarkInboxCustodyChecked: (id, {relayExpiresAtMs}) =>
        dbMarkInboxCustodyChecked(db, id, relayExpiresAtMs: relayExpiresAtMs),
    dbRecoverStuckSendingMessages:
        ({required DateTime olderThan, int limit = 50}) =>
            dbRecoverStuckSendingMessages(
              db,
              olderThan: olderThan,
              limit: limit,
            ),
    dbUpdateWireEnvelope: (id, wireEnvelope) =>
        dbUpdateWireEnvelope(db, id, wireEnvelope),
    dbInvalidateWireEnvelopeBeforePrivateUpload:
        ({
          required messageId,
          required attachmentId,
          required expectedPendingLocalPath,
        }) => dbInvalidateWireEnvelopeBeforePrivateUpload(
          db,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedPendingLocalPath: expectedPendingLocalPath,
        ),
    dbMarkOutgoingDirectPrivateUploadHandoffFailed:
        ({
          required messageId,
          required attachmentId,
          required expectedPendingLocalPath,
        }) => dbMarkOutgoingDirectPrivateUploadHandoffFailed(
          db,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedPendingLocalPath: expectedPendingLocalPath,
        ),
    dbCommitOutgoingDirectPrivateWireEnvelope:
        (
          completionRow, {
          required expectedPendingLocalPath,
          required envelope,
          required hasOwnedPendingCompletion,
        }) => dbCommitOutgoingDirectPrivateWireEnvelope(
          db,
          completionRow,
          expectedPendingLocalPath: expectedPendingLocalPath,
          envelope: envelope,
          hasOwnedPendingCompletion: hasOwnedPendingCompletion,
        ),
    dbSettleOutgoingDirectPrivateTransport:
        ({
          required messageId,
          required attachmentId,
          required expectedEnvelope,
          required status,
          required transport,
          required relayExpiresAt,
        }) => dbSettleOutgoingDirectPrivateTransport(
          db,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedEnvelope: expectedEnvelope,
          status: status,
          transport: transport,
          relayExpiresAt: relayExpiresAt,
        ),
    dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstone:
        (expectedRow, tombstoneRow) =>
            dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstone(
              db,
              expectedRow,
              tombstoneRow,
            ),
    dbStageOutgoingDirectPrivateDeleteForEveryoneRetryEnvelope:
        (tombstoneRow, {required expectedEnvelope, required envelope}) =>
            dbStageOutgoingDirectPrivateDeleteForEveryoneRetryEnvelope(
              db,
              tombstoneRow,
              expectedEnvelope: expectedEnvelope,
              envelope: envelope,
            ),
    dbSettleOutgoingDirectPrivateDeleteForEveryoneTombstone:
        (tombstoneRow, {required expectedEnvelope}) =>
            dbSettleOutgoingDirectPrivateDeleteForEveryoneTombstone(
              db,
              tombstoneRow,
              expectedEnvelope: expectedEnvelope,
            ),
    dbLoadStuckSendingOutgoingMessages:
        ({required DateTime olderThan, int limit = 50}) =>
            dbLoadStuckSendingOutgoingMessages(
              db,
              olderThan: olderThan,
              limit: limit,
            ),
    dbLoadConversationThreadSummaries: (contactPeerIds) =>
        dbLoadConversationThreadSummaries(db, contactPeerIds),
    dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(db),
    dbConditionalTransitionStatus:
        (id, {required fromStatus, required toStatus}) =>
            dbConditionalTransitionStatus(
              db,
              id,
              fromStatus: fromStatus,
              toStatus: toStatus,
            ),
    dbProjectDirectUploadFailure:
        ({required messageId, required attachmentId, required disposition}) =>
            dbProjectDirectUploadFailure(
              db,
              messageId: messageId,
              attachmentId: attachmentId,
              disposition: disposition,
            ),
    dbRearmDirectUploadRetryForManualRetry:
        ({required messageId, required attachments}) =>
            dbRearmDirectUploadRetryForManualRetry(
              db,
              messageId: messageId,
              attachments: attachments,
            ),
    dbClaimDirectPrivateMediaOpening:
        (
          id, {
          required nowMs,
          isIncoming,
          mode,
          attachmentId,
          storedLocalPath,
        }) => dbClaimDirectPrivateMediaOpening(
          db,
          id,
          nowMs: nowMs,
          isIncoming: isIncoming,
          mode: mode,
          attachmentId: attachmentId,
          storedLocalPath: storedLocalPath,
        ),
    dbMarkDirectPrivateMediaViewing:
        (
          id, {
          required nowMs,
          isIncoming,
          mode,
          attachmentId,
          storedLocalPath,
        }) => dbMarkDirectPrivateMediaViewing(
          db,
          id,
          nowMs: nowMs,
          isIncoming: isIncoming,
          mode: mode,
          attachmentId: attachmentId,
          storedLocalPath: storedLocalPath,
        ),
    dbRollbackDirectPrivateMediaOpening:
        (id, {isIncoming, mode, attachmentId, storedLocalPath}) =>
            dbRollbackDirectPrivateMediaOpening(
              db,
              id,
              isIncoming: isIncoming,
              mode: mode,
              attachmentId: attachmentId,
              storedLocalPath: storedLocalPath,
            ),
    dbQuarantineIndeterminateDirectPrivateMediaAvailable:
        (
          id, {
          required isIncoming,
          required mode,
          required attachmentId,
          required storedLocalPath,
          required nowMs,
        }) => dbQuarantineIndeterminateDirectPrivateMediaAvailable(
          db,
          id,
          isIncoming: isIncoming,
          mode: mode,
          attachmentId: attachmentId,
          storedLocalPath: storedLocalPath,
          nowMs: nowMs,
        ),
    dbConsumeDirectPrivateMedia:
        (
          id, {
          required nowMs,
          isIncoming,
          mode,
          attachmentId,
          storedLocalPath,
        }) => dbConsumeDirectPrivateMedia(
          db,
          id,
          nowMs: nowMs,
          isIncoming: isIncoming,
          mode: mode,
          attachmentId: attachmentId,
          storedLocalPath: storedLocalPath,
        ),
    dbAdvanceDirectPrivateMediaClock: (id, {required nowMs}) =>
        dbAdvanceDirectPrivateMediaClock(db, id, nowMs: nowMs),
    dbFailClosedCorruptDirectPrivateMediaState: (id, {required nowMs}) =>
        dbFailClosedCorruptDirectPrivateMediaState(db, id, nowMs: nowMs),
    dbHideDirectPrivateMediaForMe: (id, {required hiddenAt, required nowMs}) =>
        dbHideDirectPrivateMediaForMe(db, id, hiddenAt: hiddenAt, nowMs: nowMs),
    dbLoadActiveDirectPrivateMediaDisappearing: ({limit = 100}) =>
        dbLoadActiveDirectPrivateMediaDisappearing(db, limit: limit),
    dbLoadDirectPrivateMediaRecoveryCandidates: ({limit = 100}) =>
        dbLoadDirectPrivateMediaRecoveryCandidates(db, limit: limit),
    dbRotateDirectPrivateMediaRecoveryCandidate: (id, {required nowMs}) =>
        dbRotateDirectPrivateMediaRecoveryCandidate(db, id, nowMs: nowMs),
    dbLoadNextDirectPrivateMediaExpiryAtMs: () =>
        dbLoadNextDirectPrivateMediaExpiryAtMs(db),
    directReactionProjection: directReactionNotificationProjection,
    dbLoadLocallyAuthoredMessagesForProjection: () =>
        dbLoadLocallyAuthoredMessagesForReactionProjection(db),
  );

  await groupReactionProjectionIdentityReady;
  await Future.wait([
    contactRepository.mirrorAllDirectReactionContacts(),
    messageRepository.mirrorAllDirectReactionAuthoredTargets(),
  ]);

  final inboxStagingRepository = InboxStagingRepositoryImpl(
    dbInsertInboxStagingEntry: (row) => dbInsertInboxStagingEntry(db, row),
    dbLoadRecoverableInboxStagingEntries: ({limit = 50, entryIds}) =>
        dbLoadRecoverableInboxStagingEntries(
          db,
          limit: limit,
          entryIds: entryIds,
        ),
    dbLoadInboxStagingEntry: (entryId) => dbLoadInboxStagingEntry(db, entryId),
    dbDeleteInboxStagingEntry: (entryId) =>
        dbDeleteInboxStagingEntry(db, entryId),
    dbMarkInboxStagingEntryRetryable:
        (entryId, {required reasonCode, reasonDetail}) =>
            dbMarkInboxStagingEntryRetryable(
              db,
              entryId,
              reasonCode: reasonCode,
              reasonDetail: reasonDetail,
            ),
    dbMarkInboxStagingEntryRejected:
        (entryId, {required reasonCode, reasonDetail}) =>
            dbMarkInboxStagingEntryRejected(
              db,
              entryId,
              reasonCode: reasonCode,
              reasonDetail: reasonDetail,
            ),
    dbMarkInboxStagingEntryQuarantined:
        (entryId, {required reasonCode, reasonDetail}) =>
            dbMarkInboxStagingEntryQuarantined(
              db,
              entryId,
              reasonCode: reasonCode,
              reasonDetail: reasonDetail,
            ),
    dbCountQuarantinedInboxStagingEntries: () =>
        dbCountQuarantinedInboxStagingEntries(db),
    dbCountNeedsAttentionInboxStagingEntries: () =>
        dbCountNeedsAttentionInboxStagingEntries(db),
  );

  final postRepository = PostRepositoryImpl(
    dbInsertPost: (row) => dbInsertPost(db, row),
    dbLoadPost: (postId) => dbLoadPost(db, postId),
    dbLoadPostsByIds: (postIds) => dbLoadPostsByIds(db, postIds),
    dbLoadPostsFeed: () => dbLoadPostsFeed(db),
    dbLoadRetryableOutgoingPosts: () => dbLoadRetryableOutgoingPosts(db),
    dbLoadExpiredPosts: (nowIso) => dbLoadExpiredPosts(db, nowIso),
    dbDeletePostCascade: (postId) => dbDeletePostCascade(db, postId),
    dbUpsertRecipientDelivery: (row) => dbUpsertPostRecipientDelivery(db, row),
    dbLoadRecipientDeliveries: (postId) =>
        dbLoadPostRecipientDeliveries(db, postId),
    dbLoadPostPassRecipientDeliveries: (passId) =>
        dbLoadPostPassRecipientDeliveries(db, passId),
    dbUpsertPostPass: (row) => dbUpsertPostPass(db, row),
    dbLoadPostPass: (passId) => dbLoadPostPass(db, passId),
    dbLoadPostPasses: (postId) => dbLoadPostPasses(db, postId),
    dbLoadRetryableOutgoingPostPasses: () =>
        dbLoadRetryableOutgoingPostPasses(db),
    dbCountPostPasses: (postId) => dbCountPostPasses(db, postId),
    dbLoadPostPassCounts: (postIds) => dbLoadPostPassCounts(db, postIds),
    dbLoadViewerSharedToCountsForPosts: (postIds, viewerPeerId) =>
        dbLoadViewerSharedToCountsForPosts(db, postIds, viewerPeerId),
    dbUpsertRepostEngagementParticipant: (row) =>
        dbUpsertPostRepostEngagementParticipant(db, row),
    dbLoadRepostEngagementParticipants: (postId) =>
        dbLoadPostRepostEngagementParticipants(db, postId),
    dbUpsertRepostHeartBaselinePeer: (row) =>
        dbUpsertPostRepostHeartBaselinePeer(db, row),
    dbLoadRepostHeartBaselinePeers: (postId) =>
        dbLoadPostRepostHeartBaselinePeers(db, postId),
    dbLoadRepostHeartBaselinePeersForPosts: (postIds) =>
        dbLoadPostRepostHeartBaselinePeersForPosts(db, postIds),
    dbInsertRepostProjectionState: (row) =>
        dbInsertPostRepostProjectionState(db, row),
    dbLoadRepostProjectionState: (postId) =>
        dbLoadPostRepostProjectionState(db, postId),
    dbLoadRepostProjectionStates: (postIds) =>
        dbLoadPostRepostProjectionStates(db, postIds),
    dbUpsertPostOrigin: (row) => dbUpsertPostOrigin(db, row),
    dbLoadPostOrigin: (postId) => dbLoadPostOrigin(db, postId),
    dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
    dbInsertPostComment: (row) => dbInsertPostComment(db, row),
    dbLoadPostComment: (commentId) => dbLoadPostComment(db, commentId),
    dbLoadPostComments: (postId) => dbLoadPostComments(db, postId),
    dbInsertPendingChildEvent: (row) => dbInsertPendingPostChildEvent(db, row),
    dbLoadPendingChildEvents: (postId) =>
        dbLoadPendingPostChildEvents(db, postId),
    dbDeletePendingChildEvent: (eventId) =>
        dbDeletePendingPostChildEvent(db, eventId),
    dbUpsertFollowOnOutboxEvent: (row) =>
        dbUpsertPostFollowOnOutboxEvent(db, row),
    dbLoadFollowOnOutboxEvent: (eventId) =>
        dbLoadPostFollowOnOutboxEvent(db, eventId),
    dbLoadRetryableFollowOnOutboxEvents: () =>
        dbLoadRetryablePostFollowOnOutboxEvents(db),
    dbUpsertFollowOnOutboxRecipientDelivery: (row) =>
        dbUpsertPostFollowOnOutboxRecipientDelivery(db, row),
    dbLoadFollowOnOutboxRecipientDeliveries: (eventId) =>
        dbLoadPostFollowOnOutboxRecipientDeliveries(db, eventId),
    dbLoadRetryableFollowOnOutboxRecipientDeliveries: (eventIds) =>
        dbLoadRetryablePostFollowOnOutboxRecipientDeliveries(db, eventIds),
    dbUpsertPostReaction: (row) => dbUpsertPostReaction(db, row),
    dbLoadPostReaction: (reactionId) => dbLoadPostReaction(db, reactionId),
    dbLoadPostReactions: (postId) => dbLoadPostReactions(db, postId),
    dbUpsertCommentReaction: (row) => dbUpsertPostCommentReaction(db, row),
    dbLoadCommentReaction: (reactionId) =>
        dbLoadPostCommentReaction(db, reactionId),
    dbLoadCommentReactions: (commentId) =>
        dbLoadPostCommentReactions(db, commentId),
    dbUpsertPostMedia: (row) => dbUpsertPostMediaAttachment(db, row),
    dbLoadPostMedia: (postId) => dbLoadPostMediaAttachments(db, postId),
    dbReplacePostMediaUploadRecoveryItems: (postId, rows) =>
        dbReplacePostMediaUploadRecoveryItems(db, postId, rows),
    dbLoadPostMediaUploadRecoveryItems: (postId) =>
        dbLoadPostMediaUploadRecoveryItems(db, postId),
    dbLoadPendingMediaUploadPosts: () => dbLoadPendingPostMediaUploadPosts(db),
    dbLoadPostMediaForPosts: (postIds) =>
        dbLoadPostMediaAttachmentsForPosts(db, postIds),
    dbUpdatePostMediaLocalPath: (mediaId, localPath) =>
        dbUpdatePostMediaLocalPath(db, mediaId, localPath),
    dbUpdatePostMediaDownloadStatus: (mediaId, downloadStatus) =>
        dbUpdatePostMediaDownloadStatus(db, mediaId, downloadStatus),
    dbReplacePostMedia: (postId, rows) =>
        dbReplacePostMediaAttachments(db, postId, rows),
    dbUpsertPostPinState: (row) => dbUpsertPostPinState(db, row),
    dbLoadPostPinState: (postId) => dbLoadPostPinState(db, postId),
    dbLoadActivePostPinStates: () => dbLoadActivePostPinStates(db),
    dbUpsertPinDismissal: (row) => dbUpsertPostPinDismissal(db, row),
    dbLoadPinDismissals: () => dbLoadPostPinDismissals(db),
    dbDeletePinDismissal: (postId) => dbDeletePostPinDismissal(db, postId),
    dbSavePassAvatarSnapshot: (postId, authorPeerId, avatarBlob, createdAt) =>
        dbSavePassAvatarSnapshot(
          db,
          postId,
          authorPeerId,
          avatarBlob,
          createdAt,
        ),
    dbLoadPassAvatarSnapshot: (postId) => dbLoadPassAvatarSnapshot(db, postId),
    dbLoadPassAvatarSnapshotsForPosts: (postIds) =>
        dbLoadPassAvatarSnapshotsForPosts(db, postIds),
  );

  final postsPrivacySettingsRepository = PostsPrivacySettingsRepositoryImpl(
    dbLoadPostPrivacyState: () => dbLoadPostPrivacyState(db),
    dbUpsertPostPrivacyState: (row) => dbUpsertPostPrivacyState(db, row),
  );

  // 134 (decision 2): persistence for the Feed pending-reply "cleared"
  // watermarks (the `feed_cleared_threads` table, migration 092).
  final FeedClearedRepository feedClearedRepository = FeedClearedRepositoryImpl(
    dbMarkFeedClearedThread: (kind, id, ms) =>
        dbMarkFeedClearedThread(db, kind, id, ms),
    dbClearFeedClearedThread: (kind, id) =>
        dbClearFeedClearedThread(db, kind, id),
    dbLoadFeedClearedThreads: () => dbLoadFeedClearedThreads(db),
  );
  late final NearbyLocationService nearbyLocationService;
  final contactPresenceSnapshotRepository =
      ContactPresenceSnapshotRepositoryImpl(
        dbLoadPostLocationPresence: (peerId) =>
            dbLoadPostLocationPresence(db, peerId),
        dbLoadAllPostLocationPresence: () => dbLoadAllPostLocationPresence(db),
        dbUpsertPostLocationPresence: (row) =>
            dbUpsertPostLocationPresence(db, row),
      );

  // Create media attachment repository (228: owner-lane-aware seams; the
  // save closure is the atomic local-state-preserving merge, never a blind
  // INSERT OR REPLACE).
  final mediaAttachmentRepository = MediaAttachmentRepositoryImpl(
    dbSaveMediaAttachmentPreservingLocalState: (row) =>
        dbSaveMediaAttachmentPreservingLocalState(db, row),
    dbLoadMediaForMessage: (messageId, ownerLane) =>
        dbLoadMediaForMessage(db, messageId, ownerLane: ownerLane),
    dbLoadMediaById: (id) => dbLoadMediaById(db, id),
    dbLoadMediaForMessages: (messageIds, ownerLane) =>
        dbLoadMediaForMessages(db, messageIds, ownerLane: ownerLane),
    dbLoadOutgoingDirectPrivateCommittedPendingCleanupCandidates:
        ({int limit = 50}) =>
            dbLoadOutgoingDirectPrivateCommittedPendingCleanupCandidates(
              db,
              limit: limit,
            ),
    dbUpdateMediaLocalPath: (id, localPath, downloadStatus) =>
        dbUpdateMediaLocalPath(db, id, localPath, downloadStatus),
    dbUpdateMediaDownloadStatus: (id, downloadStatus) =>
        dbUpdateMediaDownloadStatus(db, id, downloadStatus),
    dbDeleteMediaForMessage: (messageId, ownerLane) =>
        dbDeleteMediaForMessage(db, messageId, ownerLane: ownerLane),
    dbDeleteMediaForContact: (contactPeerId) =>
        dbDeleteMediaForContact(db, contactPeerId),
    dbMarkUploadPendingAttachmentsFailedForMessage: (messageId, ownerLane) =>
        dbMarkUploadPendingAttachmentsFailedForMessage(
          db,
          messageId,
          ownerLane: ownerLane,
        ),
    dbApplyOutgoingDirectPrivateNonCompletionMutation:
        (row, {required missingParentIsOrdinary}) =>
            dbApplyOutgoingDirectPrivateNonCompletionMutation(
              db,
              row,
              missingParentIsOrdinary: missingParentIsOrdinary,
            ),
    dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible: (rows) =>
        dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible(db, rows),
    dbQualifyOutgoingDirectPrivatePendingAttachmentsDeletion: (messageId) =>
        dbQualifyOutgoingDirectPrivatePendingAttachmentsDeletion(db, messageId),
    dbDeleteOutgoingDirectPrivatePendingAttachmentsIfEligible: (messageId) =>
        dbDeleteOutgoingDirectPrivatePendingAttachmentsIfEligible(
          db,
          messageId,
        ),
    dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
    dbLoadUploadPendingAttachments:
        ({int limit = 50, required String ownerLane}) =>
            dbLoadUploadPendingAttachments(
              db,
              limit: limit,
              ownerLane: ownerLane,
            ),
    dbSetMediaBookmarked: (id, bookmarked) =>
        dbSetMediaBookmarked(db, id, bookmarked: bookmarked),
    dbSetDirectMediaBookmarkedIfOrdinary:
        ({required messageId, required attachmentId, required bookmarked}) =>
            dbSetDirectMediaBookmarkedIfOrdinary(
              db,
              messageId: messageId,
              attachmentId: attachmentId,
              bookmarked: bookmarked,
            ),
    dbSetGroupMediaBookmarkedIfOrdinary:
        ({
          required groupId,
          required messageId,
          required attachmentId,
          required bookmarked,
        }) => dbSetGroupMediaBookmarkedIfOrdinary(
          db,
          groupId: groupId,
          messageId: messageId,
          attachmentId: attachmentId,
          bookmarked: bookmarked,
        ),
    dbUpdateMediaPlaybackPosition: (id, positionMs) =>
        dbUpdateMediaPlaybackPosition(db, id, positionMs),
    dbLoadMediaLibraryPage:
        ({
          required String scopeKind,
          required String scopeId,
          required List<String> mediaTypes,
          required bool bookmarkedOnly,
          required bool incomingOnly,
          required int limit,
          String? afterTimestamp,
          String? afterMessageId,
          String? afterAttachmentId,
        }) => dbLoadMediaLibraryPage(
          db,
          scopeKind: scopeKind,
          scopeId: scopeId,
          mediaTypes: mediaTypes,
          bookmarkedOnly: bookmarkedOnly,
          incomingOnly: incomingOnly,
          limit: limit,
          afterTimestamp: afterTimestamp,
          afterMessageId: afterMessageId,
          afterAttachmentId: afterAttachmentId,
        ),
    dbLoadMediaStoragePage:
        ({
          required String scopeKind,
          required String scopeId,
          required List<String> mediaTypes,
          required int limit,
          String? afterTimestamp,
          String? afterMessageId,
          String? afterAttachmentId,
        }) => dbLoadMediaStoragePage(
          db,
          scopeKind: scopeKind,
          scopeId: scopeId,
          mediaTypes: mediaTypes,
          limit: limit,
          afterTimestamp: afterTimestamp,
          afterMessageId: afterMessageId,
          afterAttachmentId: afterAttachmentId,
        ),
    dbBeginMediaDownload: (id, {required String ownerLane}) =>
        dbBeginMediaDownload(db, id, ownerLane: ownerLane),
    dbCommitMediaDownloadLocalPath:
        (id, {required String ownerLane, required String localPath}) =>
            dbCommitMediaDownloadLocalPath(
              db,
              id,
              ownerLane: ownerLane,
              localPath: localPath,
            ),
    dbClaimMediaEvicted:
        (id, {required String ownerLane, required String expectedLocalPath}) =>
            dbClaimMediaEvicted(
              db,
              id,
              ownerLane: ownerLane,
              expectedLocalPath: expectedLocalPath,
            ),
    dbFinalizeMediaEvictedPathCleared: (id, {required String ownerLane}) =>
        dbFinalizeMediaEvictedPathCleared(db, id, ownerLane: ownerLane),
    dbCommitDirectPrivateMediaDownloadIfEligible:
        ({
          required messageId,
          required attachmentId,
          required localPath,
          required nowMs,
        }) => dbCommitDirectPrivateMediaDownloadIfEligible(
          db,
          messageId: messageId,
          attachmentId: attachmentId,
          localPath: localPath,
          nowMs: nowMs,
        ),
    dbBeginDirectPrivateMediaDownloadIfEligible:
        ({required messageId, required attachmentId, required nowMs}) =>
            dbBeginDirectPrivateMediaDownloadIfEligible(
              db,
              messageId: messageId,
              attachmentId: attachmentId,
              nowMs: nowMs,
            ),
    dbQualifyDirectPrivateMediaLocalReadyIfEligible:
        ({
          required messageId,
          required attachmentId,
          required expectedLocalPath,
          required nowMs,
        }) => dbQualifyDirectPrivateMediaLocalReadyIfEligible(
          db,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedLocalPath: expectedLocalPath,
          nowMs: nowMs,
        ),
    dbRepairOutgoingDirectPrivateMediaDoneLocalPathIfEligible:
        ({
          required messageId,
          required attachmentId,
          required expectedStoredLocalPath,
          required canonicalLocalPath,
          required expectedContactPeerId,
          required expectedMime,
          required expectedSize,
        }) => dbRepairOutgoingDirectPrivateMediaDoneLocalPathIfEligible(
          db,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedStoredLocalPath: expectedStoredLocalPath,
          canonicalLocalPath: canonicalLocalPath,
          expectedContactPeerId: expectedContactPeerId,
          expectedMime: expectedMime,
          expectedSize: expectedSize,
        ),
    dbQualifyDirectPrivateMediaDownloadClaimIfEligible:
        ({required messageId, required attachmentId, required nowMs}) =>
            dbQualifyDirectPrivateMediaDownloadClaimIfEligible(
              db,
              messageId: messageId,
              attachmentId: attachmentId,
              nowMs: nowMs,
            ),
    dbRecordDirectPrivateMediaDownloadFailureIfEligible:
        ({
          required messageId,
          required attachmentId,
          required nowMs,
          required incrementRetryCount,
          required failureStatus,
          required expectedDownloadStatus,
          expectedLocalPath,
          clearLocalPath = false,
        }) => dbRecordDirectPrivateMediaDownloadFailureIfEligible(
          db,
          messageId: messageId,
          attachmentId: attachmentId,
          nowMs: nowMs,
          incrementRetryCount: incrementRetryCount,
          failureStatus: failureStatus,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
          clearLocalPath: clearLocalPath,
        ),
    dbSaveDirectPrivateMediaAttachmentGuarded:
        (row, {required messageId, required nowMs}) =>
            dbSaveDirectPrivateMediaAttachmentGuarded(
              db,
              row,
              messageId: messageId,
              nowMs: nowMs,
            ),
    dbCanCleanupDirectPrivateMediaAttachmentExact:
        ({required messageId, required attachmentId}) =>
            dbCanCleanupDirectPrivateMediaAttachmentExact(
              db,
              messageId: messageId,
              attachmentId: attachmentId,
            ),
    dbDeleteDirectPrivateMediaAttachmentExact:
        ({required messageId, required attachmentId}) =>
            dbDeleteDirectPrivateMediaAttachmentExact(
              db,
              messageId: messageId,
              attachmentId: attachmentId,
            ),
    dbClassifyOutgoingDirectPrivateMediaCompletion:
        (row, {required expectedPendingLocalPath}) =>
            dbClassifyOutgoingDirectPrivateMediaCompletion(
              db,
              row,
              expectedPendingLocalPath: expectedPendingLocalPath,
            ),
    dbCommitOutgoingDirectPrivateMediaAvailableCompletion:
        (row, {required expectedPendingLocalPath}) =>
            dbCommitOutgoingDirectPrivateMediaAvailableCompletion(
              db,
              row,
              expectedPendingLocalPath: expectedPendingLocalPath,
            ),
    dbRollbackOutgoingDirectPrivateMediaOpeningWithCompletion:
        (row, {required expectedPendingLocalPath, required mode}) =>
            dbRollbackOutgoingDirectPrivateMediaOpeningWithCompletion(
              db,
              row,
              expectedPendingLocalPath: expectedPendingLocalPath,
              mode: mode,
            ),
    dbBeginGroupPrivateMediaDownloadIfEligible:
        ({
          required groupId,
          required messageId,
          required attachmentId,
          required nowMs,
        }) => dbBeginGroupPrivateMediaDownloadIfEligible(
          db,
          groupId: groupId,
          messageId: messageId,
          attachmentId: attachmentId,
          nowMs: nowMs,
        ),
    dbQualifyGroupPrivateMediaLocalReadyIfEligible:
        ({
          required groupId,
          required messageId,
          required attachmentId,
          required expectedLocalPath,
          required nowMs,
        }) => dbQualifyGroupPrivateMediaLocalReadyIfEligible(
          db,
          groupId: groupId,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedLocalPath: expectedLocalPath,
          nowMs: nowMs,
        ),
    dbQualifyGroupPrivateMediaDownloadClaimIfEligible:
        ({
          required groupId,
          required messageId,
          required attachmentId,
          required nowMs,
        }) => dbQualifyGroupPrivateMediaDownloadClaimIfEligible(
          db,
          groupId: groupId,
          messageId: messageId,
          attachmentId: attachmentId,
          nowMs: nowMs,
        ),
    dbRecordGroupPrivateMediaDownloadFailureIfEligible:
        ({
          required groupId,
          required messageId,
          required attachmentId,
          required nowMs,
          required incrementRetryCount,
          required failureStatus,
          required expectedDownloadStatus,
          expectedLocalPath,
          required clearLocalPath,
        }) => dbRecordGroupPrivateMediaDownloadFailureIfEligible(
          db,
          groupId: groupId,
          messageId: messageId,
          attachmentId: attachmentId,
          nowMs: nowMs,
          incrementRetryCount: incrementRetryCount,
          failureStatus: failureStatus,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
          clearLocalPath: clearLocalPath,
        ),
    dbCommitGroupPrivateMediaDownloadIfEligible:
        ({
          required groupId,
          required messageId,
          required attachmentId,
          required localPath,
          required nowMs,
        }) => dbCommitGroupPrivateMediaDownloadIfEligible(
          db,
          groupId: groupId,
          messageId: messageId,
          attachmentId: attachmentId,
          localPath: localPath,
          nowMs: nowMs,
        ),
    dbCanCleanupGroupPrivateMediaAttachmentExact:
        ({required messageId, required attachmentId}) =>
            dbCanCleanupGroupPrivateMediaAttachmentExact(
              db,
              messageId: messageId,
              attachmentId: attachmentId,
            ),
    dbDeleteGroupPrivateMediaAttachmentExact:
        ({required messageId, required attachmentId}) =>
            dbDeleteGroupPrivateMediaAttachmentExact(
              db,
              messageId: messageId,
              attachmentId: attachmentId,
            ),
    dbSaveGroupMediaAttachmentGuarded: (row, {required String groupId}) =>
        dbSaveGroupMediaAttachmentGuarded(db, row, groupId: groupId),
    dbCompleteGroupUploadRetryExact:
        ({
          required expectedParent,
          required expectedAttachment,
          required completedAttachment,
        }) => dbCompleteGroupUploadRetry(
          db,
          expectedParent: expectedParent,
          expectedAttachment: expectedAttachment,
          completedAttachment: completedAttachment,
        ),
    secureKeyStore: secureKeyStore,
    refreshDirectPrivateMediaParent:
        messageRepository.refreshPrivateMediaLifecycleAfterExternalMutation,
  );

  // 235: deletion-journal reconciler + the production Delete-for-me
  // coordinator. The reconciler is the ONLY consumer of journal rows; it runs
  // post-delete, on cold start (unawaited, after runApp), and on resume
  // BEFORE the account-migration network gate.
  final groupMediaDeletionReconciler = GroupMediaDeletionJournalReconciler(
    loadJournalPage:
        ({
          required int limit,
          String? afterCreatedAt,
          String? afterAttachmentId,
        }) => dbLoadGroupMediaDeletionJournalPage(
          db,
          limit: limit,
          afterCreatedAt: afterCreatedAt,
          afterAttachmentId: afterAttachmentId,
        ),
    loadAttachmentRow: (attachmentId) => dbLoadMediaById(db, attachmentId),
    loadLocalDeletionGroupId: (messageId) async {
      final row = await dbLoadGroupMessageLocalDeletion(db, messageId);
      return row?['group_id'] as String?;
    },
    parentExists: ({required String messageId, required String groupId}) async {
      final rows = await db.query(
        'group_messages',
        columns: ['id'],
        where: 'id = ? AND group_id = ?',
        whereArgs: [messageId, groupId],
        limit: 1,
      );
      return rows.isNotEmpty;
    },
    finalizeEntry:
        ({required String attachmentId, required String messageId}) =>
            dbFinalizeGroupMediaDeletionJournalEntry(
              db,
              attachmentId: attachmentId,
              messageId: messageId,
            ),
    resolveStoredPath: (relativePath) =>
        MediaFileManager().resolveStoredPath(relativePath),
    secureKeyStore: secureKeyStore,
  );
  final deleteGroupMediaForMeUseCase = DeleteGroupMediaForMeUseCase(
    prepare:
        ({
          required String groupId,
          required String messageId,
          required String operationId,
        }) => dbPrepareGroupMediaDeleteForMe(
          db,
          groupId: groupId,
          messageId: messageId,
          operationId: operationId,
        ),
    runCleanup: () async {
      await groupMediaDeletionReconciler.runBounded();
    },
  );
  // Process-wide default (229 decider pattern): every group-conversation
  // entry path (orbit, feed, list, picker, notification route) gets the real
  // coordinator; explicit injection still wins.
  defaultGroupMediaDeleteForMeCoordinator = deleteGroupMediaForMeUseCase;

  // Create reaction repository
  final reactionRepository = ReactionRepositoryImpl(
    dbInsertReaction: (row) => dbInsertReaction(db, row),
    dbApplyIncomingAdd: (row) async {
      final result = await dbApplyIncomingReactionMutation(
        db,
        row,
        mutation: DbIncomingReactionMutation.add,
      );
      return switch (result) {
        DbIncomingReactionApplyResult.inserted =>
          ReactionAddApplyResult.inserted,
        DbIncomingReactionApplyResult.updated => ReactionAddApplyResult.updated,
        DbIncomingReactionApplyResult.exactReplay =>
          ReactionAddApplyResult.exactReplay,
        DbIncomingReactionApplyResult.stale => ReactionAddApplyResult.stale,
        DbIncomingReactionApplyResult.removed => throw StateError(
          'ADD transaction returned REMOVE result',
        ),
      };
    },
    dbApplyIncomingRemove: (row) async {
      final result = await dbApplyIncomingReactionMutation(
        db,
        row,
        mutation: DbIncomingReactionMutation.remove,
      );
      return switch (result) {
        DbIncomingReactionApplyResult.removed =>
          ReactionRemoveApplyResult.applied,
        DbIncomingReactionApplyResult.exactReplay =>
          ReactionRemoveApplyResult.exactReplay,
        DbIncomingReactionApplyResult.stale => ReactionRemoveApplyResult.stale,
        DbIncomingReactionApplyResult.inserted ||
        DbIncomingReactionApplyResult.updated => throw StateError(
          'REMOVE transaction returned ADD result',
        ),
      };
    },
    dbLoadReactionsForMessage: (messageId) =>
        dbLoadReactionsForMessage(db, messageId),
    dbLoadReactionsForMessages: (messageIds) =>
        dbLoadReactionsForMessages(db, messageIds),
    dbLoadActiveOrTombstonedReactionForSender: (messageId, senderPeerId) =>
        dbLoadActiveOrTombstonedReactionForSender(db, messageId, senderPeerId),
    dbDeleteReaction: (messageId, senderPeerId, {removedAtTimestamp}) =>
        dbDeleteReaction(
          db,
          messageId,
          senderPeerId,
          removedAtTimestamp: removedAtTimestamp,
        ),
    dbDeleteReactionsForMessage: (messageId) =>
        dbDeleteReactionsForMessage(db, messageId),
    dbDeleteReactionsForContact: (contactPeerId) =>
        dbDeleteReactionsForContact(db, contactPeerId),
    groupReactionProjection: groupReactionNotificationProjection,
    dbLoadGroupReactionComparandsForProjection:
        (accountPeerId, {limit = 1024}) =>
            dbLoadGroupReactionComparandsForProjection(
              db,
              accountPeerId,
              limit: limit,
            ),
  );

  final groupReactionReplayOutboxRepository =
      GroupReactionReplayOutboxRepositoryImpl(
        dbUpsertGroupReactionReplayOutboxEntry: (row) =>
            dbUpsertGroupReactionReplayOutboxEntry(db, row),
        dbLoadGroupReactionReplayOutboxEntry: (reactionId) =>
            dbLoadGroupReactionReplayOutboxEntry(db, reactionId),
        dbLoadLatestGroupReactionReplayOutboxEntryForTarget:
            ({required groupId, required messageId, required senderPeerId}) =>
                dbLoadLatestGroupReactionReplayOutboxEntryForTarget(
                  db,
                  groupId: groupId,
                  messageId: messageId,
                  senderPeerId: senderPeerId,
                ),
        dbLoadRetryableGroupReactionReplayOutboxEntries: ({limit = 20}) =>
            dbLoadRetryableGroupReactionReplayOutboxEntries(db, limit: limit),
        dbUpdateGroupReactionReplayOutboxEntryStatus:
            (
              reactionId, {
              required deliveryStatus,
              lastError,
              required updatedAt,
            }) => dbUpdateGroupReactionReplayOutboxEntryStatus(
              db,
              reactionId,
              deliveryStatus: deliveryStatus,
              lastError: lastError,
              updatedAt: updatedAt,
            ),
        dbUpdateGroupReactionReplayOutboxEntryStatusIfExact:
            ({
              required expected,
              required deliveryStatus,
              lastError,
              required updatedAt,
            }) => dbUpdateGroupReactionReplayOutboxEntryStatusIfExact(
              db,
              expected: expected,
              deliveryStatus: deliveryStatus,
              lastError: lastError,
              updatedAt: updatedAt,
            ),
        dbDeleteGroupReactionReplayOutboxEntry: (reactionId) =>
            dbDeleteGroupReactionReplayOutboxEntry(db, reactionId),
      );

  // Create group repository
  final groupRepository = GroupRepositoryImpl(
    dbInsertGroup: (row) => dbInsertGroup(db, row),
    dbLoadAllGroups: () => dbLoadAllGroups(db),
    dbLoadGroup: (id) => dbLoadGroup(db, id),
    dbUpdateGroup: (row) => dbUpdateGroup(db, row),
    dbDeleteGroup: (id) => dbDeleteGroup(db, id),
    dbLoadActiveGroups: () => dbLoadActiveGroups(db),
    dbArchiveGroup: (id) => dbArchiveGroup(db, id),
    dbUnarchiveGroup: (id) => dbUnarchiveGroup(db, id),
    dbAdvanceGroupMembershipWatermark:
        ({required groupId, required eventAt, required eventId}) =>
            dbAdvanceGroupMembershipWatermark(
              db,
              groupId: groupId,
              eventAt: eventAt,
              eventId: eventId,
            ),
    dbLoadGroupForwardAuthorizationSnapshot: (groupId) =>
        dbLoadGroupForwardAuthorizationSnapshot(db, groupId),
    dbInsertGroupMember: (row) => dbInsertGroupMember(db, row),
    dbLoadAllGroupMembers: (groupId) => dbLoadAllGroupMembers(db, groupId),
    dbLoadGroupMember: (groupId, peerId) =>
        dbLoadGroupMember(db, groupId, peerId),
    dbUpdateGroupMemberRole: (groupId, peerId, role) =>
        dbUpdateGroupMemberRole(db, groupId, peerId, role),
    dbDeleteGroupMember: (groupId, peerId) =>
        dbDeleteGroupMember(db, groupId, peerId),
    dbDeleteAllGroupMembers: (groupId) => dbDeleteAllGroupMembers(db, groupId),
    dbInsertRemovedGroupMemberSnapshot: (row, removedAt) =>
        dbInsertRemovedGroupMemberSnapshot(db, row, removedAt),
    dbLoadRemovedGroupMemberSnapshot: (groupId, peerId) =>
        dbLoadRemovedGroupMemberSnapshot(db, groupId, peerId),
    dbUpsertGroupMemberDeviceSnapshot: (row, savedAt) =>
        dbUpsertGroupMemberDeviceSnapshot(db, row, savedAt),
    dbLoadGroupMemberDeviceSnapshot: (groupId, peerId) =>
        dbLoadGroupMemberDeviceSnapshot(db, groupId, peerId),
    dbUpsertPendingSiblingDevice: (row) =>
        dbUpsertPendingSiblingDevice(db, row),
    dbLoadPendingSiblingDevicesForGroup: (groupId) =>
        dbLoadPendingSiblingDevicesForGroup(db, groupId),
    dbLoadPendingSiblingDevice: (groupId, memberPeerId, deviceId) =>
        dbLoadPendingSiblingDevice(db, groupId, memberPeerId, deviceId),
    dbDeletePendingSiblingDevice: (groupId, memberPeerId, deviceId) =>
        dbDeletePendingSiblingDevice(db, groupId, memberPeerId, deviceId),
    dbLoadGroupRejoinStatesFn: () => dbLoadGroupRejoinStates(db),
    dbRecordGroupRejoinFailureFn: (groupId, {required nextEligibleAtMs}) =>
        dbRecordGroupRejoinFailure(
          db,
          groupId,
          nextEligibleAtMs: nextEligibleAtMs,
        ),
    dbClearGroupRejoinStateFn: (groupId) =>
        dbClearGroupRejoinState(db, groupId),
    dbForceGroupRejoinEligibleFn: (groupId) =>
        dbForceGroupRejoinEligible(db, groupId),
    dbInsertGroupKey: (row) => dbInsertGroupKey(db, row),
    dbLoadLatestGroupKey: (groupId) => dbLoadLatestGroupKey(db, groupId),
    dbLoadGroupKeyByGeneration: (groupId, generation) =>
        dbLoadGroupKeyByGeneration(db, groupId, generation),
    dbDeleteAllGroupKeys: (groupId) => dbDeleteAllGroupKeys(db, groupId),
    dbLoadAllGroupKeys: (groupId) => dbLoadAllGroupKeys(db, groupId),
    dbDeleteGroupKeysBeforeGeneration: (groupId, minKeyGenerationToKeep) =>
        dbDeleteGroupKeysBeforeGeneration(db, groupId, minKeyGenerationToKeep),
    dbUpsertPendingGroupKeyRotation: (row) =>
        dbUpsertPendingGroupKeyRotation(db, row),
    dbLoadPendingGroupKeyRotation: (groupId) =>
        dbLoadPendingGroupKeyRotation(db, groupId),
    dbDeletePendingGroupKeyRotation: (groupId, keyGeneration) =>
        dbDeletePendingGroupKeyRotation(db, groupId, keyGeneration),
    dbDeletePendingGroupKeyRotations: (groupId) =>
        dbDeletePendingGroupKeyRotations(db, groupId),
    groupKeyStore: secureKeyStore,
    pushSharedKeyStore: sharedPushKeyStore,
    groupReactionProjection: groupReactionNotificationProjection,
    dbHasGroupExitCleanupPending: (groupId) async {
      final row = await dbLoadGroupExitIntentForGroup(db, groupId);
      return row?['state'] == 'cleanup_pending';
    },
    selfRemovedShellAuthorityEnabled: true,
    dbLoadSelfRemovedGroupShellAuthority:
        ({required groupId, required selfPeerId}) =>
            dbLoadSelfRemovedGroupShellAuthoritySnapshot(
              db,
              groupId: groupId,
              selfPeerId: selfPeerId,
            ),
    dbCommitSelfRemovalAuthorityFn:
        ({required expected, required removalAt, required removalEventId}) =>
            dbCommitSelfRemovalAuthority(
              db,
              expected: expected,
              removalAt: removalAt,
              removalEventId: removalEventId,
            ),
    dbLoadRawSelfRemovedGroupKeyReferencesFn: ({required expected}) =>
        dbLoadRawSelfRemovedGroupKeyReferences(db, expected: expected),
    dbFinalizeSelfRemovedGroupKeyReferencesFn:
        ({required expected, required expectedReferences}) =>
            dbFinalizeSelfRemovedGroupKeyReferences(
              db,
              expected: expected,
              expectedReferences: expectedReferences,
            ),
    dbLoadSelfRemovedGroupMediaParentsFn:
        ({required expected, required limit}) =>
            dbLoadSelfRemovedGroupMediaParents(
              db,
              expected: expected,
              limit: limit,
            ),
    dbAppendSelfRemovedGroupFreshnessFloorFn: ({required expected}) =>
        dbAppendSelfRemovedGroupFreshnessFloor(db, expected: expected),
    dbLoadSelfRemovedGroupFreshnessFloorFn: (groupId) =>
        dbLoadLatestSelfRemovedGroupFreshnessFloor(db, groupId),
    dbPrepareSelfRemovedGroupAcceptedReentryFn:
        ({
          required groupRow,
          required rosterRows,
          required stagedKeyRow,
          required selfPeerId,
          required authorizationId,
          required signedMembershipWatermark,
          required signedIssuedAt,
          required bindingNonce,
        }) => dbPrepareSelfRemovedGroupAcceptedReentry(
          db,
          groupRow: groupRow,
          rosterRows: rosterRows,
          stagedKeyRow: stagedKeyRow,
          selfPeerId: selfPeerId,
          authorizationId: authorizationId,
          signedMembershipWatermark: signedMembershipWatermark,
          signedIssuedAt: signedIssuedAt,
          bindingNonce: bindingNonce,
        ),
    dbStageSelfRemovedGroupAcceptedReentryKeyFn:
        ({required preparation, required stagedKeyRow}) =>
            dbStageSelfRemovedGroupAcceptedReentryKey(
              db,
              preparation: preparation,
              stagedKeyRow: stagedKeyRow,
            ),
    dbCommitSelfRemovedGroupAcceptedReentryFn:
        ({
          required preparation,
          required groupRow,
          required rosterRows,
          required stagedKeyRow,
          required selfPeerId,
          required authorizationId,
          required signedMembershipWatermark,
          required signedIssuedAt,
          required bindingNonce,
        }) => dbCommitSelfRemovedGroupAcceptedReentry(
          db,
          preparation: preparation,
          groupRow: groupRow,
          rosterRows: rosterRows,
          stagedKeyRow: stagedKeyRow,
          selfPeerId: selfPeerId,
          authorizationId: authorizationId,
          signedMembershipWatermark: signedMembershipWatermark,
          signedIssuedAt: signedIssuedAt,
          bindingNonce: bindingNonce,
        ),
    dbFinalizeSelfRemovedGroupAcceptedReentryStagingFn:
        ({required preparation, required stagedKeyRow}) =>
            dbFinalizeSelfRemovedGroupAcceptedReentryStaging(
              db,
              preparation: preparation,
              stagedKeyRow: stagedKeyRow,
            ),
    dbFinalizeSelfRemovedGroupAcceptedRollbackKeyFn:
        ({required groupId, required selfPeerId, required binding}) =>
            dbFinalizeSelfRemovedGroupAcceptedRollbackKey(
              db,
              groupId: groupId,
              selfPeerId: selfPeerId,
              binding: binding,
            ),
    dbRollbackSelfRemovedGroupAcceptedReentryFn:
        ({
          required groupId,
          required selfPeerId,
          required authorizationId,
          required qualification,
        }) => dbRollbackSelfRemovedGroupAcceptedReentry(
          db,
          groupId: groupId,
          selfPeerId: selfPeerId,
          authorizationId: authorizationId,
          qualification: qualification,
        ),
    dbQualifySelfRemovedGroupAcceptedRollbackFn:
        ({required groupId, required selfPeerId, required authorizationId}) =>
            dbQualifySelfRemovedGroupAcceptedRollback(
              db,
              groupId: groupId,
              selfPeerId: selfPeerId,
              authorizationId: authorizationId,
            ),
    dbPrepareFreshAcceptedMaterializationRollbackFn:
        ({
          required groupId,
          required selfPeerId,
          required keyGeneration,
          required expectedMembershipAt,
          required expectedMetadataAt,
        }) => dbPrepareFreshAcceptedMaterializationRollback(
          db,
          groupId: groupId,
          selfPeerId: selfPeerId,
          keyGeneration: keyGeneration,
          expectedMembershipAt: expectedMembershipAt,
          expectedMetadataAt: expectedMetadataAt,
        ),
    dbCommitFreshAcceptedMaterializationRollbackFn: ({required preparation}) =>
        dbCommitFreshAcceptedMaterializationRollback(
          db,
          preparation: preparation,
        ),
    dbAuthorizeSelfRemovedGroupAcceptedReentryRetryFn:
        ({
          required groupId,
          required selfPeerId,
          required authorizationId,
          required signedMembershipWatermark,
          required signedIssuedAt,
          required keyGeneration,
        }) => dbAuthorizeSelfRemovedGroupAcceptedReentryRetry(
          db,
          groupId: groupId,
          selfPeerId: selfPeerId,
          authorizationId: authorizationId,
          signedMembershipWatermark: signedMembershipWatermark,
          signedIssuedAt: signedIssuedAt,
          keyGeneration: keyGeneration,
        ),
    dbPurgeSelfRemovedGroupShellFn:
        ({required expected, required floor, required deletedAt}) =>
            dbPurgeSelfRemovedGroupShell(
              db,
              expected: expected,
              floor: floor,
              deletedAt: deletedAt,
            ),
  );
  var selfRemovedShellOperationSequence = 0;
  final deleteSelfRemovedGroupShellUseCase = DeleteSelfRemovedGroupShellUseCase(
    repository: groupRepository,
    prepareMedia:
        ({
          required String groupId,
          required String messageId,
          required String operationId,
        }) => dbPrepareGroupMediaDeleteForMe(
          db,
          groupId: groupId,
          messageId: messageId,
          operationId: operationId,
        ),
    runMediaReconciler: groupMediaDeletionReconciler.runBounded,
    snapshotAvatarPath: (groupId) async {
      final group = await groupRepository.getGroup(groupId);
      return group?.avatarPath ?? groupAvatarRelativePath(groupId);
    },
    deleteAvatar: (path) => deleteGroupAvatar(storedPath: path),
    operationIdFactory: () {
      selfRemovedShellOperationSequence++;
      return 'self-removed-shell:'
          '${DateTime.now().toUtc().microsecondsSinceEpoch}:'
          '$selfRemovedShellOperationSequence';
    },
  );
  defaultDeleteSelfRemovedGroupShell = deleteSelfRemovedGroupShellUseCase.call;
  // 164 (cold-start-3): the shared-Keychain mirror backfill (every group key ×
  // generation + every mute projection, re-written on every launch) is unbounded
  // work that scales with group history. Move it OFF the pre-runApp critical path
  // while keeping it guaranteed-to-run: a retained top-level future, started
  // immediately but not awaited. The presence-diff in _mirrorGroupKeyForPush /
  // _mirrorGroupMutedForPush makes a re-run on an already-populated projection a
  // near-zero-write no-op. (04-P0 SI-1 NSE: the mute backfill self-heals groups
  // muted before that feature shipped; iOS NSE preview decrypt depends on the key
  // mirror eventually being complete.)
  keychainMirrorBackfill = () async {
    await groupReactionProjectionIdentityReady;
    await groupRepository.mirrorAllKeysToSecureStore();
    await groupRepository.mirrorAllMutedGroups();
    await groupRepository.mirrorAllGroupReactionNotificationContexts();
  }();

  final pendingGroupInviteRepository = PendingGroupInviteRepositoryImpl(
    dbUpsertPendingGroupInvite: (row) => dbUpsertPendingGroupInvite(db, row),
    dbLoadPendingGroupInvites: () => dbLoadPendingGroupInvites(db),
    dbLoadPendingGroupInvite: (groupId) =>
        dbLoadPendingGroupInvite(db, groupId),
    dbUpsertGroupInviteRevocation: (row) =>
        dbUpsertGroupInviteRevocation(db, row),
    dbLoadGroupInviteRevocation: (inviteId) =>
        dbLoadGroupInviteRevocation(db, inviteId),
    dbUpsertGroupInviteConsumption: (row) =>
        dbUpsertGroupInviteConsumption(db, row),
    dbLoadGroupInviteConsumption: (inviteId) =>
        dbLoadGroupInviteConsumption(db, inviteId),
    dbUpsertGroupWelcomeKeyPackageTombstone: (row) =>
        dbUpsertGroupWelcomeKeyPackageTombstone(db, row),
    dbLoadGroupWelcomeKeyPackageTombstone:
        ({required packageId, required recipientDeviceId, required groupId}) =>
            dbLoadGroupWelcomeKeyPackageTombstone(
              db,
              packageId: packageId,
              recipientDeviceId: recipientDeviceId,
              groupId: groupId,
            ),
    dbDeletePendingGroupInvite: (groupId) =>
        dbDeletePendingGroupInvite(db, groupId),
    dbDeleteExpiredPendingGroupInvites: (cutoff) =>
        dbDeleteExpiredPendingGroupInvites(db, cutoff),
    dbDeleteExpiredGroupInviteRevocations: (cutoff) =>
        dbDeleteExpiredGroupInviteRevocations(db, cutoff),
    dbDeleteExpiredGroupInviteConsumptions: (cutoff) =>
        dbDeleteExpiredGroupInviteConsumptions(db, cutoff),
    dbDeleteExpiredGroupWelcomeKeyPackageTombstones: (cutoff) =>
        dbDeleteExpiredGroupWelcomeKeyPackageTombstones(db, cutoff),
  );

  final groupInviteDeliveryAttemptRepository =
      GroupInviteDeliveryAttemptRepositoryImpl(
        dbUpsertGroupInviteDeliveryAttempt: (row) =>
            dbUpsertGroupInviteDeliveryAttempt(db, row),
        dbLoadGroupInviteDeliveryAttempt:
            ({required groupId, required peerId}) =>
                dbLoadGroupInviteDeliveryAttempt(
                  db,
                  groupId: groupId,
                  peerId: peerId,
                ),
        dbLoadGroupInviteDeliveryAttemptsForGroup: (groupId) =>
            dbLoadGroupInviteDeliveryAttemptsForGroup(db, groupId),
        dbUpdateGroupInviteDeliveryAttemptStatus:
            ({
              required groupId,
              required peerId,
              required status,
              required updatedAt,
            }) => dbUpdateGroupInviteDeliveryAttemptStatus(
              db,
              groupId: groupId,
              peerId: peerId,
              status: status,
              updatedAt: updatedAt,
            ),
        dbDeleteGroupInviteDeliveryAttempt:
            ({required groupId, required peerId}) =>
                dbDeleteGroupInviteDeliveryAttempt(
                  db,
                  groupId: groupId,
                  peerId: peerId,
                ),
        dbDeleteGroupInviteDeliveryAttemptsForGroup: (groupId) =>
            dbDeleteGroupInviteDeliveryAttemptsForGroup(db, groupId),
      );

  GroupMessageRepositoryImpl createGroupMessageRepository(
    dynamic executor, {
    bool enableInboxPageTransactions = false,
    bool enableReactionProjection = false,
  }) {
    return GroupMessageRepositoryImpl(
      dbInsertGroupMessage: (row) => dbInsertGroupMessage(executor, row),
      dbInsertExactSelfRemovalTimelineMessageFn:
          (row, {required expectedSelfRemovedAt}) =>
              dbInsertExactSelfRemovalTimelineMessage(
                executor,
                row,
                expectedSelfRemovedAt: expectedSelfRemovedAt,
              ),
      dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) =>
          dbLoadGroupMessagesPage(
            executor,
            groupId,
            limit: limit,
            offset: offset,
          ),
      dbLoadGroupMessagesAroundFn:
          (groupId, anchorMessageId, {before = 25, after = 25}) =>
              dbLoadGroupMessagesAround(
                executor,
                groupId,
                anchorMessageId,
                before: before,
                after: after,
              ),
      dbLoadGroupMessage: (id) => dbLoadGroupMessage(executor, id),
      dbLoadGroupMessageByLogicalDeliveryIdFn:
          (groupId, senderPeerId, logicalDeliveryId) =>
              dbLoadGroupMessageByLogicalDeliveryId(
                executor,
                groupId,
                senderPeerId,
                logicalDeliveryId,
              ),
      dbLoadLatestGroupMessage: (groupId) =>
          dbLoadLatestGroupMessage(executor, groupId),
      dbLoadLatestRemovalTimestampForSenderFn: (groupId, senderPeerId) =>
          dbLoadLatestGroupRemovalTimestampForSender(
            executor,
            groupId,
            senderPeerId,
          ),
      dbUpdateGroupMessageStatus: (id, status) =>
          dbUpdateGroupMessageStatus(executor, id, status),
      dbCountGroupMessages: (groupId) =>
          dbCountGroupMessages(executor, groupId),
      dbCountUnreadGroupMessages: (groupId) =>
          dbCountUnreadGroupMessages(executor, groupId),
      dbCountTotalUnreadGroupMessages: () =>
          dbCountTotalUnreadGroupMessages(executor),
      dbMarkGroupMessagesAsRead: (groupId) =>
          dbMarkGroupMessagesAsRead(executor, groupId),
      dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(executor, id),
      dbDeleteGroupMessageForMembershipRepairFn: (id) =>
          dbDeleteGroupMessageForMembershipRepair(executor, id),
      dbExistsGroupMessageByContent: (groupId, senderPeerId, text, timestamp) =>
          dbExistsGroupMessageByContent(
            executor,
            groupId,
            senderPeerId,
            text,
            timestamp,
          ),
      dbDeleteGroupMessagesForGroup: (groupId) =>
          dbDeleteGroupMessagesForGroup(executor, groupId),
      dbLoadGroupThreadSummaries: (groupIds) =>
          dbLoadGroupThreadSummaries(executor, groupIds),
      dbLoadGroupThreadPreviewsFn: (groupIds) =>
          dbLoadGroupThreadPreviews(executor, groupIds),
      dbLoadFailedOutgoingGroupMessagesFn: () =>
          dbLoadFailedOutgoingGroupMessages(executor),
      dbLoadRetryableOutgoingGroupMessagesFn: () =>
          dbLoadRetryableOutgoingGroupMessages(executor),
      dbRecoverStuckSendingGroupMessagesFn: ({DateTime? olderThan}) =>
          dbTransitionGroupSendingToFailed(executor, olderThan: olderThan),
      dbProjectGroupUploadFailureFn: executor is Database
          ? ({
              required messageId,
              required attachmentId,
              required disposition,
            }) => dbProjectGroupUploadFailure(
              executor,
              messageId: messageId,
              attachmentId: attachmentId,
              disposition: disposition,
            )
          : null,
      dbCompleteGroupUploadRetryFn: executor is Database
          ? ({
              required expectedParent,
              required expectedAttachment,
              required completedAttachment,
            }) => dbCompleteGroupUploadRetry(
              executor,
              expectedParent: expectedParent,
              expectedAttachment: expectedAttachment,
              completedAttachment: completedAttachment,
            )
          : null,
      completeGroupUploadRetrySecurelyFn: executor is Database
          ? ({
              required expectedParent,
              required expectedAttachment,
              required completedAttachment,
            }) => mediaAttachmentRepository.completeGroupUploadRetrySecurely(
              expectedParent: <String, Object?>{
                ...expectedParent.toMap(),
                'retry_attempt_count': expectedParent.retryAttemptCount,
                'next_eligible_at': expectedParent.nextEligibleAt
                    ?.toUtc()
                    .millisecondsSinceEpoch,
              },
              expectedAttachment: expectedAttachment,
              completedAttachment: completedAttachment,
            )
          : null,
      dbRearmGroupUploadRetryForManualRetryFn: executor is Database
          ? ({required messageId, required attachments}) =>
                dbRearmGroupUploadRetryForManualRetry(
                  executor,
                  messageId: messageId,
                  attachments: attachments,
                )
          : null,
      dbLoadGroupMessagesWithFailedInboxStore: ({int limit = 50}) =>
          dbLoadGroupMessagesWithFailedInboxStore(executor, limit: limit),
      dbUpdateGroupMessageInboxStoredFn: (id, {required bool stored}) =>
          dbUpdateGroupMessageInboxStored(executor, id, stored: stored),
      dbUpdateGroupMessageInboxRetryPayloadFn: (id, payload) =>
          dbUpdateGroupMessageInboxRetryPayload(executor, id, payload),
      dbUpdateGroupMessageWireEnvelopeFn: (id, envelope) =>
          dbUpdateGroupMessageWireEnvelope(executor, id, envelope),
      dbCompleteGroupInboxStoreRetryFn: executor is Database
          ? (expected) => dbCompleteGroupInboxStoreRetry(executor, expected)
          : null,
      dbRecordGroupMessageRetryFailureFn:
          (id, {required nextEligibleAtMs, required markTerminal}) =>
              dbRecordGroupMessageRetryFailure(
                executor,
                id,
                nextEligibleAtMs: nextEligibleAtMs,
                markTerminal: markTerminal,
              ),
      dbClearGroupMessageRetryBackoffFn: () =>
          dbClearGroupMessageRetryBackoff(executor),
      dbResetGroupMessageRetryStateFn: (id) =>
          dbResetGroupMessageRetryState(executor, id),
      dbAnchorOutgoingGroupPrivateMediaCustodyFn: (id, {required nowMs}) =>
          dbAnchorOutgoingGroupPrivateMediaCustody(executor, id, nowMs: nowMs),
      dbConsumeGroupPrivateMediaFn: (id, {required nowMs}) =>
          dbConsumeGroupPrivateMedia(executor, id, nowMs: nowMs),
      dbAdvanceGroupPrivateMediaClockFn: (id, {required nowMs}) =>
          dbAdvanceGroupPrivateMediaClock(executor, id, nowMs: nowMs),
      dbLoadNextGroupPrivateMediaExpiryAtMsFn: () =>
          dbLoadNextGroupPrivateMediaExpiryAtMs(executor),
      dbLoadActiveGroupPrivateMediaDisappearingFn: ({int limit = 100}) =>
          dbLoadActiveGroupPrivateMediaDisappearing(executor, limit: limit),
      dbLoadGroupPrivateMediaRecoveryCandidatesFn: ({int limit = 100}) =>
          dbLoadGroupPrivateMediaRecoveryCandidates(executor, limit: limit),
      dbRotateGroupPrivateMediaRecoveryCandidateFn: (id, {required nowMs}) =>
          dbRotateGroupPrivateMediaRecoveryCandidate(
            executor,
            id,
            nowMs: nowMs,
          ),
      dbCompleteGroupPrivateMediaCleanupFn: (id) =>
          dbCompleteGroupPrivateMediaCleanup(executor, id),
      dbLoadGroupMessageLocalDeletionFn: (messageId) =>
          dbLoadGroupMessageLocalDeletion(executor, messageId),
      dbLoadGroupInboxCursorFn: (groupId) async {
        final row = await dbLoadGroupInboxCursor(executor, groupId);
        return row?['cursor'] as String?;
      },
      dbLoadGroupMessageReceiptsFn:
          (groupId, messageId, {String? receiptType}) =>
              dbLoadGroupMessageReceipts(
                executor,
                groupId: groupId,
                messageId: messageId,
                receiptType: receiptType,
              ),
      dbRunGroupInboxPageTransactionFn: enableInboxPageTransactions
          ? ({
              required groupId,
              required nextCursor,
              required apply,
              required receipts,
              required markReadMessageIds,
            }) {
              return dbApplyGroupInboxPageTransaction(
                db,
                groupId: groupId,
                nextCursor: nextCursor,
                receiptRows: () =>
                    receipts.map((receipt) => receipt.toMap()).toList(),
                markReadMessageIds: () => markReadMessageIds,
                apply: (transactionExecutor) {
                  final transactionRepo = createGroupMessageRepository(
                    transactionExecutor,
                  );
                  return apply(transactionRepo);
                },
              );
            }
          : null,
      groupReactionProjection: enableReactionProjection
          ? groupReactionNotificationProjection
          : null,
      dbLoadAuthoredGroupMessagesForProjectionFn: enableReactionProjection
          ? (accountPeerId, {limit = 256}) =>
                dbLoadAuthoredGroupMessagesForProjection(
                  executor,
                  accountPeerId,
                  limit: limit,
                )
          : null,
    );
  }

  // Create group message repository
  final groupMessageRepository = createGroupMessageRepository(
    db,
    enableInboxPageTransactions: true,
    enableReactionProjection: true,
  );
  final groupReactionAuthoredTargetBackfill = () async {
    await groupReactionProjectionIdentityReady;
    await groupMessageRepository.mirrorAllGroupReactionAuthoredTargets();
  }();
  final groupReactionComparandBackfill = () async {
    await groupReactionAuthoredTargetBackfill;
    await reactionRepository.mirrorAllGroupReactionNotificationComparands();
  }();

  final groupPendingKeyRepairRepository = GroupPendingKeyRepairRepositoryImpl(
    dbUpsertGroupPendingKeyRepair: (row) =>
        dbUpsertGroupPendingKeyRepair(db, row),
    dbLoadGroupPendingKeyRepair: (id) => dbLoadGroupPendingKeyRepair(db, id),
    dbLoadPendingGroupKeyRepairsForEpoch:
        ({required groupId, required keyEpoch, int limit = 50}) =>
            dbLoadPendingGroupKeyRepairsForEpoch(
              db,
              groupId: groupId,
              keyEpoch: keyEpoch,
              limit: limit,
            ),
    dbLoadAllPendingGroupKeyRepairs: ({int limit = 200}) =>
        dbLoadAllPendingGroupKeyRepairs(db, limit: limit),
    dbLoadPendingGroupKeyRepairsForGroup:
        ({required groupId, int limit = 100}) =>
            dbLoadPendingGroupKeyRepairsForGroup(
              db,
              groupId: groupId,
              limit: limit,
            ),
    dbDeleteGroupPendingKeyRepair: (id) =>
        dbDeleteGroupPendingKeyRepair(db, id),
    dbDeleteGroupPendingKeyRepairIfExact: (expected) =>
        dbDeleteGroupPendingKeyRepairIfExact(db, expected),
    dbRecordGroupPendingKeyRepairAttempt:
        (id, {required lastError, required updatedAt}) =>
            dbRecordGroupPendingKeyRepairAttempt(
              db,
              id,
              lastError: lastError,
              updatedAt: updatedAt,
            ),
    dbRecordGroupPendingKeyRepairAttemptIfExact:
        (expected, {required lastError, required updatedAt}) =>
            dbRecordGroupPendingKeyRepairAttemptIfExact(
              db,
              expected,
              lastError: lastError,
              updatedAt: updatedAt,
            ),
    dbFinalizeGroupPendingKeyRepair:
        (id, {required status, required lastError, required finalizedAt}) =>
            dbFinalizeGroupPendingKeyRepair(
              db,
              id,
              status: status,
              lastError: lastError,
              finalizedAt: finalizedAt,
            ),
    dbFinalizeGroupPendingKeyRepairIfExact:
        (
          expected, {
          required status,
          required lastError,
          required finalizedAt,
        }) => dbFinalizeGroupPendingKeyRepairIfExact(
          db,
          expected,
          status: status,
          lastError: lastError,
          finalizedAt: finalizedAt,
        ),
  );

  final groupPendingKeyDistributionRepository =
      GroupPendingKeyDistributionRepositoryImpl(
        dbUpsertGroupPendingKeyDistribution: (row) =>
            dbUpsertGroupPendingKeyDistribution(db, row),
        dbReopenGroupPendingKeyDistributionForRedelivery: (row) =>
            dbReopenGroupPendingKeyDistributionForRedelivery(db, row),
        dbLoadGroupPendingKeyDistribution: (id) =>
            dbLoadGroupPendingKeyDistribution(db, id),
        dbLoadPendingGroupKeyDistributionsForPeer:
            ({required peerId, groupId, int limit = 50}) =>
                dbLoadPendingGroupKeyDistributionsForPeer(
                  db,
                  peerId: peerId,
                  groupId: groupId,
                  limit: limit,
                ),
        dbLoadPendingGroupKeyDistributionsForGroup:
            ({required groupId, int limit = 50}) =>
                dbLoadPendingGroupKeyDistributionsForGroup(
                  db,
                  groupId: groupId,
                  limit: limit,
                ),
        dbRecordGroupPendingKeyDistributionAttempt:
            (id, {required lastError, required updatedAt}) =>
                dbRecordGroupPendingKeyDistributionAttempt(
                  db,
                  id,
                  lastError: lastError,
                  updatedAt: updatedAt,
                ),
        dbRecordGroupPendingKeyDistributionAttemptIfExact:
            (expected, {required lastError, required updatedAt}) =>
                dbRecordGroupPendingKeyDistributionAttemptIfExact(
                  db,
                  expected,
                  lastError: lastError,
                  updatedAt: updatedAt,
                ),
        dbFinalizeGroupPendingKeyDistribution:
            (id, {required status, required lastError, required finalizedAt}) =>
                dbFinalizeGroupPendingKeyDistribution(
                  db,
                  id,
                  status: status,
                  lastError: lastError,
                  finalizedAt: finalizedAt,
                ),
        dbFinalizeGroupPendingKeyDistributionIfExact:
            (
              expected, {
              required status,
              required lastError,
              required finalizedAt,
            }) => dbFinalizeGroupPendingKeyDistributionIfExact(
              db,
              expected,
              status: status,
              lastError: lastError,
              finalizedAt: finalizedAt,
            ),
      );

  // Slice 2 (Finding 03): persist deferred key distributions from EVERY rotate
  // path (admin removal, voluntary leave, creator backstop) without threading a
  // callback through the widget DI chain — mirrors debugSetFlowEventSink.
  setDeferredGroupKeyDistributionSink(({
    required groupId,
    required peerId,
    required keyEpoch,
  }) async {
    final now = DateTime.now().toUtc();
    await groupPendingKeyDistributionRepository.enqueue(
      GroupPendingKeyDistribution(
        id: groupPendingKeyDistributionId(groupId, peerId),
        groupId: groupId,
        peerId: peerId,
        keyEpoch: keyEpoch,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  // B1b sibling admission: a newly-admitted device may need the current key
  // re-delivered even when the member's (group,peer) row is already terminal —
  // reopen it (overriding exhaustion, because the device set changed) so the
  // runner re-distributes to the now-larger device set.
  setDeferredGroupKeyDistributionReopenSink(({
    required groupId,
    required peerId,
    required keyEpoch,
  }) async {
    final now = DateTime.now().toUtc();
    await groupPendingKeyDistributionRepository.reopenForRedelivery(
      GroupPendingKeyDistribution(
        id: groupPendingKeyDistributionId(groupId, peerId),
        groupId: groupId,
        peerId: peerId,
        keyEpoch: keyEpoch,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  final groupPendingMembershipMessageRepository =
      GroupPendingMembershipMessageRepositoryImpl(
        dbUpsertGroupPendingMembershipMessage: (row) =>
            dbUpsertGroupPendingMembershipMessage(db, row),
        dbLoadGroupPendingMembershipMessages: ({int limit = 200}) =>
            dbLoadGroupPendingMembershipMessages(db, limit: limit),
        dbLoadGroupPendingMembershipMessagesForSenders:
            ({required groupId, required senderPeerIds, int limit = 50}) =>
                dbLoadGroupPendingMembershipMessagesForSenders(
                  db,
                  groupId: groupId,
                  senderPeerIds: senderPeerIds,
                  limit: limit,
                ),
        dbDeleteGroupPendingMembershipMessage: (id) =>
            dbDeleteGroupPendingMembershipMessage(db, id),
        dbDeleteGroupPendingMembershipMessageByGroupAndMessageId:
            ({required groupId, required messageId}) =>
                dbDeleteGroupPendingMembershipMessageByGroupAndMessageId(
                  db,
                  groupId: groupId,
                  messageId: messageId,
                ),
        dbPruneGroupPendingMembershipMessages: (groupId, {required maxRows}) =>
            dbPruneGroupPendingMembershipMessages(
              db,
              groupId,
              maxRows: maxRows,
            ),
      );

  final groupPendingReactionRepository = GroupPendingReactionRepositoryImpl(
    dbUpsertGroupPendingReaction: (row) =>
        dbUpsertGroupPendingReaction(db, row),
    dbLoadGroupPendingReactionsForMessage:
        ({required groupId, required messageId}) =>
            dbLoadGroupPendingReactionsForMessage(
              db,
              groupId: groupId,
              messageId: messageId,
            ),
    dbLoadGroupPendingReactions: ({int limit = 200}) =>
        dbLoadGroupPendingReactions(db, limit: limit),
    dbDeleteGroupPendingReaction: (id) => dbDeleteGroupPendingReaction(db, id),
    dbPruneGroupPendingReactions: (groupId, {required maxRows}) =>
        dbPruneGroupPendingReactions(db, groupId, maxRows: maxRows),
    dbDeleteExpiredGroupPendingReactions: ({required olderThanIso}) =>
        dbDeleteExpiredGroupPendingReactions(db, olderThanIso: olderThanIso),
  );

  final groupHistoryGapRepairRepository = GroupHistoryGapRepairRepositoryImpl(
    dbUpsertGroupHistoryGapRepair: (row) =>
        dbUpsertGroupHistoryGapRepair(db, row),
    dbSaveGroupHistoryGapRepair: (row) => dbSaveGroupHistoryGapRepair(db, row),
    dbReplaceGroupHistoryGapRepairIfExact:
        ({required expected, required replacement}) =>
            dbReplaceGroupHistoryGapRepairIfExact(
              db,
              expected: expected,
              replacement: replacement,
            ),
    dbLoadGroupHistoryGapRepair: ({required groupId, required gapId}) =>
        dbLoadGroupHistoryGapRepair(db, groupId: groupId, gapId: gapId),
    dbLoadLatestGroupHistoryGapRepair: ({required groupId}) =>
        dbLoadLatestGroupHistoryGapRepair(db, groupId: groupId),
    dbLoadVisibleGroupHistoryGapRepairs: ({required groupId, int limit = 20}) =>
        dbLoadVisibleGroupHistoryGapRepairs(db, groupId: groupId, limit: limit),
  );

  // Create introduction repository
  final introductionRepository = IntroductionRepositoryImpl(
    dbInsertIntroduction: (row) => dbInsertIntroduction(db, row),
    dbLoadIntroduction: (id) => dbLoadIntroduction(db, id),
    dbDeleteIntroduction: (id) => dbDeleteIntroduction(db, id),
    dbLoadIntroductionsByRecipient: (recipientId) =>
        dbLoadIntroductionsByRecipient(db, recipientId),
    dbLoadIntroductionsByIntroduced: (introducedId) =>
        dbLoadIntroductionsByIntroduced(db, introducedId),
    dbLoadIntroductionsByIntroducer: (introducerId) =>
        dbLoadIntroductionsByIntroducer(db, introducerId),
    dbLoadIntroductionsForRecipientAndIntroducer: (recipientId, introducerId) =>
        dbLoadIntroductionsForRecipientAndIntroducer(
          db,
          recipientId,
          introducerId,
        ),
    dbUpdateRecipientStatus: (id, status, respondedAt) =>
        dbUpdateRecipientStatus(db, id, status, respondedAt),
    dbUpdateIntroducedStatus: (id, status, respondedAt) =>
        dbUpdateIntroducedStatus(db, id, status, respondedAt),
    dbUpdateOverallStatus: (id, status) =>
        dbUpdateOverallStatus(db, id, status),
    dbLoadPendingIntroductionsForUser: (peerId) =>
        dbLoadPendingIntroductionsForUser(db, peerId),
    dbCountPendingIntroductions: (peerId) =>
        dbCountPendingIntroductions(db, peerId),
    dbUpsertPendingIntroductionResponse: (row) =>
        dbUpsertPendingIntroductionResponse(db, row),
    dbLoadPendingIntroductionResponses: (introductionId) =>
        dbLoadPendingIntroductionResponses(db, introductionId),
    dbDeletePendingIntroductionResponse: (responseKey) =>
        dbDeletePendingIntroductionResponse(db, responseKey),
    dbUpsertIntroductionOutboxDelivery: (row) =>
        dbUpsertIntroductionOutboxDelivery(db, row),
    dbSaveIntroductionWithOutboxDeliveries: (introductionRow, deliveryRows) =>
        dbSaveIntroductionWithOutboxDeliveries(
          db,
          introductionRow,
          deliveryRows,
        ),
    dbReplaceIntroductionWithPendingResponseMigration:
        ({
          required introductionRow,
          required deliveryRows,
          required replacedIntroductionIds,
        }) => dbReplaceIntroductionWithPendingResponseMigration(
          db,
          introductionRow: introductionRow,
          deliveryRows: deliveryRows,
          replacedIntroductionIds: replacedIntroductionIds,
        ),
    dbSaveIntroductionResponseWithOutboxDeliveries:
        ({
          required introductionId,
          required isRecipient,
          required responseStatus,
          required respondedAt,
          required overallStatus,
          required deliveryRows,
        }) => dbSaveIntroductionResponseWithOutboxDeliveries(
          db,
          introductionId: introductionId,
          isRecipient: isRecipient,
          responseStatus: responseStatus,
          respondedAt: respondedAt,
          overallStatus: overallStatus,
          deliveryRows: deliveryRows,
        ),
    dbLoadIntroductionOutboxDeliveriesForIntroduction: (introductionId) =>
        dbLoadIntroductionOutboxDeliveriesForIntroduction(db, introductionId),
    dbLoadRetryableIntroductionOutboxDeliveries:
        ({required olderThan, limit = 100}) =>
            dbLoadRetryableIntroductionOutboxDeliveries(
              db,
              olderThan: olderThan,
              limit: limit,
            ),
    dbDeleteIntroductionOutboxDelivery: (deliveryId) =>
        dbDeleteIntroductionOutboxDelivery(db, deliveryId),
    dbDeleteIntroductionOutboxDeliveriesForIntroduction: (introductionId) =>
        dbDeleteIntroductionOutboxDeliveriesForIntroduction(db, introductionId),
  );
  final introReviewSeenRepository = IntroReviewSeenRepositoryImpl(
    dbLoadSeenKeys: () => dbLoadIntroReviewSeenKeys(db),
    dbMarkAllSeen: (itemKeys, seenAt) =>
        dbMarkIntroReviewItemsSeen(db, itemKeys, seenAt),
  );

  // Create media file manager
  final mediaFileManager = MediaFileManager();
  // A new process cannot have a live forward snapshot from its predecessor.
  // Reclaim only app-owned snapshot children before this process can create a
  // live one. The pass is bounded and fail-safe, and awaiting it avoids a
  // startup scavenger racing the first forward operation.
  await mediaFileManager.scavengeGroupForwardSnapshotOrphans(
    deleteFreshOrphans: true,
  );
  final directPrivateMediaLifecycle = DirectPrivateMediaLifecycle(
    messageRepository: messageRepository,
    mediaAttachmentRepository: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
  );
  final directPrivateMediaLifecycleEngine = PrivateMediaLifecycleEngine(
    adapter: directPrivateMediaLifecycle,
    lifecycleLock: mediaAttachmentRepository.lifecycleLock,
    nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
  );
  final groupPrivateMediaLifecycleEngine = GroupPrivateMediaLifecycleEngine(
    messageRepository: groupMessageRepository,
    mediaAttachmentRepository: mediaAttachmentRepository,
    cleanupRepository: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    lifecycleLock: mediaAttachmentRepository.lifecycleLock,
    nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
  );
  final privateMediaExpiryScheduler = PrivateMediaExpiryScheduler(
    loadNextExpiryAtMs: () async {
      final direct = await directPrivateMediaLifecycleEngine
          .loadNextExpiryAtMs();
      final group = await groupPrivateMediaLifecycleEngine.loadNextExpiryAtMs();
      if (direct == null) return group;
      if (group == null) return direct;
      return min(direct, group);
    },
    sweepDueExpiries: (evaluationFloorMs) async {
      await directPrivateMediaLifecycleEngine.sweepExpiries(
        evaluationFloorMs: evaluationFloorMs,
      );
      await groupPrivateMediaLifecycleEngine.sweepExpiries(
        evaluationFloorMs: evaluationFloorMs,
      );
    },
    rescheduleSignals: _mergeVoidStreams([
      directPrivateMediaExpiryRescheduleSignals(
        messageRepository.messageChanges,
      ),
      groupPrivateMediaExpirySignals,
    ]),
    nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
  );
  final privateMediaLifecycleForegroundRuntime =
      PrivateMediaLifecycleForegroundRuntime(
        isForeground: () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        recoverLocalLifecycle: () async {
          await directPrivateMediaLifecycleEngine.reconcileLocalLifecycle();
          try {
            await retryDirectPrivateCommittedPendingCleanup(
              repository: mediaAttachmentRepository,
              lifecycle: directPrivateMediaLifecycle,
            );
          } catch (error) {
            // Candidate-load failure is local and retryable on the next real
            // resume. It must not suppress group recovery or scheduler arming.
            emitFlowEvent(
              layer: 'FL',
              event: 'DIRECT_PRIVATE_COMMITTED_PENDING_CLEANUP_LOAD_FAILED',
              details: {'error': error.runtimeType.toString()},
            );
          }
          await groupPrivateMediaLifecycleEngine.reconcileLocalLifecycle();
        },
        startScheduler: privateMediaExpiryScheduler.start,
        stopScheduler: privateMediaExpiryScheduler.stop,
        disposeScheduler: privateMediaExpiryScheduler.dispose,
      );
  Future<void>? privateMediaColdRecoveryFuture;
  Future<void> ensurePrivateMediaColdRecovery() {
    final existing = privateMediaColdRecoveryFuture;
    if (existing != null) return existing;
    final recovery = () async {
      try {
        await privateMediaLifecycleForegroundRuntime.recoverColdStartAndArm();
        emitFlowEvent(
          layer: 'FL',
          event: 'PRIVATE_MEDIA_STARTUP_RECOVERY_DONE',
          details: {},
        );
      } catch (error) {
        // The shared future always resolves: local recovery failure is
        // observable and retryable on resume, but cannot permanently suppress
        // unrelated runtime startup.
        emitFlowEvent(
          layer: 'FL',
          event: 'PRIVATE_MEDIA_STARTUP_RECOVERY_FAILED',
          details: {'error': error.runtimeType.toString()},
        );
      }
    }();
    privateMediaColdRecoveryFuture = recovery;
    return recovery;
  }

  // Create image processor (EXIF stripping + quality compression)
  final imageProcessor = ImageProcessor();

  // Create audio recorder service
  final audioRecorderService = RecordAudioRecorderService();
  final privateMediaOutboxE2EController = PrivateMediaOutboxE2EController(
    enabled: kDebugMode && kE2ETestMode,
  );

  // Create and initialize the bridge (Go native)
  final Bridge bridge = GoBridgeClient();

  // ── Auto-setup for simulator scripts (debug/test harness only) ──
  final autoSetupUsername = await resolveAutoSetupUsername(appDocDir.path);
  if (autoSetupUsername != null) {
    final existing = await repository.loadIdentity();
    if (existing == null) {
      final result = await generateNewIdentity(
        callGenerate: () => callIdentityGenerate(bridge),
        callMlKemKeygen: () => callMlKemKeygen(bridge),
        repo: repository,
      );
      if (result == GenerateIdentityResult.success) {
        final identity = await repository.loadIdentity();
        if (identity != null) {
          await repository.saveIdentity(
            IdentityModel(
              peerId: identity.peerId,
              publicKey: identity.publicKey,
              privateKey: identity.privateKey,
              mnemonic12: identity.mnemonic12,
              mlKemPublicKey: identity.mlKemPublicKey,
              mlKemSecretKey: identity.mlKemSecretKey,
              username: autoSetupUsername,
              avatarBlob: identity.avatarBlob,
              avatarVersion: identity.avatarVersion,
              createdAt: identity.createdAt,
              updatedAt: identity.updatedAt,
            ),
          );
          if (kDebugMode) {
            print('[AUTO-SETUP] Identity created: $autoSetupUsername');
          }

          // Export signed QR payload for cross-device smoke tests
          final (qrResult, qrJson) = await buildQRPayload(
            repo: repository,
            callSign: (data, key) => callSignPayload(
              bridge: bridge,
              dataToSign: data,
              privateKey: key,
            ),
            cachedIdentity: await repository.loadIdentity(),
          );
          if (qrResult == BuildQRPayloadResult.success && qrJson != null) {
            final loadedId = await repository.loadIdentity();
            await exportIdentityForIntroE2E(
              signedQrPayloadJson: qrJson,
              mlKemPublicKey: loadedId?.mlKemPublicKey,
            );
          }
        }
      }
    } else {
      if (kDebugMode) {
        print('[AUTO-SETUP] Identity already exists, ensuring export');
      }
      final (qrResult, qrJson) = await buildQRPayload(
        repo: repository,
        callSign: (data, key) =>
            callSignPayload(bridge: bridge, dataToSign: data, privateKey: key),
        cachedIdentity: existing,
      );
      if (qrResult == BuildQRPayloadResult.success && qrJson != null) {
        await exportIdentityForIntroE2E(
          signedQrPayloadJson: qrJson,
          mlKemPublicKey: existing.mlKemPublicKey,
        );
      }
    }
  }

  // Create local P2P service for WiFi-first delivery
  final LocalDiscoveryService localDiscovery = kDisableLocalDiscovery
      ? DisabledLocalDiscoveryService()
      // 180: on Android, compose the native mDNS resolver so the Pixel resolves
      // iOS `.local` adverts that NsdManager intermittently fails to complete.
      // null on iOS (the bonsoir_darwin path + 175/178 gates stay untouched).
      // SHIPS DARK behind --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true until the
      // native MdnsResolver.kt handler lands + the device-proof (TC-180-07)
      // passes — otherwise start() would hit a MissingPluginException.
      : BonsoirDiscoveryService(
          nativeResolver:
              (Platform.isAndroid &&
                  const bool.fromEnvironment('MKNOON_ENABLE_NATIVE_MDNS'))
              ? PlatformChannelMdnsResolver()
              : null,
        );
  final localWsServer = LocalWsServer();
  // NET-REL-01 P3: wire the receive-side media server in production so inbound
  // local PUT /media/<id> is accepted (token-auth + declared-size + streaming
  // SHA-256). Gated by the same flag that selects real vs disabled discovery so
  // test builds stay media-server-free. Dedicated subdirs avoid colliding with
  // relay-CDN media storage.
  final LocalMediaServer? localMediaServer = kDisableLocalDiscovery
      ? null
      : LocalMediaServer(
          tempDir: '${appDocDir.path}/local_media_tmp',
          mediaDir: '${appDocDir.path}/local_media',
        );
  if (localMediaServer != null) {
    localWsServer.configureMediaServer(localMediaServer);
  }
  final localP2PService = LocalP2PService(
    discovery: localDiscovery,
    wsServer: localWsServer,
  );
  final accountMigrationSegmentCrypto = BridgeMigrationSegmentCrypto(
    bridge: bridge,
  );
  final accountMigrationStreamCrypto = BridgeMigrationStreamCrypto(
    bridge: bridge,
  );
  final accountMigrationSecureStorageStaging = MigrationSecureStorageStaging(
    primaryStore: secureKeyStore,
    sharedStore: sharedPushKeyStore,
  );
  final accountMigrationSizeGate = AccountMigrationSizeGate(
    estimateMoveSize: AccountMigrationAccountSizeEstimator(
      databasePath: db.path,
      documentsRootPath: appDocDir.path,
    ).call,
  );
  final diskSpaceChannel = DiskSpaceChannel();
  final accountMigrationCutoverCoordinator = MigrationCutoverCoordinator(
    authorityRepository: accountMigrationAuthorityRepository,
    cutoverRepository: accountMigrationCutoverRepository,
  );
  late final P2PServiceImpl p2pService;
  final accountMigrationTransferRuntime = AccountMigrationLocalTransferRuntime(
    discovery: localDiscovery,
    wsServer: localWsServer,
    pairingSessionRepository: SecureKeyStoreMigrationPairingSessionRepository(
      secureKeyStore: secureKeyStore,
    ),
    sizeGate: accountMigrationSizeGate,
    storagePreflight: MigrationStoragePreflight(
      availableBytesProvider: () =>
          diskSpaceChannel.getAvailableBytes(appDocDir.path),
    ),
    bundleSource: AccountMigrationProductionBundleSource(
      sourceDb: db,
      primaryStore: secureKeyStore,
      sharedStore: sharedPushKeyStore,
      documentsRootPath: appDocDir.path,
      exportDirectoryPath: '${appDocDir.path}/account_migration/export',
      snapshotExporter: const MigrationDatabaseSnapshotExporter(),
    ).call,
    streamCrypto: accountMigrationStreamCrypto,
    bundleReceiver: AccountMigrationProductionBundleReceiver(
      streamCrypto: accountMigrationStreamCrypto,
      secureStorageStaging: accountMigrationSecureStorageStaging,
      databaseImportStaging: MigrationDatabaseImportStaging(
        secureStorageStaging: accountMigrationSecureStorageStaging,
      ),
      activeDatabaseImporter: MigrationDatabaseActiveImporter(
        activeDatabase: db,
      ),
      cutoverCoordinator: accountMigrationCutoverCoordinator,
      authorityRepository: accountMigrationAuthorityRepository,
      stagingDirectoryPath: '${appDocDir.path}/account_migration/import',
      documentsRootPath: appDocDir.path,
    ),
    oldPhoneCutoverCoordinator: accountMigrationCutoverCoordinator,
    oldPhoneLeaseCleanup: buildBridgeMigrationCutoverLeaseCleanup(
      bridge: bridge,
      clearLocalStalePushToken: () async {
        await pushTokenStore.clearToken();
        await directReactionNotificationProjection?.clearForLogout();
        await groupReactionNotificationProjection?.clearForLogout();
      },
      stopLocalRuntime: () async {
        await p2pService.stopNode().timeout(const Duration(seconds: 2));
      },
    ),
    transferService: MigrationSegmentedTransferService(
      crypto: accountMigrationSegmentCrypto,
      checkpointStore: FileMigrationTransferCheckpointStore(
        filePath:
            '${appDocDir.path}/account_migration/transfer_checkpoints.json',
      ),
    ),
  );
  localWsServer.configureMigrationTransferHandler(
    accountMigrationTransferRuntime.handleMigrationTransferRequest,
  );
  late final ChatMessageListener chatMessageListener;
  late final IntroductionListener introductionListener;
  // 171: forward-declared so the p2pService inbox-replay closure (below) can
  // route a cold-receiver contact_request through the listener; assigned after
  // p2pService, called only at drain time (mirrors introductionListener).
  late final ContactRequestListener contactRequestListener;

  // NET-REL-04: session-scoped, aggregate-only transport diagnostics.
  final transportMetrics = TransportMetrics();

  // 115 P2: delivery-receipt sender bound to this device's transport.
  // Receipts confirm durable persist of relay-inbox arrivals back to the
  // message sender (live send first, inbox fallback inside the use case).
  // F7: hoisted above the P2PServiceImpl construction so the deletion replay
  // callback below can reference it.
  Future<void> sendDeliveryReceiptForPeer({
    required String contactPeerId,
    required List<String> messageIds,
  }) {
    return sendDeliveryReceipt(
      p2pService: p2pService,
      targetPeerId: contactPeerId,
      messageIds: messageIds,
    );
  }

  Future<RecoveredInboxReplayOutcome> replayInboxChatMessage(
    ChatMessage message, {
    required bool suppressNotification,
    String? stagedEntryId,
  }) async {
    var outcome = await chatMessageListener.processIncomingMessage(
      message,
      suppressNotification: suppressNotification,
      stagedEntryId: stagedEntryId,
    );
    if (outcome.state == ChatMessageProcessState.unknownSender) {
      final ownPeerId = message.to;
      if (ownPeerId.isNotEmpty) {
        final resolution = await resolveUnknownInboxSender(
          introRepo: introductionRepository,
          contactRepo: contactRepository,
          ownPeerId: ownPeerId,
          senderPeerId: message.from,
        );
        if (resolution == UnknownInboxSenderResolution.contactRecovered) {
          outcome = await chatMessageListener.processIncomingMessage(
            message,
            suppressNotification: suppressNotification,
            stagedEntryId: stagedEntryId,
          );
        }
        if (outcome.state == ChatMessageProcessState.unknownSender) {
          // 172: a resolver-CONFIRMED stranger (no introduction in any
          // recoverable state) stays a terminal content-safe drop; everyone
          // else stays recoverable. The mapper's own unknownSender default is
          // now retryable (unknown_sender_recoverable), so the terminal
          // stranger verdict must be returned explicitly here — the one place
          // with resolver context.
          if (resolution == UnknownInboxSenderResolution.rejected) {
            return (
              disposition: RecoveredInboxChatDisposition.rejected,
              reasonCode: 'unknown_sender_stranger',
              reasonDetail: null,
            );
          }
          return (
            disposition: RecoveredInboxChatDisposition.retryable,
            reasonCode: 'unknown_sender_intro_pending',
            reasonDetail: null,
          );
        }
      }
    }

    return mapChatReplayOutcomeToDisposition(outcome);
  }

  final pushEnvelopeStagingStore = FilePushEnvelopeStagingStore(
    directory: await resolvePushEnvelopeStagingDirectory(),
  );
  final ingestStagedPushEnvelopesUseCase = IngestStagedPushEnvelopesUseCase(
    store: pushEnvelopeStagingStore,
    localPeerIdProvider: () async {
      final identity = await repository.loadIdentity();
      return identity?.peerId ?? '';
    },
    isSenderBlocked: (senderPeerId) async {
      final contact = await contactRepository.getContact(senderPeerId);
      return contact?.isBlocked ?? false;
    },
    accountMigrationNetworkGate: () async {
      final identity = await repository.loadIdentity();
      return accountMigrationRuntimeNetworkGate.allowsAccountNetworkSideEffects(
        peerId: identity?.peerId,
        operation: 'push_staged_envelope_ingest',
      );
    },
    replayChatMessage:
        (message, {required bool suppressNotification, String? stagedEntryId}) {
          return replayInboxChatMessage(
            message,
            suppressNotification: suppressNotification,
            stagedEntryId: stagedEntryId,
          );
        },
  );

  // 127-Bug-C: reaction-receive notification deps. The notification stack is
  // constructed further below (after p2pService), but this closure is defined
  // here — so the deps are stored in this mutable holder and read at
  // reaction-arrival time (long after bootstrap completes).
  ({
    NotificationService service,
    ActiveConversationTracker tracker,
    AppLifecycleState Function() lifecycle,
    NotificationToneTracker toneTracker,
    DurableNotificationToneLease durableCoordinator,
  })?
  reactionNotifyDeps;
  void Function(ReactionChange change)? publishPersistedReactionChange;

  // F7: reactions/deletions get the same stage-before-ack/commit durability as
  // chat. These replay closures call the use cases DIRECTLY (the listeners are
  // constructed later and aren't needed here) and resolve the SAME deps + the
  // same ML-KEM secret as the chat path (repository.loadIdentity()).
  Future<RecoveredInboxReplayOutcome> replayInboxReaction(
    ChatMessage message, {
    String? stagedEntryId,
  }) async {
    final identity = await repository.loadIdentity();
    final notify = reactionNotifyDeps;
    final (result, change) = await handleIncomingReaction(
      message: message,
      messageRepo: messageRepository,
      reactionRepo: reactionRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      ownMlKemSecretKey: identity?.mlKemSecretKey,
      // 127-Bug-C: notify the recipient that a contact reacted to their 1:1
      // message (no-op until the holder below is populated). The use case fires
      // only on a fresh ADD upsert and respects the standard suppression gates.
      notificationService: notify?.service,
      conversationTracker: notify?.tracker,
      getAppLifecycleState: notify?.lifecycle,
      notificationToneTracker: notify?.toneTracker,
      durableNotificationCoordinatorResolver: notify == null
          ? null
          : () async => notify.durableCoordinator,
      consumeRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              recentRemoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
      markRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              recentRemoteNotificationGate.markAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
    );
    if (result == HandleReactionResult.success && change != null) {
      publishPersistedReactionChange?.call(change);
    }
    // 172 TC-11: the recoverable-vs-terminal split lives in the extracted,
    // test-locked sibling mapper (recovered_inbox_sibling_dispositions.dart).
    return mapReactionReplayResultToDisposition(result);
  }

  ingestStagedPushEnvelopesUseCase.replayReactionMessage =
      (message, {String? stagedEntryId}) =>
          replayInboxReaction(message, stagedEntryId: stagedEntryId);

  Future<RecoveredInboxReplayOutcome> replayInboxMessageDeletion(
    ChatMessage message, {
    String? stagedEntryId,
  }) async {
    final identity = await repository.loadIdentity();
    final (result, _) = await handleIncomingMessageDeletion(
      message: message,
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      reactionRepo: reactionRepository,
      mediaAttachmentRepo: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      bridge: bridge,
      ownMlKemSecretKey: identity?.mlKemSecretKey,
      sendDeliveryReceipt: (messageId) => sendDeliveryReceiptForPeer(
        contactPeerId: message.from,
        messageIds: [messageId],
      ),
      stagedEntryId: stagedEntryId,
    );
    // 172 TC-11: the recoverable-vs-terminal split lives in the extracted,
    // test-locked sibling mapper (recovered_inbox_sibling_dispositions.dart).
    return mapMessageDeletionReplayResultToDisposition(result);
  }

  // CV-26 (FDC-04 DESIGN-3): the 1:1 active-conversation tracker is a
  // zero-dependency object; construct it HERE (ahead of the P2PServiceImpl
  // build) so the peer-scoped WiFi<->cellular re-warm can resolve the open
  // conversation's peer. (Moved up from its former site further down this
  // builder — nothing between here and there references it.)
  final conversationTracker = ActiveConversationTracker();

  // FDC-09 §12 / CV-14 recipient leg (217 §A1): once-per-cycle mint+register with
  // a TOTAL callback wrapper (a throwing/old relay degrades to false, never
  // spams — NET-REL-07). The register set is not relay-durable, so this re-runs
  // on each node-start (StartupRouter) + coalesced contact-change bursts.
  final issueWakeTokensUseCase = IssueWakeTokensUseCase(
    wakeTokenStore: wakeTokenStore,
    registerWakeTokens: (tokens) => registerWakeTokensViaBridge(bridge, tokens),
  );
  // Read-only per-send resolver — null-yielding (DARK) unless a build passes
  // --dart-define=MKNOON_EMIT_WAKE_TOKEN=true (§C2). Never mints/registers.
  final wakeTokenResolver = buildWakeTokenResolver(wakeTokenStore);
  // Coalesce contact-add / key-rotation bursts into ONE re-issue per window
  // (INV-5: register once-per-cycle, never per-event).
  final wakeTokenReissueCoalescer = WakeTokenReissueCoalescer(
    reissue: () async {
      final contacts = await contactRepository.getActiveContacts();
      // Exclude BLOCKED contacts (getActiveContacts filters archived only) so a
      // blocked peer's token is pruned (reconcile-down) and never re-registered.
      await issueWakeTokensUseCase.issueForContacts(
        contacts
            .where((c) => !c.isBlocked)
            .map((c) => c.peerId)
            .toList(growable: false),
      );
    },
  );
  notifyContactPushEligibilityChanged = wakeTokenReissueCoalescer.trigger;

  // Hash-only and dormant unless the dedicated E2E action arms it. Production
  // builds pass no callback into P2PServiceImpl, preserving the normal path.
  final wakeTokenAttachmentObserver = WakeTokenAcceptedAttachmentObserver();

  // Create P2P service (uses the same bridge + local P2P)
  p2pService = P2PServiceImpl(
    bridge: bridge,
    localP2PService: localP2PService,
    pushTokenStore: pushTokenStore,
    // FDC-09 §12 / CV-14: the send funnel attaches received[toPeerId] on
    // `inbox:store` (1:1 contacts only). Inert until a peer distributes a `wt`.
    receivedWakeTokenStore: receivedWakeTokenStore,
    acceptedInboxWakeTokenHashObserver: kE2ETestMode
        ? wakeTokenAttachmentObserver.observeAccepted
        : null,
    // 182: wire the OS connectivity source (FDC-04's anticipated "bounded
    // follow-up") so a foreground connectivity restore drains the offline inbox
    // immediately — instead of waiting for the next ~30s health-check poll or an
    // app resume. onNetworkChanged is total/never-throws and self-debounces.
    // CV-26 (FDC-04 DESIGN-3): activePeerId now WIRED — onNetworkChanged
    // re-warms the ONE open-conversation peer (PS-4, preferQuic); a null return
    // (no chat open) is a no-op. Branch logic is locked by TC-04-07/08/16.
    networkChangeSignal: connectivityRestoredSignal(),
    activePeerId: () => conversationTracker.activePeerId,
    accountMigrationNetworkGate:
        accountMigrationRuntimeNetworkGate.allowsAccountNetworkSideEffects,
    inboxStagingRepository: inboxStagingRepository,
    transportMetrics: transportMetrics,
    replayRecoveredInboxChatMessage: (message, {String? stagedEntryId}) =>
        replayInboxChatMessage(
          message,
          suppressNotification: true,
          stagedEntryId: stagedEntryId,
        ),
    replayLiveLanChatMessage: (message, {String? stagedEntryId}) =>
        replayInboxChatMessage(
          message,
          suppressNotification: false,
          stagedEntryId: stagedEntryId,
        ),
    // 118: live direct (1:1) messages staged as `direct:<nonce>` replay through
    // this notify-capable callback (suppressNotification:false), mirroring the
    // LAN path, so a recipient who is live-but-not-viewing gets a notification.
    replayLiveDirectChatMessage: (message, {String? stagedEntryId}) =>
        replayInboxChatMessage(
          message,
          suppressNotification: false,
          stagedEntryId: stagedEntryId,
        ),
    replayRecoveredInboxIntroductionMessage: (message) async {
      final outcome = await introductionListener.processIncomingMessage(
        message,
      );
      switch (outcome.state) {
        case IntroductionMessageProcessState.stored:
          return (
            disposition: RecoveredInboxChatDisposition.committed,
            reasonCode: outcome.reasonCode,
            reasonDetail: outcome.reasonDetail,
          );
        case IntroductionMessageProcessState.deferred:
          return (
            disposition: RecoveredInboxChatDisposition.committed,
            reasonCode: outcome.reasonCode,
            reasonDetail: outcome.reasonDetail,
          );
        case IntroductionMessageProcessState.retryableError:
          return (
            disposition: RecoveredInboxChatDisposition.retryable,
            reasonCode: outcome.reasonCode,
            reasonDetail: outcome.reasonDetail,
          );
        case IntroductionMessageProcessState.blockedSender:
        case IntroductionMessageProcessState.rejected:
          return (
            disposition: RecoveredInboxChatDisposition.rejected,
            reasonCode: outcome.reasonCode,
            reasonDetail: outcome.reasonDetail,
          );
      }
    },
    // 171: relay-inbox replay of a cold-receiver contact_request runs the SAME
    // listener processing (auto-add + reciprocal + confirm) as the live
    // broadcast — the dominant-bug fix for a freshly-installed B whose listener
    // wasn't subscribed when A's request arrived. Any returned result is
    // terminal (committed -> delete the staged row); only a thrown error
    // retries (so a transient failure re-stages instead of being lost).
    replayRecoveredInboxContactRequest: (message) async {
      try {
        await contactRequestListener.processIncomingMessage(message);
        return (
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'contact_request_processed',
          reasonDetail: null,
        );
      } catch (e) {
        return (
          disposition: RecoveredInboxChatDisposition.retryable,
          reasonCode: 'contact_request_processing_error',
          reasonDetail: e.toString(),
        );
      }
    },
    // F7: stage-before-ack/commit durability for reactions/deletions across all
    // 3 receive paths (relay-inbox, live-direct, LAN).
    replayRecoveredInboxReaction: (message, {String? stagedEntryId}) =>
        replayInboxReaction(message, stagedEntryId: stagedEntryId),
    replayRecoveredInboxMessageDeletion: (message, {String? stagedEntryId}) =>
        replayInboxMessageDeletion(message, stagedEntryId: stagedEntryId),
    // 147: decrypt-prefetch fn — the inbox-drain replay overlaps a page's chat
    // decrypts (bounded by maxConcurrentInboxDecrypts) AHEAD of the serial
    // commit loop, then threads each plaintext into the unchanged replay.
    // predecryptStagedInboxChatEntry honors the listener's blocked-sender policy
    // (a blocked contact's ciphertext is NOT decrypted), sources the SAME key
    // material as the chat path (loadIdentity + the ML-KEM ring), and runs the
    // SAME bridge decrypt + fallback ring. A null result (blocked / not v2 / key
    // unavailable / decrypt failed) is harmless — that entry decrypts in-handler.
    predecryptInboxChatEntry: (message) => predecryptStagedInboxChatEntry(
      message: message,
      contactRepo: contactRepository,
      bridge: bridge,
      loadOwnMlKemSecretKey: () async =>
          (await repository.loadIdentity())?.mlKemSecretKey,
      loadOwnMlKemSecretKeyRing: () => loadMlKemSecretKeyRing(secureKeyStore),
    ),
  );
  nearbyLocationService = NearbyLocationServiceImpl(
    settingsRepository: postsPrivacySettingsRepository,
    platformAdapter: GeolocatorNearbyLocationPlatformAdapter(),
    publishPostPresenceUpdate:
        ({
          required status,
          required capturedAt,
          latE3,
          lngE3,
          accuracyM,
          reason,
        }) {
          return publishPostPresenceUpdate(
            p2pService: p2pService,
            contactRepo: contactRepository,
            status: status,
            capturedAt: capturedAt,
            latE3: latE3,
            lngE3: lngE3,
            accuracyM: accuracyM,
            reason: reason,
          );
        },
  );

  // Create message router — single subscription, routes by type
  final messageRouter = IncomingMessageRouter(p2pService: p2pService);
  final contactRequestPresentationGate = ContactRequestPresentationGate();
  if (kE2ETestMode) {
    contactRequestPresentationGate.suppressAll();
  }

  // Create contact request listener
  // The getOwnPeerId function gets the peerId from the P2P service's current state.
  // This is populated when the node starts, so it will be empty before that.
  contactRequestListener = ContactRequestListener(
    contactRequestStream: messageRouter.contactRequestStream,
    requestRepo: contactRequestRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    getOwnPeerId: () => p2pService.currentState.peerId ?? '',
    getOwnPrivateKey: () => secureKeyStore.read('identity_private_key'),
    attemptSilentIntroRecovery: (request) => recoverIntroContactRequest(
      introRepo: introductionRepository,
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      ownPeerId: p2pService.currentState.peerId ?? '',
      request: request,
      messageRepo: messageRepository,
      bridge: bridge,
    ),
    emitRecoveredIntroductionStatus: (intro) =>
        introductionListener.emitIntroStatusChanged(intro),
    // FDC-09 §12 / CV-14: persist a distributed `wt` on the receive leg (live +
    // inbox-replay both funnel through processIncomingMessage).
    receivedWakeTokenStore: receivedWakeTokenStore,
    shouldSuppressPresentationForPeerId:
        contactRequestPresentationGate.shouldSuppress,
    // 171 follow-up (user decision): the scanned user is notified via the
    // EXISTING Accept/Decline ContactRequestDialog (the pre-171 wiring:
    // requestStream → FTE/Orbit `_onContactRequest` → showDialog), NOT a silent
    // tap-free auto-add. Leaving `autoAcceptAndReciprocate` null makes the
    // listener route every incoming request to that dialog via its existing
    // dialog fallback (ContactRequestListener._routeAutoAdd). The user taps
    // Accept to add + reciprocate (the dialog's onAccept calls
    // acceptAndReciprocateContactRequest in FTE/Orbit). The 171 DELIVERY fixes
    // (Go deferred-ack + Dart confirm + staged inbox replay) still apply, so the
    // request now reliably reaches a cold/just-online receiver under go-libp2p.
    // (kE2ETestMode already used null here — the smoke-runner's auto_accept poll
    // owns acceptance — so this is unchanged for E2E.)
    autoAcceptAndReciprocate: null,
  );

  // Create notification service and conversation trackers
  final notificationService = FlutterNotificationService(
    requestApplePermissions: !kE2ETestMode,
  );
  final PushRegistrationCoordinator? pushRegistrationCoordinator =
      shouldEnableProductionPushRegistration(isDesktop: isDesktop)
      ? PushRegistrationCoordinator(
          requestPermission: requestPushPermission,
          registerPushToken: () async {
            // The headless Android FCM engine has no live P2P state. Persist the
            // exact transport whose token is being registered so a later wake
            // can prove this installation is both active in the local roster
            // and present in the signed reaction-recipient nomination.
            final identity = await repository.loadIdentity();
            if (pushRelayRegistrationProof case final proof?) {
              if (!proof.bindAccountIdentity(identity?.peerId)) {
                emitFlowEvent(
                  layer: 'FL',
                  event: 'PUSH_REGISTER_RELAY_PROOF_IDENTITY_UNAVAILABLE',
                  details: proof.safeDetails(platform: 'android'),
                );
                return push_registration.RegisterPushTokenResult.failed;
              }
            }
            final transportPeerId = p2pService.currentState.peerId;
            await groupReactionNotificationProjection?.replaceLocalIdentity(
              accountPeerId: identity?.peerId,
              deviceId: transportPeerId,
              transportPeerId: transportPeerId,
            );
            await directReactionNotificationProjection?.replaceLocalIdentity(
              accountPeerId: identity?.peerId,
            );
            await Future.wait([
              contactRepository.mirrorAllDirectReactionContacts(),
              messageRepository.mirrorAllDirectReactionAuthoredTargets(),
            ]);
            await persistBackgroundPushRegistrationTransportPeerId(
              secureKeyStore: secureKeyStore,
              transportPeerId: transportPeerId,
            );
            return push_registration.registerPushToken(
              p2pService: p2pService,
              pushTokenStore: pushTokenStore,
              accountMigrationNetworkGate: accountMigrationRuntimeNetworkGate
                  .allowsAccountNetworkSideEffects,
              relayRegistrationProof: pushRelayRegistrationProof,
            );
          },
          // 164 (cold-start-1 regression #2): Firebase is now initialized lazily
          // inside the deferred startLiveServices, so Firebase.apps is empty here
          // on a normal launch — the old `Firebase.apps.isNotEmpty` gate would
          // build this coordinator null for the whole session (no onTokenRefresh
          // subscription, no startup registerPushToken()). Keep it non-null and
          // make the token-refresh stream LAZY: a Stream.multi whose body touches
          // FirebaseMessaging.instance only at listen-time, which happens inside
          // the coordinator's ensureStarted() — after runtime services are ready.
          tokenRefreshStream: Stream<String>.multi(
            (controller) => unawaited(
              controller.addStream(FirebaseMessaging.instance.onTokenRefresh),
            ),
          ),
          registrationSuccessDetails: pushRelayRegistrationProof == null
              ? null
              : () => pushRelayRegistrationProof.safeDetails(
                  platform: Platform.isAndroid ? 'android' : 'ios',
                ),
        )
      : null;
  // conversationTracker is constructed EARLIER (ahead of P2PServiceImpl) for the
  // CV-26 FDC-04 re-warm wiring; see the P2PServiceImpl build site above.
  final groupConversationTracker = ActiveConversationTracker();
  // 118 Phase 4: one shared per-conversation tone debounce for BOTH listeners
  // (direct + group keys are disjoint under normalizeActiveKey).
  final notificationToneTracker = NotificationToneTracker();
  final durableReactionNotificationCoordinator =
      await DurableNotificationToneLease.openDefault();
  final appShellController = AppShellController();
  final pendingPostTargetStore = PendingPostTargetStore();

  // Create chat message listener (sendDeliveryReceiptForPeer is hoisted above
  // the P2PServiceImpl construction so the F7 deletion replay can reference it).
  chatMessageListener = ChatMessageListener(
    chatMessageStream: messageRouter.chatMessageStream,
    messageRepo: messageRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    getOwnMlKemSecretKeyRing: () => loadMlKemSecretKeyRing(secureKeyStore),
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    notificationService: notificationService,
    conversationTracker: conversationTracker,
    notificationToneTracker: notificationToneTracker,
    getAppLifecycleState: () =>
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    sendDeliveryReceipt: sendDeliveryReceiptForPeer,
  );

  // 127-Bug-C: the notification stack now exists — enable reaction-receive
  // notifications for the already-defined replayInboxReaction closure (all 3
  // reaction receive paths funnel through it). Reuses the chat path's tracker,
  // lifecycle getter and tone tracker so suppression/debounce stay consistent.
  reactionNotifyDeps = (
    service: notificationService,
    tracker: conversationTracker,
    lifecycle: () =>
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    toneTracker: notificationToneTracker,
    durableCoordinator: durableReactionNotificationCoordinator,
  );

  // 115 P2: consume incoming receipts — the only place 'inboxed' rows flip
  // to 'delivered' (G4 site a).
  final deliveryReceiptListener = DeliveryReceiptListener(
    receiptStream: messageRouter.deliveryReceiptStream,
    messageRepo: messageRepository,
    mediaAttachmentRepo: mediaAttachmentRepository,
  );

  // NET-REL-01 P3: bridge inbound local-WiFi media into the attachment
  // pipeline. The bytes arrive over the local media server; the matching
  // attachment row (keyed by media.id) is already inserted by the text-envelope
  // receive path (handle_incoming_chat_message_use_case) in 'pending' status.
  // We move temp->persistent (otherwise the 5-min pendingTtl GC reclaims it)
  // and point the attachment's local path at the persisted file. Guarded by the
  // same flag that constructed the media server. Dedupe vs the relay-CDN
  // fallback: only act while the attachment is still a pending download; if the
  // relay path already completed it ('done'), skip so we don't clobber it.
  if (localMediaServer != null) {
    final mediaServer = localMediaServer;
    p2pService.incomingLocalMediaStream.listen((media) async {
      await linkIncomingLocalMedia(
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepository,
        persistMedia: mediaServer.persistMedia,
        mediaFileManager: mediaFileManager,
      );
    });
  }

  // FDC-15: inbound libp2p-LAN media (the Go `media:lan_received` event) feeds
  // the SAME attachment-link → `<canonical>.enc` → decrypt-adopt pipeline as the
  // WS leg. The Go node already staged the ciphertext to media.localPath, so
  // persistMedia hands that path straight back. Independent of the WS media
  // server — the libp2p lane has its own transport + its own default-off flag.
  if (bridge is GoBridgeClient) {
    bridge.onLocalMediaReceived = (media) async {
      await linkIncomingLocalMedia(
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepository,
        persistMedia: (mediaId, fromPeerId) async => media.localPath,
        mediaFileManager: mediaFileManager,
      );
    };
  }

  final postListener = PostListener(
    postCreateStream: messageRouter.postCreateStream,
    postRepo: postRepository,
    contactRepo: contactRepository,
    notificationService: notificationService,
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    hydratePostMediaFn: ({required attachment, required postId}) {
      return downloadPostMedia(
        bridge: bridge,
        postRepo: postRepository,
        mediaFileManager: mediaFileManager,
        attachment: attachment,
      );
    },
  );

  final postCommentListener = PostCommentListener(
    postCommentStream: messageRouter.postCommentStream,
    postRepo: postRepository,
    contactRepo: contactRepository,
    notificationService: notificationService,
  );

  final postReactionListener = PostReactionListener(
    postReactionStream: messageRouter.postReactionStream,
    postCommentReactionStream: messageRouter.postCommentReactionStream,
    postRepo: postRepository,
    contactRepo: contactRepository,
    notificationService: notificationService,
  );
  final postPresenceListener = PostPresenceListener(
    postPresenceStream: messageRouter.postPresenceStream,
    contactRepo: contactRepository,
    snapshotRepo: contactPresenceSnapshotRepository,
  );
  final postPassListener = PostPassListener(
    postPassStream: messageRouter.postPassStream,
    postRepo: postRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    hydratePostMediaFn: ({required attachment, required postId}) {
      return downloadPostMedia(
        bridge: bridge,
        postRepo: postRepository,
        mediaFileManager: mediaFileManager,
        attachment: attachment,
      );
    },
  );
  final postPinListener = PostPinListener(
    postPinUpdateStream: messageRouter.postPinUpdateStream,
    postPinRemoveStream: messageRouter.postPinRemoveStream,
    postRepo: postRepository,
    contactRepo: contactRepository,
  );

  // Create reaction listener
  final reactionListener = ReactionListener(
    reactionStream: messageRouter.reactionStream,
    messageRepo: messageRepository,
    reactionRepo: reactionRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
  );
  publishPersistedReactionChange = reactionListener.publishPersistedChange;

  final messageDeletionListener = MessageDeletionListener(
    deletionStream: messageRouter.messageDeletionStream,
    messageRepo: messageRepository,
    contactRepo: contactRepository,
    reactionRepo: reactionRepository,
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    sendDeliveryReceipt: sendDeliveryReceiptForPeer,
  );

  // Create profile update listener
  final profileUpdateListener = ProfileUpdateListener(
    profileUpdateStream: messageRouter.profileUpdateStream,
    contactRepo: contactRepository,
    bridge: bridge,
  );

  // Slice 2 / UDM-G — the real outbound active key-pull. Constructed below once
  // `groupIdentityCallbacks` exists; declared `late` here so the producer call
  // sites (GroupMessageListener, the drain backstop, key-update listener, …) can
  // reference it through `requestGroupKeyRepairViaSender`. Old peers drop the
  // unknown wire type and the sender falls back to the admin's inbox if offline,
  // so this is strictly no-worse-than the previous log-only stub.
  late final GroupKeyRepairRequestSender groupKeyRepairRequestSender;
  Future<void> requestGroupKeyRepairViaSender(
    GroupKeyRepairRequest request,
  ) async {
    await groupKeyRepairRequestSender.call(request);
  }

  // Create group message listener and wire bridge callback to stream
  late final GroupMessageListener groupMessageListener;
  late final GroupExitIntentRepositoryImpl groupExitIntentRepository;
  groupMessageListener = GroupMessageListener(
    groupRepo: groupRepository,
    msgRepo: groupMessageRepository,
    bridge: bridge,
    // R2: an account-signed device_announce is HELD pending an explicit user
    // trust decision (never auto-admitted). groupRepository implements the
    // pending-device store.
    holdPendingSiblingDevice:
        ({
          required groupId,
          required memberPeerId,
          required announcedDeviceId,
          required announcedTransportPeerId,
          required announcedDeviceSigningPublicKey,
          required verifiedAccountSigningPublicKey,
          announcedMlKemPublicKey,
          announcedKeyPackageId,
        }) => holdPendingSiblingDevice(
          pendingRepo: groupRepository,
          groupRepo: groupRepository,
          groupId: groupId,
          memberPeerId: memberPeerId,
          announcedDeviceId: announcedDeviceId,
          announcedTransportPeerId: announcedTransportPeerId,
          announcedDeviceSigningPublicKey: announcedDeviceSigningPublicKey,
          verifiedAccountSigningPublicKey: verifiedAccountSigningPublicKey,
          announcedMlKemPublicKey: announcedMlKemPublicKey,
          announcedKeyPackageId: announcedKeyPackageId,
        ),
    getSelfPeerId: () async {
      final identity = await repository.loadIdentity();
      return identity?.peerId;
    },
    terminalizeGroupExitWorkAfterRemoteDissolve: (groupId) async {
      await groupExitIntentRepository.terminalizeForGroup(groupId);
    },
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    notificationService: notificationService,
    groupConversationTracker: groupConversationTracker,
    notificationToneTracker: notificationToneTracker,
    durableNotificationCoordinatorResolver: () async =>
        durableReactionNotificationCoordinator,
    getAppLifecycleState: () =>
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    reactionRepo: reactionRepository,
    inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
    groupDiagnosticEvents: groupDiagnosticEventStream,
    pendingKeyRepairRepo: groupPendingKeyRepairRepository,
    pendingMembershipMessageRepo: groupPendingMembershipMessageRepository,
    pendingReactionRepo: groupPendingReactionRepository,
    requestGroupKeyRepair: requestGroupKeyRepairViaSender,
    rotateGroupKeyAfterRemoteRemoval: (groupId) async {
      // Forward secrecy after a remote member leave/removal the local device
      // did not author. The listener already verified the local device is the
      // group creator; rotateAndDistributeGroupKey re-checks the creator/perm
      // gates and serializes per group, so this is fail-closed.
      final identity = await repository.loadIdentity();
      if (identity == null) return false;
      final rotationOutcome = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepository,
        groupId: groupId,
        selfPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        sendP2PMessage: (peerId, message) async =>
            p2pService.sendMessage(peerId, message),
        storeP2PMessageInInbox: (peerId, message) async =>
            p2pService.storeInInbox(peerId, message),
      );
      return rotationOutcome.rotated;
    },
    recoverFromDispatcherOverflow: (_) async {
      await runAccountRuntimeNetworkVoidAction(
        operation: 'group_dispatcher_overflow_drain',
        action: () async {
          final identity = await repository.loadIdentity();
          await drainGroupOfflineInbox(
            bridge: bridge,
            groupRepo: groupRepository,
            msgRepo: groupMessageRepository,
            groupMessageListener: groupMessageListener,
            mediaAttachmentRepo: mediaAttachmentRepository,
            reactionRepo: reactionRepository,
            pendingReactionRepo: groupPendingReactionRepository,
            pendingKeyRepairRepo: groupPendingKeyRepairRepository,
            historyGapRepairRepo: groupHistoryGapRepairRepository,
            requestGroupKeyRepair: requestGroupKeyRepairViaSender,
            selfPeerId: identity?.peerId,
          );
        },
      );
    },
    appendGroupEventLogEntry:
        ({
          required groupId,
          required eventType,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required payload,
          createdAt,
        }) => dbAppendGroupEventLogEntry(
          db,
          groupId: groupId,
          eventType: eventType,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          payload: payload,
          createdAt: createdAt,
        ),
  );
  final groupMessageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  bridge.onGroupMessageReceived = (data) {
    groupMessageStreamController.add(data);
  };
  final groupReactionStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  bridge.onGroupReactionReceived = (data) {
    groupReactionStreamController.add(data);
  };

  final groupPendingKeyRepairRunner = GroupPendingKeyRepairRunner(
    bridge: bridge,
    groupRepo: groupRepository,
    msgRepo: groupMessageRepository,
    pendingKeyRepairRepo: groupPendingKeyRepairRepository,
    mediaAttachmentRepo: mediaAttachmentRepository,
    reactionRepo: reactionRepository,
    replayGroupEnvelope: (data) => groupMessageListener.handleReplayEnvelope(
      data,
      allowMembershipBuffer: true,
    ),
  );

  // Finding 02 (UDM-B): foreground backoff timer that re-runs the all-pending
  // repair sweep so persisted repairs self-heal mid-session, not only on resume.
  final groupPendingKeyRepairBackoffTimer = GroupPendingKeyRepairBackoffTimer(
    runSweep: groupPendingKeyRepairRunner.retryAllPending,
  );

  // Slice 2 (Finding 03): drainer for deferred key distributions + the prompt
  // member-key-arrival trigger (drain a peer the moment its updated config with
  // a usable ML-KEM key is applied), without threading callbacks through the UI.
  final groupPendingKeyDistributionRunner = GroupPendingKeyDistributionRunner(
    bridge: bridge,
    groupRepo: groupRepository,
    repository: groupPendingKeyDistributionRepository,
    loadIdentity: repository.loadIdentity,
    sendP2PMessage: (peerId, message) async =>
        p2pService.sendMessage(peerId, message),
    storeP2PMessageInInbox: (peerId, message) async =>
        p2pService.storeInInbox(peerId, message),
  );
  setDeferredDistributionDrainSink(({required groupId, required peerId}) async {
    await groupPendingKeyDistributionRunner.drainPendingForPeer(
      groupId: groupId,
      peerId: peerId,
    );
  });

  // Finding 07 (S2b): durable queue for group system broadcasts that failed to
  // leave the device. The metadata-edit producer enqueues through the sink; the
  // runner re-pushes on app resume / rejoin.
  final groupPendingBroadcastRepository = GroupPendingBroadcastRepositoryImpl(
    dbInsert: (row) => dbInsertPendingGroupBroadcast(db, row),
    dbLoadForGroup: (groupId) =>
        dbLoadPendingGroupBroadcastsForGroup(db, groupId),
    dbLoadAll: () => dbLoadAllPendingGroupBroadcasts(db),
    dbCountForGroup: (groupId) =>
        dbCountPendingGroupBroadcastsForGroup(db, groupId),
    dbDelete: (id) => dbDeletePendingGroupBroadcast(db, id),
    dbDeleteIfExact: (expected) =>
        dbDeletePendingGroupBroadcastIfExact(db, expected),
    dbDeleteForGroup: (groupId) =>
        dbDeletePendingGroupBroadcastsForGroup(db, groupId),
  );
  final groupPendingBroadcastRunner = GroupPendingBroadcastRunner(
    repository: groupPendingBroadcastRepository,
    rePushFinalizesSuccess: true,
    rePush: buildGroupPendingBroadcastRePush(
      bridge: bridge,
      groupRepo: groupRepository,
      loadIdentity: repository.loadIdentity,
      pendingRepository: groupPendingBroadcastRepository,
    ),
  );
  setGroupPendingBroadcastEnqueueSink(groupPendingBroadcastRepository.enqueue);
  setGroupPendingBroadcastCountSink(
    groupPendingBroadcastRepository.countForGroup,
  );
  setGroupPendingBroadcastAccessSinks(
    loadForGroup: groupPendingBroadcastRepository.forGroup,
    remove: groupPendingBroadcastRepository.remove,
    discardForGroup: groupPendingBroadcastRepository.removeForGroup,
  );
  setGroupPendingBroadcastDrainSinks(
    forGroup: groupPendingBroadcastRunner.drainForGroup,
    all: groupPendingBroadcastRunner.drainAll,
  );

  groupExitIntentRepository = GroupExitIntentRepositoryImpl(
    dbLoadForGroup: (groupId) => dbLoadGroupExitIntentForGroup(db, groupId),
    dbLoadAll: () => dbLoadAllGroupExitIntents(db),
    dbEnqueue: (row) => dbEnqueueGroupExitIntent(db, row),
    dbCancelQueued: ({required expected, required updatedAt}) =>
        dbCancelQueuedGroupExitIntent(
          db,
          expected: expected,
          updatedAt: updatedAt,
        ),
    dbPrepareLeaveNotice:
        ({
          required expected,
          required timelineRow,
          required pendingBroadcastRow,
          required updatedAt,
        }) => dbPrepareGroupExitLeaveNotice(
          db,
          expected: expected,
          timelineRow: timelineRow,
          pendingBroadcastRow: pendingBroadcastRow,
          updatedAt: updatedAt,
        ),
    dbCompleteLeaveNoticeAttempt:
        ({
          required expected,
          required pendingBroadcastRow,
          required completionCode,
          required updatedAt,
        }) => dbCompleteGroupExitLeaveNotice(
          db,
          expected: expected,
          pendingBroadcastRow: pendingBroadcastRow,
          completionCode: completionCode,
          updatedAt: updatedAt,
        ),
    dbAdvance:
        ({
          required expected,
          required nextState,
          required updatedAt,
          lastErrorCode,
        }) => dbAdvanceGroupExitIntent(
          db,
          expected: expected,
          nextState: nextState,
          updatedAt: updatedAt,
          lastErrorCode: lastErrorCode,
        ),
    dbCleanupOrRetire: ({required expected, required updatedAt}) =>
        dbCleanupOrRetireGroupExitIntent(
          db,
          expected: expected,
          updatedAt: updatedAt,
        ),
    dbRetireExact: (expected) => dbRetireExactGroupExitIntent(db, expected),
    dbTerminalizeForGroup: (groupId) =>
        dbTerminalizeGroupExitIntentForGroup(db, groupId),
  );

  final groupExitIntentRunner = GroupExitIntentRunner(
    intentRepository: groupExitIntentRepository,
    pendingRepository: groupPendingBroadcastRepository,
    pendingBroadcastRunner: groupPendingBroadcastRunner,
    groupRepository: groupRepository,
    loadCurrentSelfPeerId: () async =>
        (await repository.loadIdentity())?.peerId,
    prepareNotice:
        ({required intent, required sourceEventId, required eventAt}) async {
          final group = await groupRepository.getGroup(intent.groupId);
          if (group == null) {
            throw StateError('Group exit notice parent is unavailable.');
          }
          final result = await prepareVoluntaryLeaveNotice(
            bridge: bridge,
            groupRepo: groupRepository,
            group: group,
            identityRepo: repository,
            expectedSelfPeerId: intent.selfPeerId,
            sourceEventId: sourceEventId,
            eventAt: eventAt,
          );
          final prepared = requirePreparedVoluntaryLeaveNotice(result);
          if (prepared.identity.peerId != intent.selfPeerId) {
            throw StateError(
              'Group exit notice identity does not own the intent.',
            );
          }
          final pending = prepared.pendingBroadcast;
          return GroupExitPreparedNotice(
            timelineMessage: prepared.timelineMessage,
            pendingBroadcast: GroupPendingBroadcast(
              id: intent.pendingBroadcastId,
              groupId: pending.groupId,
              kind: pending.kind,
              sysText: pending.sysText,
              recipientPeerIds: pending.recipientPeerIds,
              eventAt: pending.eventAt,
              sourceMessageId: pending.sourceMessageId,
              createdAt: pending.createdAt,
              updatedAt: pending.updatedAt,
            ),
          );
        },
    attemptNotice: ({required intent, required pendingBroadcast}) async {
      final pending = pendingBroadcast;
      final identity = await repository.loadIdentity();
      if (identity == null) {
        throw StateError('Group exit notice identity is unavailable.');
      }
      if (identity.peerId != intent.selfPeerId) {
        throw StateError('Group exit notice identity changed after prepare.');
      }
      final members = await groupRepository.getMembers(pending.groupId);
      final selfMembers = members
          .where((member) => member.peerId == identity.peerId)
          .toList(growable: false);
      if (selfMembers.length != 1) {
        throw StateError('Exact group exit sender membership is unavailable.');
      }
      final remainingByPeerId = {
        for (final member in members)
          if (member.peerId != identity.peerId) member.peerId: member,
      };
      final remainingMembers = <GroupMember>[];
      for (final peerId in pending.recipientPeerIds) {
        final member = remainingByPeerId[peerId];
        if (member != null) remainingMembers.add(member);
      }
      final timelineIdentity = buildMemberRemovedTimelineMessage(
        groupId: pending.groupId,
        removedPeerId: identity.peerId,
        removedUsername: identity.username,
        senderId: identity.peerId,
        senderUsername: identity.username,
        eventAt: pending.eventAt,
      );
      final timelineMessage = await groupMessageRepository.getMessage(
        timelineIdentity.id,
      );
      if (timelineMessage == null) {
        throw StateError('Durable group exit timeline notice is unavailable.');
      }
      final result = await attemptPreparedVoluntaryLeaveNotice(
        bridge: bridge,
        groupRepo: groupRepository,
        prepared: PreparedVoluntaryLeaveNotice(
          pendingBroadcast: pending,
          timelineMessage: timelineMessage,
          identity: identity,
          senderBinding: resolveGroupSenderDeviceBindingFromMember(
            member: selfMembers.single,
            senderPublicKey: identity.publicKey,
          ),
          remainingMembers: remainingMembers,
        ),
        expectedSelfPeerId: intent.selfPeerId,
      );
      return switch (result.classification) {
        VoluntaryLeaveNoticeAttemptClassification.delivered =>
          GroupExitNoticeAttemptDisposition.delivered,
        VoluntaryLeaveNoticeAttemptClassification.degraded =>
          GroupExitNoticeAttemptDisposition.degraded,
        VoluntaryLeaveNoticeAttemptClassification.retryable =>
          GroupExitNoticeAttemptDisposition.retryable,
      };
    },
    rotateKeys: (intent) async {
      final rotation = await rotateVoluntaryLeaveGroupKeyBestEffort(
        bridge: bridge,
        groupRepo: groupRepository,
        groupId: intent.groupId,
        identityRepo: repository,
        expectedSelfPeerId: intent.selfPeerId,
        sendP2PMessage: p2pService.sendMessage,
        storeP2PMessageInInbox: p2pService.storeInInbox,
      );
      if (rotation.rotationDeferred) {
        throw const GroupExitRotationDeferred();
      }
    },
    nativeLeave: (intent) async {
      final identity = await repository.loadIdentity();
      if (identity == null || identity.peerId != intent.selfPeerId) {
        throw StateError('Group exit identity changed before native leave.');
      }
      await callGroupLeave(bridge, intent.groupId);
    },
  );
  final uuid = const Uuid();
  final groupExitIntentCoordinator = GroupExitIntentCoordinator(
    intentRepository: groupExitIntentRepository,
    pendingRepository: groupPendingBroadcastRepository,
    pendingBroadcastRunner: groupPendingBroadcastRunner,
    processor: groupExitIntentRunner,
    groupRepository: groupRepository,
    identityRepository: repository,
    newId: uuid.v4,
    now: () => DateTime.now().toUtc(),
  );
  Future<bool> authorizeCurrentAccountGroupRejoin(String groupId) =>
      authorizeGroupRejoinForExitIntent(
        groupId: groupId,
        loadIntent: groupExitIntentRepository.forGroup,
        loadCurrentSelfPeerId: () async =>
            (await repository.loadIdentity())?.peerId,
      );
  setGroupExitIntentActionSinks(
    requestLeave: groupExitIntentCoordinator.requestLeave,
    queueLeaveWhenSyncCompletes:
        groupExitIntentCoordinator.queueLeaveWhenSyncCompletes,
    retry: groupExitIntentCoordinator.retry,
    cancelQueued: groupExitIntentCoordinator.cancelQueued,
  );
  setGroupExitIntentAccessSinks(
    forGroup: groupExitIntentRepository.forGroup,
    all: groupExitIntentRepository.all,
  );
  setGroupExitIntentRuntimeSinks(
    canRejoin: authorizeCurrentAccountGroupRejoin,
    processExisting: (groupId) async {
      await groupExitIntentRunner.processGroup(groupId);
    },
  );
  setGroupDissolvePreflightAuthority(
    GroupDissolvePreflightAuthority(
      intentRepository: groupExitIntentRepository,
      pendingRepository: groupPendingBroadcastRepository,
    ),
  );

  Future<void> recoverGroupExitIntents() async {
    await runGroupExitIntentRecoveryPass(
      drainPendingBroadcasts: groupPendingBroadcastRunner.drainAll,
      processExitIntents: () async {
        await groupExitIntentRunner.processAll();
      },
      onError: (error, _) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_EXIT_INTENT_RECOVERY_FAILED',
          details: {'error': error.runtimeType.toString()},
        );
      },
    );
  }

  // Create group invite listener
  final groupIdentityCallbacks = buildGroupIdentityCallbacks(
    identityRepo: repository,
    p2pService: p2pService,
  );

  // Slice 2 / UDM-G — assign the real outbound active key-pull now that the
  // identity callbacks exist. Targets the group admin/creator transport peer.
  groupKeyRepairRequestSender = GroupKeyRepairRequestSender(
    bridge: bridge,
    groupRepo: groupRepository,
    getOwnPeerId: groupIdentityCallbacks.getOwnPeerId,
    getOwnDeviceId: groupIdentityCallbacks.getOwnDeviceId,
    getOwnPrivateKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.privateKey;
    },
    sendP2PMessage: (peerId, message) async =>
        p2pService.sendMessage(peerId, message),
    storeP2PMessageInInbox: (peerId, message) async =>
        p2pService.storeInInbox(peerId, message),
  );

  final groupInviteListener = GroupInviteListener(
    groupInviteStream: messageRouter.groupInviteStream,
    groupRepo: groupRepository,
    pendingInviteRepo: pendingGroupInviteRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    msgRepo: groupMessageRepository,
    mediaAttachmentRepo: mediaAttachmentRepository,
    deliveryRepo: groupInviteDeliveryAttemptRepository,
    p2pService: p2pService,
    loadOwnIdentity: () => repository.loadIdentity(),
    getOwnMlKemSecretKey: groupIdentityCallbacks.getOwnMlKemSecretKey,
    getOwnPeerId: groupIdentityCallbacks.getOwnPeerId,
    getOwnDeviceId: groupIdentityCallbacks.getOwnDeviceId,
    getOwnTransportPeerId: groupIdentityCallbacks.getOwnTransportPeerId,
    getOwnMlKemPublicKey: groupIdentityCallbacks.getOwnMlKemPublicKey,
    getOwnKeyPackageId: groupIdentityCallbacks.getOwnKeyPackageId,
    getOwnKeyPackagePublicMaterial:
        groupIdentityCallbacks.getOwnKeyPackagePublicMaterial,
    appendGroupEventLogEntry:
        ({
          required groupId,
          required eventType,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required payload,
          createdAt,
        }) => dbAppendGroupEventLogEntry(
          db,
          groupId: groupId,
          eventType: eventType,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          payload: payload,
          createdAt: createdAt,
        ),
  );

  // Create group key update listener
  final groupKeyUpdateListener = GroupKeyUpdateListener(
    groupKeyUpdateStream: messageRouter.groupKeyUpdateStream,
    groupRepo: groupRepository,
    bridge: bridge,
    getOwnMlKemSecretKey: groupIdentityCallbacks.getOwnMlKemSecretKey,
    getOwnPeerId: groupIdentityCallbacks.getOwnPeerId,
    getOwnDeviceId: groupIdentityCallbacks.getOwnDeviceId,
    retryPendingGroupKeyRepairs:
        groupPendingKeyRepairRunner.retryPendingRepairsForRequest,
    requestGroupKeyRepair: requestGroupKeyRepairViaSender,
    appendGroupEventLogEntry:
        ({
          required groupId,
          required eventType,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required payload,
          createdAt,
        }) => dbAppendGroupEventLogEntry(
          db,
          groupId: groupId,
          eventType: eventType,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          payload: payload,
          createdAt: createdAt,
        ),
  );

  // Slice 2 / UDM-G — admin-side responder for the active key-pull. Re-delivers
  // the EXACT requested epoch (never mints a new one), gated by signed-request
  // verification + member-at-epoch authz + per-(requester,groupId,epoch) rate
  // limiting. Subscribes to the new router case alongside the key-update stream.
  final groupKeyRepairResponderListener = GroupKeyRepairResponderListener(
    groupKeyRepairRequestStream: messageRouter.groupKeyRepairRequestStream,
    groupRepo: groupRepository,
    bridge: bridge,
    getOwnPeerId: groupIdentityCallbacks.getOwnPeerId,
    distributeGroupKeyAtEpochToPeer:
        ({
          required String groupId,
          required String peerId,
          required int keyEpoch,
        }) async {
          final identity = await repository.loadIdentity();
          if (identity == null) return 0;
          return distributeGroupKeyAtEpochToPeer(
            bridge: bridge,
            groupRepo: groupRepository,
            groupId: groupId,
            peerId: peerId,
            keyEpoch: keyEpoch,
            selfPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            senderUsername: identity.username,
            sendP2PMessage: (toPeerId, message) async =>
                p2pService.sendMessage(toPeerId, message),
            storeP2PMessageInInbox: (toPeerId, message) async =>
                p2pService.storeInInbox(toPeerId, message),
          );
        },
  );

  final groupMembershipUpdateListener = GroupMembershipUpdateListener(
    groupMembershipUpdateStream: messageRouter.groupMembershipUpdateStream,
    groupRepo: groupRepository,
    bridge: bridge,
    groupMessageListener: groupMessageListener,
    msgRepo: groupMessageRepository,
    pendingKeyRepairRepo: groupPendingKeyRepairRepository,
    requestGroupKeyRepair: requestGroupKeyRepairViaSender,
  );

  // Create introduction listener
  introductionListener = IntroductionListener(
    introductionStream: messageRouter.introductionStream,
    introRepo: introductionRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    messageRepo: messageRepository,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    getOwnPeerId: () async {
      final identity = await repository.loadIdentity();
      return identity?.peerId;
    },
    notificationService: notificationService,
  );

  // Create pending message retrier
  final pendingMessageRetrier = PendingMessageRetrier(
    p2pService: p2pService,
    messageRepo: messageRepository,
    identityRepo: repository,
    contactRepo: contactRepository,
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
      return runAccountRuntimeNetworkAction<bool>(
        operation: 'pending_retrier_group_rejoin',
        blockedValue: false,
        action: () async {
          final needsGroupRecovery =
              p2pService.currentState.needsGroupRecovery ?? false;
          final recoveryMethod = p2pService.lastRecoveryMethod;
          final reason = needsGroupRecovery
              ? RejoinReason.nodeRequestedRecovery
              : recoveryMethod == 'watchdog_restart'
              ? RejoinReason.watchdogRestart
              : RejoinReason.inPlaceRecovery;
          final rejoinResult = await rejoinGroupTopics(
            bridge: bridge,
            groupRepo: groupRepository,
            reason: reason,
            canRejoinForExitIntent: authorizeCurrentAccountGroupRejoin,
            processExitIntent: (groupId) async {
              await groupExitIntentRunner.processGroup(groupId);
            },
          );
          // 123 S1 — after rejoin, reconcile any missed TERMINAL dissolve so a
          // group dissolved while we were offline converges (and is left)
          // instead of staying live. AFTER rejoin so active groups re-subscribe
          // immediately; the cursor-independent probe also recovers a dissolve
          // the incremental drain already skipped.
          final reconcileIdentity = await repository.loadIdentity();
          await reconcileMissedGroupDissolves(
            bridge: bridge,
            groupRepo: groupRepository,
            groupMessageListener: groupMessageListener,
            selfPeerId: reconcileIdentity?.peerId,
          );

          return reason == RejoinReason.nodeRequestedRecovery &&
              rejoinResult.canAcknowledgeGroupRecovery;
        },
      );
    },
    acknowledgeGroupRecoveryFn: () => runAccountRuntimeNetworkVoidAction(
      operation: 'pending_retrier_group_ack_recovery',
      action: () => callGroupAcknowledgeRecovery(bridge),
    ),
    drainGroupOfflineInboxFn: () async {
      return runAccountRuntimeNetworkAction<GroupOfflineInboxDrainResult>(
        operation: 'pending_retrier_group_drain',
        blockedValue: const GroupOfflineInboxDrainResult(
          groupCount: 0,
          errorCount: 0,
        ),
        action: () async {
          final identity = await repository.loadIdentity();
          return drainGroupOfflineInbox(
            bridge: bridge,
            groupRepo: groupRepository,
            msgRepo: groupMessageRepository,
            groupMessageListener: groupMessageListener,
            mediaAttachmentRepo: mediaAttachmentRepository,
            reactionRepo: reactionRepository,
            pendingReactionRepo: groupPendingReactionRepository,
            pendingKeyRepairRepo: groupPendingKeyRepairRepository,
            historyGapRepairRepo: groupHistoryGapRepairRepository,
            requestGroupKeyRepair: requestGroupKeyRepairViaSender,
            selfPeerId: identity?.peerId,
          );
        },
      );
    },
    recoverStuckSendingGroupMessagesFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_group_stuck_recovery',
      blockedValue: 0,
      action: () => recoverStuckSendingGroupMessages(
        groupMsgRepo: groupMessageRepository,
      ),
    ),
    retryIncompleteGroupUploadsFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_group_upload_retry',
      blockedValue: 0,
      action: () => retryIncompleteGroupUploads(
        groupRepo: groupRepository,
        groupMsgRepo: groupMessageRepository,
        mediaAttachmentRepo: mediaAttachmentRepository,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: repository,
        mediaFileManager: mediaFileManager,
        inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
        tryClaimUploadLease: (attachmentIds) => mediaUploadInFlightTracker
            .tryClaimAll(attachmentIds, source: MediaUploadTriggerSource.full),
        releaseUploadLease: mediaUploadInFlightTracker.release,
        requireOsConnectivity: true,
      ),
    ),
    retryIncompleteGroupUploadsNetworkRestoredFn: () =>
        runAccountRuntimeNetworkAction(
          operation: 'pending_retrier_group_upload_retry_network_restored',
          blockedValue: 0,
          action: () => retryIncompleteGroupUploads(
            groupRepo: groupRepository,
            groupMsgRepo: groupMessageRepository,
            mediaAttachmentRepo: mediaAttachmentRepository,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: repository,
            mediaFileManager: mediaFileManager,
            inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
            tryClaimUploadLease: (attachmentIds) =>
                mediaUploadInFlightTracker.tryClaimAll(
                  attachmentIds,
                  source: MediaUploadTriggerSource.networkRestored,
                ),
            releaseUploadLease: mediaUploadInFlightTracker.release,
          ),
        ),
    retryIncompleteGroupUploadsPeriodicFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_group_upload_retry_periodic',
      blockedValue: 0,
      action: () => retryIncompleteGroupUploads(
        groupRepo: groupRepository,
        groupMsgRepo: groupMessageRepository,
        mediaAttachmentRepo: mediaAttachmentRepository,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: repository,
        mediaFileManager: mediaFileManager,
        inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
        tryClaimUploadLease: (attachmentIds) =>
            mediaUploadInFlightTracker.tryClaimAll(
              attachmentIds,
              source: MediaUploadTriggerSource.periodic,
            ),
        releaseUploadLease: mediaUploadInFlightTracker.release,
        requireOsConnectivity: true,
      ),
    ),
    retryFailedGroupMessagesFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_group_failed_retry',
      blockedValue: 0,
      action: () => retryFailedGroupMessages(
        groupMsgRepo: groupMessageRepository,
        groupRepo: groupRepository,
        identityRepo: repository,
        bridge: bridge,
        mediaAttachmentRepo: mediaAttachmentRepository,
        inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
      ),
    ),
    retryPendingIntroductionDeliveriesFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_intro_delivery_retry',
      blockedValue: 0,
      action: () => retryPendingIntroductionDeliveries(
        introRepo: introductionRepository,
        p2pService: p2pService,
      ),
    ),
    retryFailedGroupInboxStoresFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_group_inbox_store_retry',
      blockedValue: 0,
      action: () => retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: groupMessageRepository,
        reactionReplayOutboxRepo: groupReactionReplayOutboxRepository,
        groupRepo: groupRepository,
        identityRepo: repository,
      ),
    ),
    // Finding 05 Phase 4: reconnect re-arms backed-off failed group rows (local
    // DB op — no network gate needed).
    clearGroupRetryBackoffFn: groupMessageRepository.clearRetryBackoff,
    // 195: queued offline sends leave on the OS connectivity-restored edge —
    // the relay inbox store only needs an outbound dial, not the relay
    // reservation the stateStream online edge waits for (~2s vs ~8s).
    networkRestoredSignal: connectivityRestoredSignal(),
    // Finding 05 Phase 4 (P1.6): jitter the background retry cadence in prod so
    // reconnecting clients do not stampede the relay in lockstep.
    jitterRandom: Random(),
    verifyInboxCustodyFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_inbox_custody_verify',
      blockedValue: 0,
      action: () => verifyInboxCustody(
        loadInboxCustody: messageRepository.getInboxCustodyOutgoingMessages,
        storeInInboxDetailed: p2pService.storeInInboxDetailed,
        markCustodyChecked: messageRepository.markInboxCustodyChecked,
        messageRepo: messageRepository,
      ),
    ),
    recoverStuckSendingMessagesFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_message_stuck_recovery',
      blockedValue: 0,
      action: () => recoverStuckSendingMessages(messageRepo: messageRepository),
    ),
    retryIncompleteUploadsFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_upload_retry',
      blockedValue: 0,
      action: () => retryIncompleteUploads(
        mediaAttachmentRepo: mediaAttachmentRepository,
        messageRepo: messageRepository,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: repository,
        contactRepo: contactRepository,
        mediaFileManager: mediaFileManager,
        isUploadInFlight: mediaUploadInFlightTracker.isInFlight,
        tryClaimUploadLease: (attachmentIds) => mediaUploadInFlightTracker
            .tryClaimAll(attachmentIds, source: MediaUploadTriggerSource.full),
        releaseUploadLease: mediaUploadInFlightTracker.release,
        requireOsConnectivity: true,
      ),
    ),
    retryIncompleteUploadsNetworkRestoredFn: () =>
        runAccountRuntimeNetworkAction(
          operation: 'pending_retrier_upload_retry_network_restored',
          blockedValue: 0,
          action: () => retryIncompleteUploads(
            mediaAttachmentRepo: mediaAttachmentRepository,
            messageRepo: messageRepository,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: repository,
            contactRepo: contactRepository,
            mediaFileManager: mediaFileManager,
            tryClaimUploadLease: (attachmentIds) =>
                mediaUploadInFlightTracker.tryClaimAll(
                  attachmentIds,
                  source: MediaUploadTriggerSource.networkRestored,
                ),
            releaseUploadLease: mediaUploadInFlightTracker.release,
          ),
        ),
    retryIncompleteUploadsPeriodicFn: () => runAccountRuntimeNetworkAction(
      operation: 'pending_retrier_upload_retry_periodic',
      blockedValue: 0,
      action: () => retryIncompleteUploads(
        mediaAttachmentRepo: mediaAttachmentRepository,
        messageRepo: messageRepository,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: repository,
        contactRepo: contactRepository,
        mediaFileManager: mediaFileManager,
        tryClaimUploadLease: (attachmentIds) =>
            mediaUploadInFlightTracker.tryClaimAll(
              attachmentIds,
              source: MediaUploadTriggerSource.periodic,
            ),
        releaseUploadLease: mediaUploadInFlightTracker.release,
        requireOsConnectivity: true,
      ),
    ),
  );

  final pendingPostMediaUploadRetrier = PendingPostMediaUploadRetrier(
    p2pService: p2pService,
    postRepo: postRepository,
    contactRepo: contactRepository,
    secureKeyStore: secureKeyStore,
    imageProcessor: imageProcessor,
    mediaFileManager: mediaFileManager,
    bridge: bridge,
    accountMigrationNetworkGate:
        accountMigrationRuntimeNetworkGate.allowsAccountNetworkSideEffects,
  );
  final pendingPostDeliveryRetrier = PendingPostDeliveryRetrier(
    p2pService: p2pService,
    postRepo: postRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    beforeRetry: pendingPostMediaUploadRetrier.retryNow,
    accountMigrationNetworkGate:
        accountMigrationRuntimeNetworkGate.allowsAccountNetworkSideEffects,
  );
  final pendingPostFollowOnRetrier = PendingPostFollowOnRetrier(
    p2pService: p2pService,
    postRepo: postRepository,
    accountMigrationNetworkGate:
        accountMigrationRuntimeNetworkGate.allowsAccountNetworkSideEffects,
  );

  // Create key exchange retrier
  final keyExchangeRetrier = KeyExchangeRetrier(
    p2pService: p2pService,
    contactRepo: contactRepository,
    identityRepo: repository,
    bridge: bridge,
    secureKeyStore: secureKeyStore,
    accountMigrationNetworkGate:
        accountMigrationRuntimeNetworkGate.allowsAccountNetworkSideEffects,
    // FDC-09 §12 / CV-14: the backfill drain distributes wake-tokens (DARK until
    // the emission define flips) — read-only, never mints/registers.
    resolveWakeToken: wakeTokenResolver,
  );

  var liveServicesStarted = false;
  Future<void> startLiveServices() async {
    if (liveServicesStarted) {
      return;
    }
    // 234 Session 03: this is the shared cold-start recovery future also
    // kicked after runApp. Await it before even consulting the network gate so
    // bridge/listener/P2P startup can never overtake local terminalization and
    // cleanup. A concurrent caller reuses the same future.
    await ensurePrivateMediaColdRecovery();
    final groupContextBackfill = keychainMirrorBackfill;
    if (groupContextBackfill != null) {
      await groupContextBackfill;
    }
    await groupReactionComparandBackfill;
    if (liveServicesStarted) {
      return;
    }
    if (!await allowsAccountRuntimeNetworkSideEffects('live_services_start')) {
      return;
    }
    liveServicesStarted = true;

    await ensureFirebaseReady();
    await bridge.initialize();
    StartupTiming.instance.mark('bridge_initialized');
    await notificationService.initialize();
    StartupTiming.instance.mark('notification_service_ready');

    // Start router first, then listeners, then retriers.
    messageRouter.start();
    contactRequestListener.start();
    chatMessageListener.start();
    postListener.start();
    postCommentListener.start();
    postReactionListener.start();
    postPresenceListener.start();
    postPassListener.start();
    postPinListener.start();
    reactionListener.start();
    messageDeletionListener.start();
    deliveryReceiptListener.start();
    profileUpdateListener.start();
    groupMessageListener.start(
      groupMessageStreamController.stream,
      incomingGroupReactions: groupReactionStreamController.stream,
    );
    groupInviteListener.start();
    groupKeyUpdateListener.start();
    groupKeyRepairResponderListener.start();
    groupMembershipUpdateListener.start();
    introductionListener.start();

    // NOTE: rejoinGroupTopics and drainGroupOfflineInbox are called in
    // StartupRouter._doStartP2P() AFTER node:start completes. They require
    // the Go node to be running (pubsub must be initialized).
    pendingMessageRetrier.start();
    groupPendingKeyRepairBackoffTimer.start();
    pendingPostMediaUploadRetrier.start();
    pendingPostDeliveryRetrier.start();
    pendingPostFollowOnRetrier.start();
    keyExchangeRetrier.start();

    // Forward profile avatar updates through chatMessageListener so
    // FeedWired/OrbitWired (which subscribe to contactUpdatedStream) refresh.
    profileUpdateListener.contactUpdatedStream.listen((contact) {
      chatMessageListener.emitContactUpdate(contact);
    });

    // Forward ML-KEM key updates from reciprocal contact requests so
    // ConversationWired/FeedWired pick up the new encryption key.
    contactRequestListener.contactKeyUpdatedStream.listen((contact) {
      chatMessageListener.emitContactUpdate(contact);
      // FDC-09 §12 / CV-14: a key rotation changed the recipient set — coalesce
      // a single re-mint+register (INV-5).
      wakeTokenReissueCoalescer.trigger();
    });

    // 171: a one-scan tap-free auto-add — refresh the UI so the new mutual
    // contact appears immediately (same path as a key update; feed/orbit
    // surfaces listening to contact changes render the non-modal update).
    contactRequestListener.autoAddedStream.listen((contact) {
      chatMessageListener.emitContactUpdate(contact);
      // FDC-09 §12 / CV-14: a new mutual contact — coalesce a single re-issue.
      wakeTokenReissueCoalescer.trigger();
    });
    StartupTiming.instance.mark('runtime_services_ready');
  }

  // 164 (cold-start-1): startLiveServices (Firebase init + bridge + ~25 listener
  // .start() calls) is no longer awaited here on a normal launch. It is wired as
  // the unconditional deferredRuntimeStartup below and kicked off OFF the
  // pre-runApp critical path by MyApp.initState's _ensureRuntimeServicesReady
  // trigger (the same deferred path the share launch already used).

  // ── Smoke test Phase 1: pre-populate contacts before UI renders ──
  // This ensures StartupRouter sees contacts and routes to Feed, not FTE.
  if (kDebugMode && !isShareLaunch) {
    await prePopulateContactsFromIntroE2EConfig(contactRepo: contactRepository);
  }

  runApp(
    MyApp(
      repository: repository,
      contactRepository: contactRepository,
      contactRequestRepository: contactRequestRepository,
      contactRequestListener: contactRequestListener,
      // FDC-09 §12 / CV-14 (217 §A1): once-per-cycle mint+register hook, invoked
      // by StartupRouter after node-start with all active contact peerIds.
      issueWakeTokensForContacts: issueWakeTokensUseCase.issueForContacts,
      contactRequestPresentationGate: contactRequestPresentationGate,
      messageRepository: messageRepository,
      postRepository: postRepository,
      postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      feedClearedRepository: feedClearedRepository,
      contactPresenceSnapshotRepository: contactPresenceSnapshotRepository,
      nearbyLocationService: nearbyLocationService,
      mediaAttachmentRepository: mediaAttachmentRepository,
      groupMediaDeleteForMeCoordinator: deleteGroupMediaForMeUseCase,
      groupMediaDeletionCleanup: () async {
        await groupMediaDeletionReconciler.runBounded();
      },
      privateMediaLifecycleRecovery:
          privateMediaLifecycleForegroundRuntime.recoverResumeAndArm,
      stopPrivateMediaExpiryScheduler:
          privateMediaLifecycleForegroundRuntime.onBackgrounded,
      disposePrivateMediaExpiryScheduler:
          privateMediaLifecycleForegroundRuntime.dispose,
      chatMessageListener: chatMessageListener,
      postListener: postListener,
      postCommentListener: postCommentListener,
      postReactionListener: postReactionListener,
      postPresenceListener: postPresenceListener,
      postPassListener: postPassListener,
      postPinListener: postPinListener,
      reactionListener: reactionListener,
      messageDeletionListener: messageDeletionListener,
      profileUpdateListener: profileUpdateListener,
      messageRouter: messageRouter,
      pendingMessageRetrier: pendingMessageRetrier,
      pendingPostMediaUploadRetrier: pendingPostMediaUploadRetrier,
      pendingPostDeliveryRetrier: pendingPostDeliveryRetrier,
      pendingPostFollowOnRetrier: pendingPostFollowOnRetrier,
      keyExchangeRetrier: keyExchangeRetrier,
      bridge: bridge,
      p2pService: p2pService,
      transportMetrics: transportMetrics,
      mediaFileManager: mediaFileManager,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      audioRecorderService: audioRecorderService,
      privateMediaOutboxE2EController: privateMediaOutboxE2EController,
      reactionRepository: reactionRepository,
      isDesktop: isDesktop,
      notificationService: notificationService,
      appShellController: appShellController,
      pendingPostTargetStore: pendingPostTargetStore,
      conversationTracker: conversationTracker,
      groupRepository: groupRepository,
      groupMessageRepository: groupMessageRepository,
      groupInviteDeliveryAttemptRepository:
          groupInviteDeliveryAttemptRepository,
      groupPendingKeyRepairRepository: groupPendingKeyRepairRepository,
      groupPendingReactionRepository: groupPendingReactionRepository,
      groupPendingKeyRepairRunner: groupPendingKeyRepairRunner,
      groupPendingKeyRepairBackoffTimer: groupPendingKeyRepairBackoffTimer,
      groupPendingKeyDistributionRunner: groupPendingKeyDistributionRunner,
      groupExitIntentRecovery: recoverGroupExitIntents,
      canRejoinForExitIntent: authorizeCurrentAccountGroupRejoin,
      processGroupExitIntent: (groupId) async {
        await groupExitIntentRunner.processGroup(groupId);
      },
      groupHistoryGapRepairRepository: groupHistoryGapRepairRepository,
      groupReactionReplayOutboxRepository: groupReactionReplayOutboxRepository,
      groupMessageListener: groupMessageListener,
      groupInviteListener: groupInviteListener,
      groupKeyUpdateListener: groupKeyUpdateListener,
      groupKeyRepairResponderListener: groupKeyRepairResponderListener,
      requestGroupKeyRepair: requestGroupKeyRepairViaSender,
      groupMembershipUpdateListener: groupMembershipUpdateListener,
      groupConversationTracker: groupConversationTracker,
      introductionRepository: introductionRepository,
      introReviewSeenRepository: introReviewSeenRepository,
      introductionListener: introductionListener,
      shareIntentService: shareIntentService,
      pushRegistrationCoordinator: pushRegistrationCoordinator,
      accountMigrationRunTransfer:
          accountMigrationTransferRuntime.runOldPhoneTransfer,
      accountMigrationSizeGate: accountMigrationSizeGate,
      accountMigrationStartReceiver:
          accountMigrationTransferRuntime.startNewPhoneReceiver,
      accountMigrationStopReceiver:
          accountMigrationTransferRuntime.stopNewPhoneReceiver,
      accountMigrationReceiverEvents:
          accountMigrationTransferRuntime.receiverEvents,
      accountMigrationRecoverExportPause: () async {
        if (accountMigrationTransferRuntime.hasActiveExportRun) {
          return false;
        }
        return accountMigrationCutoverCoordinator
            .restoreActiveAfterExportInterrupted();
      },
      deferredRuntimeStartup: startLiveServices,
      ingestStagedPushEnvelopes: ({required String source}) async {
        await ingestStagedPushEnvelopesUseCase(source: source);
      },
      firebaseReadiness: firebaseReadiness,
      onAppDetached: () async {
        // Best-effort graceful teardown on app termination. Stopping the node
        // lets libp2p close streams and release its relay reservation / QUIC
        // sockets server-side; closing the DB drops the SQLCipher file lock
        // cleanly. Together these prevent the next cold start from stalling on
        // the splash screen (which previously only a phone reboot cleared).
        // The OS gives us a brief window, so each step is time-bounded.
        try {
          await p2pService.stopNode().timeout(const Duration(seconds: 2));
        } catch (e) {
          if (kDebugMode) debugPrint('[TEARDOWN] stopNode failed/timeout: $e');
        }
        try {
          await db.close().timeout(const Duration(seconds: 2));
        } catch (e) {
          if (kDebugMode) debugPrint('[TEARDOWN] db.close failed/timeout: $e');
        }
      },
    ),
  );
  if (directReactionNotificationProjection != null) {
    final iosSenderFixtureStore = IosSenderProjectionFixtureStore(
      loadLocalAccountPeerId: () async =>
          (await repository.loadIdentity())?.peerId,
      loadProjectionAccountPeerId:
          directReactionNotificationProjection.readLocalAccountPeerId,
      loadContact: contactRepository.getContact,
      insertContactIfAbsent: (contact) =>
          dbSimsInsertContactIfAbsent(db, contact.toMap()),
      deleteContactIfExact: (contact) =>
          dbSimsDeleteContactIfExact(db, contact.toMap()),
      loadProjectedContact: (peerId) async =>
          (await directReactionNotificationProjection.readContacts())[peerId],
      insertProjectedContactIfAbsent: (request) =>
          directReactionNotificationProjection.insertSimsFixtureContactIfAbsent(
            peerId: request.senderPeerId,
            username: request.senderUsername,
            fixtureDigest: request.fixtureDigest,
          ),
      deleteProjectedContactIfExact: (request) =>
          directReactionNotificationProjection.removeSimsFixtureContactIfExact(
            peerId: request.senderPeerId,
            username: request.senderUsername,
            fixtureDigest: request.fixtureDigest,
          ),
    );
    unawaited(
      runIosSenderProjectionFixtureLoop(
        coordinator: IosSenderProjectionFixtureCoordinator(
          iosSenderFixtureStore,
        ),
      ),
    );
  }
  StartupTiming.instance.mark('run_app_called');
  // 234 Session 03: kick the same local-only future that startLiveServices
  // awaits. The call remains off the pre-runApp path, while network startup is
  // causally ordered behind it.
  unawaited(ensurePrivateMediaColdRecovery());
  unawaited(
    sweepExpiredPosts(
      postRepo: postRepository,
      mediaFileManager: mediaFileManager,
    ).catchError((Object error, StackTrace stackTrace) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_SWEEP_STARTUP_ERROR',
        details: {'error': error.toString()},
      );
      return <String>[];
    }),
  );
  unawaited(
    sweepExpiredGroupInvites(repo: pendingGroupInviteRepository).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_SWEEP_STARTUP_ERROR',
        details: {'error': error.toString()},
      );
      return GroupInviteSweepResult.empty;
    }),
  );
  // 235: cold-start deletion-journal reconciliation — finishes any
  // Delete-for-me cleanup a previous process crashed out of. Local-only,
  // bounded, per-item isolated; errors never block startup.
  unawaited(
    groupMediaDeletionReconciler.runBounded().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEDIA_DELETION_STARTUP_RECONCILE_ERROR',
        details: {'error': error.toString()},
      );
      return GroupMediaDeletionCleanupStats();
    }),
  );

  // Keep polling for intro E2E config files in explicit test mode so
  // simulator relaunch timing does not race a single startup timer.
  startIntroE2EPoller(
    p2pService: p2pService,
    bridge: bridge,
    identityRepo: repository,
    contactRepo: contactRepository,
    contactRequestRepo: contactRequestRepository,
    introRepo: introductionRepository,
    messageRepo: messageRepository,
    pushEnvelopeStagingStore: pushEnvelopeStagingStore,
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    audioRecorderService: audioRecorderService,
    groupReactionProbeDatabase: db,
    groupReactionProbeSecureKeyStore: secureKeyStore,
    wakeTokenStore: wakeTokenStore,
    receivedWakeTokenStore: receivedWakeTokenStore,
    registerWakeTokens: (tokens) => registerWakeTokensViaBridge(bridge, tokens),
    detailedInboxStore: p2pService,
    wakeTokenAttachmentObserver: wakeTokenAttachmentObserver,
    privateMediaOutboxE2EController: privateMediaOutboxE2EController,
    resolveWakeToken: wakeTokenResolver,
    openConversationByPeerId: (peerId) async {
      for (var attempt = 0; attempt < 30; attempt++) {
        final navigator = MyApp.navigatorKey.currentState;
        final contact = await contactRepository.getContact(peerId);
        if (navigator != null && contact != null) {
          navigator.popUntil((route) => route.isFirst);
          unawaited(
            navigator.push(
              buildConversationRoute(
                builder: (_) => ConversationWired(
                  contact: contact,
                  identityRepo: repository,
                  messageRepo: messageRepository,
                  uploadRetryProjectionRepo: messageRepository,
                  chatMessageListener: chatMessageListener,
                  p2pService: p2pService,
                  bridge: bridge,
                  contactRepo: contactRepository,
                  mediaAttachmentRepo: mediaAttachmentRepository,
                  mediaFileManager: mediaFileManager,
                  imageProcessor: imageProcessor,
                  conversationTracker: conversationTracker,
                  audioRecorderService: audioRecorderService,
                  reactionRepo: reactionRepository,
                  reactionListener: reactionListener,
                  introductionRepository: introductionRepository,
                  forwardGroupRepository: groupRepository,
                  forwardGroupMessageRepository: groupMessageRepository,
                  forwardGroupInviteDeliveryAttemptRepository:
                      groupInviteDeliveryAttemptRepository,
                  forwardGroupMessageListener: groupMessageListener,
                  forwardGroupConversationTracker: groupConversationTracker,
                  appShellController: appShellController,
                  transportMetrics: transportMetrics,
                  privateMediaOutboxE2EController:
                      privateMediaOutboxE2EController,
                ),
              ),
            ),
          );
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return false;
    },
  );
}

Future<void> openIntroNotificationOrbitRoute({
  required NavigatorState navigator,
  required AppShellController appShellController,
  required MessageRepository messageRepository,
  required Widget Function(ValueListenable<int> feedUnreadCountListenable)
  builder,
}) async {
  final returnTab = appShellController.activeTab;
  final unreadCount = await messageRepository
      .getTotalUnreadCountExcludingArchived();
  final feedUnreadCountNotifier = ValueNotifier<int>(unreadCount);

  if (appShellController.activeTab != AppShellTab.orbit) {
    appShellController.switchTo(AppShellTab.orbit);
  }

  try {
    await navigator.push(
      buildOrbitSlideUpRoute(builder: (_) => builder(feedUnreadCountNotifier)),
    );
  } finally {
    if (appShellController.activeTab == AppShellTab.orbit) {
      appShellController.switchTo(returnTab);
    }
    feedUnreadCountNotifier.dispose();
  }
}

class MyApp extends StatefulWidget {
  final IdentityRepositoryImpl repository;
  final ContactRepositoryImpl contactRepository;
  final ContactRequestRepositoryImpl contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final ContactRequestPresentationGate contactRequestPresentationGate;
  // FDC-09 §12 / CV-14 (217 §A1): once-per-cycle wake-token mint+register hook.
  final Future<bool> Function(List<String> contactPeerIds)?
  issueWakeTokensForContacts;
  final MessageRepositoryImpl messageRepository;
  final PostRepositoryImpl postRepository;
  final PostsPrivacySettingsRepositoryImpl postsPrivacySettingsRepository;
  final FeedClearedRepository feedClearedRepository;
  final ContactPresenceSnapshotRepositoryImpl contactPresenceSnapshotRepository;
  final NearbyLocationService nearbyLocationService;
  final MediaAttachmentRepositoryImpl mediaAttachmentRepository;

  /// 235: production Delete-for-me coordinator (journal prepare + cleanup).
  final GroupMediaDeleteForMeCoordinator groupMediaDeleteForMeCoordinator;

  /// 235: one bounded deletion-journal reconciliation pass; runs on resume
  /// BEFORE the account-migration network gate (local-only work).
  final Future<void> Function() groupMediaDeletionCleanup;

  /// 234 Session 03: the same bounded local direct private-media recovery is
  /// used at cold start and resume. Scheduler callbacks keep expiry strictly
  /// foreground-only without coupling it to network readiness.
  final Future<void> Function()? privateMediaLifecycleRecovery;
  final void Function()? stopPrivateMediaExpiryScheduler;
  final void Function()? disposePrivateMediaExpiryScheduler;
  final ChatMessageListener chatMessageListener;
  final PostListener postListener;
  final PostCommentListener postCommentListener;
  final PostReactionListener postReactionListener;
  final PostPresenceListener postPresenceListener;
  final PostPassListener postPassListener;
  final PostPinListener postPinListener;
  final ReactionListener reactionListener;
  final MessageDeletionListener messageDeletionListener;
  final ProfileUpdateListener profileUpdateListener;
  final IncomingMessageRouter messageRouter;
  final PendingMessageRetrier pendingMessageRetrier;
  final PendingPostMediaUploadRetrier pendingPostMediaUploadRetrier;
  final PendingPostDeliveryRetrier pendingPostDeliveryRetrier;
  final PendingPostFollowOnRetrier pendingPostFollowOnRetrier;
  final KeyExchangeRetrier keyExchangeRetrier;
  final Bridge bridge;
  final P2PServiceImpl p2pService;
  final TransportMetrics? transportMetrics;
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final AudioRecorderService audioRecorderService;
  final PrivateMediaOutboxE2EController? privateMediaOutboxE2EController;
  final bool isDesktop;
  final ReactionRepositoryImpl reactionRepository;
  final NotificationService notificationService;
  final AppShellController appShellController;
  final PendingPostTargetStore pendingPostTargetStore;
  final ActiveConversationTracker conversationTracker;
  final GroupRepositoryImpl groupRepository;
  final GroupMessageRepositoryImpl groupMessageRepository;
  final GroupInviteDeliveryAttemptRepositoryImpl
  groupInviteDeliveryAttemptRepository;
  final GroupPendingKeyRepairRepositoryImpl groupPendingKeyRepairRepository;
  final GroupPendingReactionRepository groupPendingReactionRepository;
  final GroupPendingKeyRepairRunner groupPendingKeyRepairRunner;
  final GroupPendingKeyRepairBackoffTimer groupPendingKeyRepairBackoffTimer;
  final GroupPendingKeyDistributionRunner groupPendingKeyDistributionRunner;
  final Future<void> Function()? groupExitIntentRecovery;
  final Future<bool> Function(String groupId)? canRejoinForExitIntent;
  final Future<void> Function(String groupId)? processGroupExitIntent;
  final GroupHistoryGapRepairRepositoryImpl groupHistoryGapRepairRepository;
  final GroupReactionReplayOutboxRepositoryImpl
  groupReactionReplayOutboxRepository;
  final GroupMessageListener groupMessageListener;
  final GroupInviteListener groupInviteListener;
  final GroupKeyUpdateListener groupKeyUpdateListener;
  final GroupKeyRepairResponderListener groupKeyRepairResponderListener;
  final RequestGroupKeyRepair requestGroupKeyRepair;
  final GroupMembershipUpdateListener groupMembershipUpdateListener;
  final ActiveConversationTracker groupConversationTracker;
  final IntroductionRepositoryImpl introductionRepository;
  final IntroReviewSeenRepositoryImpl introReviewSeenRepository;
  final IntroductionListener introductionListener;
  final ShareIntentService shareIntentService;
  final PushRegistrationCoordinator? pushRegistrationCoordinator;
  final AccountMigrationTransferRunFn? accountMigrationRunTransfer;
  final AccountMigrationSizeGate? accountMigrationSizeGate;
  final AccountMigrationReceiverStartFn? accountMigrationStartReceiver;
  final AccountMigrationReceiverStopFn? accountMigrationStopReceiver;
  final AccountMigrationReceiverEvents? accountMigrationReceiverEvents;

  /// Restores active authority on app resume when a Move Account export
  /// pause is stale (no export run in flight). See handleAppResumed.
  final Future<bool> Function()? accountMigrationRecoverExportPause;
  final Future<void> Function()? deferredRuntimeStartup;
  final Future<void> Function({required String source})?
  ingestStagedPushEnvelopes;

  /// 191 (Fix D2): the shared Firebase-readiness latch. _MyAppState registers
  /// its push-listener arm on this (the third arm point) so a retried/late
  /// Firebase init still arms the foreground-push listeners. Optional so the
  /// widget-test harnesses (no real Firebase) construct MyApp without it.
  final FirebaseReadiness? firebaseReadiness;

  /// Best-effort teardown invoked on [AppLifecycleState.detached] (app
  /// terminating): stops the libp2p node and closes the encrypted DB so the
  /// next cold start doesn't stall on the splash screen behind a stale
  /// socket/relay reservation or DB lock.
  final Future<void> Function()? onAppDetached;

  static final navigatorKey = GlobalKey<NavigatorState>();

  // 04-P0 / QW-2: app-level messenger so notification handlers (which run
  // outside any Scaffold subtree) can surface SnackBar feedback.
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  const MyApp({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.contactRequestPresentationGate,
    this.issueWakeTokensForContacts,
    required this.messageRepository,
    required this.postRepository,
    required this.postsPrivacySettingsRepository,
    required this.feedClearedRepository,
    required this.contactPresenceSnapshotRepository,
    required this.nearbyLocationService,
    required this.mediaAttachmentRepository,
    required this.groupMediaDeleteForMeCoordinator,
    required this.groupMediaDeletionCleanup,
    this.privateMediaLifecycleRecovery,
    this.stopPrivateMediaExpiryScheduler,
    this.disposePrivateMediaExpiryScheduler,
    required this.chatMessageListener,
    required this.postListener,
    required this.postCommentListener,
    required this.postReactionListener,
    required this.postPresenceListener,
    required this.postPassListener,
    required this.postPinListener,
    required this.reactionListener,
    required this.messageDeletionListener,
    required this.profileUpdateListener,
    required this.messageRouter,
    required this.pendingMessageRetrier,
    required this.pendingPostMediaUploadRetrier,
    required this.pendingPostDeliveryRetrier,
    required this.pendingPostFollowOnRetrier,
    required this.keyExchangeRetrier,
    required this.bridge,
    required this.p2pService,
    this.transportMetrics,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.audioRecorderService,
    this.privateMediaOutboxE2EController,
    required this.reactionRepository,
    required this.isDesktop,
    required this.notificationService,
    required this.appShellController,
    required this.pendingPostTargetStore,
    required this.conversationTracker,
    required this.groupRepository,
    required this.groupMessageRepository,
    required this.groupInviteDeliveryAttemptRepository,
    required this.groupPendingKeyRepairRepository,
    required this.groupPendingReactionRepository,
    required this.groupPendingKeyRepairRunner,
    required this.groupPendingKeyRepairBackoffTimer,
    required this.groupPendingKeyDistributionRunner,
    this.groupExitIntentRecovery,
    this.canRejoinForExitIntent,
    this.processGroupExitIntent,
    required this.groupHistoryGapRepairRepository,
    required this.groupReactionReplayOutboxRepository,
    required this.groupMessageListener,
    required this.groupInviteListener,
    required this.groupKeyUpdateListener,
    required this.groupKeyRepairResponderListener,
    required this.requestGroupKeyRepair,
    required this.groupMembershipUpdateListener,
    required this.groupConversationTracker,
    required this.introductionRepository,
    required this.introReviewSeenRepository,
    required this.introductionListener,
    required this.shareIntentService,
    this.pushRegistrationCoordinator,
    this.accountMigrationRunTransfer,
    this.accountMigrationSizeGate,
    this.accountMigrationStartReceiver,
    this.accountMigrationStopReceiver,
    this.accountMigrationReceiverEvents,
    this.accountMigrationRecoverExportPause,
    this.deferredRuntimeStartup,
    this.ingestStagedPushEnvelopes,
    this.firebaseReadiness,
    this.onAppDetached,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isResuming = false;
  // 164 (cold-start-1 regression #1): unconditional idempotence latch so the
  // initState _setupPushListeners() call and the post-runtime-ready re-arm cannot
  // double-register onMessage / onMessageOpenedApp.
  bool _pushListenersArmed = false;
  final NotificationOpenRouteCoordinator _notificationRouteCoordinator =
      NotificationOpenRouteCoordinator();
  DateTime? get _notificationTappedAt =>
      _notificationRouteCoordinator.activeTappedAt;
  // 133: a notification route must be pushed ON TOP of the startup home, not
  // before it — otherwise the StartupRouter's `pushReplacement(home)` clobbers
  // the just-pushed conversation and the user lands on Feed (Android cold-tap).
  // `_startupHomeReady` flips true when StartupRouter establishes the home; the
  // fallback timer guarantees a notification is never permanently stranded if
  // that signal never arrives (degrades to the legacy push-anyway behavior).
  bool _startupHomeReady = false;
  Timer? _homeReadyFallbackTimer;
  final NotificationOpenDeferredRetryScheduler
  _deferredNotificationRouteRetryScheduler =
      NotificationOpenDeferredRetryScheduler();
  static const Duration _homeReadyFallbackDelay = Duration(seconds: 8);
  static const Duration _deferredNotificationRouteRetryDelay = Duration(
    milliseconds: 250,
  );
  static const int _maxDeferredNotificationRouteAttempts = 2;
  late final PostNotificationOpenCoordinator _postNotificationOpenCoordinator;
  late final ContactRequestNotificationMaterializer
  _contactRequestNotificationMaterializer;
  late final IosApnsNotificationOpenBridge _iosApnsNotificationOpenBridge;
  final NotificationOpenDedupeGate _remoteNotificationOpenDedupeGate =
      NotificationOpenDedupeGate();
  late final Future<void> _initialShareIntentCapture;
  Future<void>? _runtimeServicesReady;
  // 181: FDC-09 §6.3 presence self-publish lifecycle driver. Announces
  // `foreground` on resume (+ arms a 60s heartbeat) and `background` on pause so
  // the relay can report this peer reachable/unreachable to senders — activating
  // the committed send-side `unreachable` short-circuit. Best-effort, never
  // load-bearing. Constructed from the concrete P2PServiceImpl (which implements
  // RelayPresenceSet — kept off the base P2PService interface to spare the ~31
  // fakes; no cast needed because widget.p2pService is the concrete type).
  late final SetPresenceUseCase _setPresenceUseCase;

  // 183: active-chat keepalive lifecycle driver. While foreground + in a 1:1
  // chat it pings the OPEN peer (~8s, under the ~30s QUIC idle) to keep the warm
  // connection alive and detect a drop in seconds, then REUSES warmPeer +
  // drainOfflineInbox (never a new re-dial/drain). Armed on resume, cancelled on
  // pause, disposed on teardown. The probe is the concrete P2PServiceImpl (which
  // implements PeerLivenessProbe — kept off the base P2PService interface to
  // spare the ~31 fakes; no cast needed); the active 1:1 peer comes from the
  // conversation tracker. Best-effort, never load-bearing.
  late final ActivePeerKeepAliveUseCase _keepAliveUseCase;

  // 191 (Fix D2): observable, retryable, idempotent push-listener arm. Owns the
  // onMessage/onMessageOpenedApp subscription + the PUSH_LISTENERS_ARMED
  // telemetry; _setupPushListeners delegates to it.
  late final PushListenerArmer _pushListenerArmer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setPresenceUseCase = SetPresenceUseCase(presenceSetter: widget.p2pService);
    _keepAliveUseCase = ActivePeerKeepAliveUseCase(
      probe: widget.p2pService,
      activePeerId: () => widget.conversationTracker.activePeerId,
      onDropReWarm: widget.p2pService.warmPeer,
      onDropDrain: widget.p2pService.drainOfflineInbox,
      // 187: expose the keepalive drop latch to the send path (P2PServiceImpl
      // implements PeerDropSignal — no cast needed) so a send to a latched-
      // dropped active peer skips the doomed direct dial and leans on the
      // already-concurrent durable inbox.
      onLivenessChanged: widget.p2pService.setPeerDropSuspected,
    );
    widget.pendingMessageRetrier.setExternalRecoveryInProgressProvider(
      () => _isResuming || isGroupRecoveryInProgress(),
    );
    _postNotificationOpenCoordinator = PostNotificationOpenCoordinator(
      pendingTargetStore: widget.pendingPostTargetStore,
      postRepository: widget.postRepository,
      appShellController: widget.appShellController,
      revealPostsSurface: _revealPostsSurface,
    );
    _contactRequestNotificationMaterializer =
        ContactRequestNotificationMaterializer(
          requestRepository: widget.contactRequestRepository,
          contactRepository: widget.contactRepository,
          identityRepository: widget.repository,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          onProfileDownloaded: widget.chatMessageListener.emitContactUpdate,
          presentPendingRequest:
              ({
                required navigator,
                required request,
                required onAccept,
                required onDecline,
              }) async {
                if (kE2ETestMode) {
                  return;
                }
                await showDialog<void>(
                  context: navigator.context,
                  barrierDismissible: false,
                  builder: (dialogContext) => ContactRequestDialog(
                    request: request,
                    onAccept: () {
                      Navigator.of(dialogContext).pop();
                      unawaited(onAccept());
                    },
                    onDecline: () {
                      Navigator.of(dialogContext).pop();
                      unawaited(onDecline());
                    },
                  ),
                );
              },
          openConversation: ({required navigator, required contact}) =>
              _openConversationForContact(
                navigator: navigator,
                contact: contact,
              ),
        );
    // 191 (Fix D2): the foreground-push / open-app subscription + its
    // PUSH_LISTENERS_ARMED telemetry live in PushListenerArmer so the arm is
    // observable and unit-locked. _setupPushListeners delegates to arm().
    _pushListenerArmer = PushListenerArmer(
      firebaseReady: () => Firebase.apps.isNotEmpty,
      platform: kIsWeb ? 'web' : Platform.operatingSystem,
      subscribe: () {
        FirebaseMessaging.onMessage.listen((message) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_FOREGROUND_MESSAGE_RECEIVED',
            details: {
              'messageId': message.messageId,
              'dataKeys': message.data.keys.toList(),
            },
          );
          unawaited(_handleForegroundRemotePush(message));
        });

        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_MESSAGE_OPENED_APP',
            details: {
              'messageId': message.messageId,
              'dataKeys': message.data.keys.toList(),
            },
          );
          unawaited(_routeRemoteNotificationOpen(message.data));
        });
      },
    );
    _setupPushListeners();
    // 164 (cold-start-1 regression #1): Firebase is now initialized lazily inside
    // the deferred startLiveServices, so the _setupPushListeners() call above
    // no-ops on a normal launch (Firebase.apps is empty until runtime services
    // start). Re-arm the foreground-push + open-app listeners once runtime
    // services (hence Firebase) are ready. The unconditional _pushListenersArmed
    // latch inside _setupPushListeners keeps this idempotent against the (no-op)
    // initState call above.
    unawaited(_ensureRuntimeServicesReady().then((_) => _setupPushListeners()));
    unawaited(
      _ensureRuntimeServicesReady().then(
        (_) => publishIosReceiverBootstrapIdentityWhenReady(
          currentPeerId: () => widget.p2pService.currentState.peerId,
          peerIds: widget.p2pService.stateStream.map((state) => state.peerId),
          loadMlKemPublicKey: () async =>
              (await widget.repository.loadIdentity())?.mlKemPublicKey,
        ),
      ),
    );
    // 191 (Fix D2): a THIRD arm point rides Firebase first-success readiness —
    // the only event that flips Firebase.apps non-empty. If the
    // _ensureRuntimeServicesReady re-arm above fires while Firebase.apps is
    // still empty (a retried/late init), it no-ops WITHOUT consuming the
    // _pushListenersArmed latch; this readiness listener then arms the moment
    // Firebase actually becomes ready — so a transient init failure can never
    // leave push permanently disarmed.
    widget.firebaseReadiness?.addOnReadyListener(() {
      if (mounted) {
        _setupPushListeners();
      }
    });
    _setupNotificationTapHandler();
    _setupIosApnsNotificationOpenBridge();
    _setupShareIntentHandling();
    _initialShareIntentCapture = _captureInitialShareIntent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_flushDeferredNotificationRouteTarget());
    });
    // 183/181 (cold-start arm): Flutter delivers NO initial `resumed` lifecycle
    // transition on a fresh launch, so `_onResumed()` never runs and the
    // foreground-only heartbeats — the 183 active-chat keepalive and the 181
    // presence heartbeat — would stay DORMANT until the first
    // background→foreground cycle (device-proven 2026-07-01: no `peer:ping` until
    // the app was cycled). Arm them once at first frame IF the app launched
    // already foreground. Cheap timer-arms ONLY, never the full `_onResumed()`
    // cold-start work (that already runs via main()); idempotent — a later real
    // resume just re-arms the same timers (`onForegrounded()` cancels first).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _keepAliveUseCase.onForegrounded();
        unawaited(_setPresenceUseCase.onForegrounded());
      }
    });
    unawaited(_handleInitialLocalNotificationLaunchWhenReady());
  }

  Future<void> _ensureRuntimeServicesReady() {
    final existingFuture = _runtimeServicesReady;
    if (existingFuture != null) {
      return existingFuture;
    }

    final deferredRuntimeStartup = widget.deferredRuntimeStartup;
    if (deferredRuntimeStartup == null) {
      return _runtimeServicesReady = Future.value();
    }

    final startup = () async {
      StartupTiming.instance.mark('deferred_runtime_start_begin');
      await deferredRuntimeStartup();
      StartupTiming.instance.mark('deferred_runtime_start_complete');
      unawaited(_ingestStagedPushEnvelopes(source: 'runtime_ready'));
    }();
    _runtimeServicesReady = startup;
    return startup;
  }

  Future<void> _ingestStagedPushEnvelopes({required String source}) async {
    final ingest = widget.ingestStagedPushEnvelopes;
    if (ingest == null) {
      return;
    }
    try {
      await ingest(source: source);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'STAGED_PUSH_ENVELOPE_INGEST_ERROR',
        details: {'source': source, 'error': e.toString()},
      );
    }
  }

  void _setupShareIntentHandling() {
    // Warm-start: share arrives while app is running
    widget.shareIntentService.intentStream.listen((intent) {
      unawaited(
        handleShareIntent(
          intent: intent,
          shareIntentService: widget.shareIntentService,
          navigator: MyApp.navigatorKey.currentState,
          buildRoute: _buildSharePickerRoute,
        ),
      );
    });
  }

  Future<void> _captureInitialShareIntent() async {
    if (widget.shareIntentService.hasPendingIntent) {
      _routeBufferedShareIfSettled();
      return;
    }

    final intent = await widget.shareIntentService.captureInitialIntent();
    if (intent == null || !mounted) {
      return;
    }

    _routeBufferedShareIfSettled();
  }

  void _routeBufferedShareIfSettled() {
    final navigator = MyApp.navigatorKey.currentState;
    if (!widget.shareIntentService.isSettled ||
        navigator == null ||
        !widget.shareIntentService.hasPendingIntent) {
      return;
    }

    final pendingIntent = widget.shareIntentService.consumePendingIntent();
    if (pendingIntent == null) {
      return;
    }

    widget.shareIntentService.reset();
    navigator.push(_buildSharePickerRoute(pendingIntent));
  }

  Route<void> _buildSharePickerRoute(ShareIntent intent) {
    return buildShareTargetPickerRoute(
      shareIntent: intent,
      identityRepo: widget.repository,
      contactRepository: widget.contactRepository,
      messageRepository: widget.messageRepository,
      mediaAttachmentRepository: widget.mediaAttachmentRepository,
      chatMessageListener: widget.chatMessageListener,
      bridge: widget.bridge,
      p2pService: widget.p2pService,
      mediaFileManager: widget.mediaFileManager,
      imageProcessor: widget.imageProcessor,
      secureKeyStore: widget.secureKeyStore,
      conversationTracker: widget.conversationTracker,
      audioRecorderService: widget.audioRecorderService,
      reactionRepository: widget.reactionRepository,
      reactionListener: widget.reactionListener,
      groupRepository: widget.groupRepository,
      groupMessageRepository: widget.groupMessageRepository,
      groupInviteDeliveryAttemptRepository:
          widget.groupInviteDeliveryAttemptRepository,
      groupMessageListener: widget.groupMessageListener,
      groupConversationTracker: widget.groupConversationTracker,
      introductionRepository: widget.introductionRepository,
      appShellController: widget.appShellController,
      preSendReady: _ensureRuntimeServicesReady,
    );
  }

  void _setupNotificationTapHandler() {
    widget.notificationService.onNotificationTap = _onNotificationTap;
  }

  void _setupIosApnsNotificationOpenBridge() {
    _iosApnsNotificationOpenBridge = IosApnsNotificationOpenBridge();
    // 133: the `mknoon/ios_notification_open` MethodChannel only exists on iOS;
    // invoking it on Android throws MissingPluginException (log noise on every
    // cold start). Keep the field assigned (dispose references it) but only wire
    // the channel + readiness probe on iOS.
    if (!Platform.isIOS) return;
    _iosApnsNotificationOpenBridge.register(_routeRemoteNotificationOpen);
    unawaited(_prepareIosApnsNotificationOpenBridgeWhenReady());
  }

  Future<void> _prepareIosApnsNotificationOpenBridgeWhenReady({
    bool allowRetry = true,
  }) async {
    await _ensureRuntimeServicesReady();
    if (!mounted) {
      return;
    }
    final isReady = await _iosApnsNotificationOpenBridge
        .markNotificationOpenBridgeReady();
    if (!mounted) {
      return;
    }
    if (!isReady) {
      if (allowRetry) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              unawaited(
                _prepareIosApnsNotificationOpenBridgeWhenReady(
                  allowRetry: false,
                ),
              );
            }
          });
        });
      }
      return;
    }
    await _iosApnsNotificationOpenBridge.consumeInitialNotificationOpen(
      _routeRemoteNotificationOpen,
    );
  }

  Future<void> _routeRemoteNotificationOpen(Map<String, dynamic> data) async {
    if (!_remoteNotificationOpenDedupeGate.tryBegin(data)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REMOTE_NOTIFICATION_OPEN_DEDUPED',
        details: {
          'dataKeys': data.keys.toList(growable: false),
          'dedupeKey': NotificationOpenDedupeGate.dedupeKeyFor(data) ?? '',
        },
      );
      return;
    }

    var routeSucceeded = false;
    NotificationOpenRouteContext? preparedContext;
    NotificationOpenRouteCompletion? routeCompletion;
    try {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
      // Mint the ordering ordinal immediately after synchronous validation.
      // Recent-announcement persistence, delivered-notification clearing, and
      // route preparation can all yield; none of them may let an older remote
      // tap borrow a newer ordinal when local and remote opens overlap.
      preparedContext = routeTarget == null
          ? null
          : _createNotificationOpenRouteContext(routeTarget);
      final markedRecentAnnouncement =
          await markRemoteNotificationOpenAsRecentAnnouncement(
            data: data,
            gate: recentRemoteNotificationGate,
          );
      if (markedRecentAnnouncement) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REMOTE_NOTIFICATION_OPEN_MARKED_RECENT',
          details: {
            'kind': routeTarget?.kind.name ?? '',
            'hasMessageId':
                (remoteNotificationMessageIdFromData(data) ??
                        routeTarget?.messageId)
                    ?.isNotEmpty ==
                true,
          },
        );
      }
      final routeTargetResolved =
          await _withContactRequestPresentationSuppressed(
            routeTarget: routeTarget,
            action: () => routeAppRootRemoteNotificationOpenWithResult(
              data: data,
              prevalidatedRouteTarget: preparedContext?.routeTarget,
              onBeforeRouteTarget: (target) async {
                final context = preparedContext;
                if (context == null ||
                    !identical(context.routeTarget, target)) {
                  throw StateError(
                    'Remote notification route context was not validated.',
                  );
                }
                await widget.notificationService.clearDeliveredNotifications();
                await _prepareNotificationRouteTarget(context.routeTarget);
              },
              onRouteTarget: (target) async {
                routeCompletion = await _dispatchPreparedNotificationRoute(
                  preparedContext,
                  target,
                );
                _throwIfNotificationRouteFailed(routeCompletion!);
              },
              onMissingGroupRouteId: _emitMissingGroupRouteId,
              onMissingRouteTarget: widget.p2pService.drainOfflineInbox,
            ),
          );
      routeSucceeded = didNotificationOpenRouteSucceed(
        routeTargetResolved: routeTargetResolved,
        completion: routeCompletion,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REMOTE_NOTIFICATION_ROUTE_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _remoteNotificationOpenDedupeGate.finish(data, success: routeSucceeded);
    }
  }

  Future<T> _withContactRequestPresentationSuppressed<T>({
    required NotificationRouteTarget? routeTarget,
    required Future<T> Function() action,
  }) async {
    final peerId =
        routeTarget?.kind == NotificationRouteTargetKind.contactRequest
        ? routeTarget?.peerId
        : null;
    if (peerId != null) {
      widget.contactRequestPresentationGate.suppress(peerId);
    }
    try {
      return await action();
    } finally {
      if (peerId != null) {
        widget.contactRequestPresentationGate.release(peerId);
      }
    }
  }

  Future<void> _emitMissingGroupRouteId(Map<String, dynamic> data) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_GROUP_ROUTE_MISSING_GROUP_ID',
      details: NotificationRouteTarget.missingGroupIdTelemetryDetails(data),
    );
  }

  Future<void> _handleInitialLocalNotificationLaunchWhenReady() async {
    await _ensureRuntimeServicesReady();
    await _handleInitialLocalNotificationLaunch();
  }

  Future<void> _handleInitialLocalNotificationLaunch() async {
    NotificationOpenRouteContext? preparedContext;
    String? consumedPayload;
    try {
      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: () async {
          consumedPayload = await widget.notificationService
              .consumeInitialPayload();
          return consumedPayload;
        },
        // A terminated local-notification open does not pass through the warm
        // callback. Create its immutable context only after payload parsing;
        // ordinary and malformed cold starts therefore create no route state.
        onBeforeRouteTarget: (target) async {
          emitFlowEvent(
            layer: 'FL',
            event: initialLocalNotificationRouteParsedEvent,
            details: initialLocalNotificationRouteParsedDetails(
              rawPayload: consumedPayload,
              target: target,
            ),
          );
          preparedContext = _createNotificationOpenRouteContext(target);
          await _prepareNotificationRouteTarget(target);
        },
        onRouteTarget: (target) async {
          final completion = await _dispatchPreparedNotificationRoute(
            preparedContext,
            target,
          );
          _throwIfNotificationRouteFailed(completion);
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onNotificationTap(String payload) async {
    NotificationOpenRouteContext? preparedContext;
    try {
      await routeAppRootLocalNotificationTap(
        payload: payload,
        onBeforeRouteTarget: (target) async {
          preparedContext = _createNotificationOpenRouteContext(target);
          await _prepareNotificationRouteTarget(target);
        },
        onRouteTarget: (target) async {
          final completion = await _dispatchPreparedNotificationRoute(
            preparedContext,
            target,
          );
          _throwIfNotificationRouteFailed(completion);
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_TAP_NAV_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  NotificationOpenRouteContext _createNotificationOpenRouteContext(
    NotificationRouteTarget routeTarget,
  ) {
    return _notificationRouteCoordinator.createContext(
      routeTarget: routeTarget,
      tappedAt: DateTime.now(),
    );
  }

  Future<NotificationOpenRouteCompletion> _dispatchPreparedNotificationRoute(
    NotificationOpenRouteContext? preparedContext,
    NotificationRouteTarget routeTarget,
  ) async {
    if (preparedContext == null ||
        !identical(preparedContext.routeTarget, routeTarget)) {
      throw StateError('Notification route context was not prepared.');
    }
    final dispatch = await _dispatchNotificationRouteContext(preparedContext);
    return dispatch.completion;
  }

  Future<NotificationOpenRouteDispatch> _dispatchNotificationRouteContext(
    NotificationOpenRouteContext context,
  ) {
    return _notificationRouteCoordinator.dispatch(
      context: context,
      onRouteContext: _handleNotificationRouteTarget,
    );
  }

  Future<void> _beginStartupNotificationRouteContext(
    NotificationOpenRouteContext context,
  ) async {
    final dispatch = await _dispatchNotificationRouteContext(context);
    // StartupRouter must be allowed to establish the home before a deferred
    // open can complete. Observe the owned completion without awaiting it on
    // the startup critical path; the observer never throws.
    unawaited(
      _observeNotificationRouteCompletion(
        dispatch.completion,
        source: 'initial_remote',
      ),
    );
  }

  Future<void> _observeNotificationRouteCompletion(
    Future<NotificationOpenRouteCompletion> completionFuture, {
    required String source,
  }) async {
    final completion = await completionFuture;
    if (completion.status != NotificationOpenRouteCompletionStatus.failed) {
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_DEFERRED_ROUTE_COMPLETION_ERROR',
      details: {'source': source, 'error': completion.error.toString()},
    );
  }

  void _dispatchNotificationRouteUnawaited(
    NotificationOpenRouteContext context, {
    required String source,
  }) {
    unawaited(() async {
      try {
        final dispatch = await _dispatchNotificationRouteContext(context);
        await _observeNotificationRouteCompletion(
          dispatch.completion,
          source: source,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'NOTIFICATION_ROUTE_ASYNC_ERROR',
          details: {'source': source, 'error': e.toString()},
        );
      }
    }());
  }

  void _throwIfNotificationRouteFailed(
    NotificationOpenRouteCompletion completion,
  ) {
    if (completion.status != NotificationOpenRouteCompletionStatus.failed) {
      return;
    }
    Error.throwWithStackTrace(
      completion.error!,
      completion.stackTrace ?? StackTrace.current,
    );
  }

  Future<NotificationOpenRouteDisposition> _handleNotificationRouteTarget(
    NotificationOpenRouteContext context,
  ) async {
    final routeTarget = context.routeTarget;
    assert(_notificationTappedAt == context.tappedAt);
    final navigator = MyApp.navigatorKey.currentState;
    // 133: defer until BOTH the navigator exists AND the startup home has been
    // established. Routing before the home is replaced lets StartupRouter's
    // `pushReplacement(home)` clobber the conversation we push (Android cold-tap
    // → Feed). The navigator-null case re-tries on the next frame; the
    // home-not-ready case waits for `_onStartupHomeReady` (or the fallback
    // timer), so we don't busy-loop for the ~1-2s until the home lands.
    if (navigator == null || !_startupHomeReady) {
      final accepted = _notificationRouteCoordinator.defer(context);
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_flushDeferredNotificationRouteTarget());
        });
      }
      _armHomeReadyFallback();
      return accepted
          ? NotificationOpenRouteDisposition.deferred
          : NotificationOpenRouteDisposition.superseded;
    }

    if (routeTarget.kind == NotificationRouteTargetKind.post ||
        routeTarget.kind == NotificationRouteTargetKind.postComment) {
      await _postNotificationOpenCoordinator.handleRouteTarget(
        routeTarget: routeTarget,
        drainOfflineInbox: widget.p2pService.drainOfflineInbox,
      );
      return NotificationOpenRouteDisposition.routed;
    }

    switch (routeTarget.kind) {
      case NotificationRouteTargetKind.contactRequest:
        await _contactRequestNotificationMaterializer.handleRoute(
          navigator: navigator,
          peerId: routeTarget.peerId!,
        );
        return NotificationOpenRouteDisposition.routed;
      case NotificationRouteTargetKind.intros:
        // 252: snapshot the tap timestamp (matching the conversation/group
        // branches) so an introducer-acceptance redirect can hand the
        // original tap context to the conversation screen; the shared
        // coordinator falls back to the Orbit/Intros route for everything
        // else.
        await openIntroAcceptNotificationRoute(
          routeTarget: routeTarget,
          notificationTappedAt: context.tappedAt,
          resolveTarget: (target) => resolveIntroductionNotificationTarget(
            routeTarget: target,
            introRepo: widget.introductionRepository,
            contactRepo: widget.contactRepository,
            loadOwnPeerId: () async =>
                (await widget.repository.loadIdentity())?.peerId,
          ),
          isConversationAlreadyActive: (conversationTarget) =>
              isNotificationRouteTargetAlreadyActive(
                routeTarget: conversationTarget,
                groupConversationTracker: widget.groupConversationTracker,
                conversationTracker: widget.conversationTracker,
              ),
          openConversation: (contact, tappedAt) => _openConversationForContact(
            navigator: navigator,
            contact: contact,
            notificationTappedAt: tappedAt,
          ),
          openIntros: () => _openIntroOrbitRoute(navigator: navigator),
        );
        return NotificationOpenRouteDisposition.routed;
      case NotificationRouteTargetKind.group:
        final identity = await widget.repository.loadIdentity();
        final resolution = await resolveGroupNotificationRouteTarget(
          groupId: routeTarget.groupId!,
          groupRepo: widget.groupRepository,
          pendingInviteRepo: widget.groupInviteListener.pendingInviteRepo,
          drainOfflineInbox: widget.p2pService.drainOfflineInbox,
          localPeerId: identity?.peerId,
        );
        if (!_notificationRouteCoordinator.isLatest(context)) {
          return NotificationOpenRouteDisposition.superseded;
        }
        if (resolution.group == null) {
          emitFlowEvent(
            layer: 'FL',
            event: resolution.hasPendingInvite
                ? 'GROUP_NOTIFICATION_ROUTE_PENDING_INVITE_REDIRECT'
                : 'GROUP_NOTIFICATION_ROUTE_GROUP_MISSING',
            details: {
              'groupId': routeTarget.groupId!.length > 8
                  ? routeTarget.groupId!.substring(0, 8)
                  : routeTarget.groupId!,
            },
          );
          if (resolution.hasPendingInvite) {
            await _openIntroOrbitRoute(navigator: navigator);
            return NotificationOpenRouteDisposition.routed;
          }
          if (!navigator.mounted) {
            // Neither the requested group nor the visible feedback/home
            // fallback was reached. Keep remote dedupe retryable instead of
            // falsely committing this dead tap as routed.
            throw StateError(
              'Group notification fallback navigator is not available.',
            );
          }
          // 04-P0 / QW-2: the group can't be resolved and there is no pending
          // invite — don't dead-tap silently. Show feedback (with a single
          // user-driven Retry that re-runs this handler) and route home. The
          // targeted drain already ran once inside
          // resolveGroupNotificationRouteTarget; Retry is not an auto-loop.
          final l10n = AppLocalizations.of(navigator.context);
          showGroupMissingNotificationFeedback(
            messenger: MyApp.scaffoldMessengerKey.currentState,
            navigator: navigator,
            message:
                l10n?.group_notification_catching_up ??
                'This group is still catching up — try again in a moment.',
            retryLabel: l10n?.btn_retry,
            onRetry: () => _dispatchNotificationRouteUnawaited(
              context,
              source: 'group_missing_retry',
            ),
          );
          return NotificationOpenRouteDisposition.routed;
        }
        final group = resolution.group!;
        if (isNotificationRouteTargetAlreadyActive(
          routeTarget: routeTarget,
          groupConversationTracker: widget.groupConversationTracker,
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
            details: {
              'groupId': routeTarget.groupId!.length > 8
                  ? routeTarget.groupId!.substring(0, 8)
                  : routeTarget.groupId!,
              'hasMessageId': routeTarget.messageId?.isNotEmpty == true,
            },
          );
          return NotificationOpenRouteDisposition.routed;
        }
        navigator.push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group,
              groupRepo: widget.groupRepository,
              msgRepo: widget.groupMessageRepository,
              uploadRetryProjectionRepo: widget.groupMessageRepository,
              groupMessageListener: widget.groupMessageListener,
              openAnnouncementSenderConversation: (contact) =>
                  _openConversationForContact(
                    navigator: navigator,
                    contact: contact,
                  ),
              inviteDeliveryAttemptRepo:
                  widget.groupInviteDeliveryAttemptRepository,
              bridge: widget.bridge,
              identityRepo: widget.repository,
              contactRepo: widget.contactRepository,
              p2pService: widget.p2pService,
              groupConversationTracker: widget.groupConversationTracker,
              initialHighlightedMessageId: routeTarget.messageId,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaDeleteForMeCoordinator:
                  widget.groupMediaDeleteForMeCoordinator,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              audioRecorderService: widget.audioRecorderService,
              reactionRepo: widget.reactionRepository,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
              notificationTappedAt: context.tappedAt,
              backgroundPreference:
                  widget.appShellController.backgroundPreference,
              forwardMessageRepository: widget.messageRepository,
              forwardChatMessageListener: widget.chatMessageListener,
            ),
          ),
        );
        return NotificationOpenRouteDisposition.routed;
      case NotificationRouteTargetKind.conversation:
        // 139: mirror the group already-active guard. When the user taps a
        // fresh notification for a peer whose 1:1 conversation is already the
        // active (backgrounded) screen, do NOT push a second ConversationWired
        // — the mounted screen re-fetches the new message on resume
        // (conversation_wired.dart didChangeAppLifecycleState). Decided before
        // the contact lookup so suppression is a pure routing decision; when
        // `isViewing` is true the contact necessarily exists.
        if (isNotificationRouteTargetAlreadyActive(
          routeTarget: routeTarget,
          groupConversationTracker: widget.groupConversationTracker,
          conversationTracker: widget.conversationTracker,
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
            details: {
              'peerId': routeTarget.peerId!.length > 8
                  ? routeTarget.peerId!.substring(0, 8)
                  : routeTarget.peerId!,
            },
          );
          return NotificationOpenRouteDisposition.routed;
        }
        final contact = await widget.contactRepository.getContact(
          routeTarget.peerId!,
        );
        if (!_notificationRouteCoordinator.isLatest(context)) {
          return NotificationOpenRouteDisposition.superseded;
        }
        if (contact == null) {
          // The inbox/contact materialization can lag the notification. A
          // silent no-op is not a successful route: surface failure to the
          // deferred retry/remote dedupe owner so another tap can succeed once
          // the contact is available.
          throw StateError(
            'Notification conversation contact is not available yet.',
          );
        }
        await _openConversationForContact(
          navigator: navigator,
          contact: contact,
          notificationTappedAt: context.tappedAt,
        );
        return NotificationOpenRouteDisposition.routed;
      case NotificationRouteTargetKind.post:
      case NotificationRouteTargetKind.postComment:
        return NotificationOpenRouteDisposition.routed;
    }
  }

  Future<void> _openIntroOrbitRoute({required NavigatorState navigator}) async {
    await openIntroNotificationOrbitRoute(
      navigator: navigator,
      appShellController: widget.appShellController,
      messageRepository: widget.messageRepository,
      builder: (feedUnreadCountListenable) => OrbitWired(
        groupMediaDeleteForMeCoordinator:
            widget.groupMediaDeleteForMeCoordinator,
        identityRepo: widget.repository,
        contactRepo: widget.contactRepository,
        contactRequestRepo: widget.contactRequestRepository,
        contactRequestListener: widget.contactRequestListener,
        messageRepo: widget.messageRepository,
        postRepository: widget.postRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        chatMessageListener: widget.chatMessageListener,
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        mediaFileManager: widget.mediaFileManager,
        secureKeyStore: widget.secureKeyStore,
        imageProcessor: widget.imageProcessor,
        feedClearedRepository: widget.feedClearedRepository,
        conversationTracker: widget.conversationTracker,
        audioRecorderService: widget.audioRecorderService,
        reactionRepository: widget.reactionRepository,
        reactionListener: widget.reactionListener,
        groupRepository: widget.groupRepository,
        groupMessageRepository: widget.groupMessageRepository,
        groupInviteDeliveryAttemptRepository:
            widget.groupInviteDeliveryAttemptRepository,
        groupPendingKeyRepairRepository: widget.groupPendingKeyRepairRepository,
        groupHistoryGapRepairRepository: widget.groupHistoryGapRepairRepository,
        groupReactionReplayOutboxRepository:
            widget.groupReactionReplayOutboxRepository,
        groupMessageListener: widget.groupMessageListener,
        groupInviteListener: widget.groupInviteListener,
        waitForGroupMembershipUpdateIdle:
            widget.groupMembershipUpdateListener.waitForIdle,
        groupConversationTracker: widget.groupConversationTracker,
        introductionRepository: widget.introductionRepository,
        introReviewSeenRepository: widget.introReviewSeenRepository,
        introductionListener: widget.introductionListener,
        appShellController: widget.appShellController,
        feedUnreadCountListenable: feedUnreadCountListenable,
        pendingPostTargetStore: widget.pendingPostTargetStore,
        postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
        initialFilterTab: 'intros',
        transportMetrics: widget.transportMetrics,
        accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
        accountMigrationSizeGate: widget.accountMigrationSizeGate,
        // 206: the Orbit center avatar opens Settings; thread the nearby service
        // so its posts-nearby refresh is functional on this construction path.
        nearbyLocationService: widget.nearbyLocationService,
      ),
    );
  }

  Future<void> _openConversationForContact({
    required NavigatorState navigator,
    required ContactModel contact,
    DateTime? notificationTappedAt,
  }) async {
    await navigator.push(
      buildConversationRoute(
        builder: (_) => ConversationWired(
          contact: contact,
          identityRepo: widget.repository,
          messageRepo: widget.messageRepository,
          uploadRetryProjectionRepo: widget.messageRepository,
          chatMessageListener: widget.chatMessageListener,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          contactRepo: widget.contactRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
          imageProcessor: widget.imageProcessor,
          conversationTracker: widget.conversationTracker,
          audioRecorderService: widget.audioRecorderService,
          reactionRepo: widget.reactionRepository,
          reactionListener: widget.reactionListener,
          introductionRepository: widget.introductionRepository,
          forwardGroupRepository: widget.groupRepository,
          forwardGroupMessageRepository: widget.groupMessageRepository,
          forwardGroupInviteDeliveryAttemptRepository:
              widget.groupInviteDeliveryAttemptRepository,
          forwardGroupMessageListener: widget.groupMessageListener,
          forwardGroupConversationTracker: widget.groupConversationTracker,
          appShellController: widget.appShellController,
          notificationTappedAt: notificationTappedAt,
          transportMetrics: widget.transportMetrics,
          privateMediaOutboxE2EController:
              widget.privateMediaOutboxE2EController,
        ),
      ),
    );
  }

  void _revealPostsSurface() {
    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _flushDeferredNotificationRouteTarget() async {
    try {
      if (_notificationRouteCoordinator.deferred == null) {
        return;
      }
      final navigator = MyApp.navigatorKey.currentState;
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_flushDeferredNotificationRouteTarget());
        });
        return;
      }
      // 133: hold the route until the startup home is up;
      // `_onStartupHomeReady` (or the fallback timer) re-invokes this flush
      // once it is, so the conversation lands ON TOP of the home rather than
      // being replaced by it. The coordinator keeps ownership during the
      // attempt and CAS-clears only after actual route success.
      if (!_startupHomeReady) {
        _armHomeReadyFallback();
        return;
      }
      final result = await _notificationRouteCoordinator.runDeferredAttempt(
        maxAttempts: _maxDeferredNotificationRouteAttempts,
        onRouteContext: _handleNotificationRouteTarget,
      );
      switch (result.status) {
        case NotificationOpenDeferredAttemptStatus.retry:
          emitFlowEvent(
            layer: 'FL',
            event: 'NOTIFICATION_DEFERRED_ROUTE_ATTEMPT_ERROR',
            details: {
              'attempt': result.attempt,
              'maxAttempts': _maxDeferredNotificationRouteAttempts,
              'willRetry': true,
              'routeKind': result.context?.routeTarget.kind.name ?? '',
              'error': result.error.toString(),
            },
          );
          final retryContext = result.context!;
          _deferredNotificationRouteRetryScheduler.schedule(
            ownerOrdinal: retryContext.ordinal,
            delay: _deferredNotificationRouteRetryDelay,
            onRetry: () {
              if (!mounted ||
                  _notificationRouteCoordinator.deferred?.ordinal !=
                      retryContext.ordinal) {
                return;
              }
              unawaited(_flushDeferredNotificationRouteTarget());
            },
          );
          return;
        case NotificationOpenDeferredAttemptStatus.failed:
          emitFlowEvent(
            layer: 'FL',
            event: 'NOTIFICATION_DEFERRED_ROUTE_ATTEMPT_ERROR',
            details: {
              'attempt': result.attempt,
              'maxAttempts': _maxDeferredNotificationRouteAttempts,
              'willRetry': false,
              'routeKind': result.context?.routeTarget.kind.name ?? '',
              'error': result.error.toString(),
            },
          );
          final failedContext = result.context;
          if (failedContext != null) {
            _deferredNotificationRouteRetryScheduler.cancelIfOwnedBy(
              failedContext.ordinal,
            );
          }
          return;
        case NotificationOpenDeferredAttemptStatus.none:
          return;
        case NotificationOpenDeferredAttemptStatus.routed:
        case NotificationOpenDeferredAttemptStatus.retained:
        case NotificationOpenDeferredAttemptStatus.superseded:
          final completedContext = result.context;
          if (completedContext != null) {
            _deferredNotificationRouteRetryScheduler.cancelIfOwnedBy(
              completedContext.ordinal,
            );
          }
          return;
      }
    } catch (e) {
      // Every caller intentionally starts this flush unawaited. Keep this
      // boundary total so an unexpected implementation error is observable but
      // can never become an uncaught zone error.
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_DEFERRED_ROUTE_FLUSH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// 133: StartupRouter has established the home surface — release any deferred
  /// notification route so it is pushed on top of it.
  void _onStartupHomeReady() {
    _homeReadyFallbackTimer?.cancel();
    _homeReadyFallbackTimer = null;
    if (_startupHomeReady) return;
    _startupHomeReady = true;
    unawaited(_flushDeferredNotificationRouteTarget());
  }

  /// 133 safety net: if the home-ready signal never arrives (an abnormal startup
  /// path that bypasses StartupRouter), flush anyway after a bounded delay so a
  /// tapped notification is never permanently stranded — degrading to the legacy
  /// push-immediately behavior rather than a worse regression.
  void _armHomeReadyFallback() {
    if (_startupHomeReady) return;
    _homeReadyFallbackTimer ??= Timer(_homeReadyFallbackDelay, () {
      _homeReadyFallbackTimer = null;
      if (_startupHomeReady) return;
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_ROUTE_HOME_READY_FALLBACK',
        details: {},
      );
      _startupHomeReady = true;
      unawaited(_flushDeferredNotificationRouteTarget());
    });
  }

  Future<void> _prepareNotificationRouteTarget(
    NotificationRouteTarget routeTarget,
  ) async {
    final identity = await widget.repository.loadIdentity();
    await prepareNotificationRouteTarget(
      routeTarget: routeTarget,
      drainOfflineInbox: () => _runAccountRuntimeNetworkVoidAction(
        operation: 'push_notification_open_inbox_drain',
        action: widget.p2pService.drainOfflineInbox,
      ),
      bridge: widget.bridge,
      groupRepository: widget.groupRepository,
      groupMessageRepository: widget.groupMessageRepository,
      groupMessageListener: widget.groupMessageListener,
      mediaAttachmentRepository: widget.mediaAttachmentRepository,
      reactionRepository: widget.reactionRepository,
      accountMigrationNetworkGate: AccountMigrationRuntimeNetworkGate(
        authorityRepository: SecureKeyStoreAccountMigrationAuthorityRepository(
          secureKeyStore: widget.secureKeyStore,
        ),
      ).allowsAccountNetworkSideEffects,
      selfPeerId: identity?.peerId,
      // FDC-04 (WIRE-1): the only seam holding a P2PService — supply the real
      // eager-warm fn so a warm notif-tap overlaps the dial with the screen.
      warmPeer: widget.p2pService.warmPeer,
      ingestStagedPushEnvelopes: () =>
          _ingestStagedPushEnvelopes(source: 'notification_tap_prepare'),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.disposePrivateMediaExpiryScheduler?.call();

    // Orderly teardown: retriers → listeners → router → service → bridge
    widget.keyExchangeRetrier.dispose();
    widget.pendingPostFollowOnRetrier.dispose();
    widget.pendingPostDeliveryRetrier.dispose();
    widget.pendingPostMediaUploadRetrier.dispose();
    widget.pendingMessageRetrier.dispose();
    widget.groupPendingKeyRepairBackoffTimer.dispose();
    widget.introductionListener.dispose();
    widget.groupMembershipUpdateListener.dispose();
    widget.groupKeyUpdateListener.dispose();
    widget.groupKeyRepairResponderListener.dispose();
    widget.groupInviteListener.dispose();
    widget.groupMessageListener.dispose();
    widget.profileUpdateListener.dispose();
    widget.reactionListener.dispose();
    widget.messageDeletionListener.dispose();
    widget.postListener.dispose();
    widget.postCommentListener.dispose();
    widget.postReactionListener.dispose();
    widget.postPresenceListener.dispose();
    widget.postPassListener.dispose();
    widget.postPinListener.dispose();
    widget.chatMessageListener.dispose();
    widget.contactRequestListener.dispose();
    _postNotificationOpenCoordinator.dispose();
    // 181: cancel the 60s presence heartbeat Timer.
    _setPresenceUseCase.dispose();
    // 183: cancel the ~8s keepalive Timer (no leak).
    _keepAliveUseCase.dispose();
    widget.pushRegistrationCoordinator?.dispose();
    widget.contactPresenceSnapshotRepository.dispose();
    widget.postRepository.dispose();
    widget.messageRouter.dispose();
    widget.p2pService.dispose();
    widget.bridge.dispose();
    widget.audioRecorderService.dispose();
    _homeReadyFallbackTimer?.cancel();
    _deferredNotificationRouteRetryScheduler.cancelAll();
    _notificationRouteCoordinator.cancelDeferred();
    _iosApnsNotificationOpenBridge.dispose();
    widget.notificationService.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      debugPrint('[LIFECYCLE] AppLifecycleState changed → ${state.name}');
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_STATE_CHANGED',
      details: {'state': state.name},
    );

    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }

    // Commit any in-flight 'sending' messages to 'failed' before
    // the OS may freeze or kill this process. Using 'paused' and 'hidden'
    // because 'inactive' is a transient state visited during foreground
    // app-switcher and does not reliably precede backgrounding.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _onPaused();
    }

    // App is terminating: release the node + DB so the next cold start doesn't
    // stall on the splash screen behind a stale lock/socket. Intentionally NOT
    // on 'paused'/'hidden' — those fire on transient backgrounding (app
    // switcher, biometric prompt) and tearing the node down there would kill
    // connectivity on every app switch.
    if (state == AppLifecycleState.detached) {
      _onDetached();
    }
  }

  void _onDetached() {
    if (kDebugMode) {
      debugPrint('[LIFECYCLE] detached — running best-effort teardown');
    }
    final onAppDetached = widget.onAppDetached;
    if (onAppDetached != null) {
      // Fire-and-forget: the teardown itself is internally time-bounded.
      unawaited(onAppDetached());
    }
  }

  void _onPaused() {
    widget.stopPrivateMediaExpiryScheduler?.call();
    // Fire-and-forget (PS-4): we have at most a few hundred milliseconds of
    // foreground execution. handleAppPaused() is local-DB-only EXCEPT for the
    // FDC-06 bounded pause-flush, which ships ENABLED (kFdcPauseFlushEnabled;
    // kill-switch --dart-define=FDC_PAUSE_FLUSH_DISABLE=1). The flush NARROWS
    // (does not delete) the "no network on pause" rule to a single *bounded,
    // bg-assertion-protected, inbox-store-only* deposit of the newest in-flight
    // sends — persisting each accepted row to durable custody
    // ('inboxed'/'inbox') and marking the rest failed — with no unbounded
    // network and no held connection.
    //
    // Stays `unawaited` (FDC-06 Step 7, resolved): the assertion is acquired
    // inside handleAppPaused (callBgBegin) before the first network await, and
    // once held it is the native OS background task — not this Dart future —
    // that keeps the process alive across the deposit (S4 device-verified, the
    // same window the interactive send path already relies on). If a device
    // flake ever appears, the fallback is a bounded `await` here that still
    // never throws.
    //
    // FDC-S4 grant-probe is MEASUREMENT-ONLY (kFdcPauseGrantProbeEnabled, armed
    // by --dart-define=FDC_PAUSE_FLUSH=1) and must NOT fire in a normal build —
    // it takes a ~1.5s bg assertion on every pause. Kept until T8 closes on a
    // 2nd iOS major (the device RESULTS parser greps PAUSE_GRANT_PROBE).
    // 181: announce `background` (best-effort, fire-and-forget) so the relay
    // reports this peer `unreachable` to senders. The publish is unawaited INSIDE
    // onBackgrounded() — it must NOT block or widen the bounded FDC-06 pause
    // window (no new bg assertion); it also cancels the foreground heartbeat so
    // no timer fires while suspended. A lost publish is acceptable (presence is
    // non-load-bearing; the entry lapses to `unknown` after the ~180s self-TTL).
    unawaited(_setPresenceUseCase.onBackgrounded());
    // 183: cancel the active-chat keepalive loop on pause (zero pings while
    // suspended; resume re-arms it).
    _keepAliveUseCase.onBackgrounded();
    if (kFdcPauseGrantProbeEnabled) {
      unawaited(probePauseBackgroundGrant(widget.bridge));
    }
    unawaited(
      handleAppPaused(
            messageRepo: widget.messageRepository,
            mediaAttachmentRepo: widget.mediaAttachmentRepository,
            groupMsgRepo: widget.groupMessageRepository,
            enablePauseFlush: kFdcPauseFlushEnabled,
            p2pService: widget.p2pService,
            bridge: widget.bridge,
          )
          .then((result) {
            if (kDebugMode) {
              debugPrint(
                '[LIFECYCLE] _onPaused() complete: '
                'transitioned=${result.transitionedCount} '
                'groupTransitioned=${result.groupTransitionedCount}',
              );
            }
            emitFlowEvent(
              layer: 'FL',
              event: 'APP_LIFECYCLE_PAUSED_COMPLETE',
              details: {
                'transitionedCount': result.transitionedCount,
                'groupTransitionedCount': result.groupTransitionedCount,
              },
            );
          })
          .catchError((Object e) {
            if (kDebugMode) {
              debugPrint('[LIFECYCLE] _onPaused() error: $e');
            }
            emitFlowEvent(
              layer: 'FL',
              event: 'APP_LIFECYCLE_PAUSED_ERROR',
              details: {'error': e.toString()},
            );
          }),
    );
  }

  Future<void> _onResumed() async {
    // Private lifecycle recovery has its own generation/queue. Start it before
    // the broad network-resume coalescing guard: resume A may still be pending
    // after a pause when resume B arrives, and B must be able to re-arm the
    // foreground expiry scheduler independently.
    Future<void>? privateMediaRecovery;
    try {
      privateMediaRecovery = widget.privateMediaLifecycleRecovery?.call();
    } catch (error, stackTrace) {
      privateMediaRecovery = Future<void>.error(error, stackTrace);
    }
    if (_isResuming) {
      debugPrint('[LIFECYCLE] _onResumed() skipped — already resuming');
      if (privateMediaRecovery != null) {
        try {
          await privateMediaRecovery;
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_COALESCED_PRIVATE_MEDIA_RECOVERY_DONE',
            details: {},
          );
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_COALESCED_PRIVATE_MEDIA_RECOVERY_FAILED',
            details: {'error': error.runtimeType.toString()},
          );
        }
      }
      return;
    }
    _isResuming = true;
    debugPrint('[LIFECYCLE] _onResumed() starting handleAppResumed...');

    try {
      widget.p2pService.markResumeStarted();
      // 181: announce `foreground` (+ arm the 60s presence heartbeat) on resume.
      // Unawaited — best-effort hint, must add no latency to the resume path.
      unawaited(_setPresenceUseCase.onForegrounded());
      // 183: arm the active-chat keepalive loop on resume (foreground-only — it
      // can never fire while suspended).
      _keepAliveUseCase.onForegrounded();
      unawaited(_ingestStagedPushEnvelopes(source: 'app_resumed'));
      await handleAppResumed(
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        // FDC-04 (SRC-1): the 1:1 active-peer source for resume eager-warm
        // (PS-4 — only the open conversation, never the roster).
        activeConversationPeerId: () => widget.conversationTracker.activePeerId,
        recoverInterruptedExportPause:
            widget.accountMigrationRecoverExportPause,
        // 235: local deletion-journal cleanup — before the network gate.
        groupMediaDeletionCleanupFn: widget.groupMediaDeletionCleanup,
        privateMediaLifecycleRecoveryFn: privateMediaRecovery == null
            ? null
            : () => privateMediaRecovery!,
        retryPushRegistrationFn: widget.pushRegistrationCoordinator?.retryNow,
        contactRepo: widget.contactRepository,
        identityRepo: widget.repository,
        retryIncompleteKeyExchangesFn: () =>
            widget.keyExchangeRetrier.retryNow(trigger: 'app_resumed'),
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
        groupMessageListener: widget.groupMessageListener,
        canRejoinForExitIntent: widget.canRejoinForExitIntent,
        processExitIntent: widget.processGroupExitIntent,
        pendingKeyRepairRepo: widget.groupPendingKeyRepairRepository,
        drainPendingKeyDistributionsFn:
            widget.groupPendingKeyDistributionRunner.drainAllPending,
        retryAllPendingGroupKeyRepairsFn:
            widget.groupPendingKeyRepairRunner.retryAllPending,
        historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
        requestGroupKeyRepair: widget.requestGroupKeyRepair,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        reactionRepo: widget.reactionRepository,
        nearbyLocationService: widget.nearbyLocationService,
        retryPendingPostMediaUploads:
            widget.pendingPostMediaUploadRetrier.retryNow,
        retryPendingPostDeliveries: widget.pendingPostDeliveryRetrier.retryNow,
        recoverStuckSendingMessagesFn: () =>
            recoverStuckSendingMessages(messageRepo: widget.messageRepository),
        recoverStuckSendingGroupMessagesFn: () =>
            recoverStuckSendingGroupMessages(
              groupMsgRepo: widget.groupMessageRepository,
            ),
        accountMigrationNetworkGate: AccountMigrationRuntimeNetworkGate(
          authorityRepository:
              SecureKeyStoreAccountMigrationAuthorityRepository(
                secureKeyStore: widget.secureKeyStore,
              ),
        ).allowsAccountNetworkSideEffects,
        retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(
          groupRepo: widget.groupRepository,
          groupMsgRepo: widget.groupMessageRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          identityRepo: widget.repository,
          mediaFileManager: widget.mediaFileManager,
          inviteDeliveryAttemptRepo:
              widget.groupInviteDeliveryAttemptRepository,
          tryClaimUploadLease: (attachmentIds) =>
              mediaUploadInFlightTracker.tryClaimAll(
                attachmentIds,
                source: MediaUploadTriggerSource.resume,
              ),
          releaseUploadLease: mediaUploadInFlightTracker.release,
          requireOsConnectivity: true,
        ),
        retryFailedGroupMessagesFn: () => retryFailedGroupMessages(
          groupMsgRepo: widget.groupMessageRepository,
          groupRepo: widget.groupRepository,
          identityRepo: widget.repository,
          bridge: widget.bridge,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          inviteDeliveryAttemptRepo:
              widget.groupInviteDeliveryAttemptRepository,
        ),
        retryPendingIntroductionDeliveriesFn: () =>
            retryPendingIntroductionDeliveries(
              introRepo: widget.introductionRepository,
              p2pService: widget.p2pService,
            ),
        retryIncompleteUploadsFn: () => retryIncompleteUploads(
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          messageRepo: widget.messageRepository,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          identityRepo: widget.repository,
          contactRepo: widget.contactRepository,
          mediaFileManager: widget.mediaFileManager,
          isUploadInFlight: mediaUploadInFlightTracker.isInFlight,
          tryClaimUploadLease: (attachmentIds) =>
              mediaUploadInFlightTracker.tryClaimAll(
                attachmentIds,
                source: MediaUploadTriggerSource.resume,
              ),
          releaseUploadLease: mediaUploadInFlightTracker.release,
          requireOsConnectivity: true,
        ),
        retryFailedMessagesFn: () => retryFailedMessages(
          messageRepo: widget.messageRepository,
          identityRepo: widget.repository,
          contactRepo: widget.contactRepository,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
        ),
        retryUnackedMessagesFn: () => retryUnackedMessages(
          messageRepo: widget.messageRepository,
          p2pService: widget.p2pService,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
        ),
        verifyInboxCustodyFn: () => verifyInboxCustody(
          loadInboxCustody:
              widget.messageRepository.getInboxCustodyOutgoingMessages,
          storeInInboxDetailed: widget.p2pService.storeInInboxDetailed,
          markCustodyChecked: widget.messageRepository.markInboxCustodyChecked,
          messageRepo: widget.messageRepository,
        ),
        retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(
          bridge: widget.bridge,
          msgRepo: widget.groupMessageRepository,
          reactionReplayOutboxRepo: widget.groupReactionReplayOutboxRepository,
          groupRepo: widget.groupRepository,
          identityRepo: widget.repository,
        ),
      );
      // PB264-18: only start the global role/exit pass after the awaited resume
      // pipeline has rejoined each eligible topic and run its exact per-group
      // drain/exit continuation. Starting this before handleAppResumed lets a
      // native-leave phase overtake watchdog rejoin after process recreation.
      // The wrapper is error-isolated and a still-offline retry stays durable.
      final recoverGroupExits = widget.groupExitIntentRecovery;
      if (recoverGroupExits != null) {
        unawaited(recoverGroupExits());
      } else {
        // Compatibility for lightweight MyApp widget harnesses.
        unawaited(triggerGroupPendingBroadcastDrainAll());
      }
      await sweepExpiredPosts(
        postRepo: widget.postRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      // Placed last in the resume path: the 7d invite TTL never races the
      // seconds-scale accept-recovery / inbox-drain work above.
      await sweepExpiredGroupInvites(
        repo: widget.groupInviteListener.pendingInviteRepo,
      );
      widget.p2pService.checkResumeAlreadyOnline();
    } finally {
      widget.p2pService.clearResumeStarted();
      _isResuming = false;
      debugPrint('[LIFECYCLE] _onResumed() finished');
    }
  }

  void _setupPushListeners() {
    if (widget.isDesktop || Firebase.apps.isEmpty) return;
    // 164: latch AFTER the empty-Firebase.apps guard so the no-op initState call
    // on a normal launch does NOT consume the latch — the post-ready re-arm is
    // then the first effective registration; a third call is a no-op.
    if (_pushListenersArmed) return;
    _pushListenersArmed = true;
    // 191 (Fix D2): the subscription + PUSH_LISTENERS_ARMED / PUSH_LISTENER_ERROR
    // telemetry live in the observable, unit-locked PushListenerArmer. The
    // widget-level guard + _pushListenersArmed latch above preserve the 164
    // idempotence contract; the armer carries its own latch too.
    _pushListenerArmer.arm();
  }

  Future<void> _handleForegroundRemotePush(RemoteMessage message) async {
    final result = await handleForegroundRemoteMessage(
      data: message.data,
      messageId: message.messageId,
      // Off-iOS the gate has no sidecar dir provider, so the discard is a
      // no-op; passing unconditionally keeps the wiring platform-free.
      recentRemoteGate: recentRemoteNotificationGate,
      drainOfflineInbox: () => _runAccountRuntimeNetworkVoidAction(
        operation: 'push_foreground_inbox_drain',
        action: widget.p2pService.drainOfflineInbox,
      ),
      drainGroupOfflineInboxForGroup: (groupId) async {
        if (!await _allowsAccountRuntimeNetworkSideEffects(
          'push_foreground_group_drain',
        )) {
          return;
        }
        final identity = await widget.repository.loadIdentity();
        return drainGroupOfflineInboxForGroup(
          bridge: widget.bridge,
          groupRepo: widget.groupRepository,
          msgRepo: widget.groupMessageRepository,
          groupId: groupId,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          reactionRepo: widget.reactionRepository,
          pendingReactionRepo: widget.groupPendingReactionRepository,
          groupMessageListener: widget.groupMessageListener,
          pendingKeyRepairRepo: widget.groupPendingKeyRepairRepository,
          historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
          requestGroupKeyRepair: widget.requestGroupKeyRepair,
          selfPeerId: identity?.peerId,
        );
      },
    );

    DurableNotificationToneLease? groupReactionCoordinator;
    DurableNotificationToneLease? groupMessageCoordinator;
    Future<DurableNotificationToneLease>
    resolveGroupReactionCoordinator() async {
      return groupReactionCoordinator ??=
          await DurableNotificationToneLease.openDefault();
    }

    Future<DurableNotificationToneLease>
    resolveGroupMessageCoordinator() async {
      return groupMessageCoordinator ??=
          await DurableNotificationToneLease.openMobileDefault();
    }

    try {
      if (result == ForegroundRemoteMessageResult.notificationNeeded &&
          !await _allowsAccountRuntimeNetworkSideEffects(
            'push_foreground_notification_display',
          )) {
        return;
      }
      await showForegroundPushFallbackNotificationIfNeeded(
        result: result,
        notificationService: widget.notificationService,
        message: message,
        groupMessageDisplayEligibilityResolver: (groupId) async {
          final identity = await widget.repository.loadIdentity();
          return resolveGroupMessageNotificationDisplayEligibility(
            groupId: groupId,
            groupRepo: widget.groupRepository,
            pendingInviteRepo: widget.groupInviteListener.pendingInviteRepo,
            localPeerId: identity?.peerId,
          );
        },
        groupReactionNotificationResolver:
            _resolveForegroundGroupReactionNotification,
        durableReactionNotificationCoordinatorResolver:
            resolveGroupReactionCoordinator,
        groupConversationTracker: widget.groupConversationTracker,
        getAppLifecycleState: () =>
            WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
        durableGroupMessageNotificationCoordinatorResolver:
            resolveGroupMessageCoordinator,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_FOREGROUND_FALLBACK_NOTIFICATION_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<BackgroundPushNotificationFallback?>
  _resolveForegroundGroupReactionNotification(RemoteMessage message) async {
    final data = message.data;
    final action = data['action']?.toString().trim();
    final groupId = NotificationRouteTarget.groupIdFromRemoteMessageData(data);
    final actorPeerId =
        data['reactor_peer_id']?.toString().trim().isNotEmpty == true
        ? data['reactor_peer_id']!.toString().trim()
        : data['sender_id']?.toString().trim().isNotEmpty == true
        ? data['sender_id']!.toString().trim()
        : data['from']?.toString().trim();
    final targetMessageId =
        data['target_message_id']?.toString().trim().isNotEmpty == true
        ? data['target_message_id']!.toString().trim()
        : data['targetMessageId']?.toString().trim();
    final eventId = data['event_id']?.toString().trim().isNotEmpty == true
        ? data['event_id']!.toString().trim()
        : data['reaction_id']?.toString().trim();
    final keyEpoch = int.tryParse(data['keyEpoch']?.toString() ?? '');
    if (action != 'add' ||
        groupId == null ||
        actorPeerId == null ||
        actorPeerId.isEmpty ||
        targetMessageId == null ||
        targetMessageId.isEmpty ||
        eventId == null ||
        eventId.isEmpty ||
        keyEpoch == null) {
      return null;
    }

    final identity = await widget.repository.loadIdentity();
    final localPeerId = identity?.peerId.trim();
    final localTransportPeerId = widget.p2pService.currentState.peerId?.trim();
    if (localPeerId == null ||
        localPeerId.isEmpty ||
        localTransportPeerId == null ||
        localTransportPeerId.isEmpty ||
        localPeerId == actorPeerId) {
      return null;
    }
    final verifiedNomination = await verifyGroupReactionNotificationNomination(
      data: data,
      localTransportPeerId: localTransportPeerId,
      verifySignature:
          ({required publicKey, required signedPayload, required signature}) =>
              callVerifyPayload(
                bridge: widget.bridge,
                publicKey: publicKey,
                data: signedPayload,
                signature: signature,
              ),
    );
    if (verifiedNomination == null) return null;
    final group = await widget.groupRepository.getGroup(groupId);
    final target = await widget.groupMessageRepository.getMessage(
      targetMessageId,
    );
    final localMember = await widget.groupRepository.getMember(
      groupId,
      localPeerId,
    );
    final actor = await widget.groupRepository.getMember(groupId, actorPeerId);
    final key = await widget.groupRepository.getKeyByGeneration(
      groupId,
      keyEpoch,
    );
    final latestKey = await widget.groupRepository.getLatestKey(groupId);
    final currentReaction = await widget.reactionRepository
        .getReactionForSenderIncludingRemoved(
          messageId: targetMessageId,
          senderPeerId: actorPeerId,
        );
    final actorName = actor?.username?.trim();
    final localDevice = localMember?.findDeviceByTransportPeerId(
      localTransportPeerId,
      allowLegacyFallback: true,
    );
    final actorDevice = actor?.findDeviceByTransportPeerId(
      verifiedNomination.reactorTransportPeerId,
      allowLegacyFallback: true,
    );
    final routePayload = NotificationRouteTarget.group(
      groupId,
      messageId: targetMessageId,
    ).toPayload();
    if (group == null ||
        group.isMuted ||
        group.isDissolved ||
        localMember == null ||
        localDevice == null ||
        actor == null ||
        actorDevice == null ||
        actorDevice.deviceSigningPublicKey !=
            verifiedNomination.senderPublicKey ||
        actorName == null ||
        actorName.isEmpty ||
        target == null ||
        target.groupId != groupId ||
        target.senderPeerId != localPeerId ||
        target.isIncoming ||
        key == null ||
        latestKey == null ||
        !isCurrentGroupReactionKeyEpoch(
          requestedEpoch: keyEpoch,
          selectedEpoch: key.keyGeneration,
          latestEpoch: latestKey.keyGeneration,
        ) ||
        widget.groupConversationTracker.isViewing('group:$groupId') ||
        widget.groupConversationTracker.isViewing(routePayload)) {
      return null;
    }

    return resolveBackgroundPushNotification(
      message,
      groupReactionContext: GroupReactionNotificationContext(
        groupId: groupId,
        groupName: group.name,
        actorPeerId: actorPeerId,
        actorUsername: actorName,
        targetMessageId: targetMessageId,
        currentReactionTimestamp: currentReaction?.timestamp,
        currentReactionRemovedAt: currentReaction?.removedAt,
      ),
      decryptGroup:
          ({
            required groupId,
            required keyEpoch,
            required ciphertext,
            required nonce,
          }) => callGroupDecrypt(
            widget.bridge,
            key.encryptedKey,
            ciphertext,
            nonce,
          ),
    );
  }

  Future<bool> _allowsAccountRuntimeNetworkSideEffects(String operation) async {
    final identity = await widget.repository.loadIdentity();
    final allowed =
        await AccountMigrationRuntimeNetworkGate(
          authorityRepository:
              SecureKeyStoreAccountMigrationAuthorityRepository(
                secureKeyStore: widget.secureKeyStore,
              ),
        ).allowsAccountNetworkSideEffects(
          peerId: identity?.peerId,
          operation: operation,
        );
    if (!allowed) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_RUNTIME_NETWORK_ACTION_BLOCKED',
        details: {'operation': operation},
      );
    }
    return allowed;
  }

  Future<void> _runAccountRuntimeNetworkVoidAction({
    required String operation,
    required Future<void> Function() action,
  }) async {
    if (!await _allowsAccountRuntimeNetworkSideEffects(operation)) {
      return;
    }
    await action();
  }

  Future<void> _handleAccountMigrationReceiverActivated() async {
    widget.repository.invalidateCache();
    // The imported identity owns a different projection generation. Establish
    // it first (which clears prior-account rows), then rebuild recipient-owned
    // group/target state before migrated runtime push eligibility resumes.
    await widget.repository.loadIdentity();
    await Future.wait([
      widget.contactRepository.mirrorAllDirectReactionContacts(),
      widget.messageRepository.mirrorAllDirectReactionAuthoredTargets(),
    ]);
    await widget.groupRepository.mirrorAllGroupReactionNotificationContexts();
    await widget.groupMessageRepository.mirrorAllGroupReactionAuthoredTargets();
    await widget.reactionRepository
        .mirrorAllGroupReactionNotificationComparands();
  }

  @override
  Widget build(BuildContext context) {
    // 248 — bind the root ThemeMode to the live background preference so
    // selecting Signal switches the whole app (root ThemeData + every pushed
    // route/modal that falls back to it) to the warm light theme, while every
    // dark wallpaper keeps the dark root. The MaterialApp rebuilds only its
    // theme config on a background change; the navigatorKey + stable `home`
    // preserve Navigator/StartupRouter state across the flip (TC-248-03).
    return AppShellThemeBinding(
      controller: widget.appShellController,
      builder: (context, themeMode) => MaterialApp(
        title: 'mknoon',
        navigatorKey: MyApp.navigatorKey,
        scaffoldMessengerKey: MyApp.scaffoldMessengerKey,
        navigatorObservers: [directPrivateMediaRouteObserver],
        builder: (context, child) => DirectPrivateMediaRouteObserverScope(
          observer: directPrivateMediaRouteObserver,
          child: child ?? const SizedBox.shrink(),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: StartupRouter(
          repository: widget.repository,
          contactRepository: widget.contactRepository,
          contactRequestRepository: widget.contactRequestRepository,
          contactRequestListener: widget.contactRequestListener,
          issueWakeTokensForContacts: widget.issueWakeTokensForContacts,
          contactRequestPresentationGate: widget.contactRequestPresentationGate,
          messageRepository: widget.messageRepository,
          postRepository: widget.postRepository,
          mediaAttachmentRepository: widget.mediaAttachmentRepository,
          chatMessageListener: widget.chatMessageListener,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          transportMetrics: widget.transportMetrics,
          mediaFileManager: widget.mediaFileManager,
          secureKeyStore: widget.secureKeyStore,
          imageProcessor: widget.imageProcessor,
          audioRecorderService: widget.audioRecorderService,
          conversationTracker: widget.conversationTracker,
          reactionRepository: widget.reactionRepository,
          reactionListener: widget.reactionListener,
          groupRepository: widget.groupRepository,
          groupMessageRepository: widget.groupMessageRepository,
          groupPendingKeyRepairRepository:
              widget.groupPendingKeyRepairRepository,
          groupHistoryGapRepairRepository:
              widget.groupHistoryGapRepairRepository,
          groupReactionReplayOutboxRepository:
              widget.groupReactionReplayOutboxRepository,
          groupMessageListener: widget.groupMessageListener,
          canRejoinForExitIntent: widget.canRejoinForExitIntent,
          processExitIntent: widget.processGroupExitIntent,
          groupExitIntentRecovery: widget.groupExitIntentRecovery,
          groupInviteListener: widget.groupInviteListener,
          waitForGroupMembershipUpdateIdle:
              widget.groupMembershipUpdateListener.waitForIdle,
          groupConversationTracker: widget.groupConversationTracker,
          introductionRepository: widget.introductionRepository,
          introReviewSeenRepository: widget.introReviewSeenRepository,
          introductionListener: widget.introductionListener,
          requestGroupKeyRepair: widget.requestGroupKeyRepair,
          shareIntentService: widget.shareIntentService,
          initialShareIntentCapture: _initialShareIntentCapture,
          ensureRuntimeServicesReady: _ensureRuntimeServicesReady,
          // FDC-07: start LAN mDNS discovery early on the cold-start branch. Bound
          // to the concrete impl method (off the P2PService interface to avoid
          // churning the fakes); idempotent with startNode's own early seam.
          startEarlyLocalDiscovery: () =>
              widget.p2pService.startEarlyLocalDiscovery(),
          appShellController: widget.appShellController,
          pendingPostTargetStore: widget.pendingPostTargetStore,
          postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
          feedClearedRepository: widget.feedClearedRepository,
          contactPresenceSnapshotRepository:
              widget.contactPresenceSnapshotRepository,
          nearbyLocationService: widget.nearbyLocationService,
          pushRegistrationCoordinator: widget.pushRegistrationCoordinator,
          accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
          accountMigrationSizeGate: widget.accountMigrationSizeGate,
          accountMigrationStartReceiver: widget.accountMigrationStartReceiver,
          accountMigrationStopReceiver: widget.accountMigrationStopReceiver,
          accountMigrationReceiverEvents: widget.accountMigrationReceiverEvents,
          onAccountMigrationReceiverActivated:
              _handleAccountMigrationReceiverActivated,
          clearDeliveredNotifications:
              widget.notificationService.clearDeliveredNotifications,
          ingestStagedPushEnvelopes: () => _ingestStagedPushEnvelopes(
            source: 'startup_router_notification_tap',
          ),
          createNotificationRouteContext: _createNotificationOpenRouteContext,
          onNotificationRouteContext: _beginStartupNotificationRouteContext,
          onStartupHomeReady: _onStartupHomeReady,
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
