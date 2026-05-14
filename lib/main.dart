import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/share/application/handle_share_intent_use_case.dart';
import 'package:flutter_app/features/share/presentation/navigation/share_target_picker_route.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/042_media_attachment_reliability_columns.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/database/migrations/012_transport_column.dart';
import 'package:flutter_app/core/database/migrations/013_waveform_column.dart';
import 'package:flutter_app/core/database/migrations/014_wire_envelope_column.dart';
import 'package:flutter_app/core/database/migrations/015_message_status_cleanup.dart';
import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_consumptions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_revocations_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_welcome_key_package_tombstones_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_invites_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/019_introductions_table.dart';
import 'package:flutter_app/core/database/migrations/020_intro_banner_columns.dart';
import 'package:flutter_app/core/database/migrations/021_contact_introduced_by.dart';
import 'package:flutter_app/core/database/migrations/022_introduction_keys.dart';
import 'package:flutter_app/core/database/migrations/023_introduction_recipient_keys.dart';
import 'package:flutter_app/core/database/migrations/024_contact_introduced_by_peer_id.dart';
import 'package:flutter_app/core/database/migrations/025_introduction_already_connected_status.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/031_posts_pins.dart';
import 'package:flutter_app/core/database/migrations/032_posts_retry_recipient_context.dart';
import 'package:flutter_app/core/database/migrations/033_posts_follow_on_outbox.dart';
import 'package:flutter_app/core/database/migrations/034_posts_media_upload_recovery.dart';
import 'package:flutter_app/core/database/migrations/035_posts_repost_delivery_state.dart';
import 'package:flutter_app/core/database/migrations/036_posts_pass_encrypted_snapshots.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/038_posts_repost_media_crypto.dart';
import 'package:flutter_app/core/database/migrations/039_posts_pass_avatar_snapshots.dart';
import 'package:flutter_app/core/database/migrations/040_posts_repost_visual_metrics.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';
import 'package:flutter_app/core/database/migrations/043_messages_edited_at.dart';
import 'package:flutter_app/core/database/migrations/044_messages_deleted_state.dart';
import 'package:flutter_app/core/database/migrations/045_inbox_staging_entries.dart';
import 'package:flutter_app/core/database/migrations/046_pending_introduction_responses.dart';
import 'package:flutter_app/core/database/migrations/047_introduction_outbox.dart';
import 'package:flutter_app/core/database/migrations/048_groups_last_membership_event_at.dart';
import 'package:flutter_app/core/database/migrations/049_groups_metadata_columns.dart';
import 'package:flutter_app/core/database/migrations/050_groups_mute_column.dart';
import 'package:flutter_app/core/database/migrations/051_pending_group_invites.dart';
import 'package:flutter_app/core/database/migrations/052_groups_dissolve_columns.dart';
import 'package:flutter_app/core/database/migrations/053_groups_backlog_retention_columns.dart';
import 'package:flutter_app/core/database/migrations/054_group_reaction_replay_outbox.dart';
import 'package:flutter_app/core/database/migrations/055_group_invite_revocations.dart';
import 'package:flutter_app/core/database/migrations/056_group_invite_consumptions.dart';
import 'package:flutter_app/core/database/migrations/057_group_member_permissions.dart';
import 'package:flutter_app/core/database/migrations/058_media_attachment_integrity_columns.dart';
import 'package:flutter_app/core/database/migrations/059_media_attachment_encryption_columns.dart';
import 'package:flutter_app/core/database/migrations/060_group_event_log.dart';
import 'package:flutter_app/core/database/migrations/061_group_message_transport_peer_id.dart';
import 'package:flutter_app/core/database/migrations/062_group_member_device_identities.dart';
import 'package:flutter_app/core/database/migrations/063_group_pending_key_repairs.dart';
import 'package:flutter_app/core/database/migrations/064_group_welcome_key_package_tombstones.dart';
import 'package:flutter_app/core/database/migrations/065_group_history_gap_repairs.dart';
import 'package:flutter_app/core/database/migrations/066_group_sync_receipts.dart';
import 'package:flutter_app/core/database/migrations/067_group_invite_delivery_attempts.dart';
import 'package:flutter_app/core/database/migrations/068_removed_group_member_snapshots.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_history_gap_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_sync_receipts_db_helpers.dart';
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
import 'package:flutter_app/core/database/helpers/post_media_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_upload_recovery_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_pending_child_events_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_repost_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart';
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
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/message_deletion_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/recover_stuck_sending_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository_impl.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_invite_identity_callbacks.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/core/debug/e2e_test_mode.dart';
import 'package:flutter_app/core/debug/intro_e2e_runner.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/disabled_local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/ios_apns_notification_open_bridge.dart';
import 'package:flutter_app/core/notifications/notification_open_dedupe_gate.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kDebugMode, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/prepare_notification_route_target_use_case.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart'
    as push_registration;
import 'package:flutter_app/features/push/application/request_push_permission_use_case.dart';
import 'package:flutter_app/features/push/infrastructure/push_token_store_impl.dart';
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
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository_impl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupTiming.instance.mark('app_start');
  final shareIntentService = ShareIntentService();
  StartupTiming.instance.mark('share_launch_probe_begin');
  final initialShareIntent = await shareIntentService.captureInitialIntent();
  final isShareLaunch = initialShareIntent != null;
  StartupTiming.instance.mark('share_launch_probe_complete');

  // Initialize Firebase (mobile only — not available on desktop)
  final bool isDesktop =
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
  var firebaseInitialized = false;
  Future<void> ensureFirebaseReady() async {
    if (firebaseInitialized) {
      return;
    }
    firebaseInitialized = true;
    if (!isDesktop) {
      try {
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
      } catch (e) {
        debugPrint('Firebase init skipped: $e');
      }
    }
    StartupTiming.instance.mark('firebase_ready');
  }

  if (!isShareLaunch) {
    await ensureFirebaseReady();
  }

  // Initialize UserAvatar documents directory for file-based avatar loading
  final appDocDir = await getApplicationDocumentsDirectory();
  UserAvatar.setDocumentsDir(appDocDir.path);
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
  final pushTokenStore = PushTokenStoreImpl(secureKeyStore: secureKeyStore);

  // 2. Open encrypted database (handles plaintext→encrypted migration)
  final db = await openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: 'identity.db',
    version: 68,
    onCreate: (db, version) async {
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
      await runMlKemKeysMigration(db);
      // Fresh install: skip 004 (nullable) — 005 already has nullable + CHECK
      await runSecretNullChecksMigration(db);
      await runReadAtColumnMigration(db);
      await runArchiveColumnsMigration(db);
      await runBlockColumnsMigration(db);
      await runQuotedMessageIdMigration(db);
      await runMediaAttachmentsMigration(db);
      await runMediaAttachmentReliabilityColumnsMigration(db);
      await runAvatarVersionMigration(db);
      await runTransportColumnMigration(db);
      await runWaveformColumnMigration(db);
      await runWireEnvelopeMigration(db);
      await runMessageStatusCleanupMigration(db);
      await runMessageReactionsMigration(db);
      await runGroupsTablesMigration(db);
      await runGroupMessagesTablesMigration(db);
      await runIntroductionsTableMigration(db);
      await runIntroBannerColumnsMigration(db);
      await runContactIntroducedByMigration(db);
      await runIntroductionKeysMigration(db);
      await runIntroductionRecipientKeysMigration(db);
      await runContactIntroducedByPeerIdMigration(db);
      await runIntroductionAlreadyConnectedMigration(db);
      await runGroupQuotedMessageIdMigration(db);
      await runPostsCoreMigration(db);
      await runPostsEngagementMigration(db);
      await runPostsNearbyMigration(db);
      await runPostsPassAlongMigration(db);
      await runPostsPinsMigration(db);
      await runPostsRetryRecipientContextMigration(db);
      await runPostsFollowOnOutboxMigration(db);
      await runPostsMediaUploadRecoveryMigration(db);
      await runPostsRepostDeliveryStateMigration(db);
      await runPostsPassEncryptedSnapshotsMigration(db);
      await runPostsRepostEngagementStateMigration(db);
      await runPostsRepostMediaCryptoMigration(db);
      await runPostsPassAvatarSnapshotsMigration(db);
      await runPostsRepostVisualMetricsMigration(db);
      await runGroupMessageReliabilityColumnsMigration(db);
      await runMessagesEditedAtMigration(db);
      await runMessagesDeletedStateMigration(db);
      await runInboxStagingEntriesMigration(db);
      await runPendingIntroductionResponsesMigration(db);
      await runIntroductionOutboxMigration(db);
      await runGroupsLastMembershipEventAtMigration(db);
      await runGroupsMetadataColumnsMigration(db);
      await runGroupsMuteColumnMigration(db);
      await runPendingGroupInvitesMigration(db);
      await runGroupsDissolveColumnsMigration(db);
      await runGroupsBacklogRetentionColumnsMigration(db);
      await runGroupReactionReplayOutboxMigration(db);
      await runGroupInviteRevocationsMigration(db);
      await runGroupInviteConsumptionsMigration(db);
      await runGroupMemberPermissionsMigration(db);
      await runMediaAttachmentIntegrityColumnsMigration(db);
      await runMediaAttachmentEncryptionColumnsMigration(db);
      await runGroupEventLogMigration(db);
      await runGroupMessageTransportPeerIdMigration(db);
      await runGroupMemberDeviceIdentitiesMigration(db);
      await runGroupPendingKeyRepairsMigration(db);
      await runGroupWelcomeKeyPackageTombstonesMigration(db);
      await runGroupHistoryGapRepairsMigration(db);
      await runGroupSyncReceiptsMigration(db);
      await runGroupInviteDeliveryAttemptsMigration(db);
      await runRemovedGroupMemberSnapshotsMigration(db);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await runMessagesTableMigration(db);
      }
      if (oldVersion < 3) {
        await runMlKemKeysMigration(db);
      }
      if (oldVersion < 4) {
        await runNullifySecretColumnsMigration(db);
      }
      // Migration 005 is deferred — runs after secrets migration below
      if (oldVersion < 6) {
        await runReadAtColumnMigration(db);
      }
      if (oldVersion < 7) {
        await runArchiveColumnsMigration(db);
      }
      if (oldVersion < 8) {
        await runBlockColumnsMigration(db);
      }
      if (oldVersion < 9) {
        await runQuotedMessageIdMigration(db);
      }
      if (oldVersion < 10) {
        await runMediaAttachmentsMigration(db);
      }
      if (oldVersion < 42) {
        await runMediaAttachmentReliabilityColumnsMigration(db);
      }
      if (oldVersion < 11) {
        await runAvatarVersionMigration(db);
      }
      if (oldVersion < 12) {
        await runTransportColumnMigration(db);
      }
      if (oldVersion < 13) {
        await runWaveformColumnMigration(db);
      }
      if (oldVersion < 14) {
        await runWireEnvelopeMigration(db);
      }
      if (oldVersion < 15) {
        await runMessageStatusCleanupMigration(db);
      }
      if (oldVersion < 16) {
        await runMessageReactionsMigration(db);
      }
      if (oldVersion < 17) {
        await runGroupsTablesMigration(db);
      }
      if (oldVersion < 18) {
        await runGroupMessagesTablesMigration(db);
      }
      if (oldVersion < 19) {
        await runIntroductionsTableMigration(db);
      }
      if (oldVersion < 20) {
        await runIntroBannerColumnsMigration(db);
      }
      if (oldVersion < 21) {
        await runContactIntroducedByMigration(db);
      }
      if (oldVersion < 22) {
        await runIntroductionKeysMigration(db);
      }
      if (oldVersion < 23) {
        await runIntroductionRecipientKeysMigration(db);
      }
      if (oldVersion < 24) {
        await runContactIntroducedByPeerIdMigration(db);
      }
      if (oldVersion < 25) {
        await runIntroductionAlreadyConnectedMigration(db);
      }
      if (oldVersion < 26) {
        await runGroupQuotedMessageIdMigration(db);
      }
      if (oldVersion < 27) {
        await runPostsCoreMigration(db);
      }
      if (oldVersion < 28) {
        await runPostsEngagementMigration(db);
      }
      if (oldVersion < 29) {
        await runPostsNearbyMigration(db);
      }
      if (oldVersion < 30) {
        await runPostsPassAlongMigration(db);
      }
      if (oldVersion < 31) {
        await runPostsPinsMigration(db);
      }
      if (oldVersion < 32) {
        await runPostsRetryRecipientContextMigration(db);
      }
      if (oldVersion < 33) {
        await runPostsFollowOnOutboxMigration(db);
      }
      if (oldVersion < 34) {
        await runPostsMediaUploadRecoveryMigration(db);
      }
      if (oldVersion < 35) {
        await runPostsRepostDeliveryStateMigration(db);
      }
      if (oldVersion < 36) {
        await runPostsPassEncryptedSnapshotsMigration(db);
      }
      if (oldVersion < 37) {
        await runPostsRepostEngagementStateMigration(db);
      }
      if (oldVersion < 38) {
        await runPostsRepostMediaCryptoMigration(db);
      }
      if (oldVersion < 39) {
        await runPostsPassAvatarSnapshotsMigration(db);
      }
      if (oldVersion < 40) {
        await runPostsRepostVisualMetricsMigration(db);
      }
      if (oldVersion < 41) {
        await runGroupMessageReliabilityColumnsMigration(db);
      }
      if (oldVersion < 43) {
        await runMessagesEditedAtMigration(db);
      }
      if (oldVersion < 44) {
        await runMessagesDeletedStateMigration(db);
      }
      if (oldVersion < 45) {
        await runInboxStagingEntriesMigration(db);
      }
      if (oldVersion < 46) {
        await runPendingIntroductionResponsesMigration(db);
      }
      if (oldVersion < 47) {
        await runIntroductionOutboxMigration(db);
      }
      if (oldVersion < 48) {
        await runGroupsLastMembershipEventAtMigration(db);
      }
      if (oldVersion < 49) {
        await runGroupsMetadataColumnsMigration(db);
      }
      if (oldVersion < 50) {
        await runGroupsMuteColumnMigration(db);
      }
      if (oldVersion < 51) {
        await runPendingGroupInvitesMigration(db);
      }
      if (oldVersion < 52) {
        await runGroupsDissolveColumnsMigration(db);
      }
      if (oldVersion < 53) {
        await runGroupsBacklogRetentionColumnsMigration(db);
      }
      if (oldVersion < 54) {
        await runGroupReactionReplayOutboxMigration(db);
      }
      if (oldVersion < 55) {
        await runGroupInviteRevocationsMigration(db);
      }
      if (oldVersion < 56) {
        await runGroupInviteConsumptionsMigration(db);
      }
      if (oldVersion < 57) {
        await runGroupMemberPermissionsMigration(db);
      }
      if (oldVersion < 58) {
        await runMediaAttachmentIntegrityColumnsMigration(db);
      }
      if (oldVersion < 59) {
        await runMediaAttachmentEncryptionColumnsMigration(db);
      }
      if (oldVersion < 60) {
        await runGroupEventLogMigration(db);
      }
      if (oldVersion < 61) {
        await runGroupMessageTransportPeerIdMigration(db);
      }
      if (oldVersion < 62) {
        await runGroupMemberDeviceIdentitiesMigration(db);
      }
      if (oldVersion < 63) {
        await runGroupPendingKeyRepairsMigration(db);
      }
      if (oldVersion < 64) {
        await runGroupWelcomeKeyPackageTombstonesMigration(db);
      }
      if (oldVersion < 65) {
        await runGroupHistoryGapRepairsMigration(db);
      }
      if (oldVersion < 66) {
        await runGroupSyncReceiptsMigration(db);
      }
      if (oldVersion < 67) {
        await runGroupInviteDeliveryAttemptsMigration(db);
      }
      if (oldVersion < 68) {
        await runRemovedGroupMemberSnapshotsMigration(db);
      }
    },
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
    dbRecoverStuckSendingMessages:
        ({required DateTime olderThan, int limit = 50}) =>
            dbRecoverStuckSendingMessages(
              db,
              olderThan: olderThan,
              limit: limit,
            ),
    dbUpdateWireEnvelope: (id, wireEnvelope) =>
        dbUpdateWireEnvelope(db, id, wireEnvelope),
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
  );

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
  late final NearbyLocationService nearbyLocationService;
  final contactPresenceSnapshotRepository =
      ContactPresenceSnapshotRepositoryImpl(
        dbLoadPostLocationPresence: (peerId) =>
            dbLoadPostLocationPresence(db, peerId),
        dbLoadAllPostLocationPresence: () => dbLoadAllPostLocationPresence(db),
        dbUpsertPostLocationPresence: (row) =>
            dbUpsertPostLocationPresence(db, row),
      );

  // Create media attachment repository
  final mediaAttachmentRepository = MediaAttachmentRepositoryImpl(
    dbInsertMediaAttachment: (row) => dbInsertMediaAttachment(db, row),
    dbLoadMediaForMessage: (messageId) => dbLoadMediaForMessage(db, messageId),
    dbLoadMediaForMessages: (messageIds) =>
        dbLoadMediaForMessages(db, messageIds),
    dbUpdateMediaLocalPath: (id, localPath, downloadStatus) =>
        dbUpdateMediaLocalPath(db, id, localPath, downloadStatus),
    dbUpdateMediaDownloadStatus: (id, downloadStatus) =>
        dbUpdateMediaDownloadStatus(db, id, downloadStatus),
    dbDeleteMediaForMessage: (messageId) =>
        dbDeleteMediaForMessage(db, messageId),
    dbDeleteMediaForContact: (contactPeerId) =>
        dbDeleteMediaForContact(db, contactPeerId),
    dbMarkUploadPendingAttachmentsFailedForMessage: (messageId) =>
        dbMarkUploadPendingAttachmentsFailedForMessage(db, messageId),
    dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
    dbLoadUploadPendingAttachments: ({int limit = 50}) =>
        dbLoadUploadPendingAttachments(db, limit: limit),
    secureKeyStore: secureKeyStore,
  );

  // Create reaction repository
  final reactionRepository = ReactionRepositoryImpl(
    dbInsertReaction: (row) => dbInsertReaction(db, row),
    dbLoadReactionsForMessage: (messageId) =>
        dbLoadReactionsForMessage(db, messageId),
    dbLoadReactionsForMessages: (messageIds) =>
        dbLoadReactionsForMessages(db, messageIds),
    dbDeleteReaction: (messageId, senderPeerId) =>
        dbDeleteReaction(db, messageId, senderPeerId),
    dbDeleteReactionsForMessage: (messageId) =>
        dbDeleteReactionsForMessage(db, messageId),
    dbDeleteReactionsForContact: (contactPeerId) =>
        dbDeleteReactionsForContact(db, contactPeerId),
  );

  final groupReactionReplayOutboxRepository =
      GroupReactionReplayOutboxRepositoryImpl(
        dbUpsertGroupReactionReplayOutboxEntry: (row) =>
            dbUpsertGroupReactionReplayOutboxEntry(db, row),
        dbLoadGroupReactionReplayOutboxEntry: (reactionId) =>
            dbLoadGroupReactionReplayOutboxEntry(db, reactionId),
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
    dbInsertGroupKey: (row) => dbInsertGroupKey(db, row),
    dbLoadLatestGroupKey: (groupId) => dbLoadLatestGroupKey(db, groupId),
    dbLoadGroupKeyByGeneration: (groupId, generation) =>
        dbLoadGroupKeyByGeneration(db, groupId, generation),
    dbDeleteAllGroupKeys: (groupId) => dbDeleteAllGroupKeys(db, groupId),
    dbLoadAllGroupKeys: (groupId) => dbLoadAllGroupKeys(db, groupId),
    dbDeleteGroupKeysBeforeGeneration: (groupId, minKeyGenerationToKeep) =>
        dbDeleteGroupKeysBeforeGeneration(db, groupId, minKeyGenerationToKeep),
    groupKeyStore: secureKeyStore,
    pushSharedKeyStore: sharedPushKeyStore,
  );
  await groupRepository.mirrorAllKeysToSecureStore();

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
  }) {
    return GroupMessageRepositoryImpl(
      dbInsertGroupMessage: (row) => dbInsertGroupMessage(executor, row),
      dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) =>
          dbLoadGroupMessagesPage(
            executor,
            groupId,
            limit: limit,
            offset: offset,
          ),
      dbLoadGroupMessage: (id) => dbLoadGroupMessage(executor, id),
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
      dbLoadFailedOutgoingGroupMessagesFn: () =>
          dbLoadFailedOutgoingGroupMessages(executor),
      dbRecoverStuckSendingGroupMessagesFn: ({DateTime? olderThan}) =>
          dbTransitionGroupSendingToFailed(executor, olderThan: olderThan),
      dbLoadGroupMessagesWithFailedInboxStore: ({int limit = 50}) =>
          dbLoadGroupMessagesWithFailedInboxStore(executor, limit: limit),
      dbUpdateGroupMessageInboxStoredFn: (id, {required bool stored}) =>
          dbUpdateGroupMessageInboxStored(executor, id, stored: stored),
      dbUpdateGroupMessageInboxRetryPayloadFn: (id, payload) =>
          dbUpdateGroupMessageInboxRetryPayload(executor, id, payload),
      dbUpdateGroupMessageWireEnvelopeFn: (id, envelope) =>
          dbUpdateGroupMessageWireEnvelope(executor, id, envelope),
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
    );
  }

  // Create group message repository
  final groupMessageRepository = createGroupMessageRepository(
    db,
    enableInboxPageTransactions: true,
  );

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
    dbRecordGroupPendingKeyRepairAttempt:
        (id, {required lastError, required updatedAt}) =>
            dbRecordGroupPendingKeyRepairAttempt(
              db,
              id,
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
  );

  final groupHistoryGapRepairRepository = GroupHistoryGapRepairRepositoryImpl(
    dbUpsertGroupHistoryGapRepair: (row) =>
        dbUpsertGroupHistoryGapRepair(db, row),
    dbSaveGroupHistoryGapRepair: (row) => dbSaveGroupHistoryGapRepair(db, row),
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

  // Create media file manager
  final mediaFileManager = MediaFileManager();

  // Create image processor (EXIF stripping + quality compression)
  final imageProcessor = ImageProcessor();

  // Create audio recorder service
  final audioRecorderService = RecordAudioRecorderService();

  // Create and initialize the bridge (Go native)
  final Bridge bridge = GoBridgeClient();

  // ── Auto-setup for simulator scripts (dart-define only, dead-code in release) ──
  const autoSetupUsername = String.fromEnvironment('AUTO_SETUP_USERNAME');
  if (autoSetupUsername.isNotEmpty) {
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
      if (kDebugMode) print('[AUTO-SETUP] Identity already exists, skipping');
    }
  }

  // Create local P2P service for WiFi-first delivery
  final LocalDiscoveryService localDiscovery = kDisableLocalDiscovery
      ? DisabledLocalDiscoveryService()
      : BonsoirDiscoveryService();
  final localWsServer = LocalWsServer();
  final localP2PService = LocalP2PService(
    discovery: localDiscovery,
    wsServer: localWsServer,
  );
  late final ChatMessageListener chatMessageListener;
  late final IntroductionListener introductionListener;

  // Create P2P service (uses the same bridge + local P2P)
  final p2pService = P2PServiceImpl(
    bridge: bridge,
    localP2PService: localP2PService,
    pushTokenStore: pushTokenStore,
    inboxStagingRepository: inboxStagingRepository,
    replayRecoveredInboxChatMessage: (message) async {
      var outcome = await chatMessageListener.processIncomingMessage(
        message,
        suppressNotification: true,
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
              suppressNotification: true,
            );
          }
          if (outcome.state == ChatMessageProcessState.unknownSender &&
              resolution != UnknownInboxSenderResolution.rejected) {
            return (
              disposition: RecoveredInboxChatDisposition.retryable,
              reasonCode: 'unknown_sender_intro_pending',
              reasonDetail: null,
            );
          }
        }
      }

      switch (outcome.state) {
        case ChatMessageProcessState.stored:
          return (
            disposition: RecoveredInboxChatDisposition.committed,
            reasonCode: 'stored',
            reasonDetail: null,
          );
        case ChatMessageProcessState.missingMlKemSecret:
          return (
            disposition: RecoveredInboxChatDisposition.retryable,
            reasonCode: 'missing_mlkem_secret',
            reasonDetail: outcome.reasonDetail,
          );
        case ChatMessageProcessState.error:
          return (
            disposition: RecoveredInboxChatDisposition.retryable,
            reasonCode: 'listener_error',
            reasonDetail: outcome.reasonDetail,
          );
        case ChatMessageProcessState.blockedSender:
          return (
            disposition: RecoveredInboxChatDisposition.rejected,
            reasonCode: 'blocked_sender',
            reasonDetail: null,
          );
        case ChatMessageProcessState.notChatMessage:
          return (
            disposition: RecoveredInboxChatDisposition.rejected,
            reasonCode: 'not_chat_message',
            reasonDetail: null,
          );
        case ChatMessageProcessState.decryptionFailed:
          return (
            disposition: RecoveredInboxChatDisposition.rejected,
            reasonCode: 'decryption_failed',
            reasonDetail: null,
          );
        case ChatMessageProcessState.unknownSender:
          return (
            disposition: RecoveredInboxChatDisposition.rejected,
            reasonCode: 'unknown_sender',
            reasonDetail: null,
          );
        case ChatMessageProcessState.duplicate:
          return (
            disposition: RecoveredInboxChatDisposition.rejected,
            reasonCode: 'duplicate',
            reasonDetail: null,
          );
        case ChatMessageProcessState.editMissingOriginal:
          return (
            disposition: RecoveredInboxChatDisposition.rejected,
            reasonCode: 'edit_missing_original',
            reasonDetail: null,
          );
      }
    },
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
  final contactRequestListener = ContactRequestListener(
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
    shouldSuppressPresentationForPeerId:
        contactRequestPresentationGate.shouldSuppress,
  );

  // Create notification service and conversation trackers
  final notificationService = FlutterNotificationService(
    requestApplePermissions: !kE2ETestMode,
  );
  final PushRegistrationCoordinator? pushRegistrationCoordinator =
      !isDesktop && Firebase.apps.isNotEmpty && !kE2ETestMode
      ? PushRegistrationCoordinator(
          requestPermission: requestPushPermission,
          registerPushToken: () => push_registration.registerPushToken(
            p2pService: p2pService,
            pushTokenStore: pushTokenStore,
          ),
          tokenRefreshStream: FirebaseMessaging.instance.onTokenRefresh,
        )
      : null;
  final conversationTracker = ActiveConversationTracker();
  final groupConversationTracker = ActiveConversationTracker();
  final appShellController = AppShellController();
  final pendingPostTargetStore = PendingPostTargetStore();

  // Create chat message listener
  chatMessageListener = ChatMessageListener(
    chatMessageStream: messageRouter.chatMessageStream,
    messageRepo: messageRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    notificationService: notificationService,
    conversationTracker: conversationTracker,
    getAppLifecycleState: () =>
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
  );

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
  );

  // Create profile update listener
  final profileUpdateListener = ProfileUpdateListener(
    profileUpdateStream: messageRouter.profileUpdateStream,
    contactRepo: contactRepository,
    bridge: bridge,
  );

  // Create group message listener and wire bridge callback to stream
  final groupMessageListener = GroupMessageListener(
    groupRepo: groupRepository,
    msgRepo: groupMessageRepository,
    bridge: bridge,
    getSelfPeerId: () async {
      final identity = await repository.loadIdentity();
      return identity?.peerId;
    },
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    notificationService: notificationService,
    groupConversationTracker: groupConversationTracker,
    getAppLifecycleState: () =>
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    reactionRepo: reactionRepository,
    inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
    groupDiagnosticEvents: groupDiagnosticEventStream,
    pendingKeyRepairRepo: groupPendingKeyRepairRepository,
    requestGroupKeyRepair: emitGroupKeyRepairRequest,
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
    replayGroupEnvelope: groupMessageListener.handleReplayEnvelope,
  );

  // Create group invite listener
  final groupIdentityCallbacks = buildGroupIdentityCallbacks(
    identityRepo: repository,
    p2pService: p2pService,
  );
  final groupInviteListener = GroupInviteListener(
    groupInviteStream: messageRouter.groupInviteStream,
    groupRepo: groupRepository,
    pendingInviteRepo: pendingGroupInviteRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    msgRepo: groupMessageRepository,
    mediaAttachmentRepo: mediaAttachmentRepository,
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

  final groupMembershipUpdateListener = GroupMembershipUpdateListener(
    groupMembershipUpdateStream: messageRouter.groupMembershipUpdateStream,
    groupRepo: groupRepository,
    bridge: bridge,
    groupMessageListener: groupMessageListener,
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
    rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
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
      );

      return reason == RejoinReason.nodeRequestedRecovery &&
          rejoinResult.canAcknowledgeGroupRecovery;
    },
    acknowledgeGroupRecoveryFn: () => callGroupAcknowledgeRecovery(bridge),
    drainGroupOfflineInboxFn: () async {
      final identity = await repository.loadIdentity();
      return drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        mediaAttachmentRepo: mediaAttachmentRepository,
        reactionRepo: reactionRepository,
        pendingKeyRepairRepo: groupPendingKeyRepairRepository,
        historyGapRepairRepo: groupHistoryGapRepairRepository,
        requestGroupKeyRepair: emitGroupKeyRepairRequest,
        selfPeerId: identity?.peerId,
      );
    },
    recoverStuckSendingGroupMessagesFn: () =>
        recoverStuckSendingGroupMessages(groupMsgRepo: groupMessageRepository),
    retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(
      groupRepo: groupRepository,
      groupMsgRepo: groupMessageRepository,
      mediaAttachmentRepo: mediaAttachmentRepository,
      bridge: bridge,
      p2pService: p2pService,
      identityRepo: repository,
      mediaFileManager: mediaFileManager,
    ),
    retryFailedGroupMessagesFn: () => retryFailedGroupMessages(
      groupMsgRepo: groupMessageRepository,
      groupRepo: groupRepository,
      identityRepo: repository,
      bridge: bridge,
      mediaAttachmentRepo: mediaAttachmentRepository,
    ),
    retryPendingIntroductionDeliveriesFn: () =>
        retryPendingIntroductionDeliveries(
          introRepo: introductionRepository,
          p2pService: p2pService,
        ),
    retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: groupMessageRepository,
      reactionReplayOutboxRepo: groupReactionReplayOutboxRepository,
    ),
    recoverStuckSendingMessagesFn: () =>
        recoverStuckSendingMessages(messageRepo: messageRepository),
    retryIncompleteUploadsFn: () => retryIncompleteUploads(
      mediaAttachmentRepo: mediaAttachmentRepository,
      messageRepo: messageRepository,
      bridge: bridge,
      p2pService: p2pService,
      identityRepo: repository,
      contactRepo: contactRepository,
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
  );
  final pendingPostDeliveryRetrier = PendingPostDeliveryRetrier(
    p2pService: p2pService,
    postRepo: postRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    beforeRetry: pendingPostMediaUploadRetrier.retryNow,
  );
  final pendingPostFollowOnRetrier = PendingPostFollowOnRetrier(
    p2pService: p2pService,
    postRepo: postRepository,
  );

  // Create key exchange retrier
  final keyExchangeRetrier = KeyExchangeRetrier(
    p2pService: p2pService,
    contactRepo: contactRepository,
    identityRepo: repository,
    bridge: bridge,
  );

  var liveServicesStarted = false;
  Future<void> startLiveServices() async {
    if (liveServicesStarted) {
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
    profileUpdateListener.start();
    groupMessageListener.start(
      groupMessageStreamController.stream,
      incomingGroupReactions: groupReactionStreamController.stream,
    );
    groupInviteListener.start();
    groupKeyUpdateListener.start();
    groupMembershipUpdateListener.start();
    introductionListener.start();

    // NOTE: rejoinGroupTopics and drainGroupOfflineInbox are called in
    // StartupRouter._doStartP2P() AFTER node:start completes. They require
    // the Go node to be running (pubsub must be initialized).
    pendingMessageRetrier.start();
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
    });
    StartupTiming.instance.mark('runtime_services_ready');
  }

  if (!isShareLaunch) {
    await startLiveServices();
  }

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
      contactRequestPresentationGate: contactRequestPresentationGate,
      messageRepository: messageRepository,
      postRepository: postRepository,
      postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      contactPresenceSnapshotRepository: contactPresenceSnapshotRepository,
      nearbyLocationService: nearbyLocationService,
      mediaAttachmentRepository: mediaAttachmentRepository,
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
      mediaFileManager: mediaFileManager,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      audioRecorderService: audioRecorderService,
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
      groupHistoryGapRepairRepository: groupHistoryGapRepairRepository,
      groupReactionReplayOutboxRepository: groupReactionReplayOutboxRepository,
      groupMessageListener: groupMessageListener,
      groupInviteListener: groupInviteListener,
      groupKeyUpdateListener: groupKeyUpdateListener,
      groupMembershipUpdateListener: groupMembershipUpdateListener,
      groupConversationTracker: groupConversationTracker,
      introductionRepository: introductionRepository,
      introductionListener: introductionListener,
      shareIntentService: shareIntentService,
      pushRegistrationCoordinator: pushRegistrationCoordinator,
      deferredRuntimeStartup: isShareLaunch ? startLiveServices : null,
    ),
  );
  StartupTiming.instance.mark('run_app_called');
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
    openConversationByPeerId: (peerId) async {
      for (var attempt = 0; attempt < 30; attempt++) {
        final navigator = MyApp.navigatorKey.currentState;
        final contact = await contactRepository.getContact(peerId);
        if (navigator != null && contact != null) {
          navigator.popUntil((route) => route.isFirst);
          unawaited(
            navigator.push(
              buildConversationSlideUpRoute(
                builder: (_) => ConversationWired(
                  contact: contact,
                  identityRepo: repository,
                  messageRepo: messageRepository,
                  chatMessageListener: chatMessageListener,
                  p2pService: p2pService,
                  bridge: bridge,
                  contactRepo: contactRepository,
                  mediaAttachmentRepo: mediaAttachmentRepository,
                  mediaFileManager: mediaFileManager,
                  conversationTracker: conversationTracker,
                  audioRecorderService: audioRecorderService,
                  reactionRepo: reactionRepository,
                  reactionListener: reactionListener,
                  introductionRepository: introductionRepository,
                  appShellController: appShellController,
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
  final MessageRepositoryImpl messageRepository;
  final PostRepositoryImpl postRepository;
  final PostsPrivacySettingsRepositoryImpl postsPrivacySettingsRepository;
  final ContactPresenceSnapshotRepositoryImpl contactPresenceSnapshotRepository;
  final NearbyLocationService nearbyLocationService;
  final MediaAttachmentRepositoryImpl mediaAttachmentRepository;
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
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final AudioRecorderService audioRecorderService;
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
  final GroupHistoryGapRepairRepositoryImpl groupHistoryGapRepairRepository;
  final GroupReactionReplayOutboxRepositoryImpl
  groupReactionReplayOutboxRepository;
  final GroupMessageListener groupMessageListener;
  final GroupInviteListener groupInviteListener;
  final GroupKeyUpdateListener groupKeyUpdateListener;
  final GroupMembershipUpdateListener groupMembershipUpdateListener;
  final ActiveConversationTracker groupConversationTracker;
  final IntroductionRepositoryImpl introductionRepository;
  final IntroductionListener introductionListener;
  final ShareIntentService shareIntentService;
  final PushRegistrationCoordinator? pushRegistrationCoordinator;
  final Future<void> Function()? deferredRuntimeStartup;

  static final navigatorKey = GlobalKey<NavigatorState>();

  const MyApp({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.contactRequestPresentationGate,
    required this.messageRepository,
    required this.postRepository,
    required this.postsPrivacySettingsRepository,
    required this.contactPresenceSnapshotRepository,
    required this.nearbyLocationService,
    required this.mediaAttachmentRepository,
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
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.audioRecorderService,
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
    required this.groupHistoryGapRepairRepository,
    required this.groupReactionReplayOutboxRepository,
    required this.groupMessageListener,
    required this.groupInviteListener,
    required this.groupKeyUpdateListener,
    required this.groupMembershipUpdateListener,
    required this.groupConversationTracker,
    required this.introductionRepository,
    required this.introductionListener,
    required this.shareIntentService,
    this.pushRegistrationCoordinator,
    this.deferredRuntimeStartup,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isResuming = false;
  DateTime? _notificationTappedAt;
  NotificationRouteTarget? _deferredNotificationRouteTarget;
  late final PostNotificationOpenCoordinator _postNotificationOpenCoordinator;
  late final ContactRequestNotificationMaterializer
  _contactRequestNotificationMaterializer;
  late final IosApnsNotificationOpenBridge _iosApnsNotificationOpenBridge;
  final NotificationOpenDedupeGate _remoteNotificationOpenDedupeGate =
      NotificationOpenDedupeGate();
  late final Future<void> _initialShareIntentCapture;
  Future<void>? _runtimeServicesReady;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.pendingMessageRetrier.setExternalRecoveryInProgressProvider(
      () => _isResuming,
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
    _setupPushListeners();
    _setupNotificationTapHandler();
    _setupIosApnsNotificationOpenBridge();
    _setupShareIntentHandling();
    _initialShareIntentCapture = _captureInitialShareIntent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_flushDeferredNotificationRouteTarget());
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
    }();
    _runtimeServicesReady = startup;
    return startup;
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
    if (!_remoteNotificationOpenDedupeGate.shouldRoute(data)) {
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

    _notificationTappedAt = DateTime.now();
    final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
    await _withContactRequestPresentationSuppressed(
      routeTarget: routeTarget,
      action: () => routeAppRootRemoteNotificationOpen(
        data: data,
        onBeforeOpen: widget.notificationService.clearDeliveredNotifications,
        onBeforeRouteTarget: _prepareNotificationRouteTarget,
        onRouteTarget: _handleNotificationRouteTarget,
        onMissingRouteTarget: widget.p2pService.drainOfflineInbox,
      ),
    );
  }

  Future<void> _withContactRequestPresentationSuppressed({
    required NotificationRouteTarget? routeTarget,
    required Future<void> Function() action,
  }) async {
    final peerId =
        routeTarget?.kind == NotificationRouteTargetKind.contactRequest
        ? routeTarget?.peerId
        : null;
    if (peerId != null) {
      widget.contactRequestPresentationGate.suppress(peerId);
    }
    try {
      await action();
    } finally {
      if (peerId != null) {
        widget.contactRequestPresentationGate.release(peerId);
      }
    }
  }

  Future<void> _handleInitialLocalNotificationLaunchWhenReady() async {
    await _ensureRuntimeServicesReady();
    await _handleInitialLocalNotificationLaunch();
  }

  Future<void> _handleInitialLocalNotificationLaunch() async {
    try {
      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: widget.notificationService.consumeInitialPayload,
        onBeforeOpen: widget.notificationService.clearDeliveredNotifications,
        onBeforeRouteTarget: _prepareNotificationRouteTarget,
        onRouteTarget: _handleNotificationRouteTarget,
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
    _notificationTappedAt = DateTime.now();
    try {
      await routeAppRootLocalNotificationTap(
        payload: payload,
        onBeforeOpen: widget.notificationService.clearDeliveredNotifications,
        onBeforeRouteTarget: _prepareNotificationRouteTarget,
        onRouteTarget: _handleNotificationRouteTarget,
      );
    } catch (e) {
      _notificationTappedAt = null;
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_TAP_NAV_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _handleNotificationRouteTarget(
    NotificationRouteTarget routeTarget,
  ) async {
    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) {
      _deferredNotificationRouteTarget = routeTarget;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_flushDeferredNotificationRouteTarget());
      });
      return;
    }

    if (routeTarget.kind == NotificationRouteTargetKind.post ||
        routeTarget.kind == NotificationRouteTargetKind.postComment) {
      _notificationTappedAt = null;
      await _postNotificationOpenCoordinator.handleRouteTarget(
        routeTarget: routeTarget,
        drainOfflineInbox: widget.p2pService.drainOfflineInbox,
      );
      return;
    }

    switch (routeTarget.kind) {
      case NotificationRouteTargetKind.contactRequest:
        _notificationTappedAt = null;
        await _contactRequestNotificationMaterializer.handleRoute(
          navigator: navigator,
          peerId: routeTarget.peerId!,
        );
        return;
      case NotificationRouteTargetKind.intros:
        _notificationTappedAt = null;
        await _openIntroOrbitRoute(navigator: navigator);
        return;
      case NotificationRouteTargetKind.group:
        final resolution = await resolveGroupNotificationRouteTarget(
          groupId: routeTarget.groupId!,
          groupRepo: widget.groupRepository,
          pendingInviteRepo: widget.groupInviteListener.pendingInviteRepo,
          drainOfflineInbox: widget.p2pService.drainOfflineInbox,
        );
        if (resolution.group == null) {
          _notificationTappedAt = null;
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
          }
          return;
        }
        final group = resolution.group!;
        final tappedAt = _notificationTappedAt;
        _notificationTappedAt = null;
        navigator.push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group,
              groupRepo: widget.groupRepository,
              msgRepo: widget.groupMessageRepository,
              groupMessageListener: widget.groupMessageListener,
              inviteDeliveryAttemptRepo:
                  widget.groupInviteDeliveryAttemptRepository,
              bridge: widget.bridge,
              identityRepo: widget.repository,
              contactRepo: widget.contactRepository,
              p2pService: widget.p2pService,
              groupConversationTracker: widget.groupConversationTracker,
              initialHighlightedMessageId: routeTarget.messageId,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              audioRecorderService: widget.audioRecorderService,
              reactionRepo: widget.reactionRepository,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
              notificationTappedAt: tappedAt,
              backgroundPreference:
                  widget.appShellController.backgroundPreference,
            ),
          ),
        );
        return;
      case NotificationRouteTargetKind.conversation:
        final contact = await widget.contactRepository.getContact(
          routeTarget.peerId!,
        );
        if (contact == null) {
          _notificationTappedAt = null;
          return;
        }
        final tappedAt = _notificationTappedAt;
        _notificationTappedAt = null;
        await _openConversationForContact(
          navigator: navigator,
          contact: contact,
          notificationTappedAt: tappedAt,
        );
        return;
      case NotificationRouteTargetKind.post:
      case NotificationRouteTargetKind.postComment:
        return;
    }
  }

  Future<void> _openIntroOrbitRoute({required NavigatorState navigator}) async {
    await openIntroNotificationOrbitRoute(
      navigator: navigator,
      appShellController: widget.appShellController,
      messageRepository: widget.messageRepository,
      builder: (feedUnreadCountListenable) => OrbitWired(
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
        groupConversationTracker: widget.groupConversationTracker,
        introductionRepository: widget.introductionRepository,
        introductionListener: widget.introductionListener,
        appShellController: widget.appShellController,
        feedUnreadCountListenable: feedUnreadCountListenable,
        pendingPostTargetStore: widget.pendingPostTargetStore,
        postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
        initialFilterTab: 'intros',
      ),
    );
  }

  Future<void> _openConversationForContact({
    required NavigatorState navigator,
    required ContactModel contact,
    DateTime? notificationTappedAt,
  }) async {
    navigator.push(
      buildConversationSlideUpRoute(
        builder: (_) => ConversationWired(
          contact: contact,
          identityRepo: widget.repository,
          messageRepo: widget.messageRepository,
          chatMessageListener: widget.chatMessageListener,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          contactRepo: widget.contactRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
          conversationTracker: widget.conversationTracker,
          audioRecorderService: widget.audioRecorderService,
          reactionRepo: widget.reactionRepository,
          reactionListener: widget.reactionListener,
          introductionRepository: widget.introductionRepository,
          appShellController: widget.appShellController,
          notificationTappedAt: notificationTappedAt,
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
    final routeTarget = _deferredNotificationRouteTarget;
    if (routeTarget == null) {
      return;
    }
    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_flushDeferredNotificationRouteTarget());
      });
      return;
    }
    _deferredNotificationRouteTarget = null;
    await _handleNotificationRouteTarget(routeTarget);
  }

  Future<void> _prepareNotificationRouteTarget(
    NotificationRouteTarget routeTarget,
  ) async {
    await prepareNotificationRouteTarget(
      routeTarget: routeTarget,
      drainOfflineInbox: widget.p2pService.drainOfflineInbox,
      bridge: widget.bridge,
      groupRepository: widget.groupRepository,
      groupMessageRepository: widget.groupMessageRepository,
      groupMessageListener: widget.groupMessageListener,
      mediaAttachmentRepository: widget.mediaAttachmentRepository,
      reactionRepository: widget.reactionRepository,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Orderly teardown: retriers → listeners → router → service → bridge
    widget.keyExchangeRetrier.dispose();
    widget.pendingPostFollowOnRetrier.dispose();
    widget.pendingPostDeliveryRetrier.dispose();
    widget.pendingPostMediaUploadRetrier.dispose();
    widget.pendingMessageRetrier.dispose();
    widget.introductionListener.dispose();
    widget.groupMembershipUpdateListener.dispose();
    widget.groupKeyUpdateListener.dispose();
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
    widget.pushRegistrationCoordinator?.dispose();
    widget.contactPresenceSnapshotRepository.dispose();
    widget.postRepository.dispose();
    widget.messageRouter.dispose();
    widget.p2pService.dispose();
    widget.bridge.dispose();
    widget.audioRecorderService.dispose();
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
  }

  void _onPaused() {
    // Fire-and-forget: we have at most a few hundred milliseconds.
    // handleAppPaused() is local DB only — no network calls, no p2pService.
    unawaited(
      handleAppPaused(
            messageRepo: widget.messageRepository,
            groupMsgRepo: widget.groupMessageRepository,
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
    if (_isResuming) {
      debugPrint('[LIFECYCLE] _onResumed() skipped — already resuming');
      return;
    }
    _isResuming = true;
    debugPrint('[LIFECYCLE] _onResumed() starting handleAppResumed...');

    try {
      widget.p2pService.markResumeStarted();
      await handleAppResumed(
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        retryPushRegistrationFn: widget.pushRegistrationCoordinator?.retryNow,
        contactRepo: widget.contactRepository,
        identityRepo: widget.repository,
        retryIncompleteKeyExchangesFn: () =>
            widget.keyExchangeRetrier.retryNow(trigger: 'app_resumed'),
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
        groupMessageListener: widget.groupMessageListener,
        pendingKeyRepairRepo: widget.groupPendingKeyRepairRepository,
        historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
        requestGroupKeyRepair: emitGroupKeyRepairRequest,
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
        retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(
          groupRepo: widget.groupRepository,
          groupMsgRepo: widget.groupMessageRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          identityRepo: widget.repository,
          mediaFileManager: widget.mediaFileManager,
        ),
        retryFailedGroupMessagesFn: () => retryFailedGroupMessages(
          groupMsgRepo: widget.groupMessageRepository,
          groupRepo: widget.groupRepository,
          identityRepo: widget.repository,
          bridge: widget.bridge,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
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
        ),
        retryFailedMessagesFn: () => retryFailedMessages(
          messageRepo: widget.messageRepository,
          identityRepo: widget.repository,
          contactRepo: widget.contactRepository,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
        ),
        retryUnackedMessagesFn: () => retryUnackedMessages(
          messageRepo: widget.messageRepository,
          p2pService: widget.p2pService,
        ),
        retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(
          bridge: widget.bridge,
          msgRepo: widget.groupMessageRepository,
          reactionReplayOutboxRepo: widget.groupReactionReplayOutboxRepository,
        ),
      );
      await sweepExpiredPosts(
        postRepo: widget.postRepository,
        mediaFileManager: widget.mediaFileManager,
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

    try {
      FirebaseMessaging.onMessage.listen((message) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_FOREGROUND_MESSAGE_RECEIVED',
          details: {
            'messageId': message.messageId,
            'dataKeys': message.data.keys.toList(),
          },
        );
        unawaited(
          handleForegroundRemoteMessage(
            data: message.data,
            messageId: message.messageId,
            drainOfflineInbox: widget.p2pService.drainOfflineInbox,
            drainGroupOfflineInboxForGroup: (groupId) async {
              final identity = await widget.repository.loadIdentity();
              return drainGroupOfflineInboxForGroup(
                bridge: widget.bridge,
                groupRepo: widget.groupRepository,
                msgRepo: widget.groupMessageRepository,
                groupId: groupId,
                mediaAttachmentRepo: widget.mediaAttachmentRepository,
                reactionRepo: widget.reactionRepository,
                groupMessageListener: widget.groupMessageListener,
                pendingKeyRepairRepo: widget.groupPendingKeyRepairRepository,
                historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
                requestGroupKeyRepair: emitGroupKeyRepairRequest,
                selfPeerId: identity?.peerId,
              );
            },
          ),
        );
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
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mknoon',
      navigatorKey: MyApp.navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: StartupRouter(
        repository: widget.repository,
        contactRepository: widget.contactRepository,
        contactRequestRepository: widget.contactRequestRepository,
        contactRequestListener: widget.contactRequestListener,
        contactRequestPresentationGate: widget.contactRequestPresentationGate,
        messageRepository: widget.messageRepository,
        postRepository: widget.postRepository,
        mediaAttachmentRepository: widget.mediaAttachmentRepository,
        chatMessageListener: widget.chatMessageListener,
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        mediaFileManager: widget.mediaFileManager,
        secureKeyStore: widget.secureKeyStore,
        imageProcessor: widget.imageProcessor,
        audioRecorderService: widget.audioRecorderService,
        conversationTracker: widget.conversationTracker,
        reactionRepository: widget.reactionRepository,
        reactionListener: widget.reactionListener,
        groupRepository: widget.groupRepository,
        groupMessageRepository: widget.groupMessageRepository,
        groupPendingKeyRepairRepository: widget.groupPendingKeyRepairRepository,
        groupHistoryGapRepairRepository: widget.groupHistoryGapRepairRepository,
        groupReactionReplayOutboxRepository:
            widget.groupReactionReplayOutboxRepository,
        groupMessageListener: widget.groupMessageListener,
        groupInviteListener: widget.groupInviteListener,
        groupConversationTracker: widget.groupConversationTracker,
        introductionRepository: widget.introductionRepository,
        introductionListener: widget.introductionListener,
        shareIntentService: widget.shareIntentService,
        initialShareIntentCapture: _initialShareIntentCapture,
        ensureRuntimeServicesReady: _ensureRuntimeServicesReady,
        appShellController: widget.appShellController,
        pendingPostTargetStore: widget.pendingPostTargetStore,
        postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
        contactPresenceSnapshotRepository:
            widget.contactPresenceSnapshotRepository,
        nearbyLocationService: widget.nearbyLocationService,
        pushRegistrationCoordinator: widget.pushRegistrationCoordinator,
        clearDeliveredNotifications:
            widget.notificationService.clearDeliveredNotifications,
        onNotificationRouteTarget: _handleNotificationRouteTarget,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
