import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/debug/debug_e2e_composition_root.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/device/disk_space.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_rejoin_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/canonical_notification_badge_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reaction_terminal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_projection_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_forward_authorization_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_canonical_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_read_acknowledgement_db_helpers.dart';
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
import 'package:flutter_app/core/database/helpers/group_exit_diagnostics_db_helpers.dart';
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
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/data/repositories/intro_review_seen_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/core/secure_storage/legacy_group_secret_storage_scrub.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
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
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_display_outbox_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_reaction_terminal_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_read_acknowledgement_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_reconciliation_outbox_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_projection_owner.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_display_retry_coordinator.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/conversation/application/direct_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_media_blob_custody_use_case.dart';
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
import 'package:flutter_app/core/notifications/direct_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/direct_notification_read_projector.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_direct_private_committed_pending_cleanup.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart';
import 'package:flutter_app/features/conversation/application/verify_inbox_custody_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/groups/application/recover_stuck_sending_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_key_distribution_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_membership_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_reaction_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_notification_display_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_notification_reconciliation_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/pending_group_invite_repository_impl.dart';
import 'package:flutter_app/core/database/helpers/group_message_local_deletions_db_helpers.dart';
import 'package:flutter_app/features/groups/application/delete_group_media_for_me_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_media_deletion_journal_reconciler.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
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
import 'package:flutter_app/features/groups/application/group_exit_diagnostic_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_diagnosing_processor.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_release_diagnostics.dart';
import 'package:flutter_app/features/groups/application/group_exit_terminal_diagnostics.dart';
import 'package:flutter_app/features/groups/application/group_dissolve_preflight_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/data/repositories/group_exit_intent_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_exit_diagnostic_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_broadcast_repository_impl.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/reconcile_missed_group_dissolves_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
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
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';
import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/ios_notification_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/ios_notification_recovery_coordinator.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_coordinator.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/diagnostics/app_build_info.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'dart:io' show Directory, Platform;
import 'package:flutter/foundation.dart'
    show debugPrintSynchronously, kDebugMode, kIsWeb, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/core/notifications/recent_remote_gate_ios_wiring.dart';
import 'package:flutter_app/features/push/application/firebase_readiness.dart';
import 'package:flutter_app/features/push/application/ingest_staged_push_envelopes_use_case.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/application/push_relay_registration_proof.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart'
    as push_registration;
import 'package:flutter_app/features/push/application/request_push_permission_use_case.dart';
import 'package:flutter_app/features/push/infrastructure/push_token_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/push_registration_health_store.dart';
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
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/groups/application/sweep_expired_group_invites_use_case.dart';
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/data/repositories/contact_presence_snapshot_repository_impl.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/data/repositories/posts_privacy_settings_repository_impl.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository_impl.dart';

import 'package:flutter_app/app/application_root.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';

/// 164 (cold-start-3): retained reference to the launch-time shared-Keychain
/// mirror backfill so it runs off the pre-runApp critical path without the
/// analyzer/GC silently dropping it. Assigned (not awaited) during production
/// bootstrap preparation.
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

final class ProductionApplicationBootstrap implements ApplicationBootstrap {
  const ProductionApplicationBootstrap({
    this.disposableProfileOverride,
    this.disposableResetOverride,
    this.normalPrepareOverride,
  });

  @visibleForTesting
  final bool Function()? disposableProfileOverride;

  @visibleForTesting
  final Future<bool> Function()? disposableResetOverride;

  @visibleForTesting
  final Future<PreparedApplication> Function()? normalPrepareOverride;

  @override
  Future<PreparedApplication> prepare() async {
    final isDisposableProfile =
        disposableProfileOverride?.call() ??
        DebugE2ECompositionRoot.isInstalledDisposableProfile;
    if (isDisposableProfile) {
      final resetHandled =
          await (disposableResetOverride?.call() ??
              DebugE2ECompositionRoot.runDisposableResetIfRequested());
      if (resetHandled) {
        return _CallbackPreparedApplication(
          buildRootWidget: _buildInertRootWidget,
          afterRunApp: _noopAfterRunApp,
        );
      }
    }

    final prepareOverride = normalPrepareOverride;
    if (prepareOverride != null) {
      return prepareOverride();
    }
    return _prepareNormalApplication();
  }

  Future<PreparedApplication> _prepareNormalApplication() async {
    const isGroupMediaIosDisposableProfile =
        DebugE2ECompositionRoot.isInstalledIosDisposableProfile;
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
    final debugE2EComposition = DebugE2ECompositionRoot.tryCreate(
      stateDirectory: appDocDir,
    );
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
        if (!kIsWeb && Platform.isIOS && !isGroupMediaIosDisposableProfile) {
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
    final SecureKeyStore? sharedPushKeyStore =
        !kIsWeb && Platform.isIOS && !isGroupMediaIosDisposableProfile
        ? FlutterSecureKeyStore(appleAccessGroup: mknoonSharedAppleAccessGroup)
        : null;
    final droppedPushRecoveryBridge = DroppedPushRecoveryBridge();
    final CanonicalRuntimeLeaseGateway? canonicalRuntimeLeaseGateway =
        !kIsWeb && Platform.isAndroid
        ? MethodChannelCanonicalRuntimeLeaseGateway()
        : null;
    final canonicalWritableRuntimeSession = canonicalRuntimeLeaseGateway == null
        ? null
        : CanonicalWritableRuntimeSession(
            gateway: canonicalRuntimeLeaseGateway,
          );
    final pendingNotificationOverlayBindingPublisher =
        canonicalRuntimeLeaseGateway == null
        ? null
        : await PendingConversationNotificationOverlayStore.openDefault();
    final canonicalRuntimeBindingCoordinator =
        canonicalRuntimeLeaseGateway == null
        ? null
        : CanonicalRuntimeBindingCoordinator(
            secureKeyStore: secureKeyStore,
            leaseGateway: canonicalRuntimeLeaseGateway,
            droppedPushBindingPublisher: droppedPushRecoveryBridge,
            rebindPendingNotificationOverlay:
                pendingNotificationOverlayBindingPublisher?.rebind,
          );
    final canonicalRuntimeStartupBinding =
        await canonicalRuntimeBindingCoordinator?.loadStartupBinding();
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
    final mediaAutoDownloadDecider =
        PreferenceBackedMediaAutoDownloadDecider.fromSecureKeyStore(
          secureKeyStore: secureKeyStore,
        );
    defaultMediaAutoDownloadDecider = mediaAutoDownloadDecider;
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
        SecureKeyStoreMigrationCutoverRepository(
          secureKeyStore: secureKeyStore,
        );
    final accountMigrationRuntimeNetworkGate =
        AccountMigrationRuntimeNetworkGate(
          authorityRepository: accountMigrationAuthorityRepository,
        );

    // 2. Acquire Android's process-wide writable lease before SQLCipher. Other
    // platforms retain their existing single-engine open path.
    Future<Database> openIdentityDatabase() => openEncryptedDatabase(
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
    final db = canonicalWritableRuntimeSession == null
        ? await openIdentityDatabase()
        : await canonicalWritableRuntimeSession.acquireThenOpen(
            binding: canonicalRuntimeStartupBinding!.leaseBinding,
            openDatabase: openIdentityDatabase,
            closeDatabaseOnRuntimeAttachFailure: (database) async {
              await database.close();
              return true;
            },
          );
    Future<bool>? canonicalRuntimeShutdownInFlight;
    Future<bool> shutdownCanonicalRuntime() {
      final current = canonicalRuntimeShutdownInFlight;
      if (current != null) return current;
      final writableSession = canonicalWritableRuntimeSession;
      if (writableSession == null) return Future<bool>.value(true);
      late final Future<bool> operation;
      operation = () async {
        try {
          await writableSession.drainCloseRelease(
            stopRuntime: () async {
              if (!await canonicalRuntimeLeaseGateway!.quiesceRuntime()) {
                throw StateError('Go runtime did not quiesce');
              }
            },
            closeDatabase: () async {
              if (db.isOpen) {
                await db.close().timeout(const Duration(seconds: 2));
              }
            },
          );
          final snapshot = await canonicalRuntimeLeaseGateway!.status();
          return snapshot.state == CanonicalRuntimeLeaseState.released &&
              !db.isOpen;
        } catch (error) {
          // Failure is deliberately sticky in native DRAINING state. The
          // Activity retains its engine until this attempt replies/times out;
          // neither side may infer DB close from plugin detach.
          if (kDebugMode) {
            debugPrint('[TEARDOWN] canonical runtime retained: $error');
          }
          return false;
        } finally {
          if (identical(canonicalRuntimeShutdownInFlight, operation)) {
            canonicalRuntimeShutdownInFlight = null;
          }
        }
      }();
      canonicalRuntimeShutdownInFlight = operation;
      return operation;
    }

    if (canonicalWritableRuntimeSession != null) {
      const MethodChannel(
        'mknoon/canonical_runtime_shutdown',
      ).setMethodCallHandler((call) async {
        if (call.method != 'shutdown') {
          throw MissingPluginException(
            'Unsupported canonical runtime shutdown method: ${call.method}',
          );
        }
        final released = await shutdownCanonicalRuntime();
        final snapshot = await canonicalRuntimeLeaseGateway!.status();
        return <String, Object?>{
          'released': released,
          'databaseClosed': !db.isOpen,
          'leaseState': snapshot.state.name,
        };
      });
    }
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

    final groupExitDiagnosticRepository = GroupExitDiagnosticRepositoryImpl(
      dbAppendOutcome: (rows) => dbAppendGroupExitDiagnosticOutcome(db, rows),
      dbLoadNewest: () => dbLoadNewestGroupExitDiagnostics(db),
      dbLoadForAction: ({required groupRef, required intentRef}) =>
          dbLoadGroupExitDiagnosticsForAction(
            db,
            groupRef: groupRef,
            intentRef: intentRef,
          ),
      dbClear: () => dbClearGroupExitDiagnostics(db),
    );
    setGroupExitDiagnosticAccessSink(
      loadForAction: groupExitDiagnosticRepository.loadForAction,
    );

    // 5. Create repository with database helpers + secure key store
    final repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
      secureKeyStore: secureKeyStore,
      pushSharedKeyStore: sharedPushKeyStore,
      directReactionProjection: directReactionNotificationProjection,
      groupReactionProjection: groupReactionNotificationProjection,
      publishCanonicalAccountBinding: canonicalRuntimeBindingCoordinator == null
          ? null
          : (accountPeerId) async {
              await canonicalRuntimeBindingCoordinator.publishAccount(
                accountPeerId,
              );
            },
      retireCanonicalAccountBinding: canonicalRuntimeBindingCoordinator == null
          ? null
          : () async {
              await canonicalRuntimeBindingCoordinator.retireAccount();
            },
    );
    // Establish (or clear) projection ownership off the pre-runApp critical path.
    // Both group backfills and deferred Firebase/push eligibility await this
    // retained future below.
    final groupReactionProjectionIdentityReady = repository.loadIdentity();
    Future<bool> allowsAccountRuntimeNetworkSideEffects(
      String operation,
    ) async {
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
      onPushEligibilityChanged: () =>
          notifyContactPushEligibilityChanged?.call(),
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

    // v107 direct notification durability is production-owned from the first
    // canonical direct mutation. Repositories are created against the same
    // writable database generation as MessageRepositoryImpl.
    final directNotificationDisplayOutboxRepository =
        DirectNotificationDisplayOutboxRepositoryImpl(
          dbStage: (row) =>
              dbStageDirectNotificationDisplayOutboxEntry(db, row),
          dbLoadExact:
              ({required peerId, required eventKind, required eventId}) =>
                  dbLoadDirectNotificationDisplayOutboxEntry(
                    db,
                    peerId: peerId,
                    eventKind: eventKind,
                    eventId: eventId,
                  ),
          dbPromoteReadyIfExact:
              ({
                required peerId,
                required eventKind,
                required eventId,
                required expectedRevision,
                required updatedAt,
              }) => dbPromoteDirectNotificationDisplayOutboxReadyIfExact(
                db,
                peerId: peerId,
                eventKind: eventKind,
                eventId: eventId,
                expectedRevision: expectedRevision,
                updatedAt: updatedAt,
              ),
          dbLoadReady: ({limit = 20, required eligibleAt}) =>
              dbLoadReadyDirectNotificationDisplayOutboxEntries(
                db,
                limit: limit,
                eligibleAt: eligibleAt,
              ),
          dbLoadEarliestNextAttemptAt: () =>
              dbLoadEarliestDirectNotificationDisplayOutboxNextAttemptAt(db),
          dbRecordRetryIfExact:
              ({
                required peerId,
                required eventKind,
                required eventId,
                required expectedRevision,
                required lastErrorCode,
                required lastAttemptAt,
                required nextAttemptAt,
                required updatedAt,
              }) => dbRecordDirectNotificationDisplayOutboxRetryIfExact(
                db,
                peerId: peerId,
                eventKind: eventKind,
                eventId: eventId,
                expectedRevision: expectedRevision,
                lastErrorCode: lastErrorCode,
                lastAttemptAt: lastAttemptAt,
                nextAttemptAt: nextAttemptAt,
                updatedAt: updatedAt,
              ),
          dbCompleteIfExact:
              ({
                required eventId,
                required expectedRevision,
                required expectedEventKind,
                required expectedPeerId,
                required expectedMessageId,
                required expectedActorPeerId,
                required expectedEventTimestamp,
                required expectedReactionId,
                required expectedReactionAction,
                required expectedReactionTombstone,
                required completedAt,
              }) => dbCompleteDirectNotificationDisplayOutboxEntryIfExact(
                db,
                eventId: eventId,
                expectedRevision: expectedRevision,
                expectedEventKind: expectedEventKind,
                expectedPeerId: expectedPeerId,
                expectedMessageId: expectedMessageId,
                expectedActorPeerId: expectedActorPeerId,
                expectedEventTimestamp: expectedEventTimestamp,
                expectedReactionId: expectedReactionId,
                expectedReactionAction: expectedReactionAction,
                expectedReactionTombstone: expectedReactionTombstone,
                completedAt: completedAt,
              ),
          dbRetireIfExact:
              ({
                required eventId,
                required expectedRevision,
                required expectedEventKind,
                required expectedPeerId,
                required expectedMessageId,
                required expectedActorPeerId,
                required expectedEventTimestamp,
                required expectedReactionId,
                required expectedReactionAction,
                required expectedReactionTombstone,
              }) => dbRetireDirectNotificationDisplayOutboxEntryIfExact(
                db,
                eventId: eventId,
                expectedRevision: expectedRevision,
                expectedEventKind: expectedEventKind,
                expectedPeerId: expectedPeerId,
                expectedMessageId: expectedMessageId,
                expectedActorPeerId: expectedActorPeerId,
                expectedEventTimestamp: expectedEventTimestamp,
                expectedReactionId: expectedReactionId,
                expectedReactionAction: expectedReactionAction,
                expectedReactionTombstone: expectedReactionTombstone,
              ),
          dbDeleteForPeer: (peerId) =>
              dbDeleteDirectNotificationDisplayOutboxForPeer(db, peerId),
          dbDeleteForMessage: ({required peerId, required messageId}) =>
              dbDeleteDirectNotificationDisplayOutboxForMessage(
                db,
                peerId: peerId,
                messageId: messageId,
              ),
          dbDeleteForReactionActor:
              ({required peerId, required messageId, required actorPeerId}) =>
                  dbDeleteDirectNotificationDisplayOutboxForReactionActor(
                    db,
                    peerId: peerId,
                    messageId: messageId,
                    actorPeerId: actorPeerId,
                  ),
        );
    final directNotificationReadAcknowledgementRepository =
        DirectNotificationReadAcknowledgementRepositoryImpl(
          dbRecord:
              ({
                required peerId,
                required contentKind,
                required eventIdentity,
                required messageId,
                required actorPeerId,
                required generation,
                required acknowledgedAt,
              }) => dbRecordDirectNotificationReadAcknowledgement(
                db,
                peerId: peerId,
                contentKind: contentKind,
                eventIdentity: eventIdentity,
                messageId: messageId,
                actorPeerId: actorPeerId,
                generation: generation,
                acknowledgedAt: acknowledgedAt,
              ),
          dbLoadExact:
              ({
                required peerId,
                required contentKind,
                required eventIdentity,
                generation,
              }) => dbLoadExactDirectNotificationReadAcknowledgement(
                db,
                peerId: peerId,
                contentKind: contentKind,
                eventIdentity: eventIdentity,
                generation: generation,
              ),
          dbConsumeExact:
              ({
                required peerId,
                required contentKind,
                required eventIdentity,
              }) => dbConsumeExactDirectNotificationReadAcknowledgement(
                db,
                peerId: peerId,
                contentKind: contentKind,
                eventIdentity: eventIdentity,
              ),
          dbDeleteForPeer: (peerId) =>
              dbDeleteDirectNotificationReadAcknowledgementsForPeer(db, peerId),
        );
    final directNotificationReactionTerminalRepository =
        DirectNotificationReactionTerminalRepositoryImpl(
          dbUpsert:
              ({
                required peerId,
                required messageId,
                required actorPeerId,
                required reactionId,
                required terminalEventId,
                required updatedAt,
              }) => dbUpsertDirectNotificationReactionTerminalEvent(
                db,
                peerId: peerId,
                messageId: messageId,
                actorPeerId: actorPeerId,
                reactionId: reactionId,
                terminalEventId: terminalEventId,
                updatedAt: updatedAt,
              ),
          dbLoadExact:
              ({required peerId, required messageId, required actorPeerId}) =>
                  dbLoadDirectNotificationReactionTerminalEvent(
                    db,
                    peerId: peerId,
                    messageId: messageId,
                    actorPeerId: actorPeerId,
                  ),
          dbLoadByTerminalEvent:
              ({required peerId, required terminalEventId}) =>
                  dbLoadDirectNotificationReactionTerminalEventByIdentity(
                    db,
                    peerId: peerId,
                    terminalEventId: terminalEventId,
                  ),
          dbMarkAcknowledgedIfExact:
              ({
                required peerId,
                required messageId,
                required actorPeerId,
                required terminalEventId,
                required acknowledgedAt,
              }) => dbMarkDirectNotificationReactionTerminalAcknowledgedIfExact(
                db,
                peerId: peerId,
                messageId: messageId,
                actorPeerId: actorPeerId,
                terminalEventId: terminalEventId,
                acknowledgedAt: acknowledgedAt,
              ),
          dbConsumeAcknowledgementIfExact:
              ({
                required peerId,
                required messageId,
                required actorPeerId,
                required terminalEventId,
                required generation,
              }) =>
                  dbConsumeDirectNotificationReactionAcknowledgementIntoTerminalIfExact(
                    db,
                    peerId: peerId,
                    messageId: messageId,
                    actorPeerId: actorPeerId,
                    terminalEventId: terminalEventId,
                    generation: generation,
                  ),
          dbDeleteForActor:
              ({required peerId, required messageId, required actorPeerId}) =>
                  dbDeleteDirectNotificationReactionTerminalForActor(
                    db,
                    peerId: peerId,
                    messageId: messageId,
                    actorPeerId: actorPeerId,
                  ),
          dbDeleteForMessage: ({required peerId, required messageId}) =>
              dbDeleteDirectNotificationReactionTerminalsForMessage(
                db,
                peerId: peerId,
                messageId: messageId,
              ),
          dbDeleteForPeer: (peerId) =>
              dbDeleteDirectNotificationReactionTerminalsForPeer(db, peerId),
        );
    final directNotificationReconciliationOutboxRepository =
        DirectNotificationReconciliationOutboxRepositoryImpl(
          dbLoadEligible: ({limit = 20, required eligibleAt}) =>
              dbLoadEligibleDirectNotificationReconciliationOutboxEntries(
                db,
                limit: limit,
                eligibleAt: eligibleAt,
              ),
          dbLoadEarliestNextAttemptAt: () =>
              dbLoadEarliestDirectNotificationReconciliationOutboxNextAttemptAt(
                db,
              ),
          dbRecordFailureIfExact:
              ({
                required peerId,
                required expectedIncarnationId,
                required expectedRevision,
                required lastAttemptAt,
                required nextAttemptAt,
                required updatedAt,
              }) =>
                  dbRecordDirectNotificationReconciliationOutboxFailureIfExact(
                    db,
                    peerId: peerId,
                    expectedIncarnationId: expectedIncarnationId,
                    expectedRevision: expectedRevision,
                    lastAttemptAt: lastAttemptAt,
                    nextAttemptAt: nextAttemptAt,
                    updatedAt: updatedAt,
                  ),
          dbCompleteIfExact:
              ({
                required peerId,
                required expectedIncarnationId,
                required expectedRevision,
              }) => dbCompleteDirectNotificationReconciliationOutboxIfExact(
                db,
                peerId: peerId,
                expectedIncarnationId: expectedIncarnationId,
                expectedRevision: expectedRevision,
              ),
        );
    late final Future<int> Function(String peerId)
    projectDirectConversationRead;

    // Create message repository
    late final MediaAttachmentRepositoryImpl mediaAttachmentRepository;
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
      projectConversationRead: (contactPeerId) =>
          projectDirectConversationRead(contactPeerId),
      dbCountUnreadForContact: (contactPeerId) =>
          dbCountUnreadForContact(db, contactPeerId),
      dbCountTotalUnread: () => dbCountTotalUnread(db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(db),
      dbDeleteMessagesForContact: (contactPeerId) =>
          dbDeleteMessagesForContact(db, contactPeerId),
      dbDeleteMessage: (id) => dbDeleteMessage(db, id),
      dbExistsMessageByContent:
          (contactPeerId, senderPeerId, text, timestamp) =>
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
      dbStageOutgoingOrdinaryAttempt:
          ({required expectedRow, required stagedRow, required kind}) =>
              dbStageOutgoingOrdinaryAttempt(
                db,
                expectedRow: expectedRow,
                stagedRow: stagedRow,
                kind: kind,
              ),
      dbStageOutgoingDirectTextInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required recipientPeerId,
            required messageId,
            required incarnationId,
            required wireEnvelope,
          }) => dbStageOutgoingDirectTextInboxCustody(
            db,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            recipientPeerId: recipientPeerId,
            messageId: messageId,
            incarnationId: incarnationId,
            wireEnvelope: wireEnvelope,
          ),
      dbLoadDirectInboxCustodyOutbox: ({limit = 50}) =>
          dbLoadDirectInboxCustodyOutbox(db, limit: limit),
      dbLoadDirectInboxCustodyOutboxForMessage:
          ({required recipientPeerId, required messageId}) =>
              dbLoadDirectInboxCustodyOutboxForMessage(
                db,
                recipientPeerId: recipientPeerId,
                messageId: messageId,
              ),
      dbLoadDirectInboxCustodyOutboxOwnerForMessageId: ({required messageId}) =>
          dbLoadDirectInboxCustodyOutboxOwnerForMessageId(
            db,
            messageId: messageId,
          ),
      dbRecordDirectInboxCustodyFailureIfExact:
          ({
            required recipientPeerId,
            required messageId,
            required expectedIncarnationId,
            required expectedWireEnvelope,
            required errorCode,
            required attemptedAt,
          }) => dbRecordDirectInboxCustodyFailureIfExact(
            db,
            recipientPeerId: recipientPeerId,
            messageId: messageId,
            expectedIncarnationId: expectedIncarnationId,
            expectedWireEnvelope: expectedWireEnvelope,
            errorCode: errorCode,
            attemptedAt: attemptedAt,
          ),
      dbCompleteAcceptedDirectInboxCustodyIfExact:
          ({
            required recipientPeerId,
            required messageId,
            required expectedIncarnationId,
            required expectedWireEnvelope,
            required relayExpiresAt,
          }) => dbCompleteAcceptedDirectInboxCustodyIfExact(
            db,
            recipientPeerId: recipientPeerId,
            messageId: messageId,
            expectedIncarnationId: expectedIncarnationId,
            expectedWireEnvelope: expectedWireEnvelope,
            relayExpiresAt: relayExpiresAt,
          ),
      dbStageOutgoingDirectTextMutationInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required recipientPeerId,
            required eventId,
            required wireEnvelope,
          }) => dbStageOutgoingDirectTextMutationInboxCustody(
            db,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            wireEnvelope: wireEnvelope,
          ),
      dbLoadDirectTextMutationInboxCustodyForEvent:
          ({required recipientPeerId, required eventId}) =>
              dbLoadDirectReactionInboxCustodyOutboxForEvent(
                db,
                recipientPeerId: recipientPeerId,
                eventId: eventId,
              ),
      dbRecordDirectTextMutationInboxCustodyFailureIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
            required errorCode,
            required attemptedAt,
          }) => dbRecordDirectReactionInboxCustodyFailureIfExact(
            db,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            expectedWireEnvelope: expectedWireEnvelope,
            errorCode: errorCode,
            attemptedAt: attemptedAt,
          ),
      dbCompleteAcceptedDirectTextMutationInboxCustodyIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
            required relayExpiresAt,
          }) => dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
            db,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            expectedWireEnvelope: expectedWireEnvelope,
            relayExpiresAt: relayExpiresAt,
          ),
      dbApplyIncomingOrdinaryTextMutation:
          ({required incomingRow, required kind}) =>
              dbApplyIncomingOrdinaryTextMutation(
                db,
                incomingRow: incomingRow,
                kind: kind,
              ),
      dbSettleOutgoingOrdinaryTransport:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required status,
            required transport,
            required relayExpiresAt,
            required mode,
          }) => dbSettleOutgoingOrdinaryTransport(
            db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            status: status,
            transport: transport,
            relayExpiresAt: relayExpiresAt,
            mode: mode,
          ),
      dbSettleOutgoingOrdinaryDeleteTombstone:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required status,
            required transport,
            required relayExpiresAt,
            required mode,
          }) => dbSettleOutgoingOrdinaryDeleteTombstone(
            db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            status: status,
            transport: transport,
            relayExpiresAt: relayExpiresAt,
            mode: mode,
          ),
      dbInvalidateOutgoingOrdinaryEnvelope:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
          }) => dbInvalidateOutgoingOrdinaryEnvelope(
            db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
          ),
      dbQuarantineUnsafeLegacyOutgoingEnvelope:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required isDeleteTombstone,
          }) => dbQuarantineUnsafeLegacyOutgoingEnvelope(
            db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            isDeleteTombstone: isDeleteTombstone,
          ),
      loadOutgoingOrdinaryMedia: (messageId) => mediaAttachmentRepository
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct),
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
      dbHideDirectPrivateMediaForMe:
          (id, {required hiddenAt, required nowMs}) =>
              dbHideDirectPrivateMediaForMe(
                db,
                id,
                hiddenAt: hiddenAt,
                nowMs: nowMs,
              ),
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
      dbLoadInboxStagingEntry: (entryId) =>
          dbLoadInboxStagingEntry(db, entryId),
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
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
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
      dbInsertPendingChildEvent: (row) =>
          dbInsertPendingPostChildEvent(db, row),
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
      dbLoadPendingMediaUploadPosts: () =>
          dbLoadPendingPostMediaUploadPosts(db),
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
      dbLoadPassAvatarSnapshot: (postId) =>
          dbLoadPassAvatarSnapshot(db, postId),
      dbLoadPassAvatarSnapshotsForPosts: (postIds) =>
          dbLoadPassAvatarSnapshotsForPosts(db, postIds),
    );

    final postsPrivacySettingsRepository = PostsPrivacySettingsRepositoryImpl(
      dbLoadPostPrivacyState: () => dbLoadPostPrivacyState(db),
      dbUpsertPostPrivacyState: (row) => dbUpsertPostPrivacyState(db, row),
    );

    // 134 (decision 2): persistence for the Feed pending-reply "cleared"
    // watermarks (the `feed_cleared_threads` table, migration 092).
    final FeedClearedRepository feedClearedRepository =
        FeedClearedRepositoryImpl(
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
          dbLoadAllPostLocationPresence: () =>
              dbLoadAllPostLocationPresence(db),
          dbUpsertPostLocationPresence: (row) =>
              dbUpsertPostLocationPresence(db, row),
        );

    // Create media attachment repository (228: owner-lane-aware seams; the
    // save closure is the atomic local-state-preserving merge, never a blind
    // INSERT OR REPLACE).
    mediaAttachmentRepository = MediaAttachmentRepositoryImpl(
      dbSaveMediaAttachmentPreservingLocalState: (row) =>
          dbSaveMediaAttachmentPreservingLocalState(db, row),
      dbCanApplyGenericMediaAttachmentSave: (row) =>
          dbCanApplyGenericMediaAttachmentSave(db, row),
      dbStageOutgoingOrdinaryAttemptWithMedia:
          ({
            required expectedRow,
            required stagedRow,
            required attachmentRows,
            required kind,
          }) => dbStageOutgoingOrdinaryAttemptWithMedia(
            db,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            attachmentRows: attachmentRows,
            kind: kind,
          ),
      dbStageOutgoingDirectMediaInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required attachmentRows,
            required kind,
            required recipientPeerId,
            required wireEnvelope,
            wireMediaBlobManifestHash,
            wireMediaBlobExpiresAtMs,
          }) => dbStageOutgoingDirectMediaInboxCustody(
            db,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            attachmentRows: attachmentRows,
            kind: kind,
            recipientPeerId: recipientPeerId,
            wireEnvelope: wireEnvelope,
            wireMediaBlobManifestHash: wireMediaBlobManifestHash,
            wireMediaBlobExpiresAtMs: wireMediaBlobExpiresAtMs,
          ),
      dbStageOutgoingDirectMediaBlobGeneration:
          ({
            required expectedParentRow,
            required expectedAttachmentRows,
            required preparedAttachmentRows,
            required custodyRows,
          }) => dbStageOutgoingDirectMediaBlobGeneration(
            db,
            expectedParentRow: expectedParentRow,
            expectedAttachmentRows: expectedAttachmentRows,
            preparedAttachmentRows: preparedAttachmentRows,
            custodyRows: custodyRows,
          ),
      dbStageFreshOutgoingDirectMediaBlobGeneration:
          ({
            required parentRow,
            required expectedAttachmentRows,
            required preparedAttachmentRows,
            required custodyRows,
            authorizedForwardDedupKey,
          }) => dbStageFreshOutgoingDirectMediaBlobGeneration(
            db,
            parentRow: parentRow,
            expectedAttachmentRows: expectedAttachmentRows,
            preparedAttachmentRows: preparedAttachmentRows,
            custodyRows: custodyRows,
            authorizedForwardDedupKey: authorizedForwardDedupKey,
          ),
      dbLoadDirectMediaBlobCustodyForAttachment: ({required attachmentId}) =>
          dbLoadDirectMediaBlobCustodyForAttachment(
            db,
            attachmentId: attachmentId,
          ),
      dbLoadDirectMediaBlobCustodyForMessage: ({required messageId}) =>
          dbLoadDirectMediaBlobCustodyForMessage(db, messageId: messageId),
      dbLoadDirectMediaBlobCustodyByStates:
          ({required states, int limit = 50}) =>
              dbLoadDirectMediaBlobCustodyByStates(
                db,
                states: states,
                limit: limit,
              ),
      dbTransitionDirectMediaBlobCustodyIfExact:
          ({required expected, required next}) =>
              dbTransitionDirectMediaBlobCustodyIfExact(
                db,
                expected: expected,
                next: next,
              ),
      dbDeleteDirectMediaBlobCleanupPendingIfExact: ({required expected}) =>
          dbDeleteDirectMediaBlobCleanupPendingIfExact(db, expected: expected),
      dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact:
          ({required expectedRows, required reason, required nowMs}) =>
              dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact(
                db,
                expectedRows: expectedRows,
                reason: reason,
                nowMs: nowMs,
              ),
      dbStageIncomingDirectMediaBlobCustody:
          ({
            required messageRow,
            required attachmentRows,
            required custodyRows,
          }) => dbStageIncomingDirectMediaBlobCustody(
            db,
            messageRow: messageRow,
            attachmentRows: attachmentRows,
            custodyRows: custodyRows,
          ),
      dbCommitIncomingDirectMediaBlobLocalPath:
          ({
            required expectedAttachmentRow,
            required expectedCustody,
            required localPath,
            required sourceRelayPeerId,
            required updatedAt,
          }) => dbCommitIncomingDirectMediaBlobLocalPath(
            db,
            expectedAttachmentRow: expectedAttachmentRow,
            expectedCustody: expectedCustody,
            localPath: localPath,
            sourceRelayPeerId: sourceRelayPeerId,
            updatedAt: updatedAt,
          ),
      dbDeleteIncomingDirectMediaBlobAckPendingIfExact: ({required expected}) =>
          dbDeleteIncomingDirectMediaBlobAckPendingIfExact(
            db,
            expected: expected,
          ),
      dbDeleteIncomingDirectMediaBlobIfExpired:
          ({required expected, required nowMs}) =>
              dbDeleteIncomingDirectMediaBlobIfExpired(
                db,
                expected: expected,
                nowMs: nowMs,
              ),
      dbProjectOutgoingDirectMediaCustodyUploadFailure:
          ({
            required expectedParentRow,
            required expectedAttachmentRows,
            required failedAttachmentId,
            required disposition,
          }) => dbProjectOutgoingDirectMediaCustodyUploadFailure(
            db,
            expectedParentRow: expectedParentRow,
            expectedAttachmentRows: expectedAttachmentRows,
            failedAttachmentId: failedAttachmentId,
            disposition: disposition,
          ),
      publishOutgoingOrdinaryMutation:
          ({required messageId, required outcome, required committedMedia}) =>
              messageRepository.publishOutgoingOrdinaryMutation(
                messageId: messageId,
                outcome: outcome,
                committedMedia: committedMedia,
              ),
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
          dbQualifyOutgoingDirectPrivatePendingAttachmentsDeletion(
            db,
            messageId,
          ),
      dbDeleteOutgoingDirectPrivatePendingAttachmentsIfEligible: (messageId) =>
          dbDeleteOutgoingDirectPrivatePendingAttachmentsIfEligible(
            db,
            messageId,
          ),
      dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
      dbLoadRecoverableGroupMediaDownloadPage:
          ({
            required int limit,
            String? afterCreatedAt,
            String? afterAttachmentId,
          }) => dbLoadRecoverableGroupMediaDownloadPage(
            db,
            limit: limit,
            afterCreatedAt: afterCreatedAt,
            afterAttachmentId: afterAttachmentId,
          ),
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
      dbBeginOrdinaryGroupAutomaticMediaDownloadExact:
          (
            id, {
            required groupId,
            required messageId,
            required expectedDownloadStatus,
            required expectedLocalPath,
          }) => dbBeginOrdinaryGroupAutomaticMediaDownloadExact(
            db,
            id,
            groupId: groupId,
            messageId: messageId,
            expectedDownloadStatus: expectedDownloadStatus,
            expectedLocalPath: expectedLocalPath,
          ),
      dbBeginOrdinaryGroupExplicitMediaDownloadExact:
          (
            id, {
            required groupId,
            required messageId,
            required expectedDownloadStatus,
            required expectedLocalPath,
          }) => dbBeginOrdinaryGroupExplicitMediaDownloadExact(
            db,
            id,
            groupId: groupId,
            messageId: messageId,
            expectedDownloadStatus: expectedDownloadStatus,
            expectedLocalPath: expectedLocalPath,
          ),
      dbCommitOrdinaryGroupAutomaticMediaDownloadLocalPathExact:
          (
            id, {
            required groupId,
            required messageId,
            required expectedLocalPath,
            required localPath,
          }) => dbCommitOrdinaryGroupAutomaticMediaDownloadLocalPathExact(
            db,
            id,
            groupId: groupId,
            messageId: messageId,
            expectedLocalPath: expectedLocalPath,
            localPath: localPath,
          ),
      dbCommitOrdinaryGroupExplicitMediaDownloadLocalPathExact:
          (
            id, {
            required groupId,
            required messageId,
            required expectedLocalPath,
            required localPath,
          }) => dbCommitOrdinaryGroupExplicitMediaDownloadLocalPathExact(
            db,
            id,
            groupId: groupId,
            messageId: messageId,
            expectedLocalPath: expectedLocalPath,
            localPath: localPath,
          ),
      dbRecordOrdinaryGroupMediaDownloadFailureExact:
          (
            id, {
            required groupId,
            required messageId,
            required incrementRetryCount,
            required failureStatus,
            required expectedDownloadStatus,
            required expectedLocalPath,
            required clearLocalPath,
          }) => dbRecordOrdinaryGroupMediaDownloadFailureExact(
            db,
            id,
            groupId: groupId,
            messageId: messageId,
            incrementRetryCount: incrementRetryCount,
            failureStatus: failureStatus,
            expectedDownloadStatus: expectedDownloadStatus,
            expectedLocalPath: expectedLocalPath,
            clearLocalPath: clearLocalPath,
          ),
      dbClaimMediaEvicted:
          (
            id, {
            required String ownerLane,
            required String expectedLocalPath,
          }) => dbClaimMediaEvicted(
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
      parentExists:
          ({required String messageId, required String groupId}) async {
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
          DbIncomingReactionApplyResult.updated =>
            ReactionAddApplyResult.updated,
          DbIncomingReactionApplyResult.exactReplay =>
            ReactionAddApplyResult.exactReplay,
          DbIncomingReactionApplyResult.stale => ReactionAddApplyResult.stale,
          DbIncomingReactionApplyResult.removed => throw StateError(
            'ADD transaction returned REMOVE result',
          ),
        };
      },
      dbApplyGroupAdd:
          ({
            required groupId,
            required notificationEventId,
            required row,
          }) async {
            final result = await dbApplyIncomingReactionMutation(
              db,
              row,
              mutation: DbIncomingReactionMutation.add,
              groupIdForNotificationCleanup: groupId,
              notificationEventIdForStaleAddCleanup: notificationEventId,
            );
            return switch (result) {
              DbIncomingReactionApplyResult.inserted =>
                ReactionAddApplyResult.inserted,
              DbIncomingReactionApplyResult.updated =>
                ReactionAddApplyResult.updated,
              DbIncomingReactionApplyResult.exactReplay =>
                ReactionAddApplyResult.exactReplay,
              DbIncomingReactionApplyResult.stale ||
              DbIncomingReactionApplyResult.removed =>
                ReactionAddApplyResult.stale,
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
          DbIncomingReactionApplyResult.stale =>
            ReactionRemoveApplyResult.stale,
          DbIncomingReactionApplyResult.inserted ||
          DbIncomingReactionApplyResult.updated => throw StateError(
            'REMOVE transaction returned ADD result',
          ),
        };
      },
      dbApplyGroupRemove: ({required groupId, required row}) async {
        final result = await dbApplyIncomingReactionMutation(
          db,
          row,
          mutation: DbIncomingReactionMutation.remove,
          groupIdForNotificationCleanup: groupId,
        );
        return switch (result) {
          DbIncomingReactionApplyResult.removed =>
            ReactionRemoveApplyResult.applied,
          DbIncomingReactionApplyResult.exactReplay =>
            ReactionRemoveApplyResult.exactReplay,
          DbIncomingReactionApplyResult.stale =>
            ReactionRemoveApplyResult.stale,
          DbIncomingReactionApplyResult.inserted ||
          DbIncomingReactionApplyResult.updated => throw StateError(
            'group REMOVE transaction returned ADD result',
          ),
        };
      },
      dbLoadReactionsForMessage: (messageId) =>
          dbLoadReactionsForMessage(db, messageId),
      dbLoadReactionsForMessages: (messageIds) =>
          dbLoadReactionsForMessages(db, messageIds),
      dbLoadActiveOrTombstonedReactionForSender: (messageId, senderPeerId) =>
          dbLoadActiveOrTombstonedReactionForSender(
            db,
            messageId,
            senderPeerId,
          ),
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
      dbStageOutgoingDirectReactionInboxCustody:
          ({
            required reactionRow,
            required recipientPeerId,
            required action,
            required wireEnvelope,
          }) => dbStageOutgoingDirectReactionInboxCustody(
            db,
            reactionRow: reactionRow,
            recipientPeerId: recipientPeerId,
            action: action,
            wireEnvelope: wireEnvelope,
          ),
      dbLoadDirectReactionInboxCustodyOutbox: ({limit = 50}) =>
          dbLoadDirectReactionInboxCustodyOutbox(db, limit: limit),
      dbLoadDirectReactionInboxCustodyOutboxForEvent:
          ({required recipientPeerId, required eventId}) =>
              dbLoadDirectReactionInboxCustodyOutboxForEvent(
                db,
                recipientPeerId: recipientPeerId,
                eventId: eventId,
              ),
      dbRecordDirectReactionInboxCustodyFailureIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
            required errorCode,
            required attemptedAt,
          }) => dbRecordDirectReactionInboxCustodyFailureIfExact(
            db,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            expectedWireEnvelope: expectedWireEnvelope,
            errorCode: errorCode,
            attemptedAt: attemptedAt,
          ),
      dbCompleteAcceptedDirectReactionInboxCustodyIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
          }) => dbCompleteAcceptedDirectReactionInboxCustodyIfExact(
            db,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            expectedWireEnvelope: expectedWireEnvelope,
          ),
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
          dbAttachGroupReactionReplayOutboxPayload:
              ({
                required reactionId,
                required inboxRetryPayload,
                required updatedAt,
              }) => dbAttachGroupReactionReplayOutboxPayload(
                db,
                reactionId: reactionId,
                inboxRetryPayload: inboxRetryPayload,
                updatedAt: updatedAt,
              ),
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
    final groupNotificationDisplayOutboxRepository =
        GroupNotificationDisplayOutboxRepositoryImpl(
          dbStage: (row) => dbStageGroupNotificationDisplayOutboxEntry(db, row),
          dbLoadByEventId: (eventId) =>
              dbLoadGroupNotificationDisplayOutboxEntry(db, eventId),
          dbPromoteReadyIfExact:
              ({
                required eventId,
                required expectedRevision,
                required updatedAt,
              }) => dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
                db,
                eventId: eventId,
                expectedRevision: expectedRevision,
                updatedAt: updatedAt,
              ),
          dbLoadReady: ({limit = 20, required eligibleAt}) =>
              dbLoadReadyGroupNotificationDisplayOutboxEntries(
                db,
                limit: limit,
                eligibleAt: eligibleAt,
              ),
          dbLoadEarliestNextAttemptAt: () =>
              dbLoadEarliestGroupNotificationDisplayOutboxNextAttemptAt(db),
          dbRecordRetryIfExact:
              ({
                required eventId,
                required expectedRevision,
                required lastErrorCode,
                required lastAttemptAt,
                required nextAttemptAt,
                required updatedAt,
              }) => dbRecordGroupNotificationDisplayOutboxRetryIfExact(
                db,
                eventId: eventId,
                expectedRevision: expectedRevision,
                lastErrorCode: lastErrorCode,
                lastAttemptAt: lastAttemptAt,
                nextAttemptAt: nextAttemptAt,
                updatedAt: updatedAt,
              ),
          dbCompleteIfExact:
              ({
                required eventId,
                required expectedRevision,
                required expectedEventKind,
                required expectedGroupId,
                required expectedMessageId,
                required expectedActorPeerId,
                required expectedEventTimestamp,
                required expectedReactionId,
                required expectedReactionAction,
                required expectedReactionTombstone,
              }) => dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
                db,
                eventId: eventId,
                expectedRevision: expectedRevision,
                expectedEventKind: expectedEventKind,
                expectedGroupId: expectedGroupId,
                expectedMessageId: expectedMessageId,
                expectedActorPeerId: expectedActorPeerId,
                expectedEventTimestamp: expectedEventTimestamp,
                expectedReactionId: expectedReactionId,
                expectedReactionAction: expectedReactionAction,
                expectedReactionTombstone: expectedReactionTombstone,
              ),
          dbReconcileMessageAliasReady:
              ({
                required aliasEventId,
                required canonicalEventId,
                required groupId,
                required actorPeerId,
                required eventTimestamp,
                required updatedAt,
              }) => dbReconcileGroupNotificationDisplayOutboxMessageAliasReady(
                db,
                aliasEventId: aliasEventId,
                canonicalEventId: canonicalEventId,
                groupId: groupId,
                actorPeerId: actorPeerId,
                eventTimestamp: eventTimestamp,
                updatedAt: updatedAt,
              ),
          dbDeleteForGroup: (groupId) =>
              dbDeleteGroupNotificationDisplayOutboxForGroup(db, groupId),
          dbDeleteForMessage: ({required groupId, required messageId}) =>
              dbDeleteGroupNotificationDisplayOutboxForMessage(
                db,
                groupId: groupId,
                messageId: messageId,
              ),
          dbDeleteForReaction:
              ({required groupId, required messageId, required reactionId}) =>
                  dbDeleteGroupNotificationDisplayOutboxForReaction(
                    db,
                    groupId: groupId,
                    messageId: messageId,
                    reactionId: reactionId,
                  ),
          dbDeleteForReactionActor:
              ({required groupId, required messageId, required actorPeerId}) =>
                  dbDeleteGroupNotificationDisplayOutboxForReactionActor(
                    db,
                    groupId: groupId,
                    messageId: messageId,
                    actorPeerId: actorPeerId,
                  ),
        );
    final groupNotificationReconciliationOutboxRepository =
        GroupNotificationReconciliationOutboxRepositoryImpl(
          dbLoadEligible: ({limit = 20, required eligibleAt}) =>
              dbLoadEligibleGroupNotificationReconciliationOutboxEntries(
                db,
                limit: limit,
                eligibleAt: eligibleAt,
              ),
          dbLoadEarliestNextAttemptAt: () =>
              dbLoadEarliestGroupNotificationReconciliationOutboxNextAttemptAt(
                db,
              ),
          dbRecordFailureIfExact:
              ({
                required groupId,
                required expectedIncarnationId,
                required expectedRevision,
                required lastAttemptAt,
                required nextAttemptAt,
                required updatedAt,
              }) => dbRecordGroupNotificationReconciliationOutboxFailureIfExact(
                db,
                groupId: groupId,
                expectedIncarnationId: expectedIncarnationId,
                expectedRevision: expectedRevision,
                lastAttemptAt: lastAttemptAt,
                nextAttemptAt: nextAttemptAt,
                updatedAt: updatedAt,
              ),
          dbCompleteIfExact:
              ({
                required groupId,
                required expectedIncarnationId,
                required expectedRevision,
              }) => dbCompleteGroupNotificationReconciliationOutboxIfExact(
                db,
                groupId: groupId,
                expectedIncarnationId: expectedIncarnationId,
                expectedRevision: expectedRevision,
              ),
        );

    // Create group repository
    final groupRepository = GroupRepositoryImpl(
      dbInsertGroup: (row) => dbInsertGroup(db, row),
      dbLoadAllGroups: () => dbLoadAllGroups(db),
      dbLoadGroup: (id) => dbLoadGroup(db, id),
      dbUpdateGroup: (row) => dbUpdateGroup(db, row),
      dbCommitDissolvedGroup: (row) =>
          dbCommitDissolvedGroupAndDeleteNotificationDisplayOutbox(db, row),
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
      dbDeleteAllGroupMembers: (groupId) =>
          dbDeleteAllGroupMembers(db, groupId),
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
          dbDeleteGroupKeysBeforeGeneration(
            db,
            groupId,
            minKeyGenerationToKeep,
          ),
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
      dbCommitFreshAcceptedMaterializationRollbackFn:
          ({required preparation}) =>
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
    final deleteSelfRemovedGroupShellUseCase =
        DeleteSelfRemovedGroupShellUseCase(
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
          ({
            required packageId,
            required recipientDeviceId,
            required groupId,
          }) => dbLoadGroupWelcomeKeyPackageTombstone(
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

    // The repository read boundary and every foreground group presentation
    // share this key. Capturing the currently managed generation before the SQL
    // read commit therefore cannot race a foreground final-show call.
    final iosNotificationRecoveryEnabled =
        !kIsWeb && Platform.isIOS && !isGroupMediaIosDisposableProfile;
    final iosNotificationRecoveryCoordinator = iosNotificationRecoveryEnabled
        ? IosNotificationRecoveryCoordinator(
            platformEnabled: true,
            bridge: MethodChannelIosNotificationRecoveryBridge(),
            loadActiveAccountPeerId: () async =>
                (await repository.loadIdentity())?.peerId,
            loadCanonicalState: () => dbLoadCanonicalNotificationBadgeState(db),
          )
        : null;
    final notificationService = FlutterNotificationService(
      requestApplePermissions: !kE2ETestMode,
      onNotificationUpdated: iosNotificationRecoveryCoordinator?.reconcile,
      onConversationCleared: iosNotificationRecoveryCoordinator == null
          ? null
          : (_) => iosNotificationRecoveryCoordinator.reconcile(),
      onAllNotificationsCleared: iosNotificationRecoveryCoordinator?.reconcile,
    );
    final groupNotificationPresentationCoordinator =
        GroupNotificationPresentationCoordinator();

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
            groupNotificationPresentationCoordinator.runForGroup(
              groupId,
              () async {
                ConversationNotificationContentMetadata? metadata;
                if (!isDesktop) {
                  try {
                    metadata = await notificationService
                        .lookupConversationNotificationContentMetadata(
                          'group:$groupId',
                        );
                  } catch (error) {
                    emitFlowEvent(
                      layer: 'FL',
                      event:
                          'GROUP_NOTIFICATION_READ_METADATA_CAPTURE_UNAVAILABLE',
                      details: {'errorType': error.runtimeType.toString()},
                    );
                  }
                }
                final eventIdentity = metadata?.eventIdentity?.trim();
                final generation = metadata?.generation?.trim();
                if (metadata == null ||
                    eventIdentity == null ||
                    eventIdentity.isEmpty ||
                    generation == null ||
                    generation.isEmpty) {
                  return dbMarkGroupMessagesAsRead(executor, groupId);
                }
                return dbMarkGroupMessagesAsRead(
                  executor,
                  groupId,
                  acknowledgedContentKind: metadata.kind.name,
                  acknowledgedEventIdentity: eventIdentity,
                  acknowledgedGeneration: generation,
                );
              },
            ),
        dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(executor, id),
        dbDeleteGroupMessageForMembershipRepairFn: (id) =>
            dbDeleteGroupMessageForMembershipRepair(executor, id),
        dbExistsGroupMessageByContent:
            (groupId, senderPeerId, text, timestamp) =>
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
            dbAnchorOutgoingGroupPrivateMediaCustody(
              executor,
              id,
              nowMs: nowMs,
            ),
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
    final diagnosingDeleteSelfRemovedGroupShellAction =
        DiagnosingDeleteSelfRemovedGroupShellAction(
          loadCurrentSelfPeerId: () async =>
              (await repository.loadIdentity())?.peerId,
          inner: deleteSelfRemovedGroupShellUseCase.call,
          submit: groupExitDiagnosticRepository.appendOutcome,
        );
    defaultDiagnosingDeleteSelfRemovedGroupShellAction =
        diagnosingDeleteSelfRemovedGroupShellAction.call;
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
              (
                id, {
                required status,
                required lastError,
                required finalizedAt,
              }) => dbFinalizeGroupPendingKeyDistribution(
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
          dbPruneGroupPendingMembershipMessages:
              (groupId, {required maxRows}) =>
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
      dbDeleteGroupPendingReaction: (id) =>
          dbDeleteGroupPendingReaction(db, id),
      dbPruneGroupPendingReactions: (groupId, {required maxRows}) =>
          dbPruneGroupPendingReactions(db, groupId, maxRows: maxRows),
      dbDeleteExpiredGroupPendingReactions: ({required olderThanIso}) =>
          dbDeleteExpiredGroupPendingReactions(db, olderThanIso: olderThanIso),
    );

    final groupHistoryGapRepairRepository = GroupHistoryGapRepairRepositoryImpl(
      dbUpsertGroupHistoryGapRepair: (row) =>
          dbUpsertGroupHistoryGapRepair(db, row),
      dbSaveGroupHistoryGapRepair: (row) =>
          dbSaveGroupHistoryGapRepair(db, row),
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
      dbLoadVisibleGroupHistoryGapRepairs:
          ({required groupId, int limit = 20}) =>
              dbLoadVisibleGroupHistoryGapRepairs(
                db,
                groupId: groupId,
                limit: limit,
              ),
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
      dbLoadIntroductionsForRecipientAndIntroducer:
          (recipientId, introducerId) =>
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
          dbDeleteIntroductionOutboxDeliveriesForIntroduction(
            db,
            introductionId,
          ),
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
        final group = await groupPrivateMediaLifecycleEngine
            .loadNextExpiryAtMs();
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
              WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed,
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
    final privateMediaOutboxE2EController = debugE2EComposition
        ?.initializePrivateMediaController();

    // Create and initialize the bridge (Go native)
    final Bridge bridge = GoBridgeClient();
    final strictDirectMediaBlobDownloadAckOwner =
        StrictDirectMediaBlobDownloadAckOwner(
          bridge: bridge,
          mediaAttachmentRepository: mediaAttachmentRepository,
          mediaFileManager: mediaFileManager,
        );
    final directMediaBlobCustodyDrain = DirectMediaBlobCustodyDrain(
      repository: mediaAttachmentRepository,
      incomingRepository: mediaAttachmentRepository,
      artifactStore: DirectMediaBlobArtifactStore(
        documentsDirectoryProvider: () async => appDocDir,
      ),
      identityPeerId: () async => (await repository.loadIdentity())?.peerId,
      strictDownloadAckOwner: strictDirectMediaBlobDownloadAckOwner,
      retryIncomingDownload: (row) async {
        final parent = await messageRepository.getMessage(row.messageId);
        if (parent == null || !parent.isIncoming) return false;
        final attachments = await mediaAttachmentRepository
            .getAttachmentsForMessage(
              row.messageId,
              owner: MediaOwnerLane.direct,
            );
        final candidates = attachments.where(
          (attachment) => attachment.id == row.attachmentId,
        );
        if (candidates.length != 1) return false;
        return await strictDirectMediaBlobDownloadAckOwner
                .downloadAndAcknowledge(
                  attachment: candidates.single,
                  contactPeerId: parent.contactPeerId,
                ) !=
            null;
      },
    );
    Future<int> cleanupDirectMediaBlobCustodyLocally() async {
      final result = await directMediaBlobCustodyDrain.runLocalCleanupBounded();
      emitFlowEvent(
        layer: 'FL',
        event: 'DIRECT_MEDIA_BLOB_CUSTODY_LOCAL_DRAIN_RESULT',
        details: <String, Object?>{
          'completed': result.completed,
          'retained': result.retained,
          'failed': result.failed,
        },
      );
      return result.completed;
    }

    Future<int> drainDirectMediaBlobCustody() async {
      final result = await directMediaBlobCustodyDrain.runNetworkBounded();
      emitFlowEvent(
        layer: 'FL',
        event: 'DIRECT_MEDIA_BLOB_CUSTODY_NETWORK_DRAIN_RESULT',
        details: <String, Object?>{
          'completed': result.completed,
          'retained': result.retained,
          'failed': result.failed,
        },
      );
      return result.completed;
    }

    final diagnosingDeleteDissolvedGroupShellAction =
        DiagnosingDeleteDissolvedGroupShellAction(
          inner: (groupId) => deleteGroupAndMessages(
            groupRepo: groupRepository,
            groupMessageRepo: groupMessageRepository,
            groupId: groupId,
          ),
          submit: groupExitDiagnosticRepository.appendOutcome,
        );
    defaultDiagnosingDeleteDissolvedGroupShellAction =
        diagnosingDeleteDissolvedGroupShellAction.call;

    // ── Auto-setup for simulator scripts (debug/test harness only) ──
    await DebugE2ECompositionRoot.runSimulatorAutoSetupIfConfigured(
      documentsPath: appDocDir.path,
      identityRepository: repository,
      bridge: bridge,
    );

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
        publishCanonicalAccountBinding:
            canonicalRuntimeBindingCoordinator == null
            ? null
            : (accountPeerId) async {
                await canonicalRuntimeBindingCoordinator.publishAccount(
                  accountPeerId,
                );
              },
        stagingDirectoryPath: '${appDocDir.path}/account_migration/import',
        documentsRootPath: appDocDir.path,
      ),
      oldPhoneCutoverCoordinator: accountMigrationCutoverCoordinator,
      oldPhoneLeaseCleanup: buildBridgeMigrationCutoverLeaseCleanup(
        bridge: bridge,
        clearLocalStalePushToken: () async {
          try {
            await iosNotificationRecoveryCoordinator?.clearAccount();
          } catch (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'ACCOUNT_MIGRATION_IOS_NOTIFICATION_CLEAR_FAILED',
              details: {'errorType': error.runtimeType.toString()},
            );
          }
          await pushTokenStore.clearToken();
          await canonicalRuntimeBindingCoordinator?.retireAccount();
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
      Map<String, String>? mutationEventIds,
    }) {
      return sendDeliveryReceipt(
        p2pService: p2pService,
        targetPeerId: contactPeerId,
        messageIds: messageIds,
        mutationEventIds: mutationEventIds,
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
        return accountMigrationRuntimeNetworkGate
            .allowsAccountNetworkSideEffects(
              peerId: identity?.peerId,
              operation: 'push_staged_envelope_ingest',
            );
      },
      replayChatMessage:
          (
            message, {
            required bool suppressNotification,
            String? stagedEntryId,
          }) {
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
    DirectNotificationProjectionOwner? directNotificationOwner;
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
        loadConversationNotificationSnapshot: () =>
            loadDirectConversationNotificationSnapshot(
              messageRepository: messageRepository,
              contactPeerId: message.from,
              mediaAttachmentRepository: mediaAttachmentRepository,
              pendingNotificationOverlay:
                  pendingNotificationOverlayBindingPublisher,
            ),
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
        stageNotificationDisplayCustody: directNotificationOwner?.stageReaction,
        promoteNotificationDisplayCustody:
            directNotificationOwner?.promoteReactionReadyIfExact,
        commitNotificationRemove:
            directNotificationOwner?.onReactionRemoveCommitted,
        retryNotificationDisplays: directNotificationOwner?.retryNow,
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
        sendMutationDeliveryReceipt: (messageId, {required mutationEventId}) =>
            sendDeliveryReceiptForPeer(
              contactPeerId: message.from,
              messageIds: [messageId],
              mutationEventIds: <String, String>{messageId: mutationEventId},
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
      registerWakeTokens: (tokens) =>
          registerWakeTokensViaBridge(bridge, tokens),
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
    final acceptedWakeTokenHashObserver = debugE2EComposition
        ?.initializeWakeTokenObserver();

    // Create P2P service (uses the same bridge + local P2P)
    p2pService = P2PServiceImpl(
      bridge: bridge,
      localP2PService: localP2PService,
      pushTokenStore: pushTokenStore,
      // Plan 320 P2: relay-health re-registration reads the LIVE provider token
      // so a relay-side eviction of a dead token is not undone by replaying the
      // cached one. Falls back to the cache when the provider read fails.
      liveFcmTokenReader: () => FirebaseMessaging.instance.getToken(),
      // FDC-09 §12 / CV-14: the send funnel attaches received[toPeerId] on
      // `inbox:store` (1:1 contacts only). Inert until a peer distributes a `wt`.
      receivedWakeTokenStore: receivedWakeTokenStore,
      acceptedInboxWakeTokenHashObserver: acceptedWakeTokenHashObserver,
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

    // Create conversation trackers (the notification service and shared group
    // presentation coordinator were created at the repository read boundary).
    final pushRegistrationEnabled = shouldEnableProductionPushRegistration(
      isDesktop: isDesktop,
    );
    final pushRegistrationHealthNotifier = pushRegistrationEnabled
        ? PushRegistrationHealthNotifier()
        : null;
    final PushRegistrationHealthStorage? pushRegistrationHealthStore =
        pushRegistrationEnabled
        ? ResolvingPushRegistrationHealthStore(
            secureKeyStore: secureKeyStore,
            resolveBinding: () async {
              final identity = await repository.loadIdentity();
              final transportPeerId = p2pService.currentState.peerId;
              if (identity == null ||
                  transportPeerId == null ||
                  transportPeerId.trim().isEmpty) {
                throw StateError(
                  'Push registration health binding is unavailable.',
                );
              }
              return (
                accountPeerId: identity.peerId,
                installationId: transportPeerId,
              );
            },
          )
        : null;
    final PushRegistrationCoordinator? pushRegistrationCoordinator =
        pushRegistrationEnabled
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
            healthStore: pushRegistrationHealthStore,
            healthNotifier: pushRegistrationHealthNotifier,
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
    final directNotificationPresentationCoordinator =
        DirectNotificationPresentationCoordinator();
    final directNotificationReadProjector = DirectNotificationReadProjector(
      coordinator: directNotificationPresentationCoordinator,
      cancellation: notificationService,
      commitRead: (peerId, metadata) =>
          dbMarkDirectConversationReadAndAcknowledge(
            db,
            peerId: peerId,
            metadata: metadata,
          ),
    );
    projectDirectConversationRead =
        directNotificationReadProjector.markConversationRead;

    Future<bool> directPeerAllowsNotification(String peerId) async {
      final contact = await contactRepository.getContact(peerId);
      return contact != null && !contact.isBlocked && !contact.isArchived;
    }

    Future<DirectNotificationCanonicalContentDecision>
    resolveDirectCanonicalContent(
      String peerId,
      ConversationNotificationContentMetadata metadata,
    ) async {
      final eventIdentity = metadata.eventIdentity?.trim();
      if (eventIdentity == null || eventIdentity.isEmpty) {
        return DirectNotificationCanonicalContentDecision.unknown;
      }
      if (!await directPeerAllowsNotification(peerId)) {
        return DirectNotificationCanonicalContentDecision.retire;
      }
      switch (metadata.kind) {
        case ConversationNotificationContentKind.message:
          final message = await messageRepository.getMessage(eventIdentity);
          if (message == null) {
            final acknowledgement =
                await directNotificationReadAcknowledgementRepository.loadExact(
                  peerId: peerId,
                  contentKind: 'message',
                  eventIdentity: eventIdentity,
                  generation: metadata.generation,
                );
            return acknowledgement == null
                ? DirectNotificationCanonicalContentDecision.unknown
                : DirectNotificationCanonicalContentDecision.retire;
          }
          return message.contactPeerId == peerId &&
                  message.isIncoming &&
                  message.readAt == null &&
                  !message.isDeleted &&
                  message.hiddenAt == null
              ? DirectNotificationCanonicalContentDecision.keep
              : DirectNotificationCanonicalContentDecision.retire;
        case ConversationNotificationContentKind.reaction:
          final terminal = await directNotificationReactionTerminalRepository
              .loadByTerminalEvent(
                peerId: peerId,
                terminalEventId: eventIdentity,
              );
          if (terminal == null) {
            final acknowledgement =
                await directNotificationReadAcknowledgementRepository.loadExact(
                  peerId: peerId,
                  contentKind: 'reaction',
                  eventIdentity: eventIdentity,
                  generation: metadata.generation,
                );
            return acknowledgement == null
                ? DirectNotificationCanonicalContentDecision.unknown
                : DirectNotificationCanonicalContentDecision.retire;
          }
          if (terminal.notificationAcknowledgedAt != null) {
            return DirectNotificationCanonicalContentDecision.retire;
          }
          final target = await messageRepository.getMessage(terminal.messageId);
          final reaction = await reactionRepository
              .getReactionForSenderIncludingRemoved(
                messageId: terminal.messageId,
                senderPeerId: terminal.actorPeerId,
              );
          return target != null &&
                  target.contactPeerId == peerId &&
                  !target.isIncoming &&
                  !target.isDeleted &&
                  reaction != null &&
                  !reaction.isRemoved &&
                  reaction.id == terminal.reactionId
              ? DirectNotificationCanonicalContentDecision.keep
              : DirectNotificationCanonicalContentDecision.retire;
      }
    }

    Future<CanonicalConversationNotificationReplacement?>
    loadDirectCanonicalReplacement(
      String peerId,
      ConversationNotificationContentMetadata currentMetadata,
    ) async {
      final contact = await contactRepository.getContact(peerId);
      if (contact == null || contact.isBlocked || contact.isArchived) {
        return null;
      }
      final messages = await messageRepository.getMessagesForContact(peerId);
      final unread =
          messages
              .where(
                (message) =>
                    message.isIncoming &&
                    message.readAt == null &&
                    !message.isDeleted &&
                    message.hiddenAt == null,
              )
              .toList(growable: false)
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (unread.isNotEmpty) {
        final message = unread.first;
        return CanonicalConversationNotificationReplacement(
          senderUsername: contact.username,
          messageText: notificationBodyForMessage(
            message.text,
            message.media,
            privateMediaPolicy: message.privateMediaPolicy,
          ),
          routePayload: NotificationRouteTarget.conversation(
            peerId,
            messageId: message.id,
          ).toPayload(),
          contentKind: ConversationNotificationContentKind.message,
          eventIdentity: message.id,
          snapshot: await loadDirectConversationNotificationSnapshot(
            messageRepository: messageRepository,
            contactPeerId: peerId,
            mediaAttachmentRepository: mediaAttachmentRepository,
            pendingNotificationOverlay:
                pendingNotificationOverlayBindingPublisher,
          ),
        );
      }
      if (currentMetadata.kind ==
          ConversationNotificationContentKind.reaction) {
        final eventIdentity = currentMetadata.eventIdentity?.trim();
        if (eventIdentity == null || eventIdentity.isEmpty) return null;
        final terminal = await directNotificationReactionTerminalRepository
            .loadByTerminalEvent(
              peerId: peerId,
              terminalEventId: eventIdentity,
            );
        if (terminal == null || terminal.notificationAcknowledgedAt != null) {
          return null;
        }
        final reaction = await reactionRepository
            .getReactionForSenderIncludingRemoved(
              messageId: terminal.messageId,
              senderPeerId: terminal.actorPeerId,
            );
        if (reaction == null ||
            reaction.isRemoved ||
            reaction.id != terminal.reactionId) {
          return null;
        }
        return CanonicalConversationNotificationReplacement(
          senderUsername: contact.username,
          messageText: 'Reacted ${reaction.emoji} to your message',
          routePayload: NotificationRouteTarget.conversation(
            peerId,
            messageId: terminal.messageId,
          ).toPayload(),
          contentKind: ConversationNotificationContentKind.reaction,
          eventIdentity: terminal.terminalEventId,
          snapshot: await loadDirectConversationNotificationSnapshot(
            messageRepository: messageRepository,
            contactPeerId: peerId,
            mediaAttachmentRepository: mediaAttachmentRepository,
            pendingNotificationOverlay:
                pendingNotificationOverlayBindingPublisher,
          ),
        );
      }
      return null;
    }

    final directCanonicalReconciler = DirectNotificationCanonicalReconciler(
      coordinator: directNotificationPresentationCoordinator,
      generationCancellation: notificationService,
      generationReplacement: notificationService,
      isCurrentContentCanonical: resolveDirectCanonicalContent,
      loadReplacement: loadDirectCanonicalReplacement,
    );
    directNotificationOwner = DirectNotificationProjectionOwner(
      displayOutbox: directNotificationDisplayOutboxRepository,
      reconciliationOutbox: directNotificationReconciliationOutboxRepository,
      reactionTerminal: directNotificationReactionTerminalRepository,
      coordinator: directNotificationPresentationCoordinator,
      canonicalReconciler: directCanonicalReconciler,
      enqueueReconciliation: (peerId) =>
          dbEnqueueDirectNotificationReconciliationOutbox(db, peerId: peerId),
      projectDisplay: (entry) async {
        if (!await directPeerAllowsNotification(entry.peerId)) return null;
        final contact = await contactRepository.getContact(entry.peerId);
        if (contact == null) return null;
        switch (entry.eventKind) {
          case DirectNotificationDisplayOutboxKind.message:
            final message = await messageRepository.getMessage(entry.messageId);
            if (message == null) {
              throw const DirectNotificationDisplayStateUnavailableException();
            }
            if (message.contactPeerId != entry.peerId ||
                message.senderPeerId != entry.actorPeerId ||
                message.timestamp != entry.eventTimestamp ||
                !message.isIncoming ||
                message.readAt != null ||
                message.isDeleted ||
                message.hiddenAt != null) {
              return null;
            }
            return maybeShowNotification(
              notificationService: notificationService,
              conversationTracker: conversationTracker,
              getAppLifecycleState: () =>
                  WidgetsBinding.instance.lifecycleState ??
                  AppLifecycleState.resumed,
              contactPeerId: entry.peerId,
              routePayload: NotificationRouteTarget.conversation(
                entry.peerId,
                messageId: entry.messageId,
              ).toPayload(),
              senderUsername: contact.username,
              messageText: notificationBodyForMessage(
                message.text,
                message.media,
                privateMediaPolicy: message.privateMediaPolicy,
              ),
              messageId: entry.messageId,
              notificationEventIdentity: entry.eventId,
              notificationEventType: 'new_message',
              toneTracker: notificationToneTracker,
              durableNotificationCoordinatorResolver: () async =>
                  durableReactionNotificationCoordinator,
              loadConversationNotificationSnapshot: () =>
                  loadDirectConversationNotificationSnapshot(
                    messageRepository: messageRepository,
                    contactPeerId: entry.peerId,
                    mediaAttachmentRepository: mediaAttachmentRepository,
                    pendingNotificationOverlay:
                        pendingNotificationOverlayBindingPublisher,
                  ),
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
          case DirectNotificationDisplayOutboxKind.reaction:
            final target = await messageRepository.getMessage(entry.messageId);
            final reaction = await reactionRepository
                .getReactionForSenderIncludingRemoved(
                  messageId: entry.messageId,
                  senderPeerId: entry.actorPeerId,
                );
            if (target == null) {
              throw const DirectNotificationDisplayStateUnavailableException();
            }
            if (target.contactPeerId != entry.peerId ||
                target.isIncoming ||
                target.isDeleted ||
                reaction == null ||
                reaction.isRemoved ||
                reaction.id != entry.reactionId ||
                reaction.timestamp != entry.eventTimestamp) {
              return null;
            }
            return maybeShowNotification(
              notificationService: notificationService,
              conversationTracker: conversationTracker,
              getAppLifecycleState: () =>
                  WidgetsBinding.instance.lifecycleState ??
                  AppLifecycleState.resumed,
              contactPeerId: entry.peerId,
              routePayload: NotificationRouteTarget.conversation(
                entry.peerId,
                messageId: entry.messageId,
              ).toPayload(),
              senderUsername: contact.username,
              messageText: 'Reacted ${reaction.emoji} to your message',
              messageId: entry.reactionId,
              notificationEventIdentity: entry.eventId,
              notificationEventType: 'message_reaction',
              toneTracker: notificationToneTracker,
              durableNotificationCoordinatorResolver: () async =>
                  durableReactionNotificationCoordinator,
              loadConversationNotificationSnapshot: () =>
                  loadDirectConversationNotificationSnapshot(
                    messageRepository: messageRepository,
                    contactPeerId: entry.peerId,
                    mediaAttachmentRepository: mediaAttachmentRepository,
                    pendingNotificationOverlay:
                        pendingNotificationOverlayBindingPublisher,
                  ),
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
          default:
            return null;
        }
      },
    );
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
      stageNotificationDisplayCustody: directNotificationOwner.stageMessage,
      promoteNotificationDisplayCustody:
          directNotificationOwner.promoteMessageReadyIfExact,
      retryNotificationDisplays: directNotificationOwner.retryNow,
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
      resolveNotificationDependencies: (contactPeerId) {
        final notify = reactionNotifyDeps;
        if (notify == null) return null;
        return (
          service: notify.service,
          tracker: notify.tracker,
          lifecycle: notify.lifecycle,
          toneTracker: notify.toneTracker,
          durableCoordinatorResolver: () async => notify.durableCoordinator,
          consumeRemoteAnnouncement: ({required payload, String? messageId}) =>
              recentRemoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
          markRemoteAnnouncement: ({required payload, String? messageId}) =>
              recentRemoteNotificationGate.markAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
          loadSnapshot: () => loadDirectConversationNotificationSnapshot(
            messageRepository: messageRepository,
            contactPeerId: contactPeerId,
            mediaAttachmentRepository: mediaAttachmentRepository,
            pendingNotificationOverlay:
                pendingNotificationOverlayBindingPublisher,
          ),
        );
      },
      stageNotificationDisplayCustody: directNotificationOwner.stageReaction,
      promoteNotificationDisplayCustody:
          directNotificationOwner.promoteReactionReadyIfExact,
      commitNotificationRemove:
          directNotificationOwner.onReactionRemoveCommitted,
      retryNotificationDisplays: directNotificationOwner.retryNow,
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

    final debugE2EGroupMediaDownloadHooks = debugE2EComposition
        ?.bindGroupMediaDownloadHooks(
          loadCurrentAttachment: mediaAttachmentRepository.getAttachmentById,
        );
    final groupMediaDownloadCoordinator = RetryIncompleteGroupDownloadsUseCase(
      loadPage: ({required after, required limit}) async {
        final rows = await mediaAttachmentRepository
            .loadRecoverableGroupDownloadPage(
              after: after == null
                  ? null
                  : DurableGroupMediaDownloadCursor(
                      createdAt: after.createdAt,
                      attachmentId: after.attachmentId,
                    ),
              limit: limit,
            );
        return rows
            .map(
              (candidate) => RecoverableGroupDownloadCandidate(
                attachment: candidate.attachment,
                groupId: candidate.groupId,
              ),
            )
            .toList(growable: false);
      },
      loadCurrentAttachment: mediaAttachmentRepository.getAttachmentById,
      loadCurrentParent: groupMessageRepository.getMessage,
      loadCurrentGroup: groupRepository.getGroup,
      autoDownloadDecider: mediaAutoDownloadDecider,
      allowsNetworkSideEffects: () async {
        if (debugE2EComposition?.holdsAutomaticGroupMediaRecovery ?? false) {
          return false;
        }
        return allowsAccountRuntimeNetworkSideEffects(
          'group_media_download_recovery',
        );
      },
      transfer: ({required attachment, required parent, required group}) async {
        return downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepository,
          mediaFileManager: mediaFileManager,
          attachment: attachment,
          contactPeerId: group.id,
          owner: MediaOwnerLane.group,
          enforceGroupMediaPolicy: true,
          groupMessageRepo: groupMessageRepository,
          groupMediaAutomaticDownloadAttemptStarted:
              debugE2EGroupMediaDownloadHooks
                  ?.onAutomaticDownloadAttemptStarted,
          groupMediaPostClaimPreCommit:
              debugE2EGroupMediaDownloadHooks?.onPostClaimPreCommit,
        );
      },
    );

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
      groupMediaDownloadCoordinator: groupMediaDownloadCoordinator,
      notificationService: notificationService,
      groupConversationTracker: groupConversationTracker,
      notificationToneTracker: notificationToneTracker,
      notificationPresentationCoordinator:
          groupNotificationPresentationCoordinator,
      pendingConversationNotificationOverlay:
          pendingNotificationOverlayBindingPublisher,
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
      notificationDisplayOutbox: groupNotificationDisplayOutboxRepository,
      notificationReconciliationOutbox:
          groupNotificationReconciliationOutboxRepository,
      loadLatestUnreadNotificationMessage: (groupId) async {
        final row = await dbLoadLatestUnreadGroupNotificationMessage(
          db,
          groupId,
        );
        return row == null ? null : GroupMessage.fromMap(row);
      },
      isActiveGroupNotificationReaction:
          ({required groupId, required selfPeerId, required eventIdentity}) =>
              dbIsActiveGroupNotificationReaction(
                db,
                groupId: groupId,
                selfPeerId: selfPeerId,
                eventIdentity: eventIdentity,
              ),
      loadLatestActiveNotificationReaction:
          ({required groupId, required selfPeerId}) async {
            final row = await dbLoadLatestActiveGroupNotificationReaction(
              db,
              groupId: groupId,
              selfPeerId: selfPeerId,
            );
            if (row == null) return null;
            final messageId = (row['message_id'] as String?)?.trim();
            final actorPeerId = (row['sender_peer_id'] as String?)?.trim();
            final eventIdentity =
                (row['notification_display_terminal_event_id'] as String?)
                    ?.trim();
            final timestamp = DateTime.tryParse(
              (row['timestamp'] as String?)?.trim() ?? '',
            );
            if (messageId == null ||
                messageId.isEmpty ||
                actorPeerId == null ||
                actorPeerId.isEmpty ||
                eventIdentity == null ||
                eventIdentity.isEmpty ||
                timestamp == null) {
              throw StateError(
                'canonical group reaction descriptor is malformed',
              );
            }
            return GroupNotificationCanonicalReaction(
              messageId: messageId,
              actorPeerId: actorPeerId,
              eventIdentity: eventIdentity,
              timestamp: timestamp.toUtc(),
            );
          },
      isGroupNotificationEventAcknowledged:
          ({required groupId, required contentKind, required eventIdentity}) =>
              dbIsGroupNotificationEventAcknowledged(
                db,
                groupId: groupId,
                contentKind: contentKind,
                eventIdentity: eventIdentity,
              ),
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
    setDeferredDistributionDrainSink(({
      required groupId,
      required peerId,
    }) async {
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
    setGroupPendingBroadcastEnqueueSink(
      groupPendingBroadcastRepository.enqueue,
    );
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

    final groupExitDiagnosticObserver = GroupExitDiagnosticObserver(
      repository: groupExitDiagnosticRepository,
      now: () => DateTime.now().toUtc(),
      onSubmissionFailure: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_EXIT_DIAGNOSTIC_WRITE_FAILED',
          details: const {
            'code': 'EX01',
            'phase': 'authority',
            'severity': 'failure',
          },
        );
      },
    );
    final rawGroupExitIntentRunner = GroupExitIntentRunner(
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
          throw StateError(
            'Exact group exit sender membership is unavailable.',
          );
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
          throw StateError(
            'Durable group exit timeline notice is unavailable.',
          );
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
        try {
          final identity = await repository.loadIdentity();
          if (identity == null || identity.peerId != intent.selfPeerId) {
            throw StateError(
              'Group exit identity changed before native leave.',
            );
          }
        } catch (error, stackTrace) {
          throwGroupExitAuthorityFailure(error, stackTrace);
        }
        await runTypedGroupExitNativeLeave(
          () => callGroupLeave(bridge, intent.groupId),
        );
      },
    );
    final groupExitIntentProcessor = DiagnosingGroupExitIntentProcessor(
      inner: rawGroupExitIntentRunner,
      observer: groupExitDiagnosticObserver,
    );
    final uuid = const Uuid();
    final groupExitIntentCoordinator = GroupExitIntentCoordinator(
      intentRepository: groupExitIntentRepository,
      pendingRepository: groupPendingBroadcastRepository,
      pendingBroadcastRunner: groupPendingBroadcastRunner,
      processor: groupExitIntentProcessor,
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
    final currentGroupExitSnapshotResolver = CurrentGroupExitSnapshotResolver(
      identityRepository: repository,
      groupRepository: groupRepository,
      messageRepository: groupMessageRepository,
      inviteDeliveryAttemptRepository: groupInviteDeliveryAttemptRepository,
      loadPendingBroadcasts: groupPendingBroadcastRepository.forGroup,
    );
    final groupExitActionAdapter = DiagnosingGroupExitActionAdapter(
      resolveSnapshot: currentGroupExitSnapshotResolver.call,
      requestLeaveInner: groupExitIntentCoordinator.requestLeave,
      queueLeaveInner: groupExitIntentCoordinator.queueLeaveWhenSyncCompletes,
      retryInner: groupExitIntentCoordinator.retry,
      observer: groupExitDiagnosticObserver,
    );
    setGroupExitIntentActionSinks(
      resolveSnapshot: groupExitActionAdapter.loadSnapshot,
      requestLeave: groupExitActionAdapter.requestLeave,
      queueLeaveWhenSyncCompletes:
          groupExitActionAdapter.queueLeaveWhenSyncCompletes,
      retry: groupExitActionAdapter.retry,
      cancelQueued: groupExitIntentCoordinator.cancelQueued,
    );
    setGroupExitIntentAccessSinks(
      forGroup: groupExitIntentRepository.forGroup,
      all: groupExitIntentRepository.all,
    );
    setGroupExitIntentRuntimeSinks(
      canRejoin: authorizeCurrentAccountGroupRejoin,
      processExisting: (groupId) async {
        await groupExitIntentProcessor.processGroup(groupId);
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
          await groupExitIntentProcessor.processAll();
        },
        onError: (error, _) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_EXIT_INTENT_RECOVERY_FAILED',
            details: const {
              'code': 'EX99',
              'phase': 'authority',
              'severity': 'failure',
            },
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
      loadOwnInviteIdentity: groupIdentityCallbacks.loadOwnInviteIdentity,
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

    // TC-343-06a: one production closure owns both immutable direct-custody
    // families for every lifecycle trigger. Each bounded drain has its own
    // fault boundary, so a poison row/family cannot starve its sibling or the
    // failed/unacked rebuild work that follows this shared callback.
    Future<int> drainDirectInboxCustodyFamilies() =>
        runAccountRuntimeNetworkAction(
          operation: 'direct_inbox_custody_families_drain',
          blockedValue: 0,
          action: () async {
            var completed = 0;
            try {
              completed += await drainDirectInboxCustodyOutbox(
                custodyRepository: messageRepository,
                storeInAckCustodyInboxDetailed:
                    p2pService.storeInAckCustodyInboxDetailed,
                storeInMediaExpiryBoundedInboxDetailed:
                    p2pService.storeInMediaExpiryBoundedInboxDetailed,
              );
            } catch (error) {
              emitFlowEvent(
                layer: 'FL',
                event: 'DIRECT_TEXT_INBOX_CUSTODY_FAMILY_DRAIN_ERROR',
                details: {'errorType': error.runtimeType.toString()},
              );
            }
            try {
              completed += await drainDirectReactionInboxCustodyOutbox(
                custodyRepository: reactionRepository,
                mutationCustodyRepository: messageRepository,
                storeInAckCustodyInboxDetailed:
                    p2pService.storeInAckCustodyInboxDetailed,
              );
            } catch (error) {
              emitFlowEvent(
                layer: 'FL',
                event: 'DIRECT_REACTION_INBOX_CUSTODY_FAMILY_DRAIN_ERROR',
                details: {'errorType': error.runtimeType.toString()},
              );
            }
            return completed;
          },
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
                await groupExitIntentProcessor.processGroup(groupId);
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
          tryClaimUploadLease: (attachmentIds) =>
              mediaUploadInFlightTracker.tryClaimAll(
                attachmentIds,
                source: MediaUploadTriggerSource.full,
              ),
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
      retryIncompleteGroupUploadsPeriodicFn: () =>
          runAccountRuntimeNetworkAction(
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
      retryIncompleteGroupDownloadsFn: () => runAccountRuntimeNetworkAction(
        operation: 'pending_retrier_group_download_recovery',
        blockedValue: 0,
        action: groupMediaDownloadCoordinator.call,
      ),
      retryIncompleteGroupDownloadsPeriodicFn: () =>
          runAccountRuntimeNetworkAction(
            operation: 'pending_retrier_group_download_recovery_periodic',
            blockedValue: 0,
            action: groupMediaDownloadCoordinator.call,
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
      retryPendingIntroductionDeliveriesFn: () =>
          runAccountRuntimeNetworkAction(
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
      drainDirectInboxCustodyOutboxFn: drainDirectInboxCustodyFamilies,
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
        action: () =>
            recoverStuckSendingMessages(messageRepo: messageRepository),
      ),
      drainDirectMediaBlobCustodyFn: () => runAccountRuntimeNetworkAction(
        operation: 'pending_retrier_direct_media_blob_custody',
        blockedValue: 0,
        action: drainDirectMediaBlobCustody,
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
          tryClaimUploadLease: (attachmentIds) =>
              mediaUploadInFlightTracker.tryClaimAll(
                attachmentIds,
                source: MediaUploadTriggerSource.full,
              ),
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

    final liveServiceStartupSteps = AccountMigrationRuntimeStartupSteps();
    final liveServiceForwardingSubscriptions = <StreamSubscription<dynamic>>[];
    var liveServicesStarted = false;
    Future<void> startLiveServices() async {
      if (liveServicesStarted) {
        return;
      }
      // 234 Session 03: this is the shared cold-start recovery future also
      // kicked after runApp. Await it before even consulting the network gate so
      // bridge/listener/P2P startup can never overtake local terminalization and
      // cleanup. A concurrent caller reuses the same future.
      await liveServiceStartupSteps.runAsync(
        'private_media_cold_recovery',
        () async {
          await ensurePrivateMediaColdRecovery();
        },
      );
      await liveServiceStartupSteps.runAsync(
        'direct_media_blob_local_cleanup',
        cleanupDirectMediaBlobCustodyLocally,
      );
      final groupContextBackfill = keychainMirrorBackfill;
      if (groupContextBackfill != null) {
        await liveServiceStartupSteps.runAsync(
          'group_context_backfill',
          () async {
            await groupContextBackfill;
          },
        );
      }
      await liveServiceStartupSteps.runAsync(
        'group_reaction_comparand_backfill',
        () async {
          await groupReactionComparandBackfill;
        },
      );
      if (liveServicesStarted) {
        return;
      }
      if (!await allowsAccountRuntimeNetworkSideEffects(
        'live_services_start',
      )) {
        return;
      }
      await liveServiceStartupSteps.runAsync('firebase_ready', () async {
        await ensureFirebaseReady();
      });
      await liveServiceStartupSteps.runAsync('bridge_initialize', () async {
        await bridge.initialize();
        StartupTiming.instance.mark('bridge_initialized');
      });
      await liveServiceStartupSteps.runAsync(
        'notification_service_initialize',
        () async {
          await notificationService.initialize();
          StartupTiming.instance.mark('notification_service_ready');
        },
      );

      // Start router first, then listeners, then retriers.
      liveServiceStartupSteps.runSync(
        'message_router_start',
        messageRouter.start,
      );
      liveServiceStartupSteps.runSync(
        'contact_request_listener_start',
        contactRequestListener.start,
      );
      liveServiceStartupSteps.runSync(
        'chat_message_listener_start',
        chatMessageListener.start,
      );
      liveServiceStartupSteps.runSync(
        'post_listener_start',
        postListener.start,
      );
      liveServiceStartupSteps.runSync(
        'post_comment_listener_start',
        postCommentListener.start,
      );
      liveServiceStartupSteps.runSync(
        'post_reaction_listener_start',
        postReactionListener.start,
      );
      liveServiceStartupSteps.runSync(
        'post_presence_listener_start',
        postPresenceListener.start,
      );
      liveServiceStartupSteps.runSync(
        'post_pass_listener_start',
        postPassListener.start,
      );
      liveServiceStartupSteps.runSync(
        'post_pin_listener_start',
        postPinListener.start,
      );
      liveServiceStartupSteps.runSync(
        'reaction_listener_start',
        reactionListener.start,
      );
      liveServiceStartupSteps.runSync(
        'message_deletion_listener_start',
        messageDeletionListener.start,
      );
      liveServiceStartupSteps.runSync(
        'delivery_receipt_listener_start',
        deliveryReceiptListener.start,
      );
      liveServiceStartupSteps.runSync(
        'profile_update_listener_start',
        profileUpdateListener.start,
      );
      liveServiceStartupSteps.runSync('group_message_listener_start', () {
        groupMessageListener.start(
          groupMessageStreamController.stream,
          incomingGroupReactions: groupReactionStreamController.stream,
        );
      });
      liveServiceStartupSteps.runSync(
        'group_invite_listener_start',
        groupInviteListener.start,
      );
      liveServiceStartupSteps.runSync(
        'group_key_update_listener_start',
        groupKeyUpdateListener.start,
      );
      liveServiceStartupSteps.runSync(
        'group_key_repair_responder_listener_start',
        groupKeyRepairResponderListener.start,
      );
      liveServiceStartupSteps.runSync(
        'group_membership_update_listener_start',
        groupMembershipUpdateListener.start,
      );
      liveServiceStartupSteps.runSync(
        'introduction_listener_start',
        introductionListener.start,
      );

      // NOTE: rejoinGroupTopics and drainGroupOfflineInbox are called in
      // StartupRouter._doStartP2P() AFTER node:start completes. They require
      // the Go node to be running (pubsub must be initialized).
      liveServiceStartupSteps.runSync(
        'pending_message_retrier_start',
        pendingMessageRetrier.start,
      );
      liveServiceStartupSteps.runSync(
        'group_pending_key_repair_backoff_timer_start',
        groupPendingKeyRepairBackoffTimer.start,
      );
      liveServiceStartupSteps.runSync(
        'pending_post_media_upload_retrier_start',
        pendingPostMediaUploadRetrier.start,
      );
      liveServiceStartupSteps.runSync(
        'pending_post_delivery_retrier_start',
        pendingPostDeliveryRetrier.start,
      );
      liveServiceStartupSteps.runSync(
        'pending_post_follow_on_retrier_start',
        pendingPostFollowOnRetrier.start,
      );
      liveServiceStartupSteps.runSync(
        'key_exchange_retrier_start',
        keyExchangeRetrier.start,
      );

      // Forward profile avatar updates through chatMessageListener so
      // FeedWired/OrbitWired (which subscribe to contactUpdatedStream) refresh.
      liveServiceStartupSteps.runSync('profile_update_forwarder_install', () {
        liveServiceForwardingSubscriptions.add(
          profileUpdateListener.contactUpdatedStream.listen((contact) {
            chatMessageListener.emitContactUpdate(contact);
          }),
        );
      });

      // Forward ML-KEM key updates from reciprocal contact requests so
      // ConversationWired/FeedWired pick up the new encryption key.
      liveServiceStartupSteps.runSync(
        'contact_key_update_forwarder_install',
        () {
          liveServiceForwardingSubscriptions.add(
            contactRequestListener.contactKeyUpdatedStream.listen((contact) {
              chatMessageListener.emitContactUpdate(contact);
              // FDC-09 §12 / CV-14: a key rotation changed the recipient set —
              // coalesce a single re-mint+register (INV-5).
              wakeTokenReissueCoalescer.trigger();
            }),
          );
        },
      );

      // 171: a one-scan tap-free auto-add — refresh the UI so the new mutual
      // contact appears immediately (same path as a key update; feed/orbit
      // surfaces listening to contact changes render the non-modal update).
      liveServiceStartupSteps.runSync('auto_added_forwarder_install', () {
        liveServiceForwardingSubscriptions.add(
          contactRequestListener.autoAddedStream.listen((contact) {
            chatMessageListener.emitContactUpdate(contact);
            // FDC-09 §12 / CV-14: a new mutual contact — coalesce a single
            // re-issue.
            wakeTokenReissueCoalescer.trigger();
          }),
        );
      });
      StartupTiming.instance.mark('runtime_services_ready');
      liveServicesStarted = true;
    }

    Future<bool> startLiveServicesIfAllowed() async {
      await startLiveServices();
      return liveServicesStarted;
    }

    // 164 (cold-start-1): startLiveServices (Firebase init + bridge + ~25 listener
    // .start() calls) is no longer awaited here on a normal launch. It is wired as
    // the unconditional deferredRuntimeStartup below and kicked off OFF the
    // pre-runApp critical path by MyApp.initState's _ensureRuntimeServicesReady
    // trigger (the same deferred path the share launch already used).

    // ignore: no_leading_underscores_for_local_identifiers
    Future<Widget> _buildRootWidget() async {
      // ── Smoke test Phase 1: pre-populate contacts before UI renders ──
      // This ensures StartupRouter sees contacts and routes to Feed, not FTE.
      await debugE2EComposition?.prepopulateContactsBeforeRunApp(
        isShareLaunch: isShareLaunch,
        contactRepository: contactRepository,
      );
      final debugE2EOverlayBuilder = debugE2EComposition?.overlayBuilder;
      final debugE2EStartP2PNodeOverride = debugE2EComposition
          ?.buildDisposableNodeStart(
            identityRepository: repository,
            secureKeyStore: secureKeyStore,
            bridge: bridge,
            p2pService: p2pService,
          );
      final debugE2EAfterRuntimeReady = debugE2EComposition
          ?.buildReceiverPublication(
            identityRepository: repository,
            p2pService: p2pService,
          );

      final droppedPushRecoveryCoordinator = DroppedPushRecoveryCoordinator(
        gateway: droppedPushRecoveryBridge,
        ensureRuntimeReady: () async {
          // All production entry points route through ApplicationRoot's
          // AccountMigrationRuntimeStartupLatch before reaching this guard.
          if (!liveServicesStarted) {
            throw StateError('runtime services are not ready');
          }
        },
        ensureTransportHealthy: p2pService.performImmediateHealthCheck,
        drainDirectInboxFully: p2pService.drainOfflineInboxFully,
        drainGroupInboxFully: () async {
          final result = await runWithGroupRecoveryGate(() {
            return runAccountRuntimeNetworkAction<GroupOfflineInboxDrainResult>(
              operation: 'dropped_push_group_inbox_recovery',
              blockedValue: const GroupOfflineInboxDrainResult(
                groupCount: 0,
                errorCount: 1,
                hasMorePages: true,
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
                  drainAllPages: true,
                );
              },
            );
          });
          return DroppedPushGroupDrainOutcome(
            isSuccessful: result.isSuccessful,
            hasMorePages: result.hasMorePages,
          );
        },
      );

      return MyApp(
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
        directMediaBlobLocalCleanup: cleanupDirectMediaBlobCustodyLocally,
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
        drainDirectInboxCustodyOutbox: drainDirectInboxCustodyFamilies,
        drainDirectMediaBlobCustody: drainDirectMediaBlobCustody,
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
        debugE2EOverlayBuilder: debugE2EOverlayBuilder,
        debugE2EStartP2PNodeOverride: debugE2EStartP2PNodeOverride,
        debugE2EAfterRuntimeReady: debugE2EAfterRuntimeReady,
        reactionRepository: reactionRepository,
        isDesktop: isDesktop,
        notificationService: notificationService,
        iosNotificationRecoveryCoordinator: iosNotificationRecoveryCoordinator,
        retryDirectNotificationProjection: directNotificationOwner!.retryNow,
        groupNotificationPresentationCoordinator:
            groupNotificationPresentationCoordinator,
        groupNotificationPendingReadAcknowledgementResolver:
            ({
              required groupId,
              required contentKind,
              required eventIdentity,
            }) async =>
                await dbLoadExactGroupNotificationReadAcknowledgement(
                  db,
                  groupId: groupId,
                  contentKind: contentKind.name,
                  eventIdentity: eventIdentity,
                ) !=
                null,
        droppedPushRecoveryCoordinator: droppedPushRecoveryCoordinator,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        conversationTracker: conversationTracker,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupExitDiagnosticRepository: groupExitDiagnosticRepository,
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
          await groupExitIntentProcessor.processGroup(groupId);
        },
        groupHistoryGapRepairRepository: groupHistoryGapRepairRepository,
        groupReactionReplayOutboxRepository:
            groupReactionReplayOutboxRepository,
        groupMessageListener: groupMessageListener,
        groupMediaDownloadCoordinator: groupMediaDownloadCoordinator,
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
        pushRegistrationHealthNotifier: pushRegistrationHealthNotifier,
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
        deferredRuntimeStartup: startLiveServicesIfAllowed,
        ingestStagedPushEnvelopes: ({required String source}) async {
          final result = await ingestStagedPushEnvelopesUseCase(source: source);
          return result.isCanonicalStateComplete;
        },
        firebaseReadiness: firebaseReadiness,
        onAppDetached: () async {
          if (canonicalWritableRuntimeSession != null) {
            await shutdownCanonicalRuntime();
            return;
          }

          // Non-Android platforms retain their prior best-effort teardown.
          try {
            await p2pService.stopNode().timeout(const Duration(seconds: 2));
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[TEARDOWN] stopNode failed/timeout: $e');
            }
          }
          try {
            await db.close().timeout(const Duration(seconds: 2));
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[TEARDOWN] db.close failed/timeout: $e');
            }
          }
        },
      );
    }

    // ignore: no_leading_underscores_for_local_identifiers
    void _afterRunApp() {
      debugE2EComposition?.startIosSenderProjectionAfterRunApp(
        directReactionNotificationProjection:
            directReactionNotificationProjection,
        identityRepository: repository,
        contactRepository: contactRepository,
        database: db,
      );
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
        sweepExpiredGroupInvites(repo: pendingGroupInviteRepository).catchError(
          (Object error, StackTrace stackTrace) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_INVITE_SWEEP_STARTUP_ERROR',
              details: {'error': error.toString()},
            );
            return GroupInviteSweepResult.empty;
          },
        ),
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

      if (debugE2EComposition?.startsIntroPoller ?? false) {
        debugE2EComposition!.startIntroPollerAfterColdRecovery(
          DebugE2EPollerDependencies(
            documentsDirectory: Directory(appDocDir.path),
            navigatorKey: MyApp.navigatorKey,
            p2pService: p2pService,
            bridge: bridge,
            identityRepository: repository,
            contactRepository: contactRepository,
            contactRequestRepository: contactRequestRepository,
            introductionRepository: introductionRepository,
            messageRepository: messageRepository,
            pushEnvelopeStagingStore: pushEnvelopeStagingStore,
            mediaAttachmentRepository: mediaAttachmentRepository,
            mediaFileManager: mediaFileManager,
            audioRecorderService: audioRecorderService,
            database: db,
            secureKeyStore: secureKeyStore,
            wakeTokenStore: wakeTokenStore,
            receivedWakeTokenStore: receivedWakeTokenStore,
            pendingGroupInviteRepository: pendingGroupInviteRepository,
            groupRepository: groupRepository,
            groupMessageRepository: groupMessageRepository,
            reactionRepository: reactionRepository,
            groupMessageListener: groupMessageListener,
            groupInviteDeliveryAttemptRepository:
                groupInviteDeliveryAttemptRepository,
            pendingMessageRetrier: pendingMessageRetrier,
            groupMediaDownloadCoordinator: groupMediaDownloadCoordinator,
            groupConversationTracker: groupConversationTracker,
            conversationTracker: conversationTracker,
            groupMediaDeleteForMeCoordinator: deleteGroupMediaForMeUseCase,
            imageProcessor: imageProcessor,
            appShellController: appShellController,
            groupReactionReplayOutboxRepository:
                groupReactionReplayOutboxRepository,
            groupHistoryGapRepairRepository: groupHistoryGapRepairRepository,
            chatMessageListener: chatMessageListener,
            reactionListener: reactionListener,
            transportMetrics: transportMetrics,
            allowsAccountRuntimeNetworkSideEffects:
                allowsAccountRuntimeNetworkSideEffects,
            wakeTokenResolver: wakeTokenResolver,
          ),
        );
      }
    }

    return _CallbackPreparedApplication(
      buildRootWidget: _buildRootWidget,
      afterRunApp: _afterRunApp,
    );
  }
}

final class _CallbackPreparedApplication implements PreparedApplication {
  const _CallbackPreparedApplication({
    required Future<Widget> Function() buildRootWidget,
    required void Function() afterRunApp,
  }) : _buildRootWidget = buildRootWidget,
       _afterRunApp = afterRunApp;

  final Future<Widget> Function() _buildRootWidget;
  final void Function() _afterRunApp;

  @override
  Future<Widget> buildRootWidget() => _buildRootWidget();

  @override
  void afterRunApp() => _afterRunApp();
}

Future<Widget> _buildInertRootWidget() async => const SizedBox.shrink();

void _noopAfterRunApp() {}
