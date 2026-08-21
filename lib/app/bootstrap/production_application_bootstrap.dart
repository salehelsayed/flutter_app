import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/application/protected_group_content_runtime_quiescence.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_app/core/notifications/group_notification_reconciliation_signal.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_drainer.dart';
import 'package:flutter_app/core/notifications/ios_mailbox_alert_silent_replay_context.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/app/bootstrap/role_aware_deferred_runtime_start.dart';
import 'package:flutter_app/app/bootstrap/production_canonical_direct_replay_composition.dart';
import 'package:flutter_app/app/bootstrap/production_canonical_direct_projection_composition.dart';
import 'package:flutter_app/app/bootstrap/production_canonical_group_replay_composition.dart';
import 'package:flutter_app/features/contacts/application/direct_contact_device_trust.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_import_precondition.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart'
    show
        AccountMigrationReceiverStartResult,
        AccountMigrationReceiverStartFailureCode;
import 'package:flutter_app/debug/debug_e2e_composition_root.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
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
import 'package:flutter_app/core/database/helpers/linked_group_bootstrap_db_helpers.dart';
import 'package:flutter_app/features/groups/application/manage_pending_sibling_device.dart';
import 'package:flutter_app/core/secure_storage/ml_kem_secret_ring.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_reaction_target_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_distributions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_membership_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
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
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/core/secure_storage/legacy_group_secret_storage_scrub.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
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
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/app/bootstrap/direct_blob_free_linked_services.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/prepared_group_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_authoring_resolver.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/presentation/screens/linked_group_conversation_wired.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart'
    show dbReadDirectContactFanoutSnapshot;
import 'package:flutter_app/features/contacts/domain/repositories/direct_contact_conversation_purge.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_blob_free_linked_event_fanout_use_case.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_projection_owner.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/application/direct_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_media_blob_custody_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/private_media_expiry_scheduler.dart';
import 'package:flutter_app/features/conversation/application/delivery_receipt_listener.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart'
    show sendDeliveryReceipt;
import 'package:flutter_app/features/conversation/application/link_incoming_local_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/message_deletion_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_direct_private_committed_pending_cleanup.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart';
import 'package:flutter_app/features/conversation/application/verify_inbox_custody_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/groups/application/recover_stuck_sending_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_envelope.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_reconciliation.dart';
import 'package:flutter_app/features/groups/application/linked_group_status_refresh.dart';
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
import 'package:flutter_app/features/groups/application/strict_group_media_blob_download_ack_owner.dart';
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
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
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
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
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
import 'package:flutter_app/core/notifications/android_opaque_wake_readiness.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/ios_notification_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/ios_notification_recovery_coordinator.dart';
import 'package:flutter_app/core/notifications/ios_nse_inbox_projection.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_coordinator.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
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

/// Production's exact restart path for a persisted deferred-key PREPARED fact.
///
/// Kept as one testable seam because a deferred distribution may be reopened at
/// the same key epoch after a sibling-device admission. The caller must address
/// that new operation with a fresh transition ID; once addressed, this helper
/// accepts only the proof-bound ACL and its exact surviving immutable rows.
@visibleForTesting
Future<ProtectedGroupAuthorityPreparation?>
resumeProductionPreparedProtectedGroupKeyAuthority({
  required AuthenticatedGroupAuthorityProof persistedProof,
  required ProtectedGroupAuthorityPrepareRequest request,
  required int keyEpoch,
  required GroupPendingBroadcastRepository pendingRepository,
}) async {
  if (!request.resumePreparedSurvivors ||
      request.control != ProtectedGroupAuthorityControl.groupKeyUpdate ||
      persistedProof.groupId != request.groupId ||
      persistedProof.eventId != request.transitionId) {
    return null;
  }
  if (!protectedGroupAuthorityProofMatchesPrepareRequest(
    proof: persistedProof,
    request: request,
    keyEpoch: keyEpoch,
  )) {
    return null;
  }
  final rawAcl = persistedProof.authorityData['recipientTransportPeerIds'];
  if (rawAcl is! List || rawAcl.any((recipient) => recipient is! String)) {
    return null;
  }
  final acl = rawAcl.cast<String>().toSet();
  if (acl.length != rawAcl.length) return null;
  final seen = <String>{};
  final survivors = <GroupPendingBroadcast>[];
  final pending = await pendingRepository.forGroup(request.groupId);
  for (final row in pending) {
    if (row.kind != groupPendingBroadcastKindProtectedAuthority) continue;
    final identity = parseProtectedGroupAuthorityDeliveryId(
      row.sourceMessageId ?? '',
    );
    if (identity == null) return null;
    if (identity.transitionId != request.transitionId) continue;
    if (identity.control != request.control ||
        row.recipientPeerIds.length != 1) {
      return null;
    }
    final recipient = row.recipientPeerIds.single;
    if (identity.recipientTransportPeerId != recipient ||
        !acl.contains(recipient) ||
        !seen.add(recipient)) {
      return null;
    }
    survivors.add(row);
  }
  survivors.sort(
    (left, right) =>
        left.recipientPeerIds.single.compareTo(right.recipientPeerIds.single),
  );
  return ProtectedGroupAuthorityPreparation(
    groupId: request.groupId,
    rows: survivors,
    authorityProof: persistedProof,
    control: request.control,
    replayData: Map<String, dynamic>.from(request.replayData),
  );
}

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
    final linkedInstallationAuthority = LinkedInstallationAuthority(
      secureKeyStore: secureKeyStore,
    );
    final SecureKeyStore? sharedPushKeyStore =
        !kIsWeb && Platform.isIOS && !isGroupMediaIosDisposableProfile
        ? FlutterSecureKeyStore(appleAccessGroup: mknoonSharedAppleAccessGroup)
        : null;
    final droppedPushRecoveryBridge = DroppedPushRecoveryBridge();
    final isMobileNotificationRuntime =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final durableNotificationIdRegistry = isMobileNotificationRuntime
        ? await DurableConversationNotificationIdRegistry.openDefault(
            useIosAppGroup: Platform.isIOS,
          )
        : null;
    final localNotificationLedgerStore = durableNotificationIdRegistry == null
        ? null
        : LocalNotificationLedgerStore(
            directory: durableNotificationIdRegistry.directory,
          );
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
    final canonicalRuntimeBindingCoordinator = !isMobileNotificationRuntime
        ? null
        : CanonicalRuntimeBindingCoordinator(
            secureKeyStore: secureKeyStore,
            recoveryGraphRegistered: true,
            leaseGateway: canonicalRuntimeLeaseGateway,
            droppedPushBindingPublisher: Platform.isAndroid
                ? droppedPushRecoveryBridge
                : null,
            rebindPendingNotificationOverlay:
                pendingNotificationOverlayBindingPublisher?.rebind,
            publishSharedBinding: sharedPushKeyStore == null
                ? null
                : (binding) => publishCanonicalRuntimeSharedBinding(
                    sharedKeyStore: sharedPushKeyStore,
                    opaqueBinding: binding,
                  ),
            suspendLocalNotificationLedgerClaims:
                localNotificationLedgerStore == null
                ? null
                : (binding) async {
                    if (binding == null) return;
                    var suspended = await localNotificationLedgerStore
                        .suspendClaims(currentOpaqueBinding: binding);
                    if (suspended == null) {
                      final initialized = await localNotificationLedgerStore
                          .initializeOrRebind(currentOpaqueBinding: binding);
                      if (initialized != null) {
                        suspended = await localNotificationLedgerStore
                            .suspendClaims(currentOpaqueBinding: binding);
                      }
                    }
                    if (suspended == null || !suspended.claimsSuspended) {
                      throw StateError(
                        'local notification ledger claim suspension failed',
                      );
                    }
                  },
            rebindLocalNotificationLedger: localNotificationLedgerStore == null
                ? null
                : (binding) async {
                    if (binding == null) return;
                    final rebound = await localNotificationLedgerStore
                        .initializeOrRebind(currentOpaqueBinding: binding);
                    if (rebound == null || rebound.claimsSuspended) {
                      throw StateError(
                        'local notification ledger binding publication failed',
                      );
                    }
                  },
          );
    final canonicalRuntimeStartupBinding =
        await canonicalRuntimeBindingCoordinator?.loadStartupBinding();
    final directReactionNotificationProjection = sharedPushKeyStore == null
        ? null
        : DirectReactionNotificationProjection(store: sharedPushKeyStore);
    final groupReactionNotificationProjection = sharedPushKeyStore == null
        ? null
        : GroupReactionNotificationProjection(store: sharedPushKeyStore);
    final iosNseInboxTransportProjection = sharedPushKeyStore == null
        ? null
        : IosNseInboxTransportProjection(store: sharedPushKeyStore);
    final iosNseTransportAdmissionActive =
        iosNseInboxTransportProjection != null &&
        kWakeOutcomeCoordinatorAdmissionEnabled &&
        !kIsWeb &&
        Platform.isIOS;
    if (iosNseInboxTransportProjection != null &&
        !kWakeOutcomeCoordinatorAdmissionEnabled) {
      // Rollback/default-off cleanup is outside the linked registration hook:
      // that hook itself remains zero-work while admission is disabled, while
      // stale private transport bytes cannot survive a downgraded launch.
      await iosNseInboxTransportProjection.retireAndReadBack();
    }
    void Function()? notifyContactPushEligibilityChanged;
    Future<void> Function(IdentityModel identity)?
    refreshIosNseTransportAfterIdentityCommit;
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
    await repairDirectNotificationDurabilityDeleteTriggers(db);
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
    // A crash between the native authority fence and its secure-storage write
    // deliberately leaves recovery disabled.  Only this supported production
    // graph may retire those stale mutation tokens, and it does so after the
    // foreground process owns the writable lease and the existing database has
    // completed every post-open migration.  Any work scheduled by the
    // reconciliation therefore still loses admission to this foreground owner.
    await canonicalRuntimeBindingCoordinator
        ?.reconcileCurrentAccountRecoveryReadiness();
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
      retireIosNseInboxTransport: iosNseTransportAdmissionActive
          ? iosNseInboxTransportProjection.retireAndReadBack
          : null,
      refreshIosNseInboxTransport: iosNseTransportAdmissionActive
          ? (identity) async {
              final refresh = refreshIosNseTransportAfterIdentityCommit;
              if (refresh != null) await refresh(identity);
            }
          : null,
    );
    Future<void> Function()? notificationCompletedOutcomeDrainKick;
    void kickNotificationCompletedOutcomeDrain() {
      final drain = notificationCompletedOutcomeDrainKick;
      if (drain == null) return;
      unawaited(
        drain().catchError((Object error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'NOTIFICATION_COMPLETED_OUTCOME_POST_COMMIT_KICK_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
        }),
      );
    }

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

    // 361: the ONE shared physical->logical reverse transport authority.
    final directTransportAuthority = DatabaseDirectTransportAuthority(
      database: db,
    );

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
      // 361: the exact final serialized contact-conversation purge owner.
      dbPurgeDirectContactConversationAndContact: (peerId) async {
        final result = await dbPurgeDirectContactConversationAndContact(
          db,
          peerId,
        );
        return DirectContactConversationPurgeSummary(
          deletedTextCustodyRows: result.deletedTextCustodyRows,
          deletedEventCustodyRows: result.deletedEventCustodyRows,
          deletedReactions: result.deletedReactions,
          deletedMessages: result.deletedMessages,
          deletedContact: result.deletedContact,
        );
      },
      directReactionProjection: directReactionNotificationProjection,
      loadDirectNotificationAuthorizedTransports: (peerId) =>
          loadDirectNotificationAuthorizedTransportPeerIds(db, peerId),
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
                outcome,
              }) async {
                final completed =
                    await dbCompleteDirectNotificationDisplayOutboxEntryIfExact(
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
                      outcome: outcome,
                    );
                if (completed && outcome != null) {
                  kickNotificationCompletedOutcomeDrain();
                }
                return completed;
              },
          dbRetireAfterDurableSettlementIfExact:
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
              }) =>
                  dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact(
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
      // 361: v113 blob-free fanout + linked-transport authority delegates.
      dbReadDirectContactFanoutSnapshot: ({required contactAccountPeerId}) =>
          dbReadDirectContactFanoutSnapshot(
            db,
            contactAccountPeerId: contactAccountPeerId,
          ),
      dbLoadDirectInboxCustodyOutboxRowsForMessageId: ({required messageId}) =>
          dbLoadDirectInboxCustodyOutboxRowsForMessageId(
            db,
            messageId: messageId,
          ),
      dbLoadDirectReactionInboxCustodyOutboxRowsForEventId:
          ({required eventId}) =>
              dbLoadDirectReactionInboxCustodyOutboxRowsForEventId(
                db,
                eventId: eventId,
              ),
      dbStageOutgoingDirectTextFanoutInboxCustody:
          ({
            required stagedRow,
            required messageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) => dbStageOutgoingDirectTextFanoutInboxCustody(
            db,
            stagedRow: stagedRow,
            messageId: messageId,
            contactAccountPeerId: contactAccountPeerId,
            senderTransportPeerId: senderTransportPeerId,
            expectedSnapshot: expectedSnapshot,
            candidates: candidates,
          ),
      dbStageOutgoingDirectTextMutationFanoutInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required eventId,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) => dbStageOutgoingDirectTextMutationFanoutInboxCustody(
            db,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            eventId: eventId,
            parentMessageId: parentMessageId,
            contactAccountPeerId: contactAccountPeerId,
            senderTransportPeerId: senderTransportPeerId,
            expectedSnapshot: expectedSnapshot,
            candidates: candidates,
          ),
      dbApplyIncomingOrdinaryTextMutationWithAuthority:
          ({
            required incomingRow,
            required kind,
            required authenticatedTransportPeerId,
          }) => dbApplyIncomingOrdinaryTextMutation(
            db,
            incomingRow: incomingRow,
            kind: kind,
            authenticatedTransportPeerId: authenticatedTransportPeerId,
          ),
      dbApplyIncomingDirectMessageDeletionWithAuthority:
          ({
            required messageId,
            required senderPeerId,
            required deletedAt,
            required transport,
            required createdAt,
            required authenticatedTransportPeerId,
          }) => dbApplyIncomingDirectMessageDeletion(
            db,
            messageId: messageId,
            senderPeerId: senderPeerId,
            deletedAt: deletedAt,
            transport: transport,
            createdAt: createdAt,
            authenticatedTransportPeerId: authenticatedTransportPeerId,
          ),
      dbSettleOutgoingOrdinaryTransportWithFanoutAuthority:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required status,
            required transport,
            required relayExpiresAt,
            required mode,
            required isDeleteTombstone,
            expectedDirectEventFanoutGenerationId,
            authenticatedTransportPeerId,
          }) => isDeleteTombstone
          ? dbSettleOutgoingOrdinaryDeleteTombstone(
              db,
              messageId: messageId,
              expectedContactPeerId: expectedContactPeerId,
              expectedEnvelope: expectedEnvelope,
              status: status,
              transport: transport,
              relayExpiresAt: relayExpiresAt,
              mode: mode,
              expectedDirectEventFanoutGenerationId:
                  expectedDirectEventFanoutGenerationId,
              authenticatedTransportPeerId: authenticatedTransportPeerId,
            )
          : dbSettleOutgoingOrdinaryTransport(
              db,
              messageId: messageId,
              expectedContactPeerId: expectedContactPeerId,
              expectedEnvelope: expectedEnvelope,
              status: status,
              transport: transport,
              relayExpiresAt: relayExpiresAt,
              mode: mode,
              expectedDirectEventFanoutGenerationId:
                  expectedDirectEventFanoutGenerationId,
              authenticatedTransportPeerId: authenticatedTransportPeerId,
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
      dbApplyIncomingDirectMessageDeletion:
          ({
            required messageId,
            required senderPeerId,
            required deletedAt,
            required transport,
            required createdAt,
          }) => dbApplyIncomingDirectMessageDeletion(
            db,
            messageId: messageId,
            senderPeerId: senderPeerId,
            deletedAt: deletedAt,
            transport: transport,
            createdAt: createdAt,
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
      dbCommitOutgoingDirectPrivateWireEnvelopeWithInboxCustody:
          (
            completionRow, {
            required expectedPendingLocalPath,
            required envelope,
            required hasOwnedPendingCompletion,
            required wireMediaBlobManifestHash,
            required wireMediaBlobExpiresAtMs,
          }) => dbCommitOutgoingDirectPrivateWireEnvelopeWithInboxCustody(
            db,
            completionRow,
            expectedPendingLocalPath: expectedPendingLocalPath,
            envelope: envelope,
            hasOwnedPendingCompletion: hasOwnedPendingCompletion,
            wireMediaBlobManifestHash: wireMediaBlobManifestHash,
            wireMediaBlobExpiresAtMs: wireMediaBlobExpiresAtMs,
          ),
      dbCommitOutgoingDirectPrivateWireEnvelopeFanoutWithInboxCustody:
          (
            completionRow, {
            required expectedPendingLocalPath,
            required hasOwnedPendingCompletion,
            required senderTransportPeerId,
            required contactAccountPeerId,
            required authority,
            required expectedSnapshot,
            required targetBindings,
          }) => dbCommitOutgoingDirectPrivateWireEnvelopeFanoutWithInboxCustody(
            db,
            completionRow,
            expectedPendingLocalPath: expectedPendingLocalPath,
            hasOwnedPendingCompletion: hasOwnedPendingCompletion,
            senderTransportPeerId: senderTransportPeerId,
            contactAccountPeerId: contactAccountPeerId,
            authority: authority,
            expectedSnapshot: expectedSnapshot,
            targetBindings: targetBindings,
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
      dbStageOutgoingDirectPrivateDeletionInboxCustody:
          ({
            required expectedRow,
            required tombstoneRow,
            required recipientPeerId,
            required eventId,
            required wireEnvelope,
          }) => dbStageOutgoingDirectPrivateDeletionInboxCustody(
            db,
            expectedRow: expectedRow,
            tombstoneRow: tombstoneRow,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            wireEnvelope: wireEnvelope,
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
      dbMarkInboxStagingEntryPrerequisiteWaiting:
          (entryId, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryPrerequisiteWaiting(
                db,
                entryId,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbMarkInboxStagingEntryProtectedAckPending: (entryId) =>
          dbMarkInboxStagingEntryProtectedAckPending(db, entryId),
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
      dbClassifyOutgoingDirectDeletionLane: ({required messageId}) =>
          dbClassifyOutgoingDirectDeletionLane(db, messageId: messageId),
      dbStageOutgoingDirectMediaDeletionInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required recipientPeerId,
            required eventId,
            required wireEnvelope,
            required updatedAt,
          }) => dbStageOutgoingDirectMediaDeletionInboxCustody(
            db,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            wireEnvelope: wireEnvelope,
            updatedAt: updatedAt,
          ),
      dbLoadOutgoingDirectMediaCaptionEditProjection: ({required messageId}) =>
          dbLoadOutgoingDirectMediaCaptionEditProjection(
            db,
            messageId: messageId,
          ),
      dbStageOutgoingDirectMediaCaptionEditInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required recipientPeerId,
            required eventId,
            required wireEnvelope,
            required expectedAttachmentRows,
          }) => dbStageOutgoingDirectMediaCaptionEditInboxCustody(
            db,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            recipientPeerId: recipientPeerId,
            eventId: eventId,
            wireEnvelope: wireEnvelope,
            expectedAttachmentRows: expectedAttachmentRows,
          ),
      dbApplyIncomingDirectMediaCaptionEdit:
          ({
            required expectedParentIdentity,
            required expectedAttachmentRows,
            required text,
            required editedAt,
          }) => dbApplyIncomingDirectMediaCaptionEdit(
            db,
            expectedParentIdentity: expectedParentIdentity,
            expectedAttachmentRows: expectedAttachmentRows,
            text: text,
            editedAt: editedAt,
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
      dbStageOutgoingDirectPrivateMediaBlobGeneration:
          ({
            required expectedParentRow,
            required expectedAttachmentRow,
            required preparedAttachmentRow,
            required custodyRow,
          }) => dbStageOutgoingDirectPrivateMediaBlobGeneration(
            db,
            expectedParentRow: expectedParentRow,
            expectedAttachmentRow: expectedAttachmentRow,
            preparedAttachmentRow: preparedAttachmentRow,
            custodyRow: custodyRow,
          ),
      dbStageOutgoingDirectPrivateMediaBlobFanoutGeneration:
          ({
            required expectedParentRow,
            required expectedAttachmentRow,
            required preparedAttachmentRow,
            required custodyRows,
            required contactAccountPeerId,
            required expectedSnapshot,
          }) => dbStageOutgoingDirectPrivateMediaBlobFanoutGeneration(
            db,
            expectedParentRow: expectedParentRow,
            expectedAttachmentRow: expectedAttachmentRow,
            preparedAttachmentRow: preparedAttachmentRow,
            custodyRows: custodyRows,
            contactAccountPeerId: contactAccountPeerId,
            expectedSnapshot: expectedSnapshot,
          ),
      dbReadDirectContactFanoutSnapshotForMedia:
          ({required contactAccountPeerId}) =>
              dbReadDirectContactFanoutSnapshot(
                db,
                contactAccountPeerId: contactAccountPeerId,
              ),
      dbStageOutgoingDirectLinkedMediaBlobFanoutGeneration:
          ({
            required expectedParentRow,
            required expectedAttachmentRows,
            required preparedAttachmentRows,
            required custodyRows,
            required contactAccountPeerId,
            required expectedSnapshot,
            allowFreshParent = false,
            authorizedForwardDedupKey,
          }) => dbStageOutgoingDirectLinkedMediaBlobFanoutGeneration(
            db,
            expectedParentRow: expectedParentRow,
            expectedAttachmentRows: expectedAttachmentRows,
            preparedAttachmentRows: preparedAttachmentRows,
            custodyRows: custodyRows,
            contactAccountPeerId: contactAccountPeerId,
            expectedSnapshot: expectedSnapshot,
            allowFreshParent: allowFreshParent,
            authorizedForwardDedupKey: authorizedForwardDedupKey,
          ),
      dbStageOutgoingDirectMediaFanoutInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required attachmentRows,
            required senderTransportPeerId,
            required contactAccountPeerId,
            required authority,
            required expectedSnapshot,
            required targetBindings,
          }) => dbStageOutgoingDirectMediaFanoutInboxCustody(
            db,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            attachmentRows: attachmentRows,
            senderTransportPeerId: senderTransportPeerId,
            contactAccountPeerId: contactAccountPeerId,
            authority: authority,
            expectedSnapshot: expectedSnapshot,
            targetBindings: targetBindings,
          ),
      dbLoadDirectMediaBlobCustodyRowsForAttachment:
          ({required attachmentId}) =>
              dbLoadDirectMediaBlobCustodyRowsForAttachment(
                db,
                attachmentId: attachmentId,
              ),
      dbLoadDirectMediaBlobCustodyForTarget:
          ({required attachmentId, required direction, recipientPeerId}) =>
              dbLoadDirectMediaBlobCustodyForTarget(
                db,
                attachmentId: attachmentId,
                direction: direction,
                recipientPeerId: recipientPeerId,
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
      dbLoadLinkedDirectMediaBlobCustodyByStates:
          ({required states, int limit = 50}) =>
              dbLoadLinkedDirectMediaBlobCustodyByStates(
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
      dbStageFreshOutgoingGroupMediaBlobGeneration:
          ({
            required parentRow,
            required attachmentRows,
            required custodyRows,
            required custodyBlobIdsByAttachmentId,
          }) => dbStageFreshOutgoingGroupMediaBlobGeneration(
            db,
            parentRow: parentRow,
            attachmentRows: attachmentRows,
            custodyRows: custodyRows,
            custodyBlobIdsByAttachmentId: custodyBlobIdsByAttachmentId,
          ),
      dbLoadGroupMediaBlobCustodyForMessage:
          ({required groupId, required messageId}) =>
              dbLoadGroupMediaBlobCustodyForMessage(
                db,
                groupId: groupId,
                messageId: messageId,
              ),
      dbLoadGroupMediaBlobCustodyByStates:
          ({required states, int limit = 50}) =>
              dbLoadGroupMediaBlobCustodyByStates(
                db,
                states: states,
                limit: limit,
              ),
      dbLoadGroupMediaBlobArtifactRelativePaths: () =>
          dbLoadGroupMediaBlobArtifactRelativePaths(db),
      dbLoadGroupMediaBlobCustodyForTarget:
          ({
            required groupId,
            required attachmentId,
            required custodyBlobId,
            required direction,
            recipientPeerId,
          }) => dbLoadGroupMediaBlobCustodyForTarget(
            db,
            groupId: groupId,
            attachmentId: attachmentId,
            custodyBlobId: custodyBlobId,
            direction: direction,
            recipientPeerId: recipientPeerId,
          ),
      dbTransitionGroupMediaBlobCustodyIfExact:
          ({required expected, required next}) =>
              dbTransitionGroupMediaBlobCustodyIfExact(
                db,
                expected: expected,
                next: next,
              ),
      dbDeleteGroupMediaBlobCleanupPendingIfExact: ({required expected}) =>
          dbDeleteGroupMediaBlobCleanupPendingIfExact(db, expected: expected),
      dbCommitIncomingGroupMediaBlobLocalPath:
          ({
            required expectedAttachmentRow,
            required expectedCustody,
            required localPath,
            required sourceRelayPeerId,
            required updatedAt,
            required nowMs,
          }) => dbCommitIncomingGroupMediaBlobLocalPath(
            db,
            expectedAttachmentRow: expectedAttachmentRow,
            expectedCustody: expectedCustody,
            localPath: localPath,
            sourceRelayPeerId: sourceRelayPeerId,
            updatedAt: updatedAt,
            nowMs: nowMs,
          ),
      dbTerminalizeIncomingGroupMediaBlobForLocalDeletion:
          ({
            required expectedAttachmentRow,
            required expectedCustody,
            required sourceRelayPeerId,
            required updatedAt,
          }) => dbTerminalizeIncomingGroupMediaBlobForLocalDeletion(
            db,
            expectedAttachmentRow: expectedAttachmentRow,
            expectedCustody: expectedCustody,
            sourceRelayPeerId: sourceRelayPeerId,
            updatedAt: updatedAt,
          ),
      dbDeleteIncomingGroupMediaBlobAckPendingIfExact: ({required expected}) =>
          dbDeleteIncomingGroupMediaBlobAckPendingIfExact(
            db,
            expected: expected,
          ),
      dbDeleteIncomingGroupMediaBlobIfExpired:
          ({required expected, required nowMs}) =>
              dbDeleteIncomingGroupMediaBlobIfExpired(
                db,
                expected: expected,
                nowMs: nowMs,
              ),
      dbCountOtherGroupMediaBlobCustodyRowsReferencingArtifact:
          ({
            required ciphertextRelativePath,
            required contentHash,
            required ciphertextSize,
            required excluding,
          }) => dbCountOtherGroupMediaBlobCustodyRowsReferencingArtifact(
            db,
            ciphertextRelativePath: ciphertextRelativePath,
            contentHash: contentHash,
            ciphertextSize: ciphertextSize,
            excluding: excluding,
          ),
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
            authenticatedTransportPeerId,
          }) => dbStageIncomingDirectMediaBlobCustody(
            db,
            messageRow: messageRow,
            attachmentRows: attachmentRows,
            custodyRows: custodyRows,
            authenticatedTransportPeerId: authenticatedTransportPeerId,
          ),
      dbStageIncomingDirectPrivateMediaBlobCustody:
          ({
            required messageRow,
            required attachmentRow,
            required custodyRow,
            authenticatedTransportPeerId,
          }) => dbStageIncomingDirectPrivateMediaBlobCustody(
            db,
            messageRow: messageRow,
            attachmentRow: attachmentRow,
            custodyRow: custodyRow,
            authenticatedTransportPeerId: authenticatedTransportPeerId,
          ),
      dbCommitIncomingDirectMediaBlobLocalPath:
          ({
            required expectedAttachmentRow,
            required expectedCustody,
            required localPath,
            required sourceRelayPeerId,
            required updatedAt,
            required nowMs,
          }) => dbCommitIncomingDirectMediaBlobLocalPath(
            db,
            expectedAttachmentRow: expectedAttachmentRow,
            expectedCustody: expectedCustody,
            localPath: localPath,
            sourceRelayPeerId: sourceRelayPeerId,
            updatedAt: updatedAt,
            // 358: forwarded unchanged so the strict owner's sampled clock —
            // never this delegate — decides the disappearing deadline.
            nowMs: nowMs,
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
    // Constructed later in this bootstrap method. Delete-for-me only invokes
    // its strict network callback after the app runtime has initialized it.
    late final Bridge bridge;
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
      terminalizeStrictCustody:
          ({required String groupId, required String messageId}) =>
              StrictGroupMediaBlobDownloadAckOwner(
                bridge: bridge,
                mediaAttachmentRepository: mediaAttachmentRepository,
                mediaFileManager: MediaFileManager(),
              ).terminalizeLocallyDeletedMessage(
                groupId: groupId,
                messageId: messageId,
              ),
    );
    // Process-wide default (229 decider pattern): every group-conversation
    // entry path (orbit, feed, list, picker, notification route) gets the real
    // coordinator; explicit injection still wins.
    defaultGroupMediaDeleteForMeCoordinator = deleteGroupMediaForMeUseCase;

    // Create reaction repository
    final reactionRepository = ReactionRepositoryImpl(
      dbInsertReaction: (row) => dbInsertReaction(db, row),
      // 361: linked-transport reaction applies (in-transaction reauth) and
      // the v113 blob-free reaction fanout stage.
      dbApplyIncomingAddWithAuthority:
          (row, {required authenticatedTransportPeerId}) async {
            final result = await dbApplyIncomingReactionMutation(
              db,
              row,
              mutation: DbIncomingReactionMutation.add,
              authenticatedTransportPeerId: authenticatedTransportPeerId,
            );
            return switch (result) {
              DbIncomingReactionApplyResult.inserted =>
                ReactionAddApplyResult.inserted,
              DbIncomingReactionApplyResult.updated =>
                ReactionAddApplyResult.updated,
              DbIncomingReactionApplyResult.exactReplay =>
                ReactionAddApplyResult.exactReplay,
              DbIncomingReactionApplyResult.stale =>
                ReactionAddApplyResult.stale,
              DbIncomingReactionApplyResult.removed => throw StateError(
                'ADD transaction returned REMOVE result',
              ),
            };
          },
      dbApplyIncomingRemoveWithAuthority:
          (row, {required authenticatedTransportPeerId}) async {
            final result = await dbApplyIncomingReactionMutation(
              db,
              row,
              mutation: DbIncomingReactionMutation.remove,
              authenticatedTransportPeerId: authenticatedTransportPeerId,
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
      dbStageOutgoingDirectReactionFanoutInboxCustody:
          ({
            required reactionRow,
            required action,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) => dbStageOutgoingDirectReactionFanoutInboxCustody(
            db,
            reactionRow: reactionRow,
            action: action,
            parentMessageId: parentMessageId,
            contactAccountPeerId: contactAccountPeerId,
            senderTransportPeerId: senderTransportPeerId,
            expectedSnapshot: expectedSnapshot,
            candidates: candidates,
          ),
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
          dbLoadRetryableGroupReactionReplayOutboxEntries:
              ({limit = 20, strictContentOnly = false, offset = 0}) =>
                  dbLoadRetryableGroupReactionReplayOutboxEntries(
                    db,
                    limit: limit,
                    strictContentOnly: strictContentOnly,
                    offset: offset,
                  ),
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
          dbReplaceGroupReactionReplayOutboxPayloadIfExact:
              ({required expected, required replacement, required updatedAt}) =>
                  dbReplaceGroupReactionReplayOutboxPayloadIfExact(
                    db,
                    expected: expected,
                    replacement: replacement,
                    updatedAt: updatedAt,
                  ),
          dbCompleteGroupReactionContentIfExact:
              ({
                required expected,
                required reactionRow,
                required action,
                required transitionId,
                required sourcePeerId,
                required sourceEventId,
                required sourceTimestamp,
                required eventPayload,
                required updatedAt,
              }) => dbCompleteGroupReactionContentIfExact(
                db,
                expected: expected,
                reactionRow: reactionRow,
                action: action,
                transitionId: transitionId,
                sourcePeerId: sourcePeerId,
                sourceEventId: sourceEventId,
                sourceTimestamp: sourceTimestamp,
                eventPayload: eventPayload,
                updatedAt: updatedAt,
              ),
          dbStageAndCompleteLocalGroupReactionContentFn:
              ({
                required expected,
                required reactionRow,
                required action,
                required transitionId,
                required sourcePeerId,
                required sourceEventId,
                required sourceTimestamp,
                required eventPayload,
              }) => dbStageAndCompleteLocalGroupReactionContent(
                db,
                expected: expected,
                reactionRow: reactionRow,
                action: action,
                transitionId: transitionId,
                sourcePeerId: sourcePeerId,
                sourceEventId: sourceEventId,
                sourceTimestamp: sourceTimestamp,
                eventPayload: eventPayload,
              ),
          dbStagePreparedLocalGroupReactionContentFn:
              ({
                required expected,
                required sourcePeerId,
                required sourceEventId,
                required sourceTimestamp,
                required preparedEventPayload,
              }) => dbStagePreparedLocalGroupReactionContent(
                db,
                expected: expected,
                sourcePeerId: sourcePeerId,
                sourceEventId: sourceEventId,
                sourceTimestamp: sourceTimestamp,
                preparedEventPayload: preparedEventPayload,
              ),
          dbTerminalizePreparedLocalGroupReactionIfExactFn:
              ({
                required expected,
                required preparedEventPayload,
                required terminalSourcePeerId,
                required terminalSourceEventId,
                required terminalSourceTimestamp,
                required terminalEventPayload,
              }) => dbTerminalizePreparedLocalGroupReactionIfExact(
                db,
                expected: expected,
                preparedEventPayload: preparedEventPayload,
                terminalSourcePeerId: terminalSourcePeerId,
                terminalSourceEventId: terminalSourceEventId,
                terminalSourceTimestamp: terminalSourceTimestamp,
                terminalEventPayload: terminalEventPayload,
              ),
          dbHasExactPreparedLocalGroupReactionFn:
              ({required expected, required eventPayload}) =>
                  dbHasExactPreparedLocalGroupReaction(
                    db,
                    expected: expected,
                    eventPayload: eventPayload,
                  ),
          dbDeleteGroupReactionReplayOutboxEntry: (reactionId) =>
              dbDeleteGroupReactionReplayOutboxEntry(db, reactionId),
        );
    final groupNotificationDisplayOutboxRepository =
        GroupNotificationDisplayOutboxRepositoryImpl(
          dbStage: (row) => dbStageGroupNotificationDisplayOutboxEntry(db, row),
          dbLoadByEventId: (eventId) =>
              dbLoadGroupNotificationDisplayOutboxEntry(db, eventId),
          dbBindDurableCorrelationIfExact:
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
                required durableEventCorrelation,
                required updatedAt,
              }) =>
                  dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
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
                    durableEventCorrelation: durableEventCorrelation,
                    updatedAt: updatedAt,
                  ),
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
                required completedAt,
                outcome,
              }) async {
                final completed =
                    await dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
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
                      completedAt: completedAt,
                      outcome: outcome,
                    );
                if (completed && outcome != null) {
                  kickNotificationCompletedOutcomeDrain();
                }
                return completed;
              },
          dbCompleteOrVerifyIfExact:
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
                required completedAt,
                outcome,
                durableEventCorrelation,
              }) async {
                final handoff =
                    await dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
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
                      completedAt: completedAt,
                      outcome: outcome,
                      durableEventCorrelation: durableEventCorrelation,
                    );
                if (handoff !=
                        DurableLocalNotificationSqlHandoffResult
                            .retryableMismatch &&
                    outcome != null) {
                  kickNotificationCompletedOutcomeDrain();
                }
                return handoff;
              },
          dbRetireAfterDurableSettlementIfExact:
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
                durableEventCorrelation,
              }) =>
                  dbRetireGroupNotificationDisplayOutboxAfterDurableSettlementIfExact(
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
                    durableEventCorrelation: durableEventCorrelation,
                  ),
          dbRetireIfExact:
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
              }) => dbRetireGroupNotificationDisplayOutboxEntryIfExact(
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
      dbCommitProtectedGroupMetadataAuthorityFn:
          ({
            required expectedGroupRow,
            required expectedMemberRows,
            required expectedLatestKeyGeneration,
            required groupRow,
            required pendingBroadcastRows,
            required authorityPreparedSourcePeerId,
            required authorityPreparedSourceEventId,
            required authorityPreparedSourceTimestamp,
            required authorityPreparedPayload,
          }) => dbCommitProtectedGroupMetadataAuthority(
            db,
            expectedGroupRow: expectedGroupRow,
            expectedMemberRows: expectedMemberRows,
            expectedLatestKeyGeneration: expectedLatestKeyGeneration,
            groupRow: groupRow,
            pendingBroadcastRows: pendingBroadcastRows,
            authorityPreparedSourcePeerId: authorityPreparedSourcePeerId,
            authorityPreparedSourceEventId: authorityPreparedSourceEventId,
            authorityPreparedSourceTimestamp: authorityPreparedSourceTimestamp,
            authorityPreparedPayload: authorityPreparedPayload,
          ),
      dbCommitDissolvedGroup: (row) =>
          dbCommitDissolvedGroupAndDeleteNotificationDisplayOutbox(db, row),
      dbCommitProtectedDissolvedGroup:
          ({
            required groupRow,
            required expectedBroadcastRows,
            required authorityCompleteSourcePeerId,
            required authorityCompleteSourceEventId,
            required authorityCompleteSourceTimestamp,
            required authorityCompletePayload,
          }) => dbCommitProtectedDissolvedGroup(
            db,
            groupRow: groupRow,
            expectedBroadcastRows: expectedBroadcastRows,
            authorityCompleteSourcePeerId: authorityCompleteSourcePeerId,
            authorityCompleteSourceEventId: authorityCompleteSourceEventId,
            authorityCompleteSourceTimestamp: authorityCompleteSourceTimestamp,
            authorityCompletePayload: authorityCompletePayload,
          ),
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
      dbCommitLinkedGroupBootstrapAuthoringFn:
          ({
            required expectedGroup,
            required expectedMembers,
            required expectedSelfMember,
            required expectedLatestKeyGeneration,
            required expectedLatestKeyCreatedAt,
            required updatedSelfMember,
            required pendingDevice,
            required pendingBroadcast,
            required authorityGenesisSourcePeerId,
            required authorityGenesisSourceEventId,
            required authorityGenesisSourceTimestamp,
            required authorityGenesisPayload,
          }) => dbCommitLinkedGroupBootstrapAuthoring(
            db,
            expectedGroup: expectedGroup,
            expectedMembers: expectedMembers,
            expectedSelfMember: expectedSelfMember,
            expectedLatestKeyGeneration: expectedLatestKeyGeneration,
            expectedLatestKeyCreatedAt: expectedLatestKeyCreatedAt,
            updatedSelfMember: updatedSelfMember,
            pendingDevice: pendingDevice,
            pendingBroadcast: pendingBroadcast,
            authorityGenesisSourcePeerId: authorityGenesisSourcePeerId,
            authorityGenesisSourceEventId: authorityGenesisSourceEventId,
            authorityGenesisSourceTimestamp: authorityGenesisSourceTimestamp,
            authorityGenesisPayload: authorityGenesisPayload,
          ),
      dbCompleteLinkedGroupBootstrapCustodyFn:
          ({required expectedDevice, required expectedBroadcast}) =>
              dbCompleteLinkedGroupBootstrapCustody(
                db,
                expectedDevice: expectedDevice,
                expectedBroadcast: expectedBroadcast,
              ),
      dbCommitLinkedGroupBootstrapMaterializationFn:
          ({
            required groupRow,
            required memberRows,
            required keyRow,
            required authorityGenesisSourcePeerId,
            required authorityGenesisSourceEventId,
            required authorityGenesisSourceTimestamp,
            required authorityGenesisPayload,
          }) => dbCommitLinkedGroupBootstrapMaterialization(
            db,
            groupRow: groupRow,
            memberRows: memberRows,
            keyRow: keyRow,
            authorityGenesisSourcePeerId: authorityGenesisSourcePeerId,
            authorityGenesisSourceEventId: authorityGenesisSourceEventId,
            authorityGenesisSourceTimestamp: authorityGenesisSourceTimestamp,
            authorityGenesisPayload: authorityGenesisPayload,
          ),
      dbHasLinkedGroupBootstrapIntentFn:
          ({required groupId, required transportPeerId}) =>
              dbHasLinkedGroupBootstrapIntent(
                db,
                groupId: groupId,
                transportPeerId: transportPeerId,
              ),
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
      dbCommitProtectedGroupKeyAuthority:
          ({
            required keyRow,
            required authorityCompleteSourcePeerId,
            required authorityCompleteSourceEventId,
            required authorityCompleteSourceTimestamp,
            required authorityCompletePayload,
          }) => dbCommitGroupKeyWithAuthorityComplete(
            db,
            keyRow: keyRow,
            authorityCompleteSourcePeerId: authorityCompleteSourcePeerId,
            authorityCompleteSourceEventId: authorityCompleteSourceEventId,
            authorityCompleteSourceTimestamp: authorityCompleteSourceTimestamp,
            authorityCompletePayload: authorityCompletePayload,
          ),
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
      notificationIdRegistryResolver: durableNotificationIdRegistry == null
          ? null
          : () async => durableNotificationIdRegistry,
      notificationContentRegistryResolver: durableNotificationIdRegistry == null
          ? null
          : () async => durableNotificationIdRegistry,
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
        dbLoadGroupMessagesWithFailedInboxStore:
            ({
              int limit = 50,
              bool strictContentOnly = false,
              int offset = 0,
            }) => dbLoadGroupMessagesWithFailedInboxStore(
              executor,
              limit: limit,
              strictContentOnly: strictContentOnly,
              offset: offset,
            ),
        dbUpdateGroupMessageInboxStoredFn: (id, {required bool stored}) =>
            dbUpdateGroupMessageInboxStored(executor, id, stored: stored),
        dbUpdateGroupMessageInboxRetryPayloadFn: (id, payload) =>
            dbUpdateGroupMessageInboxRetryPayload(executor, id, payload),
        dbUpdateGroupMessageWireEnvelopeFn: (id, envelope) =>
            dbUpdateGroupMessageWireEnvelope(executor, id, envelope),
        dbCompleteGroupInboxStoreRetryFn: executor is Database
            ? (expected) => dbCompleteGroupInboxStoreRetry(executor, expected)
            : null,
        dbCompleteGroupContentInboxStoreRetryIfExactFn: executor is Database
            ? ({
                required expected,
                required sourcePeerId,
                required sourceEventId,
                required sourceTimestamp,
                required eventPayload,
              }) => dbCompleteGroupContentInboxStoreRetryIfExact(
                executor,
                expected: expected,
                sourcePeerId: sourcePeerId,
                sourceEventId: sourceEventId,
                sourceTimestamp: sourceTimestamp,
                eventPayload: eventPayload,
              )
            : null,
        dbStageAndCompleteLocalGroupContentMessageFn: executor is Database
            ? ({
                required expected,
                required sourcePeerId,
                required sourceEventId,
                required sourceTimestamp,
                required eventPayload,
              }) => dbStageAndCompleteLocalGroupContentMessage(
                executor,
                expected: expected,
                sourcePeerId: sourcePeerId,
                sourceEventId: sourceEventId,
                sourceTimestamp: sourceTimestamp,
                eventPayload: eventPayload,
              )
            : null,
        dbStagePreparedLocalGroupContentMessageFn: executor is Database
            ? ({
                required expected,
                required sourcePeerId,
                required sourceEventId,
                required sourceTimestamp,
                required preparedEventPayload,
              }) => dbStagePreparedLocalGroupContentMessage(
                executor,
                expected: expected,
                sourcePeerId: sourcePeerId,
                sourceEventId: sourceEventId,
                sourceTimestamp: sourceTimestamp,
                preparedEventPayload: preparedEventPayload,
              )
            : null,
        dbTerminalizePreparedLocalGroupContentMessageIfExactFn:
            executor is Database
            ? ({
                required expected,
                required preparedEventPayload,
                required terminalSourcePeerId,
                required terminalSourceEventId,
                required terminalSourceTimestamp,
                required terminalEventPayload,
              }) => dbTerminalizePreparedLocalGroupContentMessageIfExact(
                executor,
                expected: expected,
                preparedEventPayload: preparedEventPayload,
                terminalSourcePeerId: terminalSourcePeerId,
                terminalSourceEventId: terminalSourceEventId,
                terminalSourceTimestamp: terminalSourceTimestamp,
                terminalEventPayload: terminalEventPayload,
              )
            : null,
        dbHasExactPreparedLocalGroupContentMessageFn:
            ({required expected, required eventPayload}) =>
                dbHasExactPreparedLocalGroupContentMessage(
                  executor,
                  expected: expected,
                  eventPayload: eventPayload,
                ),
        dbIsStrictGroupReactionTargetEligibleFn: (expected) =>
            dbIsStrictGroupReactionTargetEligible(executor, expected),
        dbReplaceGroupInboxRetryPayloadIfExactFn: executor is Database
            ? (expected, replacement) => dbReplaceGroupInboxRetryPayloadIfExact(
                executor,
                expected,
                replacement,
              )
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
    final preparedGroupMediaBlobCustodyCoordinator =
        PreparedGroupMediaBlobCustodyCoordinator(
          artifactStore: GroupMediaBlobArtifactStore(),
        );
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
    bridge = GoBridgeClient();
    // Declared before the drain composition so its per-kick live read can
    // reference the one shared platform readiness resolver; assigned below
    // with the platform readers, before any drain kick can run.
    late final OpaqueWakePlatformConsumerReadiness
    opaqueWakePlatformConsumerReadiness;
    String currentPushPlatformName() => Platform.isIOS ? 'ios' : 'android';
    final notificationCompletedOutcomeDrainComposition =
        NotificationCompletedOutcomeDrainComposition(
          database: db,
          sendOutcome: ({required correlation}) =>
              callP2PInboxWakeOutcome(bridge, correlation: correlation),
          admissionEnabled: kWakeOutcomeCoordinatorAdmissionEnabled,
          readPlatformConsumerReady: () => opaqueWakePlatformConsumerReadiness
              .isReadyFor(currentPushPlatformName()),
          runNetworkAction: (action) => runAccountRuntimeNetworkVoidAction(
            operation: 'notification_completed_outcome_drain',
            action: action,
          ),
        );
    final drainNotificationCompletedOutcomes =
        notificationCompletedOutcomeDrainComposition.drain;
    notificationCompletedOutcomeDrainKick = drainNotificationCompletedOutcomes;
    // Declared before the linked-media drain closure that captures it. The
    // service is assigned later in this composition phase, before any runtime
    // owner can invoke that closure.
    late final P2PServiceImpl p2pService;
    final strictDirectMediaBlobDownloadAckOwner =
        StrictDirectMediaBlobDownloadAckOwner(
          bridge: bridge,
          mediaAttachmentRepository: mediaAttachmentRepository,
          mediaFileManager: mediaFileManager,
        );
    Future<bool> retryOutgoingLinkedDirectMediaBlobMessage(
      String messageId,
    ) async {
      // Once v108 exists, its immutable per-target envelopes are the sole
      // network authority. Drain every media sibling directly; the singular
      // owner lookup intentionally rejects plural generations.
      final siblingMaps = await messageRepository.loadDirectTextFanoutSiblings(
        messageId,
      );
      final mediaSiblings = siblingMaps
          .map(DirectInboxCustodyOutboxEntry.fromMap)
          .where(
            (entry) =>
                entry.contactAccountPeerId != null &&
                entry.mediaBlobManifestHash != null &&
                entry.mediaBlobExpiresAtMs != null,
          )
          .toList(growable: false);
      if (mediaSiblings.isNotEmpty) {
        var allCompleted = true;
        for (final entry in mediaSiblings) {
          final attempt = await drainOwnedDirectInboxCustodyOutboxEntry(
            entry: entry,
            custodyRepository: messageRepository,
            storeInAckCustodyInboxDetailed:
                p2pService.storeInAckCustodyInboxDetailed,
            storeInMediaExpiryBoundedInboxDetailed:
                p2pService.storeInMediaExpiryBoundedInboxDetailed,
          );
          allCompleted = allCompleted && attempt.completed;
        }
        return allCompleted;
      }

      // Pre-v108 prepared/stored generations retain `upload_pending`
      // attachments. Run the incumbent retrier against ONLY the message ids
      // selected by the linked v114 loader; historical primary rows never
      // enter this restricted runtime.
      return await retryIncompleteUploads(
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
                  source: MediaUploadTriggerSource.full,
                ),
            releaseUploadLease: mediaUploadInFlightTracker.release,
            restrictToMessageIds: <String>{messageId},
          ) >
          0;
    }

    final directMediaBlobCustodyDrain = DirectMediaBlobCustodyDrain(
      repository: mediaAttachmentRepository,
      incomingRepository: mediaAttachmentRepository,
      artifactStore: DirectMediaBlobArtifactStore(
        documentsDirectoryProvider: () async => appDocDir,
      ),
      identityPeerId: () async => (await repository.loadIdentity())?.peerId,
      strictDownloadAckOwner: strictDirectMediaBlobDownloadAckOwner,
      retryOutgoingLinkedMessage: retryOutgoingLinkedDirectMediaBlobMessage,
      // 362: the shared encrypted artifact is unlinked only by the LAST v114
      // sibling still referencing its exact (path, hash, size) proof; earlier
      // target retirements delete their row but must preserve the ciphertext
      // the surviving targets still retry from.
      countOtherArtifactReferences:
          ({
            required ciphertextRelativePath,
            required contentHash,
            required ciphertextSize,
            required excluding,
          }) => dbCountOtherDirectMediaBlobCustodyRowsReferencingArtifact(
            db,
            ciphertextRelativePath: ciphertextRelativePath,
            contentHash: contentHash,
            ciphertextSize: ciphertextSize,
            excluding: excluding,
          ),
      retryIncomingDownload: (row) async {
        final parent = await messageRepository.getMessage(row.messageId);
        // 355: the exact shared drain predicate decides. A tombstoned, hidden
        // or redacted parent is retained WITHOUT network; an ordinary strict
        // parent still converges automatically. The independent v111
        // obligation converges on its own either way: an already ACK-pending
        // row keeps retrying its source ACK, and expiry still applies.
        if (!directMediaBlobDrainMayDownloadIncomingParent(parent)) {
          if (parent != null && parent.privateMediaPolicy.requiresRedaction) {
            emitFlowEvent(
              layer: 'FL',
              event: 'DIRECT_MEDIA_BLOB_DRAIN_PRIVATE_RETAINED',
              details: {
                'id': row.messageId.length > 8
                    ? row.messageId.substring(0, 8)
                    : row.messageId,
              },
            );
          }
          return false;
        }
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
                  contactPeerId: parent!.contactPeerId,
                ) !=
            null;
      },
    );
    Future<String?> resolveCompletedOutcomePhysicalPeerId() async {
      try {
        final identity = await repository.loadIdentity();
        if (identity == null) return null;

        final authority = await linkedInstallationAuthority.load(
          expectedAccountPeerId: identity.peerId,
        );
        return selectNotificationCompletedOutcomePhysicalPeerId(
          accountPeerId: identity.peerId,
          accountPublicKey: identity.publicKey,
          authority: authority,
        );
      } catch (_) {
        return null;
      }
    }

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

    Future<int> cleanupGroupMediaBlobCustodyLocally() async {
      final identity = await repository.loadIdentity();
      if (identity == null) return 0;
      final completed = await preparedGroupMediaBlobCustodyCoordinator
          .drainOutgoingCleanupAndOrphans(
            mediaAttachmentRepository: mediaAttachmentRepository,
            identityPeerId: identity.peerId,
          );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEDIA_BLOB_CUSTODY_LOCAL_DRAIN_RESULT',
        details: <String, Object?>{'completed': completed},
      );
      return completed;
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

    // 362: the restricted linked runtime's strict-media converger. It reuses
    // the ONE shared v111 lifecycle owner through its linked-scoped entry
    // point, so a linked secondary converges only rows it owns and never the
    // primary's historical single-target ones. Do NOT construct a second
    // drain: the bootstrap phase contract freezes that constructor to exactly
    // one occurrence by raw text scan, which is also why this comment must not
    // spell the constructor out.
    //
    // Only the NETWORK leg is wired. The local-cleanup leg is deliberately
    // left unsupplied: `runLocalCleanupBounded`'s orphan sweep builds its
    // referenced-path set from a GLOBAL live-outgoing inventory, so pairing it
    // with a linked-only page would classify primary-authored ciphertext as
    // unreferenced and delete it.
    Future<void> drainLinkedDirectMediaBlobCustody() async {
      final result = await directMediaBlobCustodyDrain
          .runNetworkBoundedLinked();
      emitFlowEvent(
        layer: 'FL',
        event: 'DIRECT_MEDIA_BLOB_CUSTODY_LINKED_NETWORK_DRAIN_RESULT',
        details: <String, Object?>{
          'completed': result.completed,
          'retained': result.retained,
          'failed': result.failed,
        },
      );
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
            : (accountPeerId) => runWithRetiredIosNseTransportAuthority<void>(
                projection: iosNseTransportAdmissionActive
                    ? iosNseInboxTransportProjection
                    : null,
                mutateAuthority: () async {
                  await canonicalRuntimeBindingCoordinator.publishAccount(
                    accountPeerId,
                  );
                },
              ),
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
          await iosNseInboxTransportProjection?.retireAndReadBack();
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
    late final GroupMessageListener groupMessageListener;
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

    late final ProductionCanonicalDirectReplayComposition
    productionDirectReplayComposition;

    Future<RecoveredInboxReplayOutcome> replayInboxChatMessage(
      ChatMessage message, {
      required bool suppressNotification,
      String? stagedEntryId,
    }) => productionDirectReplayComposition.replayChatMessage(
      message,
      suppressNotification: suppressNotification,
      stagedEntryId: stagedEntryId,
    );

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
      AppVisibilitySuppressionReader appVisibility,
      NotificationToneTracker toneTracker,
      DurableNotificationToneLease durableCoordinator,
    })?
    reactionNotifyDeps;
    DirectNotificationProjectionOwner? directNotificationOwner;
    void Function(ReactionChange change)? publishPersistedReactionChange;

    productionDirectReplayComposition =
        ProductionCanonicalDirectReplayComposition(
          loadIdentity: repository.loadIdentity,
          chatMessageListener: () => chatMessageListener,
          introductionListener: () => introductionListener,
          contactRequestListener: () => contactRequestListener,
          introductionRepository: introductionRepository,
          contactRepository: contactRepository,
          messageRepository: messageRepository,
          reactionRepository: reactionRepository,
          mediaAttachmentRepository: mediaAttachmentRepository,
          transportAuthority: directTransportAuthority,
          bridge: bridge,
          secureKeyStore: secureKeyStore,
          mediaFileManager: mediaFileManager,
          sendDeliveryReceipt: sendDeliveryReceiptForPeer,
          notificationOwner: () => directNotificationOwner,
          reactionNotificationDependencies: () {
            final notify = reactionNotifyDeps;
            return notify == null
                ? null
                : ProductionDirectReactionNotificationDependencies(
                    service: notify.service,
                    appVisibility: notify.appVisibility,
                    toneTracker: notify.toneTracker,
                    durableCoordinator: notify.durableCoordinator,
                  );
          },
          pendingNotificationOverlay:
              pendingNotificationOverlayBindingPublisher,
          forceSilentNotification: isIosMailboxAlertSilentReplayContext,
          publishPersistedReactionChange: () => publishPersistedReactionChange,
        );

    // F7: reactions/deletions get the same stage-before-ack/commit durability as
    // chat. These replay closures call the use cases DIRECTLY (the listeners are
    // constructed later and aren't needed here) and resolve the SAME deps + the
    // same ML-KEM secret as the chat path (repository.loadIdentity()).
    Future<RecoveredInboxReplayOutcome> replayInboxReaction(
      ChatMessage message, {
      String? stagedEntryId,
    }) => productionDirectReplayComposition.replayReaction(
      message,
      stagedEntryId: stagedEntryId,
    );

    ingestStagedPushEnvelopesUseCase.replayReactionMessage =
        (message, {String? stagedEntryId}) =>
            replayInboxReaction(message, stagedEntryId: stagedEntryId);

    Future<RecoveredInboxReplayOutcome> replayInboxMessageDeletion(
      ChatMessage message, {
      String? stagedEntryId,
    }) => productionDirectReplayComposition.replayMessageDeletion(
      message,
      stagedEntryId: stagedEntryId,
    );

    // CV-26 (FDC-04 DESIGN-3): the 1:1 active-conversation tracker is a
    // zero-dependency object; construct it HERE (ahead of the P2PServiceImpl
    // build) so the peer-scoped WiFi<->cellular re-warm can resolve the open
    // conversation's peer. (Moved up from its former site further down this
    // builder — nothing between here and there references it.)
    final conversationTracker = ActiveConversationTracker();
    final appVisibilityAuthority = AppVisibilityAuthority(
      platformBridge: MethodChannelAppVisibilityPlatformBridge(),
    );
    final appVisibilityRouteRegistry = AppVisibilityRouteRegistry(
      authority: appVisibilityAuthority,
      onExactConversationActivated:
          buildProductionExactConversationActivationCleanup(
            notificationService,
          ),
    );

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

    // 360: forward reference to the role-aware deferred-start owner, which is
    // constructed far below (it needs `startLiveServicesIfAllowed`). The
    // closure below defers the read until node start, by which time the
    // deferred start has already resolved persisted authority. Null — an
    // ordinary primary, or any moment before the deferred start ran — makes
    // the qualification a no-op, which is exactly the incumbent behavior.

    /// 361: the account peer the deferred role-aware start last observed —
    /// consumed synchronously by the route-push fanout authoring resolver.
    String? lastKnownAccountPeerId;
    RoleAwareDeferredRuntimeStart? roleAwareDeferredRuntimeStartRef;
    // Plan 375: the one live Android consumer read-back behind the shared
    // platform readiness. Production never infers readiness from the platform
    // alone — the native Plan-374 bridge and the current secure binding are
    // read at each consult, on the same epoch as producer/drainer/register.
    final androidOpaqueWakeReadiness = !kIsWeb && Platform.isAndroid
        ? AndroidOpaqueWakeReadiness(
            admissionEnabled: kWakeOutcomeCoordinatorAdmissionEnabled,
            readConsumerSnapshot:
                droppedPushRecoveryBridge.opaqueWakeConsumerSnapshot,
            readCurrentSecureBinding: () async =>
                canonicalRuntimeBindingCoordinator?.readCurrentAccountBinding(),
          )
        : null;
    opaqueWakePlatformConsumerReadiness = OpaqueWakePlatformConsumerReadiness(
      admissionEnabled: kWakeOutcomeCoordinatorAdmissionEnabled,
      readAndroidConsumer: androidOpaqueWakeReadiness?.isConsumerReady,
      readIosConsumer: iosNseInboxTransportProjection == null
          ? null
          : () async {
              if (kIsWeb || !Platform.isIOS) return false;
              final identityRow = await dbLoadIdentityRow(db);
              final logicalAccountPeerId = identityRow?['peer_id'];
              final transportPeerId = p2pService.currentState.peerId;
              final sharedOpaqueBinding = await sharedPushKeyStore!.read(
                canonicalRuntimeSharedAccountBindingStorageKey,
              );
              final canonicalOpaqueBinding =
                  await canonicalRuntimeBindingCoordinator
                      ?.readCurrentAccountBinding();
              if (logicalAccountPeerId is! String ||
                  transportPeerId == null ||
                  canonicalOpaqueBinding == null ||
                  sharedOpaqueBinding != canonicalOpaqueBinding) {
                return false;
              }
              return iosNseInboxTransportProjection.isBindingQualified(
                opaqueBinding: canonicalOpaqueBinding,
                logicalAccountPeerId: logicalAccountPeerId,
                transportPeerId: transportPeerId,
                relayMultiaddrs: defaultRelayAddresses(),
              );
            },
    );

    // Create P2P service (uses the same bridge + local P2P)
    p2pService = P2PServiceImpl(
      requiredTransportPeerId: () =>
          roleAwareDeferredRuntimeStartRef?.activeLinkedTransportPeerId,
      logicalAccountPeerId: () =>
          roleAwareDeferredRuntimeStartRef?.activeLinkedAccountPeerId,
      publishQualifiedIosNseTransport: iosNseInboxTransportProjection == null
          ? null
          : ({
              required logicalAccountPeerId,
              required transportPeerId,
              required transportPrivateKeyBase64,
              required relayMultiaddrs,
            }) async {
              if (kIsWeb ||
                  !Platform.isIOS ||
                  !kWakeOutcomeCoordinatorAdmissionEnabled) {
                return false;
              }
              try {
                final identityRow = await dbLoadIdentityRow(db);
                final committedAccountPeerId = identityRow?['peer_id'];
                final sharedOpaqueBinding = await sharedPushKeyStore!.read(
                  canonicalRuntimeSharedAccountBindingStorageKey,
                );
                final canonicalOpaqueBinding =
                    await canonicalRuntimeBindingCoordinator
                        ?.readCurrentAccountBinding();
                if (committedAccountPeerId is! String ||
                    committedAccountPeerId != logicalAccountPeerId ||
                    canonicalOpaqueBinding == null ||
                    sharedOpaqueBinding != canonicalOpaqueBinding) {
                  throw StateError('iOS NSE transport binding is not current');
                }
                await iosNseInboxTransportProjection.publishAndReadBack(
                  opaqueBinding: canonicalOpaqueBinding,
                  logicalAccountPeerId: logicalAccountPeerId,
                  transportPeerId: transportPeerId,
                  transportPrivateKeyBase64: transportPrivateKeyBase64,
                  relayMultiaddrs: relayMultiaddrs,
                );
                return true;
              } on Object {
                await iosNseInboxTransportProjection.retireAndReadBack();
                return false;
              }
            },
      readOpaqueWakePlatformConsumerReadiness:
          opaqueWakePlatformConsumerReadiness.isReadyFor,
      beginIosInboxDrainGeneration:
          iosNotificationRecoveryCoordinator?.beginInboxDrainGeneration,
      endIosInboxDrainGeneration:
          iosNotificationRecoveryCoordinator?.endInboxDrainGeneration,
      bridge: bridge,
      localP2PService: localP2PService,
      pushTokenStore: pushTokenStore,
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
            suppressNotification: !isIosMailboxAlertSilentReplayContext,
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
        return productionDirectReplayComposition.replayIntroduction(message);
      },
      // 171: relay-inbox replay of a cold-receiver contact_request runs the SAME
      // listener processing (auto-add + reciprocal + confirm) as the live
      // broadcast — the dominant-bug fix for a freshly-installed B whose listener
      // wasn't subscribed when A's request arrived. Any returned result is
      // terminal (committed -> delete the staged row); only a thrown error
      // retries (so a transient failure re-stages instead of being lost).
      replayRecoveredInboxContactRequest: (message) async {
        return productionDirectReplayComposition.replayContactRequest(message);
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
      predecryptInboxChatEntry:
          productionDirectReplayComposition.predecryptChatMessage,
    );
    if (iosNseTransportAdmissionActive) {
      refreshIosNseTransportAfterIdentityCommit = (identity) async {
        if (!p2pService.currentState.isStarted) return;
        if (!await p2pService.refreshQualifiedIosNseTransportProjection(
          logicalAccountPeerId: identity.peerId,
        )) {
          throw StateError(
            'qualified iOS NSE transport refresh failed after identity commit',
          );
        }
      };
    }
    // 364: one owner per production bootstrap/runtime. It spans inbound
    // protected replay plus every strict linked outgoing custody operation;
    // no process-global pause bit can leak between runtime instances.
    final linkedGroupContentQuiescence = ProtectedGroupContentRuntimeQuiescence(
      pauseInboundAdmission: p2pService.pauseProtectedGroupContentAdmission,
      resumeInboundAdmission: p2pService.resumeProtectedGroupContentAdmission,
      quiesceOutgoingMedia: () => mediaAttachmentRepository
          .runGroupMediaBlobCustodyLifecycle<void>(() async {}),
      quiesceIncomingMedia: () => mediaAttachmentRepository
          .runGroupMediaBlobCustodyLifecycle<void>(() async {}),
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
                // The DB identity row is the logical account peer for both
                // roles; a linked physical transport peer is a relay route,
                // never migration/account authority.
                logicalAuthorityPeerId: identity?.peerId,
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
    // Plan 375: persisted-token restore and every relay-health transition
    // route through this one late-installed retry owner; afterward no raw
    // bridge registration path remains in the service.
    if (pushRegistrationCoordinator != null) {
      p2pService.installPushRegistrationRetryNow(
        pushRegistrationCoordinator.retryNow,
      );
    }
    // conversationTracker is constructed EARLIER (ahead of P2PServiceImpl) for the
    // CV-26 FDC-04 re-warm wiring; see the P2PServiceImpl build site above.
    final groupConversationTracker = ActiveConversationTracker();
    // 118 Phase 4: one shared per-conversation tone debounce for BOTH listeners
    // (direct + group keys are disjoint under normalizeActiveKey).
    final notificationToneTracker = NotificationToneTracker();
    final durableReactionNotificationCoordinator =
        await DurableNotificationToneLease.openDefault();
    final directProjectionComposition =
        buildProductionCanonicalDirectProjectionComposition(
          ProductionCanonicalDirectProjectionDependencies(
            database: db,
            notificationService: notificationService,
            appVisibility: appVisibilityAuthority,
            contactRepository: contactRepository,
            messageRepository: messageRepository,
            reactionRepository: reactionRepository,
            mediaAttachmentRepository: mediaAttachmentRepository,
            displayOutbox: directNotificationDisplayOutboxRepository,
            reconciliationOutbox:
                directNotificationReconciliationOutboxRepository,
            reactionTerminal: directNotificationReactionTerminalRepository,
            readAcknowledgement:
                directNotificationReadAcknowledgementRepository,
            durableRegistry: durableNotificationIdRegistry,
            readCurrentOpaqueBinding: () async =>
                canonicalRuntimeBindingCoordinator?.readCurrentAccountBinding(),
            resolvePhysicalPeerId: resolveCompletedOutcomePhysicalPeerId,
            presentationOwner: LocalNotificationPresentationOwner.mainApp,
            completedOutcomeProducerEnabled:
                kWakeOutcomeCoordinatorAdmissionEnabled,
            readCompletedOutcomeProducerReady: () =>
                opaqueWakePlatformConsumerReadiness.isReadyFor(
                  currentPushPlatformName(),
                ),
            notificationToneTracker: notificationToneTracker,
            durableNotificationCoordinatorResolver: () async =>
                durableReactionNotificationCoordinator,
            pendingNotificationOverlay:
                pendingNotificationOverlayBindingPublisher,
            kickCompletedOutcomeDrain: kickNotificationCompletedOutcomeDrain,
          ),
        );
    directNotificationOwner = directProjectionComposition.owner;
    projectDirectConversationRead =
        directProjectionComposition.readProjector.markConversationRead;

    final appShellController = AppShellController();
    final pendingPostTargetStore = PendingPostTargetStore();

    // Create chat message listener (sendDeliveryReceiptForPeer is hoisted above
    // the P2PServiceImpl construction so the F7 deletion replay can reference it).
    chatMessageListener = ChatMessageListener(
      transportAuthority: directTransportAuthority,
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
      appVisibility: appVisibilityAuthority,
      notificationToneTracker: notificationToneTracker,
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
      appVisibility: appVisibilityAuthority,
      toneTracker: notificationToneTracker,
      durableCoordinator: durableReactionNotificationCoordinator,
    );

    // 115 P2: consume incoming receipts — the only place 'inboxed' rows flip
    // to 'delivered' (G4 site a).
    final deliveryReceiptListener = DeliveryReceiptListener(
      transportAuthority: directTransportAuthority,
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
      transportAuthority: directTransportAuthority,
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
          appVisibility: notify.appVisibility,
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
      transportAuthority: directTransportAuthority,
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
      retryPendingStrictAcknowledgements: () =>
          StrictGroupMediaBlobDownloadAckOwner(
            bridge: bridge,
            mediaAttachmentRepository: mediaAttachmentRepository,
            mediaFileManager: mediaFileManager,
          ).retryPendingAcknowledgements(),
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
      appVisibility: appVisibilityAuthority,
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
      resolveCompletedOutcomePhysicalPeerId:
          resolveCompletedOutcomePhysicalPeerId,
      completedOutcomeProducerEnabled: kWakeOutcomeCoordinatorAdmissionEnabled,
      readCompletedOutcomeProducerReady: () =>
          opaqueWakePlatformConsumerReadiness.isReadyFor(
            currentPushPlatformName(),
          ),
      resolveCurrentOpaqueBinding:
          canonicalRuntimeBindingCoordinator?.readCurrentAccountBinding,
      durableLocalNotificationEffectRegistry: durableNotificationIdRegistry,
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
      dbInsertProtectedBatch:
          ({
            required groupId,
            required rows,
            required authorityPreparedSourcePeerId,
            required authorityPreparedSourceEventId,
            required authorityPreparedSourceTimestamp,
            required authorityPreparedPayload,
          }) => dbInsertPendingGroupBroadcastsWithAuthorityPreparedAtomically(
            db,
            groupId: groupId,
            rows: rows,
            authorityPreparedSourcePeerId: authorityPreparedSourcePeerId,
            authorityPreparedSourceEventId: authorityPreparedSourceEventId,
            authorityPreparedSourceTimestamp: authorityPreparedSourceTimestamp,
            authorityPreparedPayload: authorityPreparedPayload,
          ),
      dbAbortProtectedBatch:
          ({
            required groupId,
            required expectedRows,
            required authorityPreparedSourcePeerId,
            required authorityPreparedSourceEventId,
            required authorityPreparedSourceTimestamp,
            required authorityPreparedPayload,
            required authorityAbortedSourcePeerId,
            required authorityAbortedSourceEventId,
            required authorityAbortedSourceTimestamp,
            required authorityAbortedPayload,
            required authorityCompleteSourceEventId,
          }) async {
            final result =
                await dbAbortPendingGroupBroadcastsWithAuthorityAtomically(
                  db,
                  groupId: groupId,
                  expectedRows: expectedRows,
                  authorityPreparedSourcePeerId: authorityPreparedSourcePeerId,
                  authorityPreparedSourceEventId:
                      authorityPreparedSourceEventId,
                  authorityPreparedSourceTimestamp:
                      authorityPreparedSourceTimestamp,
                  authorityPreparedPayload: authorityPreparedPayload,
                  authorityAbortedSourcePeerId: authorityAbortedSourcePeerId,
                  authorityAbortedSourceEventId: authorityAbortedSourceEventId,
                  authorityAbortedSourceTimestamp:
                      authorityAbortedSourceTimestamp,
                  authorityAbortedPayload: authorityAbortedPayload,
                  authorityCompleteSourceEventId:
                      authorityCompleteSourceEventId,
                );
            return switch (result) {
              DbProtectedGroupAuthorityAbortResult.aborted =>
                ProtectedGroupAuthorityAbortResult.aborted,
              DbProtectedGroupAuthorityAbortResult.alreadyAborted =>
                ProtectedGroupAuthorityAbortResult.alreadyAborted,
              DbProtectedGroupAuthorityAbortResult.refusedComplete =>
                ProtectedGroupAuthorityAbortResult.refusedComplete,
              DbProtectedGroupAuthorityAbortResult.conflict =>
                ProtectedGroupAuthorityAbortResult.conflict,
            };
          },
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
      dbRemoveRecipientIfExact:
          ({required expected, required recipientPeerId, required updatedAt}) =>
              dbRemovePendingGroupBroadcastRecipientIfExact(
                db,
                expected: expected,
                recipientPeerId: recipientPeerId,
                updatedAt: updatedAt,
              ),
    );

    Future<AuthenticatedGroupAuthorityProof?> loadLocalAuthorityProof({
      required String groupId,
      required AuthenticatedGroupAuthorityPhase phase,
      required String eventId,
    }) => loadAuthenticatedGroupAuthorityProofFromEventLog(
      loadRow: ({required groupId, required sourceEventId}) =>
          dbLoadGroupEventLogEntryExact(
            db,
            groupId: groupId,
            sourceEventId: sourceEventId,
          ),
      groupId: groupId,
      phase: phase,
      eventId: eventId,
      verify: ({required publicKey, required data, required signature}) =>
          callVerifyPayload(
            bridge: bridge,
            publicKey: publicKey,
            data: data,
            signature: signature,
          ),
    );

    Future<void> appendLocalAuthorityProof({
      required AuthenticatedGroupAuthorityPhase phase,
      required AuthenticatedGroupAuthorityProof proof,
    }) async {
      await dbAppendGroupEventLogEntry(
        db,
        groupId: proof.groupId,
        eventType: phase.eventType,
        sourcePeerId: proof.actorAccountPeerId,
        sourceEventId: authenticatedGroupAuthoritySourceEventId(
          phase,
          proof.eventId,
        ),
        sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
        payload: authenticatedGroupAuthorityFactPayload(proof),
      );
    }

    Future<ProtectedGroupAuthorityApplyResult>
    applyLocalProtectedSystemAuthorityReplay(
      ProtectedGroupAuthorityControl control,
      Map<String, dynamic> replayData,
      VerifiedProtectedGroupAuthorityReplay authority,
    ) async {
      if (control == ProtectedGroupAuthorityControl.groupKeyUpdate ||
          !authority.authorizesSystemReplay(replayData)) {
        return ProtectedGroupAuthorityApplyResult.rejected;
      }
      try {
        await groupMessageListener.handleAuthenticatedAuthorityReplayEnvelope(
          replayData,
          authority: authority,
          rethrowOnError: true,
          membershipPhaseHeld: true,
        );
        final after = await protectedGroupAuthorityReplayConverged(
          control: control,
          replayData: replayData,
          groupRepository: groupRepository,
          requireMembershipVersion:
              control == ProtectedGroupAuthorityControl.memberAdd ||
              control == ProtectedGroupAuthorityControl.memberRole ||
              control == ProtectedGroupAuthorityControl.memberRemove,
          allowDominatingMembershipVersion: true,
        );
        return after == true
            ? ProtectedGroupAuthorityApplyResult.applied
            : ProtectedGroupAuthorityApplyResult.retryable;
      } on ProtectedGroupAuthorityReplaySuperseded {
        return ProtectedGroupAuthorityApplyResult.superseded;
      } catch (_) {
        return ProtectedGroupAuthorityApplyResult.retryable;
      }
    }

    Future<bool> completeLocalProtectedAuthority(
      AuthenticatedGroupAuthorityProof expected,
    ) async {
      final control = ProtectedGroupAuthorityControl.fromWire(expected.control);
      if (control == null) return false;
      late final bool completed;
      if (control == ProtectedGroupAuthorityControl.memberAdd ||
          control == ProtectedGroupAuthorityControl.memberRole ||
          control == ProtectedGroupAuthorityControl.memberRemove ||
          control == ProtectedGroupAuthorityControl.memberConfig) {
        completed = await recoverLocalPreparedProtectedSystemAuthority(
          proof: expected,
          groupRepository: groupRepository,
          verifyAuthorityProof:
              ({required publicKey, required data, required signature}) =>
                  callVerifyPayload(
                    bridge: bridge,
                    publicKey: publicKey,
                    data: data,
                    signature: signature,
                  ),
          loadAuthorityProof:
              ({required groupId, required phase, required eventId}) =>
                  loadLocalAuthorityProof(
                    groupId: groupId,
                    phase: phase,
                    eventId: eventId,
                  ),
          appendAuthorityProof: ({required phase, required proof}) =>
              appendLocalAuthorityProof(phase: phase, proof: proof),
          applyReplay: applyLocalProtectedSystemAuthorityReplay,
        );
      } else {
        completed = await ensureLocalProtectedGroupAuthorityComplete(
          groupId: expected.groupId,
          eventId: expected.eventId,
          expectedControl: control,
          expectedProof: expected,
          groupRepository: groupRepository,
          loadAuthorityProof:
              ({required groupId, required phase, required eventId}) =>
                  loadLocalAuthorityProof(
                    groupId: groupId,
                    phase: phase,
                    eventId: eventId,
                  ),
          appendAuthorityProof: ({required phase, required proof}) =>
              appendLocalAuthorityProof(phase: phase, proof: proof),
        );
      }
      return completed &&
          await reconcileCompletedProtectedGroupAuthority(
            groupRepository,
            expected,
          );
    }

    Future<List<ProtectedGroupAuthorityPreparation>>
    discoverLocalPreparedAuthorities(String? onlyGroupId) async {
      final identity = await repository.loadIdentity();
      if (identity == null) return const <ProtectedGroupAuthorityPreparation>[];
      final installation = await linkedInstallationAuthority.load(
        expectedAccountPeerId: identity.peerId,
      );
      if (installation.refusesStartup) {
        return const <ProtectedGroupAuthorityPreparation>[];
      }
      final localTransportPeerId = installation.isActiveLinkedSecondary
          ? installation.credential?.transportPeerId
          : identity.peerId;
      if (localTransportPeerId == null || localTransportPeerId.isEmpty) {
        return const <ProtectedGroupAuthorityPreparation>[];
      }
      final groups = onlyGroupId == null
          ? await groupRepository.getAllGroups()
          : <GroupModel>[?await groupRepository.getGroup(onlyGroupId)];
      final discoveries = <ProtectedGroupAuthorityPreparation>[];
      for (final group in groups) {
        if (group.selfRemovedAt != null) continue;
        final localAuthorTransports = <String, String>{
          localTransportPeerId: installation.isActiveLinkedSecondary
              ? installation.credential!.transportPublicKey
              : identity.publicKey,
        };
        if (!installation.isActiveLinkedSecondary) {
          final selfMember = await groupRepository.getMember(
            group.id,
            identity.peerId,
          );
          if (selfMember != null) {
            for (final device in selfMember.activeDevicesWithLegacyFallback()) {
              if (device.deviceSigningPublicKey == identity.publicKey) {
                localAuthorTransports[device.transportPeerId] =
                    device.deviceSigningPublicKey;
              }
            }
          }
        }
        final pending = await groupPendingBroadcastRepository.forGroup(
          group.id,
        );
        if (pending.any(
          (row) =>
              row.kind == groupPendingBroadcastKindProtectedAuthority &&
              parseProtectedGroupAuthorityDeliveryId(
                    row.sourceMessageId ?? '',
                  ) ==
                  null,
        )) {
          // An unparseable protected row might own any PREPARED transition in
          // this group. Row absence is recovery evidence only when every
          // protected owner is attributable, so fail this group's discovery
          // closed and leave ordinary row draining to report the corruption.
          continue;
        }
        final rowOwnedEventIds = <String>{
          for (final row in pending)
            if (row.kind == groupPendingBroadcastKindProtectedAuthority)
              if (parseProtectedGroupAuthorityDeliveryId(
                    row.sourceMessageId ?? '',
                  )
                  case final identity?)
                identity.transitionId,
        };
        String? afterTimestamp;
        String? afterEventId;
        for (var pageIndex = 0; pageIndex < 4; pageIndex++) {
          final page = await loadAuthenticatedGroupAuthorityProofPage(
            loadRows:
                ({
                  required groupId,
                  required eventType,
                  afterSourceTimestamp,
                  afterSourceEventId,
                  throughSourceTimestamp,
                  required limit,
                }) {
                  if (eventType != protectedGroupAuthorityPreparedEventType ||
                      throughSourceTimestamp != null) {
                    return Future<List<Map<String, Object?>>>.value(
                      const <Map<String, Object?>>[],
                    );
                  }
                  return dbLoadUnfinishedProtectedAuthorityPage(
                    db,
                    groupId: groupId,
                    sourcePeerId: identity.peerId,
                    afterSourceTimestamp: afterSourceTimestamp,
                    afterSourceEventId: afterSourceEventId,
                    limit: limit,
                  );
                },
            groupId: group.id,
            phase: AuthenticatedGroupAuthorityPhase.prepared,
            verify: ({required publicKey, required data, required signature}) =>
                callVerifyPayload(
                  bridge: bridge,
                  publicKey: publicKey,
                  data: data,
                  signature: signature,
                ),
            afterSourceTimestamp: afterTimestamp,
            afterSourceEventId: afterEventId,
            limit: 200,
          );
          for (final proof in page) {
            if (proof.actorAccountPeerId != identity.peerId ||
                proof.actorAccountPublicKey != identity.publicKey ||
                localAuthorTransports[proof.senderTransportPeerId] !=
                    proof.senderTransportPublicKey ||
                rowOwnedEventIds.contains(proof.eventId)) {
              continue;
            }
            final aborted = await loadLocalAuthorityProof(
              groupId: group.id,
              phase: AuthenticatedGroupAuthorityPhase.aborted,
              eventId: proof.eventId,
            );
            if (aborted != null) {
              if (!sameAuthenticatedGroupAuthorityProof(aborted, proof)) {
                throw StateError('conflicting prepared/aborted authority');
              }
              continue;
            }
            final complete = await loadLocalAuthorityProof(
              groupId: group.id,
              phase: AuthenticatedGroupAuthorityPhase.complete,
              eventId: proof.eventId,
            );
            if (complete != null) {
              if (!sameAuthenticatedGroupAuthorityProof(complete, proof)) {
                throw StateError('conflicting prepared/complete authority');
              }
              continue;
            }
            final control = ProtectedGroupAuthorityControl.fromWire(
              proof.control,
            );
            if (control == null) continue;
            if (control == ProtectedGroupAuthorityControl.groupKeyUpdate) {
              final rawRecipients =
                  proof.authorityData['recipientTransportPeerIds'];
              if (rawRecipients is! List || rawRecipients.isNotEmpty) {
                // A rowless nonempty ACL can be an aborted preparation; row
                // absence alone is not a custody receipt. Key transitions with
                // recipients complete before their rows may retire, so only a
                // signed empty ACL belongs to prepared-only key recovery.
                continue;
              }
            }
            discoveries.add(
              ProtectedGroupAuthorityPreparation(
                groupId: group.id,
                rows: const <GroupPendingBroadcast>[],
                authorityProof: proof,
                control: control,
                replayData: Map<String, dynamic>.from(proof.authorityData),
              ),
            );
          }
          if (page.length < 200) break;
          final last = page.last;
          afterTimestamp = fixedGroupAuthorityUtc(last.eventAt);
          afterEventId = authenticatedGroupAuthoritySourceEventId(
            AuthenticatedGroupAuthorityPhase.prepared,
            last.eventId,
          );
        }
      }
      discoveries.sort((left, right) {
        final leftProof = left.authorityProof!;
        final rightProof = right.authorityProof!;
        final byTime = leftProof.eventAt.compareTo(rightProof.eventAt);
        return byTime != 0
            ? byTime
            : leftProof.eventId.compareTo(rightProof.eventId);
      });
      return discoveries;
    }

    Future<bool> recoverLocalPreparedKeyAuthority(
      AuthenticatedGroupAuthorityProof proof,
    ) => recoverPreparedProtectedGroupKey(
      proof: proof,
      groupRepository: groupRepository,
      promoteKey: (key) => callGroupUpdateKey(
        bridge,
        groupId: key.groupId,
        groupKey: key.encryptedKey,
        keyEpoch: key.keyGeneration,
      ),
      loadAuthorityProof:
          ({required groupId, required phase, required eventId}) =>
              loadLocalAuthorityProof(
                groupId: groupId,
                phase: phase,
                eventId: eventId,
              ),
    );

    Future<bool> recoverLocalRowOwnedPreparedKeyAuthority(
      AuthenticatedGroupAuthorityProof proof,
      GroupPendingBroadcast broadcast,
    ) => recoverRowOwnedPreparedProtectedGroupKey(
      proof: proof,
      triggerRow: broadcast,
      groupRepository: groupRepository,
      pendingRepository: groupPendingBroadcastRepository,
      loadAuthorityProof:
          ({required groupId, required phase, required eventId}) =>
              loadLocalAuthorityProof(
                groupId: groupId,
                phase: phase,
                eventId: eventId,
              ),
      promoteKey: (key) => callGroupUpdateKey(
        bridge,
        groupId: key.groupId,
        groupKey: key.encryptedKey,
        keyEpoch: key.keyGeneration,
      ),
    );

    Future<bool> ensureProtectedAuthorityComplete(
      GroupPendingBroadcast broadcast,
    ) async {
      if (broadcast.kind != groupPendingBroadcastKindProtectedAuthority ||
          broadcast.recipientPeerIds.length != 1) {
        return false;
      }
      final recipient = broadcast.recipientPeerIds.single;
      final identity = parseProtectedGroupAuthorityDeliveryId(
        broadcast.sourceMessageId ?? '',
      );
      if (identity == null) return false;
      final expectedDeliveryId = protectedGroupAuthorityDeliveryId(
        identity.control.wireValue,
        identity.transitionId,
        recipient,
      );
      final envelope = ProtectedGroupEnvelope.tryParse(
        broadcast.sysText,
        expectedType: protectedGroupAuthorityEnvelopeType,
      );
      if (identity.recipientTransportPeerId != recipient ||
          broadcast.sourceMessageId != expectedDeliveryId ||
          broadcast.id != 'protected-authority:$expectedDeliveryId' ||
          envelope == null ||
          envelope.id != expectedDeliveryId ||
          envelope.recipientPeerId != recipient) {
        return false;
      }
      return runGroupAuthorityPhaseIfNeeded(
        groupId: broadcast.groupId,
        authorityPhaseHeld: isGroupAuthorityPhaseHeld(broadcast.groupId),
        action: () async {
          final aborted = await loadLocalAuthorityProof(
            groupId: broadcast.groupId,
            phase: AuthenticatedGroupAuthorityPhase.aborted,
            eventId: identity.transitionId,
          );
          if (aborted != null) return false;
          final prepared = await loadLocalAuthorityProof(
            groupId: broadcast.groupId,
            phase: AuthenticatedGroupAuthorityPhase.prepared,
            eventId: identity.transitionId,
          );
          if (prepared == null ||
              prepared.groupId != broadcast.groupId ||
              prepared.eventId != identity.transitionId ||
              prepared.control != identity.control.wireValue ||
              envelope.senderPeerId != prepared.senderTransportPeerId) {
            return false;
          }
          final complete = await loadLocalAuthorityProof(
            groupId: broadcast.groupId,
            phase: AuthenticatedGroupAuthorityPhase.complete,
            eventId: identity.transitionId,
          );
          if (complete != null &&
              !sameAuthenticatedGroupAuthorityProof(complete, prepared)) {
            return false;
          }
          if (identity.control ==
              ProtectedGroupAuthorityControl.groupKeyUpdate) {
            return recoverLocalRowOwnedPreparedKeyAuthority(
              prepared,
              broadcast,
            );
          }
          if (complete != null) return true;
          return completeLocalProtectedAuthority(prepared);
        },
      );
    }

    Future<bool> finalizeLocalProtectedDissolve(
      String groupId,
      String eventId,
    ) => recoverPreparedProtectedGroupDissolve(
      groupId: groupId,
      eventId: eventId,
      groupRepository: groupRepository,
      pendingRepository: groupPendingBroadcastRepository,
      protectedInboxStore: p2pService,
      pendingSiblingDeviceRepository: groupRepository,
      loadAuthorityProof:
          ({required groupId, required phase, required eventId}) =>
              loadLocalAuthorityProof(
                groupId: groupId,
                phase: phase,
                eventId: eventId,
              ),
    );

    final groupPendingBroadcastRunner = GroupPendingBroadcastRunner(
      repository: groupPendingBroadcastRepository,
      protectedInboxStore: p2pService,
      pendingSiblingDeviceRepository: groupRepository,
      linkedGroupBootstrapRepository: groupRepository,
      ensureProtectedAuthorityComplete: ensureProtectedAuthorityComplete,
      finalizeProtectedDissolve: (broadcast) {
        final identity = parseProtectedGroupAuthorityDeliveryId(
          broadcast.sourceMessageId ?? '',
        );
        if (identity == null ||
            identity.control != ProtectedGroupAuthorityControl.groupDissolve) {
          return Future<bool>.value(false);
        }
        return finalizeLocalProtectedDissolve(
          broadcast.groupId,
          identity.transitionId,
        );
      },
      discoverPreparedAuthorities: discoverLocalPreparedAuthorities,
      recoverPreparedAuthority: (preparation) {
        final proof = preparation.authorityProof;
        final control = preparation.control;
        if (proof == null || control == null) {
          return Future<bool>.value(false);
        }
        if (control == ProtectedGroupAuthorityControl.groupDissolve) {
          return finalizeLocalProtectedDissolve(
            preparation.groupId,
            proof.eventId,
          );
        }
        if (control == ProtectedGroupAuthorityControl.groupKeyUpdate) {
          return recoverLocalPreparedKeyAuthority(proof);
        }
        return runGroupAuthorityPhaseIfNeeded(
          groupId: preparation.groupId,
          authorityPhaseHeld: isGroupAuthorityPhaseHeld(preparation.groupId),
          action: () => completeLocalProtectedAuthority(proof),
        );
      },
      rePushFinalizesSuccess: true,
      rePush: buildGroupPendingBroadcastRePush(
        bridge: bridge,
        groupRepo: groupRepository,
        loadIdentity: repository.loadIdentity,
        pendingRepository: groupPendingBroadcastRepository,
        resolveProtectedPreparedAuthority:
            ({required groupId, required eventId}) async {
              final aborted = await loadLocalAuthorityProof(
                groupId: groupId,
                phase: AuthenticatedGroupAuthorityPhase.aborted,
                eventId: eventId,
              );
              if (aborted != null) {
                return ProtectedPreparedAuthorityGate.aborted;
              }
              final prepared = await loadLocalAuthorityProof(
                groupId: groupId,
                phase: AuthenticatedGroupAuthorityPhase.prepared,
                eventId: eventId,
              );
              if (prepared == null) {
                return ProtectedPreparedAuthorityGate.notProtected;
              }
              if (prepared.control !=
                  ProtectedGroupAuthorityControl.memberRole.wireValue) {
                return ProtectedPreparedAuthorityGate.retryable;
              }
              return await completeLocalProtectedAuthority(prepared)
                  ? ProtectedPreparedAuthorityGate.complete
                  : ProtectedPreparedAuthorityGate.retryable;
            },
      ),
    );
    setProtectedGroupAuthorityAdapter(
      prepare: (request) => runGroupAuthorityPhaseIfNeeded(
        groupId: request.groupId,
        authorityPhaseHeld: isGroupAuthorityPhaseHeld(request.groupId),
        action: () async {
          final aborted = await loadLocalAuthorityProof(
            groupId: request.groupId,
            phase: AuthenticatedGroupAuthorityPhase.aborted,
            eventId: request.transitionId,
          );
          if (aborted != null) {
            // An exact ABORTED fact permanently fences this deterministic
            // event address. Producers must mint a fresh authority version;
            // never recreate delivery rows beneath an abandoned PREPARED.
            return null;
          }
          if (request.control == ProtectedGroupAuthorityControl.groupDissolve) {
            final pendingDissolves =
                (await groupPendingBroadcastRepository.forGroup(
                      request.groupId,
                    ))
                    .map(
                      (row) => parseProtectedGroupAuthorityDeliveryId(
                        row.sourceMessageId ?? '',
                      ),
                    )
                    .whereType<ProtectedGroupAuthorityDeliveryIdentity>()
                    .where(
                      (identity) =>
                          identity.control ==
                          ProtectedGroupAuthorityControl.groupDissolve,
                    )
                    .map((identity) => identity.transitionId)
                    .toSet();
            if (pendingDissolves.any(
              (transitionId) => transitionId != request.transitionId,
            )) {
              // A prior custody-complete/pre-terminal crash owns recovery. Do
              // not mint a second terminal authority version while its exact
              // rows remain durable; the protected runner will finish it.
              return null;
            }
          }
          final replayKeyEpoch = request.replayData['keyGeneration'];
          final authorityKeyEpoch =
              request.control ==
                      ProtectedGroupAuthorityControl.groupKeyUpdate &&
                  replayKeyEpoch is int
              ? replayKeyEpoch
              : (await groupRepository.getLatestKey(
                  request.groupId,
                ))?.keyGeneration;
          if (authorityKeyEpoch == null || authorityKeyEpoch <= 0) {
            return ProtectedGroupAuthorityPreparation(
              groupId: request.groupId,
              rows: const <GroupPendingBroadcast>[],
            );
          }
          if (request.resumePreparedSurvivors) {
            if (request.control !=
                ProtectedGroupAuthorityControl.groupKeyUpdate) {
              return null;
            }
            final persistedProof = await loadLocalAuthorityProof(
              groupId: request.groupId,
              phase: AuthenticatedGroupAuthorityPhase.prepared,
              eventId: request.transitionId,
            );
            if (persistedProof != null) {
              return resumeProductionPreparedProtectedGroupKeyAuthority(
                persistedProof: persistedProof,
                request: request,
                keyEpoch: authorityKeyEpoch,
                pendingRepository: groupPendingBroadcastRepository,
              );
            }
          }
          final preparation = await buildProtectedGroupAuthorityRows(
            groupId: request.groupId,
            transitionId: request.transitionId,
            control: request.control,
            replayData: request.replayData,
            keyEpoch: authorityKeyEpoch,
            actorAccountPeerId: request.actorAccountPeerId,
            actorAccountPublicKey: request.actorAccountPublicKey,
            actorAccountPrivateKey: request.actorAccountPrivateKey,
            senderDevice: request.senderDevice,
            frozenRecipients: request.frozenRecipients,
            deliveryRecipients: request.deliveryRecipients,
            deliveryReplayDataByTransportPeerId:
                request.deliveryReplayDataByTransportPeerId,
            sharedAuthorityProof: request.sharedAuthorityProof,
            callSign: (data, privateKey) => callSignPayload(
              bridge: bridge,
              dataToSign: data,
              privateKey: privateKey,
            ),
            callEncrypt:
                ({required recipientMlKemPublicKey, required plaintext}) =>
                    callEncryptMessage(
                      bridge: bridge,
                      recipientMlKemPublicKey: recipientMlKemPublicKey,
                      plaintext: plaintext,
                    ),
          );
          final rows = preparation.rows;
          if (!preparation.hasAuthenticatedAuthority) return preparation;
          final persistence =
              await persistPreparedProtectedGroupAuthorityForRequest(
                repository: groupPendingBroadcastRepository,
                request: request,
                preparation: preparation,
              );
          if (persistence ==
              ProtectedGroupAuthorityPreparationPersistence.deferred) {
            return preparation;
          }
          if (persistence ==
              ProtectedGroupAuthorityPreparationPersistence.persisted) {
            return preparation;
          }

          final persistedProof = await loadLocalAuthorityProof(
            groupId: request.groupId,
            phase: AuthenticatedGroupAuthorityPhase.prepared,
            eventId: request.transitionId,
          );
          final persistedControl = persistedProof == null
              ? null
              : ProtectedGroupAuthorityControl.fromWire(persistedProof.control);
          if (persistedProof == null ||
              persistedControl != request.control ||
              !sameAuthenticatedGroupAuthorityProof(
                persistedProof,
                preparation.authorityProof!,
              )) {
            return null;
          }
          if (rows.isEmpty) {
            return ProtectedGroupAuthorityPreparation(
              groupId: request.groupId,
              rows: const <GroupPendingBroadcast>[],
              authorityProof: persistedProof,
              control: persistedControl,
              replayData: Map<String, dynamic>.from(preparation.replayData!),
            );
          }

          // A deterministic retry may re-mint after a crash while its earlier
          // exact bytes are still pending. Recover those persisted bytes by the
          // target-qualified identity and drain them; never overwrite them with
          // newly encrypted bytes sharing the same v86 source id.
          final expectedById = <String, GroupPendingBroadcast>{
            for (final row in rows) row.id: row,
          };
          final persisted = await groupPendingBroadcastRepository.forGroup(
            request.groupId,
          );
          final recovered = persisted
              .where((candidate) {
                final expected = expectedById[candidate.id];
                return expected != null &&
                    candidate.kind == expected.kind &&
                    candidate.groupId == expected.groupId &&
                    candidate.sourceMessageId == expected.sourceMessageId &&
                    candidate.recipientPeerIds.length == 1 &&
                    candidate.recipientPeerIds.single ==
                        expected.recipientPeerIds.single;
              })
              .toList(growable: false);
          if (recovered.length != rows.length) return null;
          return ProtectedGroupAuthorityPreparation(
            groupId: request.groupId,
            rows: recovered,
            authorityProof: persistedProof,
            control: persistedControl,
            replayData: Map<String, dynamic>.from(persistedProof.authorityData),
          );
        },
      ),
      activate: (preparation, {required requireAllCustody}) async {
        final proof = preparation.authorityProof;
        final control = preparation.control;
        if (proof == null ||
            control == null ||
            proof.control != control.wireValue) {
          return false;
        }
        if (control == ProtectedGroupAuthorityControl.groupDissolve) {
          return finalizeLocalProtectedDissolve(
            preparation.groupId,
            proof.eventId,
          );
        }
        if (!await runGroupAuthorityPhaseIfNeeded(
          groupId: preparation.groupId,
          authorityPhaseHeld: isGroupAuthorityPhaseHeld(preparation.groupId),
          action: () => completeLocalProtectedAuthority(proof),
        )) {
          return false;
        }
        await groupPendingBroadcastRunner.drainForGroup(preparation.groupId);
        if (!requireAllCustody) return true;
        final pending = await groupPendingBroadcastRepository.forGroup(
          preparation.groupId,
        );
        final pendingIds = pending.map((row) => row.id).toSet();
        return preparation.rows.every((row) => !pendingIds.contains(row.id));
      },
      cancel: (preparation) => runGroupAuthorityPhaseIfNeeded(
        groupId: preparation.groupId,
        authorityPhaseHeld: isGroupAuthorityPhaseHeld(preparation.groupId),
        action: () async {
          final proof = preparation.authorityProof;
          final control = preparation.control;
          if (proof == null ||
              control == null ||
              proof.groupId != preparation.groupId ||
              proof.control != control.wireValue) {
            return false;
          }
          final complete = await loadLocalAuthorityProof(
            groupId: preparation.groupId,
            phase: AuthenticatedGroupAuthorityPhase.complete,
            eventId: proof.eventId,
          );
          if (complete != null) return false;
          final prepared = await loadLocalAuthorityProof(
            groupId: preparation.groupId,
            phase: AuthenticatedGroupAuthorityPhase.prepared,
            eventId: proof.eventId,
          );
          if (prepared == null) {
            // Deferred metadata preparation deliberately has no durable owner
            // until its projection transaction commits. A pre-commit failure is
            // already durably absent and therefore needs no ABORTED fact.
            final pending = await groupPendingBroadcastRepository.forGroup(
              preparation.groupId,
            );
            final expectedIds = <String>{
              ...preparation.rows.map((row) => row.id),
              ...preparation.abortRows.map((row) => row.id),
            };
            return pending.every((row) => !expectedIds.contains(row.id));
          }
          if (!sameAuthenticatedGroupAuthorityProof(prepared, proof)) {
            return false;
          }
          final expectedRows = <String, GroupPendingBroadcast>{
            for (final row in preparation.rows) row.id: row,
            for (final row in preparation.abortRows) row.id: row,
          }.values.toList(growable: false);
          final aborted = await groupPendingBroadcastRepository
              .abortProtectedBatch(
                expectedRows,
                groupId: preparation.groupId,
                authorityPrepared: GroupPendingBroadcastAuthorityFact(
                  sourcePeerId: proof.actorAccountPeerId,
                  sourceEventId: authenticatedGroupAuthoritySourceEventId(
                    AuthenticatedGroupAuthorityPhase.prepared,
                    proof.eventId,
                  ),
                  sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
                  payload: authenticatedGroupAuthorityFactPayload(proof),
                ),
                authorityAborted: GroupPendingBroadcastAuthorityFact(
                  sourcePeerId: proof.actorAccountPeerId,
                  sourceEventId: authenticatedGroupAuthoritySourceEventId(
                    AuthenticatedGroupAuthorityPhase.aborted,
                    proof.eventId,
                  ),
                  sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
                  payload: authenticatedGroupAuthorityFactPayload(proof),
                ),
                authorityCompleteSourceEventId:
                    authenticatedGroupAuthoritySourceEventId(
                      AuthenticatedGroupAuthorityPhase.complete,
                      proof.eventId,
                    ),
              );
          return aborted == ProtectedGroupAuthorityAbortResult.aborted ||
              aborted == ProtectedGroupAuthorityAbortResult.alreadyAborted;
        },
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

    final protectedGroupAuthoritySupport =
        ProductionCanonicalProtectedGroupAuthoritySupport(
          database: db,
          bridge: bridge,
          groupRepository: groupRepository,
        );

    Future<bool> reconcileCompletedContentAuthority(
      AuthenticatedGroupAuthorityProof authority, {
      bool allowDominatingProjection = false,
    }) => protectedGroupAuthoritySupport.reconcileCompletedContentAuthority(
      authority,
      allowDominatingProjection: allowDominatingProjection,
    );

    // Local producers may commit authority COMPLETE atomically with their
    // projection. Repair the content frontier immediately after that commit;
    // the pending-authority scan below invokes the same seam for upgrade or
    // crash histories that predate this runtime.
    setReconcileCompletedProtectedGroupAuthority(
      groupRepository,
      reconcileCompletedContentAuthority,
    );

    Future<bool> hasUnfinishedProtectedContentAuthority(String groupId) =>
        protectedGroupAuthoritySupport.hasUnfinishedContentAuthority(groupId);

    Future<ProtectedGroupContentRetryAuthorityDisposition>
    classifyStrictGroupContentRetryAuthority({
      required String groupId,
      required GroupContentAuthorityVersion observedAuthority,
      required DateTime contentAt,
      required String contentEventId,
    }) => classifyProtectedGroupContentRetryAuthority(
      groupId: groupId,
      observedAuthority: observedAuthority,
      contentAt: contentAt,
      contentEventId: contentEventId,
      loadPreparedPage:
          ({afterSourceTimestamp, afterSourceEventId, required limit}) =>
              loadAuthenticatedGroupAuthorityProofPage(
                loadRows:
                    ({
                      required groupId,
                      required eventType,
                      afterSourceTimestamp,
                      afterSourceEventId,
                      throughSourceTimestamp,
                      required limit,
                    }) => dbLoadGroupEventLogTypePage(
                      db,
                      groupId: groupId,
                      eventType: eventType,
                      afterSourceTimestamp: afterSourceTimestamp,
                      afterSourceEventId: afterSourceEventId,
                      throughSourceTimestamp: throughSourceTimestamp,
                      newestFirst: true,
                      limit: limit,
                    ),
                groupId: groupId,
                phase: AuthenticatedGroupAuthorityPhase.prepared,
                verify:
                    ({required publicKey, required data, required signature}) =>
                        callVerifyPayload(
                          bridge: bridge,
                          publicKey: publicKey,
                          data: data,
                          signature: signature,
                        ),
                afterSourceTimestamp: afterSourceTimestamp,
                afterSourceEventId: afterSourceEventId,
                limit: limit,
              ),
      loadExactPhase: ({required phase, required eventId}) =>
          loadAuthenticatedGroupAuthorityProofFromEventLog(
            loadRow: ({required groupId, required sourceEventId}) =>
                dbLoadGroupEventLogEntryExact(
                  db,
                  groupId: groupId,
                  sourceEventId: sourceEventId,
                ),
            groupId: groupId,
            phase: phase,
            eventId: eventId,
            verify: ({required publicKey, required data, required signature}) =>
                callVerifyPayload(
                  bridge: bridge,
                  publicKey: publicKey,
                  data: data,
                  signature: signature,
                ),
          ),
      loadReconciliationRow: (authorityEventId) =>
          dbLoadGroupEventLogEntryExact(
            db,
            groupId: groupId,
            sourceEventId:
                protectedGroupContentReconciliationCompleteSourceEventId(
                  authorityEventId,
                ),
          ),
    );

    Future<AuthenticatedGroupAuthorityProof?>
    loadLatestSettledProtectedContentAuthority(String groupId) async {
      if (await hasUnfinishedProtectedContentAuthority(groupId)) return null;
      Future<AuthenticatedGroupAuthorityProof?> latest(
        AuthenticatedGroupAuthorityPhase phase,
      ) async {
        final page = await loadAuthenticatedGroupAuthorityProofPage(
          loadRows:
              ({
                required groupId,
                required eventType,
                afterSourceTimestamp,
                afterSourceEventId,
                throughSourceTimestamp,
                required limit,
              }) => dbLoadGroupEventLogTypePage(
                db,
                groupId: groupId,
                eventType: eventType,
                afterSourceTimestamp: afterSourceTimestamp,
                afterSourceEventId: afterSourceEventId,
                throughSourceTimestamp: throughSourceTimestamp,
                newestFirst: true,
                limit: limit,
              ),
          groupId: groupId,
          phase: phase,
          verify: ({required publicKey, required data, required signature}) =>
              callVerifyPayload(
                bridge: bridge,
                publicKey: publicKey,
                data: data,
                signature: signature,
              ),
          limit: 1,
        );
        return page.isEmpty ? null : page.single;
      }

      final complete = await latest(AuthenticatedGroupAuthorityPhase.complete);
      final genesis = await latest(AuthenticatedGroupAuthorityPhase.genesis);
      var selected = complete;
      if (selected == null ||
          (genesis != null &&
              (genesis.eventAt.isAfter(selected.eventAt) ||
                  (genesis.eventAt == selected.eventAt &&
                      genesis.eventId.compareTo(selected.eventId) > 0)))) {
        selected = genesis;
      }
      if (selected == null) return null;
      if (complete != null && identical(selected, complete)) {
        final reconciliation = await dbLoadGroupEventLogEntryExact(
          db,
          groupId: groupId,
          sourceEventId:
              protectedGroupContentReconciliationCompleteSourceEventId(
                selected.eventId,
              ),
        );
        if (!isProtectedGroupContentReconciliationCompleteRow(
          reconciliation,
          authority: selected,
        )) {
          return null;
        }
      }
      final currentKey = await groupRepository.getLatestKey(groupId);
      return currentKey?.keyGeneration == selected.keyEpoch ? selected : null;
    }

    Future<GroupNotificationSenderAuthority?>
    loadCurrentGroupNotificationSenderAuthority(String groupId) async {
      final proof = await loadLatestSettledProtectedContentAuthority(groupId);
      if (proof == null) return null;
      final tuples = <GroupNotificationSenderAuthorityTuple>[];
      for (final member in await groupRepository.getMembers(groupId)) {
        for (final device in member.activeDevicesWithLegacyFallback()) {
          if (!device.isActive ||
              member.peerId.trim().isEmpty ||
              device.deviceId.trim().isEmpty ||
              device.transportPeerId.trim().isEmpty ||
              device.deviceSigningPublicKey.trim().isEmpty) {
            continue;
          }
          tuples.add(
            GroupNotificationSenderAuthorityTuple(
              logicalSender: member.peerId,
              deviceId: device.deviceId,
              transportPeerId: device.transportPeerId,
              signingPublicKey: device.deviceSigningPublicKey,
            ),
          );
        }
      }
      if (tuples.isEmpty) return null;
      return GroupNotificationSenderAuthority(
        authorityEventAt: fixedGroupAuthorityUtc(proof.eventAt),
        authorityEventId: proof.eventId,
        keyEpoch: proof.keyEpoch,
        tuples: tuples,
      );
    }

    groupRepository.setGroupNotificationSenderAuthorityLoader(
      loadCurrentGroupNotificationSenderAuthority,
    );
    keychainMirrorBackfill = (keychainMirrorBackfill ?? Future<void>.value())
        .then(
          (_) => groupRepository.mirrorAllGroupNotificationSenderAuthorities(),
        );

    Future<bool> isLinkedGroupAuthoritySettled(String groupId) async =>
        await loadLatestSettledProtectedContentAuthority(groupId) != null;

    final resolveGroupContentAuthoringForSend =
        buildProtectedGroupContentAuthoringResolver(
          loadIdentity: () async {
            final identity = await repository.loadIdentity();
            return identity == null
                ? null
                : (peerId: identity.peerId, publicKey: identity.publicKey);
          },
          loadMember: groupRepository.getMember,
          loadInstallationAuthority: (expectedAccountPeerId) =>
              linkedInstallationAuthority.load(
                expectedAccountPeerId: expectedAccountPeerId,
              ),
          loadLatestSettledAuthority:
              loadLatestSettledProtectedContentAuthority,
          readCurrentTransportPeerId: () => p2pService.currentState.peerId,
          inboxStore: p2pService,
          directLinkedDeviceSelector: const DirectLinkedDeviceSelector(),
          multiDeviceSyncEnabled: kMultiDeviceSyncEnabled,
        );

    setGroupContentAuthoringResolver(
      groupRepository,
      resolveGroupContentAuthoringForSend,
    );

    Future<List<Map<String, Object?>>> loadLinkedProtectedEventRows(
      String groupId,
      String eventType,
    ) async {
      final rows = <Map<String, Object?>>[];
      String? afterAt;
      String? afterId;
      while (true) {
        final next = await dbLoadGroupEventLogTypePage(
          db,
          groupId: groupId,
          eventType: eventType,
          afterSourceTimestamp: afterAt,
          afterSourceEventId: afterId,
          newestFirst: true,
          limit: 200,
        );
        rows.addAll(next);
        if (next.length < 200) return rows;
        final nextAt = next.last['source_timestamp'] as String?;
        final nextId = next.last['source_event_id'] as String?;
        if (nextAt == null ||
            nextId == null ||
            (nextAt == afterAt && nextId == afterId)) {
          throw StateError('linked protected event history cursor stalled');
        }
        afterAt = nextAt;
        afterId = nextId;
      }
    }

    // 363/364: the protected P2P coordinator owns stage-before-handler and
    // handler-before-ACK. Installing this callback does not start group topic,
    // history, invite, notification, or content listeners on a linked role.
    final protectedGroupReplay =
        ProductionCanonicalProtectedGroupReplayComposition(
          database: db,
          bridge: bridge,
          groupRepository: groupRepository,
          groupMessageListener: groupMessageListener,
          groupKeyUpdateListener: groupKeyUpdateListener,
          authoritySupport: protectedGroupAuthoritySupport,
          loadIdentity: repository.loadIdentity,
          loadLinkedAuthority: (expectedAccountPeerId) =>
              linkedInstallationAuthority.load(
                expectedAccountPeerId: expectedAccountPeerId,
              ),
          applySystemAuthorityReplay: applyLocalProtectedSystemAuthorityReplay,
          retryPendingKeyRepairs:
              groupPendingKeyRepairRunner.retryPendingRepairsForRequest,
        );
    p2pService.setProtectedGroupReplayHandler(protectedGroupReplay.replay);

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
    // 361: the restricted linked drain — EXACT nonnull-v113 blob-free rows
    // only, never a broad historical/media/private loader. Durable rows drain
    // even with the authoring selector OFF.
    Future<int> drainDirectBlobFreeLinkedOutboxes() =>
        runAccountRuntimeNetworkAction<int>(
          operation: 'direct_blob_free_linked_fanout_drain',
          blockedValue: 0,
          action: () => drainDirectBlobFreeLinkedEventFanout(
            loadExactTextFanoutRows: () =>
                dbLoadDirectInboxCustodyOutboxExactFanoutRows(db),
            loadExactEventFanoutRows: () =>
                dbLoadDirectReactionInboxCustodyOutboxExactFanoutRows(db),
            custodyRepository: messageRepository,
            storeInAckCustodyInboxDetailed:
                p2pService.storeInAckCustodyInboxDetailed,
            mutationCustodyRepository: messageRepository,
            reactionCustodyRepository: reactionRepository,
          ),
        );

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
    final groupInboxRetryFairnessCursor = GroupInboxRetryFairnessCursor();
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
          groupContentInboxStore: p2pService,
          classifyStrictContentAuthority:
              classifyStrictGroupContentRetryAuthority,
          classifyStrictReactionTarget:
              ({required groupId, required messageId}) =>
                  dbClassifyProtectedGroupReactionTargetWithEvidence(
                    db,
                    groupId: groupId,
                    messageId: messageId,
                  ),
          fairnessCursor: groupInboxRetryFairnessCursor,
          inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
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
      drainNotificationCompletedOutcomesFn: drainNotificationCompletedOutcomes,
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
      await liveServiceStartupSteps.runAsync(
        'group_media_blob_local_cleanup',
        cleanupGroupMediaBlobCustodyLocally,
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

    Future<int> drainLinkedGroupOutgoingMediaCustody() =>
        linkedGroupContentQuiescence.runOutgoing(
          blockedValue: 0,
          operation: () => runAccountRuntimeNetworkAction(
            operation: 'linked_group_media_blob_outgoing_drain',
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
                    source: MediaUploadTriggerSource.resume,
                  ),
              releaseUploadLease: mediaUploadInFlightTracker.release,
              preparedGroupMediaBlobCustodyCoordinator:
                  preparedGroupMediaBlobCustodyCoordinator,
              strictGroupCustodyOnly: true,
            ),
          ),
        );

    Future<int> drainLinkedGroupIncomingMediaCustody() =>
        runAccountRuntimeNetworkAction(
          operation: 'linked_group_media_blob_incoming_drain',
          blockedValue: 0,
          action: groupMediaDownloadCoordinator.callStrictGroupMediaCustodyOnly,
        );

    // 360: the deferred runtime start is decided by persisted installation
    // ROLE, before the router. An ordinary primary keeps calling
    // `startLiveServicesIfAllowed` unchanged; an active linked secondary
    // starts only the bridge, which is the sole prerequisite its
    // node/status/QR owners need. Generic runtime startup — Firebase, push
    // registration, the listener fleet, contact/key-exchange retry, group
    // recovery, message retry and inbox drain — runs ZERO times in linked
    // mode, because every one of those owners assumes a single primary
    // installation on one account mailbox. Plan 361 makes them device-aware.
    final roleAwareDeferredRuntimeStart = RoleAwareDeferredRuntimeStart(
      hasIdentity: () async => await repository.loadIdentity() != null,
      // 360: bind the load to the CURRENT account peer. Without the expected
      // peer, a credential bound to a different logical account resolves as a
      // usable `active` snapshot instead of `failClosed`, and this installation
      // would start a transport that belongs to someone else's account.
      loadLinkedAuthority: () async {
        final identity = await repository.loadIdentity();
        // 361: cache the account peer for the route-push fanout resolver.
        lastKnownAccountPeerId = identity?.peerId;
        return linkedInstallationAuthority.load(
          expectedAccountPeerId: identity?.peerId,
        );
      },
      startPrimaryRuntimeServices: startLiveServicesIfAllowed,
      // 361: the restricted linked runtime starts ONLY the exact direct
      // blob-free owners — router, chat/reaction/deletion/receipt listeners,
      // one exact inbox replay pass, and the exact v113 fanout drain. It
      // deliberately never calls the generic startLiveServices.
      startLinkedFoundationPrerequisites: () async {
        StartupTiming.instance.mark('bridge_initialized');
        final linkedServices = DirectBlobFreeLinkedServices(
          initializeBridge: bridge.initialize,
          startMessageRouter: messageRouter.start,
          startChatMessageListener: chatMessageListener.start,
          startReactionListener: reactionListener.start,
          startMessageDeletionListener: messageDeletionListener.start,
          startDeliveryReceiptListener: deliveryReceiptListener.start,
          startLinkedTransport: () async {
            final identity = await repository.loadIdentity();
            if (identity == null) return false;
            final authority = await linkedInstallationAuthority.load(
              expectedAccountPeerId: identity.peerId,
            );
            // The role-aware owner selected this branch from an ACTIVE snapshot,
            // but authority is storage-backed and can change before node start.
            // Re-read and refuse rather than ever falling back to the account
            // transport on a linked-runtime path.
            if (!authority.isActiveLinkedSecondary) return false;
            final expectedTransportPeerId =
                authority.credential?.transportPeerId;
            final currentNode = p2pService.currentState;
            if (expectedTransportPeerId != null &&
                currentNode.isStarted &&
                currentNode.peerId == expectedTransportPeerId) {
              return true;
            }
            final result = await startP2PNode(
              identityRepo: repository,
              p2pService: p2pService,
              accountMigrationNetworkGate: accountMigrationRuntimeNetworkGate
                  .allowsAccountNetworkSideEffects,
              linkedAuthority: authority,
            );
            return result == StartNodeResult.success;
          },
          afterLinkedTransportQualified:
              kWakeOutcomeCoordinatorAdmissionEnabled &&
                  !kIsWeb &&
                  (Platform.isIOS || Platform.isAndroid)
              ? () async {
                  // Role-gated: runs only after the linked transport peer has
                  // qualified. The exact consumer/binding read-back precedes
                  // any Firebase or registration work, and the same one
                  // coordinator owns the pair-only registration frame.
                  final platformName = currentPushPlatformName();
                  if (!await opaqueWakePlatformConsumerReadiness.isReadyFor(
                    platformName,
                  )) {
                    throw StateError(
                      'linked $platformName opaque-wake consumer is not ready',
                    );
                  }
                  await ensureFirebaseReady();
                  if (!firebaseReadiness.isReady) {
                    throw StateError(
                      'linked $platformName Firebase is not ready',
                    );
                  }
                  final registration = pushRegistrationCoordinator;
                  if (registration == null) {
                    throw StateError(
                      'linked $platformName push registration owner is '
                      'unavailable',
                    );
                  }
                  await registration.ensureStarted();
                }
              : null,
          drainOfflineInbox: p2pService.drainOfflineInbox,
          drainExactBlobFreeFanoutOutboxes: drainDirectBlobFreeLinkedOutboxes,
          drainLinkedDirectMediaBlobCustody: drainLinkedDirectMediaBlobCustody,
          materializeLinkedGroupBootstrap: p2pService.drainOfflineInbox,
          replayLinkedGroupAuthority: p2pService.drainOfflineInbox,
          pauseLinkedGroupContentAdmission: linkedGroupContentQuiescence.pause,
          resumeLinkedGroupContentAdmission: (contentPause) =>
              contentPause.resume(),
          replayLinkedGroupContent:
              p2pService.drainProtectedGroupContentFixedPoint,
          drainLinkedGroupOutgoingMedia: drainLinkedGroupOutgoingMediaCustody,
          drainLinkedGroupIncomingMedia: drainLinkedGroupIncomingMediaCustody,
          retryLinkedGroupContent: () =>
              linkedGroupContentQuiescence.runOutgoing<int>(
                blockedValue: 0,
                operation: () => runAccountRuntimeNetworkAction(
                  operation: 'linked_group_content_retry',
                  blockedValue: 0,
                  action: () => retryFailedGroupInboxStores(
                    bridge: bridge,
                    msgRepo: groupMessageRepository,
                    reactionReplayOutboxRepo:
                        groupReactionReplayOutboxRepository,
                    groupRepo: groupRepository,
                    identityRepo: repository,
                    groupContentInboxStore: p2pService,
                    classifyStrictContentAuthority:
                        classifyStrictGroupContentRetryAuthority,
                    classifyStrictReactionTarget:
                        ({required groupId, required messageId}) =>
                            dbClassifyProtectedGroupReactionTargetWithEvidence(
                              db,
                              groupId: groupId,
                              messageId: messageId,
                            ),
                    fairnessCursor: groupInboxRetryFairnessCursor,
                    inviteDeliveryAttemptRepo:
                        groupInviteDeliveryAttemptRepository,
                    strictContentOnly: true,
                  ),
                ),
              ),
          drainLinkedGroupNotificationDisplayCustody:
              groupMessageListener.retryPendingNotificationDisplays,
          refreshLinkedGroupList: refreshLinkedGroupStatusProjection,
        );
        return linkedServices.start();
      },
    );
    // Publish it to the P2P service's transport-peer qualifier.
    roleAwareDeferredRuntimeStartRef = roleAwareDeferredRuntimeStart;

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

      final linkedGroupMediaVoiceActionOwner = LinkedGroupMediaVoiceActionOwner(
        bridge: bridge,
        groupRepository: groupRepository,
        messageRepository: groupMessageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        preparedCustodyCoordinator: preparedGroupMediaBlobCustodyCoordinator,
        inviteDeliveryAttemptRepository: groupInviteDeliveryAttemptRepository,
        imageProcessor: imageProcessor,
        audioRecorderService: audioRecorderService,
        loadIdentity: () async {
          final identity = await repository.loadIdentity();
          return identity == null
              ? null
              : LinkedGroupMediaAuthorIdentity(
                  peerId: identity.peerId,
                  publicKey: identity.publicKey,
                  privateKey: identity.privateKey,
                  username: identity.username,
                );
        },
        retryStrictOutgoing: drainLinkedGroupOutgoingMediaCustody,
        retryStrictIncoming: drainLinkedGroupIncomingMediaCustody,
        refreshProjection: refreshLinkedGroupStatusProjection,
      );
      Future<bool> runLinkedGroupMediaAuthorAction(
        Future<bool> Function() operation,
      ) => linkedGroupContentQuiescence.runOutgoing(
        blockedValue: false,
        operation: operation,
      );

      return MyApp(
        repository: repository,
        // 360: the real database-backed linked-device trust authority. The
        // contact profile is the only surface that admits or withdraws a
        // device, and it requires a non-null capability.
        directDeviceTrust: DatabaseDirectContactDeviceTrust(
          database: db,
          notificationProjection: directReactionNotificationProjection,
        ),
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
        drainNotificationCompletedOutcomes: drainNotificationCompletedOutcomes,
        // 361: blob-free fanout authoring plus the restricted linked runtime
        // seams. The resolver builds the authoring owner at route-push time so
        // role facts and the local transport identity are current; a
        // pre-identity call yields null (incumbent senders).
        directEventFanoutResolver: () {
          final linkedTransport =
              roleAwareDeferredRuntimeStart.activeLinkedTransportPeerId;
          final senderTransport = linkedTransport ?? lastKnownAccountPeerId;
          if (senderTransport == null || senderTransport.isEmpty) return null;
          return DirectEventFanoutAuthoring(
            selector: const DirectLinkedEventFanoutSelector(),
            linkedOrigin: linkedTransport != null,
            senderTransportPeerId: senderTransport,
            readSnapshot: messageRepository.readDirectContactFanoutSnapshot,
            encrypt:
                ({required recipientMlKemPublicKey, required plaintext}) async {
                  final result = await callEncryptMessage(
                    bridge: bridge,
                    recipientMlKemPublicKey: recipientMlKemPublicKey,
                    plaintext: plaintext,
                  );
                  if (result['ok'] != true) return null;
                  return (
                    kem: result['kem'] as String,
                    ciphertext: result['ciphertext'] as String,
                    nonce: result['nonce'] as String,
                  );
                },
            loadTextSiblings: messageRepository.loadDirectTextFanoutSiblings,
            stageTextFanout: messageRepository.stageDirectTextFanout,
            loadEventSiblings: messageRepository.loadDirectEventFanoutSiblings,
            stageMutationFanout:
                messageRepository.stageDirectTextMutationFanout,
            stageReactionFanout: reactionRepository.stageDirectReactionFanout,
          );
        },
        isLinkedBlobFreeRuntime: () =>
            roleAwareDeferredRuntimeStart.activeLinkedTransportPeerId != null,
        drainDirectBlobFreeLinkedOutboxes: drainDirectBlobFreeLinkedOutboxes,
        drainDirectMediaBlobCustody: drainDirectMediaBlobCustody,
        // 362: the linked-scoped converger; distinct from the unrestricted
        // drain on the line above, which stays the primary's.
        drainLinkedDirectMediaBlobCustody: drainLinkedDirectMediaBlobCustody,
        drainLinkedGroupBootstrap: p2pService.drainOfflineInbox,
        replayLinkedGroupAuthority: p2pService.drainOfflineInbox,
        pauseLinkedGroupContentAdmission: linkedGroupContentQuiescence.pause,
        resumeLinkedGroupContentAdmission: (contentPause) =>
            contentPause.resume(),
        replayLinkedGroupContent:
            p2pService.drainProtectedGroupContentFixedPoint,
        drainLinkedGroupOutgoingMedia: drainLinkedGroupOutgoingMediaCustody,
        drainLinkedGroupIncomingMedia: drainLinkedGroupIncomingMediaCustody,
        retryLinkedGroupContent: () =>
            linkedGroupContentQuiescence.runOutgoing<int>(
              blockedValue: 0,
              operation: () => runAccountRuntimeNetworkAction(
                operation: 'linked_group_content_retry',
                blockedValue: 0,
                action: () => retryFailedGroupInboxStores(
                  bridge: bridge,
                  msgRepo: groupMessageRepository,
                  reactionReplayOutboxRepo: groupReactionReplayOutboxRepository,
                  groupRepo: groupRepository,
                  identityRepo: repository,
                  groupContentInboxStore: p2pService,
                  classifyStrictContentAuthority:
                      classifyStrictGroupContentRetryAuthority,
                  classifyStrictReactionTarget:
                      ({required groupId, required messageId}) =>
                          dbClassifyProtectedGroupReactionTargetWithEvidence(
                            db,
                            groupId: groupId,
                            messageId: messageId,
                          ),
                  fairnessCursor: groupInboxRetryFairnessCursor,
                  inviteDeliveryAttemptRepo:
                      groupInviteDeliveryAttemptRepository,
                  strictContentOnly: true,
                ),
              ),
            ),
        isLinkedGroupAuthoritySettled: isLinkedGroupAuthoritySettled,
        linkedGroupConversationBuilder: (context, group) =>
            LinkedGroupConversationWired(
              group: group,
              loadCurrentGroup: groupRepository.getGroup,
              backgroundPreference: appShellController.backgroundPreference,
              groupConversationTracker: groupConversationTracker,
              isAuthoritySettled: isLinkedGroupAuthoritySettled,
              canAuthorProtectedContent: (groupId) async {
                final identity = await repository.loadIdentity();
                if (identity == null) return false;
                final resolution = await resolveGroupContentAuthoringForSend(
                  groupId: groupId,
                  senderPeerId: identity.peerId,
                  senderPublicKey: identity.publicKey,
                  senderDeviceId: null,
                  senderTransportPeerId: null,
                );
                final authoring = resolution.context;
                return resolution.kind ==
                        GroupContentAuthoringResolutionKind.strict &&
                    authoring != null &&
                    authoring.requireLinkedTransportCredential &&
                    authoring.linkedTransportCredential?.state ==
                        LinkedTransportCredentialState.active &&
                    authoring
                        .directLinkedDeviceSelector
                        .allowsLinkedDeviceAuthoring &&
                    authoring.multiDeviceSyncEnabled &&
                    authoring.authorityVersion != null &&
                    authoring.inboxStore != null;
              },
              loadProtectedMessages: (groupId) async {
                final terminalRows = await loadLinkedProtectedEventRows(
                  groupId,
                  protectedGroupContentTerminalEventType,
                );
                final messages = await groupMessageRepository.getMessagesPage(
                  groupId,
                  limit: 100,
                );
                final protected = <GroupMessage>[];
                for (final message in messages) {
                  final attachments = await mediaAttachmentRepository
                      .getAttachmentsForMessage(
                        message.id,
                        owner: MediaOwnerLane.group,
                      );
                  final evidence = await dbLoadGroupEventLogEntryExact(
                    db,
                    groupId: groupId,
                    sourceEventId: protectedGroupMessageSourceEventId(
                      message.id,
                    ),
                  );
                  if (isExactLinkedProtectedMessageEvidence(
                    groupId: groupId,
                    message: message,
                    evidenceRow: evidence,
                    terminalRows: terminalRows,
                    media: attachments,
                  )) {
                    protected.add(message);
                  }
                }
                return protected;
              },
              loadProtectedMedia: (messageIds) async {
                final terminalRows = await loadLinkedProtectedEventRows(
                  group.id,
                  protectedGroupContentTerminalEventType,
                );
                final protected = <String, List<MediaAttachment>>{};
                for (final messageId in messageIds.toSet()) {
                  final message = await groupMessageRepository.getMessage(
                    messageId,
                  );
                  if (message == null || message.groupId != group.id) continue;
                  final attachments = await mediaAttachmentRepository
                      .getAttachmentsForMessage(
                        messageId,
                        owner: MediaOwnerLane.group,
                      );
                  if (attachments.isEmpty) continue;
                  final evidence = await dbLoadGroupEventLogEntryExact(
                    db,
                    groupId: group.id,
                    sourceEventId: protectedGroupMessageSourceEventId(
                      messageId,
                    ),
                  );
                  if (isExactLinkedProtectedMessageEvidence(
                    groupId: group.id,
                    message: message,
                    evidenceRow: evidence,
                    terminalRows: terminalRows,
                    media: attachments,
                  )) {
                    protected[messageId] = attachments;
                  }
                }
                return protected;
              },
              loadProtectedReactions: (messageIds) async {
                final loaded = await reactionRepository.getReactionsForMessages(
                  messageIds,
                );
                final evidenceRows = await loadLinkedProtectedEventRows(
                  group.id,
                  protectedGroupReactionEventType,
                );
                final terminalRows = await loadLinkedProtectedEventRows(
                  group.id,
                  protectedGroupContentTerminalEventType,
                );
                return <String, List<MessageReaction>>{
                  for (final entry in loaded.entries)
                    entry.key: entry.value
                        .where(
                          (reaction) => isExactLinkedProtectedReactionEvidence(
                            groupId: group.id,
                            reaction: reaction,
                            evidenceRows: evidenceRows,
                            terminalRows: terminalRows,
                          ),
                        )
                        .toList(growable: false),
                };
              },
              markVisibleMessagesRead: (groupId, messageIds) async {
                final exactIds = messageIds
                    .map((messageId) => messageId.trim())
                    .where((messageId) => messageId.isNotEmpty)
                    .toSet()
                    .toList(growable: false);
                if (exactIds.isEmpty) return;
                final placeholders = List.filled(
                  exactIds.length,
                  '?',
                ).join(',');
                await db.rawUpdate(
                  'UPDATE group_messages '
                  'SET read_at = COALESCE(read_at, ?) '
                  'WHERE group_id = ? AND is_incoming = 1 '
                  'AND read_at IS NULL AND id IN ($placeholders)',
                  <Object?>[
                    DateTime.now().toUtc().toIso8601String(),
                    groupId,
                    ...exactIds,
                  ],
                );
                emitGroupNotificationReconciliationSignal(groupId);
                // The generic group listener owner is intentionally not started
                // on linked installations. Drive the durable reconciliation
                // explicitly so opening this narrow route retires its OS card.
                await groupMessageListener.retryPendingNotificationDisplays();
                await refreshLinkedGroupStatusProjection();
              },
              sendProtectedText: (groupId, text) =>
                  linkedGroupContentQuiescence.runOutgoing<bool>(
                    blockedValue: false,
                    operation: () async {
                      final identity = await repository.loadIdentity();
                      if (identity == null) return false;
                      final result = await sendGroupMessage(
                        bridge: bridge,
                        groupRepo: groupRepository,
                        msgRepo: groupMessageRepository,
                        groupId: groupId,
                        text: text,
                        senderPeerId: identity.peerId,
                        senderPublicKey: identity.publicKey,
                        senderPrivateKey: identity.privateKey,
                        senderUsername: identity.username,
                        inviteDeliveryAttemptRepo:
                            groupInviteDeliveryAttemptRepository,
                      );
                      await refreshLinkedGroupStatusProjection();
                      return result.$2 != null;
                    },
                  ),
              attachOrdinaryMedia: (groupId) => runLinkedGroupMediaAuthorAction(
                () => linkedGroupMediaVoiceActionOwner.attachOrdinaryMedia(
                  groupId,
                ),
              ),
              startVoiceRecording: (groupId) => runLinkedGroupMediaAuthorAction(
                () => linkedGroupMediaVoiceActionOwner.startVoiceRecording(
                  groupId,
                ),
              ),
              stopVoiceRecording: (groupId) => runLinkedGroupMediaAuthorAction(
                () => linkedGroupMediaVoiceActionOwner.stopVoiceRecording(
                  groupId,
                ),
              ),
              cancelVoiceRecording:
                  linkedGroupMediaVoiceActionOwner.cancelVoiceRecording,
              retryOrdinaryMedia:
                  linkedGroupMediaVoiceActionOwner.retryOrdinaryMedia,
              toggleProtectedReaction:
                  ({
                    required groupId,
                    required message,
                    required emoji,
                    required remove,
                  }) => linkedGroupContentQuiescence.runOutgoing<bool>(
                    blockedValue: false,
                    operation: () async {
                      final identity = await repository.loadIdentity();
                      if (identity == null) return false;
                      if (remove) {
                        final result = await removeGroupReaction(
                          bridge: bridge,
                          groupRepo: groupRepository,
                          reactionRepo: reactionRepository,
                          reactionReplayOutboxRepo:
                              groupReactionReplayOutboxRepository,
                          groupId: groupId,
                          messageId: message.id,
                          emoji: emoji,
                          senderPeerId: identity.peerId,
                          senderPublicKey: identity.publicKey,
                          senderPrivateKey: identity.privateKey,
                          msgRepo: groupMessageRepository,
                          inviteDeliveryAttemptRepo:
                              groupInviteDeliveryAttemptRepository,
                          targetMessage: message,
                        );
                        await refreshLinkedGroupStatusProjection();
                        return result == RemoveGroupReactionResult.success ||
                            result == RemoveGroupReactionResult.queuedForRetry;
                      }
                      final result = await sendGroupReaction(
                        bridge: bridge,
                        groupRepo: groupRepository,
                        msgRepo: groupMessageRepository,
                        reactionRepo: reactionRepository,
                        reactionReplayOutboxRepo:
                            groupReactionReplayOutboxRepository,
                        groupId: groupId,
                        messageId: message.id,
                        emoji: emoji,
                        senderPeerId: identity.peerId,
                        senderPublicKey: identity.publicKey,
                        senderPrivateKey: identity.privateKey,
                        inviteDeliveryAttemptRepo:
                            groupInviteDeliveryAttemptRepository,
                      );
                      await refreshLinkedGroupStatusProjection();
                      return result.$2 != null;
                    },
                  ),
            ),
        drainLinkedGroupNotificationDisplayCustody:
            groupMessageListener.retryPendingNotificationDisplays,
        refreshLinkedGroupList: refreshLinkedGroupStatusProjection,
        flushLinkedGroupAuthorityOnPause: () async {
          await groupPendingBroadcastRunner.drainProtectedAll();
        },
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
        appVisibilityAuthority: appVisibilityAuthority,
        appVisibilityRouteRegistry: appVisibilityRouteRegistry,
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
        // 360: the linked-DESTINATION refusal must be on the REAL journey, not
        // only on an injected helper. A linked secondary is a restricted role,
        // not a second primary, so it can never receive an account import —
        // that would leave one installation holding both a promoted primary
        // identity and a transport credential contacts have already bound
        // device rows to. Checked BEFORE the receiver starts, and the
        // linked-role check inside the precondition deliberately runs ahead of
        // the explicit-erase escape hatch, because erasing a migrated-out
        // account does not retire linked authority.
        accountMigrationStartReceiver: (output) async {
          final precondition = await evaluateAccountMigrationImportPrecondition(
            identityRepository: repository,
            authorityRepository:
                SecureKeyStoreAccountMigrationAuthorityRepository(
                  secureKeyStore: secureKeyStore,
                ),
            explicitErasePreconditionSatisfied: true,
            linkedInstallationAuthority: linkedInstallationAuthority,
          );
          if (precondition.status ==
              AccountMigrationImportPreconditionStatus
                  .linkedSecondaryInstallation) {
            return const AccountMigrationReceiverStartResult.failure(
              code:
                  AccountMigrationReceiverStartFailureCode.receiverUnavailable,
              safeMessage:
                  'This device is set up as a linked device, so it cannot '
                  'receive an account. Use a phone that is not linked.',
            );
          }
          return accountMigrationTransferRuntime.startNewPhoneReceiver(output);
        },
        accountMigrationStopReceiver:
            accountMigrationTransferRuntime.stopNewPhoneReceiver,
        accountMigrationReceiverEvents:
            accountMigrationTransferRuntime.receiverEvents,
        retireCanonicalNotificationBinding:
            canonicalRuntimeBindingCoordinator == null &&
                iosNseInboxTransportProjection == null
            ? null
            : () async {
                await iosNseInboxTransportProjection?.retireAndReadBack();
                await canonicalRuntimeBindingCoordinator?.retireAccount();
              },
        retireIosNseInboxTransport: iosNseTransportAdmissionActive
            ? iosNseInboxTransportProjection.retireAndReadBack
            : null,
        accountMigrationRecoverExportPause: () async {
          if (accountMigrationTransferRuntime.hasActiveExportRun) {
            return false;
          }
          return accountMigrationCutoverCoordinator
              .restoreActiveAfterExportInterrupted();
        },
        deferredRuntimeStartup: roleAwareDeferredRuntimeStart.start,
        ingestStagedPushEnvelopes: ({required String source}) async {
          final result = await ingestStagedPushEnvelopesUseCase(source: source);
          return result.isCanonicalStateComplete;
        },
        firebaseReadiness: firebaseReadiness,
        mayArmPushListeners: () {
          return switch (roleAwareDeferredRuntimeStart.lastOutcome) {
            RoleAwareRuntimeStartOutcome.primaryRuntimeStarted => true,
            RoleAwareRuntimeStartOutcome.linkedFoundationStarted =>
              kWakeOutcomeCoordinatorAdmissionEnabled &&
                  !kIsWeb &&
                  (Platform.isIOS || Platform.isAndroid),
            _ => false,
          };
        },
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
