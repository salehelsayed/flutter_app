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
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_comments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_comment_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_location_presence_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_origin_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_passes_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_privacy_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_pending_child_events_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/download_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/publish_post_presence_update_use_case.dart';
import 'package:flutter_app/features/posts/application/post_presence_listener.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_notification_open_coordinator.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository_impl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupTiming.instance.mark('app_start');

  // Initialize Firebase (mobile only — not available on desktop)
  final bool isDesktop =
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
  if (!isDesktop) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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

  // Initialize UserAvatar documents directory for file-based avatar loading
  final appDocDir = await getApplicationDocumentsDirectory();
  UserAvatar.setDocumentsDir(appDocDir.path);

  // Initialize database based on platform
  if (isDesktop) {
    // Desktop platforms need FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 1. Create secure key store
  final secureKeyStore = FlutterSecureKeyStore();

  // 2. Open encrypted database (handles plaintext→encrypted migration)
  final db = await openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: 'identity.db',
    version: 30,
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
    },
  );

  // 3. Run one-time secrets migration (DB → secure storage)
  //    Must run BEFORE migration 005 so CHECK constraints don't reject
  //    existing non-null secret values during the table rebuild.
  await migrateSecretsToSecureStorage(db: db, secureKeyStore: secureKeyStore);

  // 4. Apply CHECK constraints now that secret columns are guaranteed NULL
  await runSecretNullChecksMigration(db);

  // 5. Create repository with database helpers + secure key store
  final repository = IdentityRepositoryImpl(
    dbLoadIdentityRow: () => dbLoadIdentityRow(db),
    dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
    secureKeyStore: secureKeyStore,
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
    dbLoadConversationThreadSummaries: (contactPeerIds) =>
        dbLoadConversationThreadSummaries(db, contactPeerIds),
  );

  final postRepository = PostRepositoryImpl(
    dbInsertPost: (row) => dbInsertPost(db, row),
    dbLoadPost: (postId) => dbLoadPost(db, postId),
    dbLoadPostsFeed: () => dbLoadPostsFeed(db),
    dbLoadExpiredPosts: (nowIso) => dbLoadExpiredPosts(db, nowIso),
    dbDeletePostCascade: (postId) => dbDeletePostCascade(db, postId),
    dbUpsertRecipientDelivery: (row) => dbUpsertPostRecipientDelivery(db, row),
    dbLoadRecipientDeliveries: (postId) =>
        dbLoadPostRecipientDeliveries(db, postId),
    dbUpsertPostPass: (row) => dbUpsertPostPass(db, row),
    dbLoadPostPass: (passId) => dbLoadPostPass(db, passId),
    dbLoadPostPasses: (postId) => dbLoadPostPasses(db, postId),
    dbCountPostPasses: (postId) => dbCountPostPasses(db, postId),
    dbLoadPostPassCounts: (postIds) => dbLoadPostPassCounts(db, postIds),
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
    dbLoadPostMediaForPosts: (postIds) =>
        dbLoadPostMediaAttachmentsForPosts(db, postIds),
    dbUpdatePostMediaLocalPath: (mediaId, localPath) =>
        dbUpdatePostMediaLocalPath(db, mediaId, localPath),
    dbUpdatePostMediaDownloadStatus: (mediaId, downloadStatus) =>
        dbUpdatePostMediaDownloadStatus(db, mediaId, downloadStatus),
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
    dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
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
    dbInsertGroupKey: (row) => dbInsertGroupKey(db, row),
    dbLoadLatestGroupKey: (groupId) => dbLoadLatestGroupKey(db, groupId),
    dbLoadGroupKeyByGeneration: (groupId, generation) =>
        dbLoadGroupKeyByGeneration(db, groupId, generation),
    dbDeleteAllGroupKeys: (groupId) => dbDeleteAllGroupKeys(db, groupId),
  );

  // Create group message repository
  final groupMessageRepository = GroupMessageRepositoryImpl(
    dbInsertGroupMessage: (row) => dbInsertGroupMessage(db, row),
    dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) =>
        dbLoadGroupMessagesPage(db, groupId, limit: limit, offset: offset),
    dbLoadGroupMessage: (id) => dbLoadGroupMessage(db, id),
    dbLoadLatestGroupMessage: (groupId) =>
        dbLoadLatestGroupMessage(db, groupId),
    dbUpdateGroupMessageStatus: (id, status) =>
        dbUpdateGroupMessageStatus(db, id, status),
    dbCountGroupMessages: (groupId) => dbCountGroupMessages(db, groupId),
    dbCountUnreadGroupMessages: (groupId) =>
        dbCountUnreadGroupMessages(db, groupId),
    dbCountTotalUnreadGroupMessages: () => dbCountTotalUnreadGroupMessages(db),
    dbMarkGroupMessagesAsRead: (groupId) =>
        dbMarkGroupMessagesAsRead(db, groupId),
    dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(db, id),
    dbExistsGroupMessageByContent: (groupId, senderPeerId, text, timestamp) =>
        dbExistsGroupMessageByContent(
          db,
          groupId,
          senderPeerId,
          text,
          timestamp,
        ),
    dbDeleteGroupMessagesForGroup: (groupId) =>
        dbDeleteGroupMessagesForGroup(db, groupId),
    dbLoadGroupThreadSummaries: (groupIds) =>
        dbLoadGroupThreadSummaries(db, groupIds),
  );

  // Create introduction repository
  final introductionRepository = IntroductionRepositoryImpl(
    dbInsertIntroduction: (row) => dbInsertIntroduction(db, row),
    dbLoadIntroduction: (id) => dbLoadIntroduction(db, id),
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
  );

  // Create media file manager
  final mediaFileManager = MediaFileManager();

  // Create image processor (EXIF stripping + quality compression)
  final imageProcessor = ImageProcessor();

  // Create audio recorder service
  final audioRecorderService = RecordAudioRecorderService();

  // Create and initialize the bridge (Go native)
  final Bridge bridge = GoBridgeClient();
  await bridge.initialize();
  StartupTiming.instance.mark('bridge_initialized');

  // Create local P2P service for WiFi-first delivery
  final localDiscovery = BonsoirDiscoveryService();
  final localWsServer = LocalWsServer();
  final localP2PService = LocalP2PService(
    discovery: localDiscovery,
    wsServer: localWsServer,
  );

  // Create P2P service (uses the same bridge + local P2P)
  final p2pService = P2PServiceImpl(
    bridge: bridge,
    localP2PService: localP2PService,
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
  );

  // Create notification service and conversation trackers
  final notificationService = FlutterNotificationService();
  await notificationService.initialize();
  final conversationTracker = ActiveConversationTracker();
  final groupConversationTracker = ActiveConversationTracker();
  final appShellController = AppShellController();
  final pendingPostTargetStore = PendingPostTargetStore();

  // Create chat message listener
  final chatMessageListener = ChatMessageListener(
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
  );

  // Create reaction listener
  final reactionListener = ReactionListener(
    reactionStream: messageRouter.reactionStream,
    reactionRepo: reactionRepository,
    contactRepo: contactRepository,
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

  // Create group invite listener
  final groupInviteListener = GroupInviteListener(
    groupInviteStream: messageRouter.groupInviteStream,
    groupRepo: groupRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    msgRepo: groupMessageRepository,
    mediaAttachmentRepo: mediaAttachmentRepository,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
  );

  // Create group key update listener
  final groupKeyUpdateListener = GroupKeyUpdateListener(
    groupKeyUpdateStream: messageRouter.groupKeyUpdateStream,
    groupRepo: groupRepository,
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
  );

  // Create introduction listener
  final introductionListener = IntroductionListener(
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
  );

  // Create key exchange retrier
  final keyExchangeRetrier = KeyExchangeRetrier(
    p2pService: p2pService,
    contactRepo: contactRepository,
    identityRepo: repository,
    bridge: bridge,
  );

  // Start router first, then listeners, then retriers
  messageRouter.start();
  contactRequestListener.start();
  chatMessageListener.start();
  postListener.start();
  postCommentListener.start();
  postReactionListener.start();
  postPresenceListener.start();
  postPassListener.start();
  reactionListener.start();
  profileUpdateListener.start();
  groupMessageListener.start(
    groupMessageStreamController.stream,
    incomingGroupReactions: groupReactionStreamController.stream,
  );
  groupInviteListener.start();
  groupKeyUpdateListener.start();

  introductionListener.start();

  // NOTE: rejoinGroupTopics and drainGroupOfflineInbox are called in
  // StartupRouter._doStartP2P() AFTER node:start completes. They require
  // the Go node to be running (pubsub must be initialized).
  pendingMessageRetrier.start();
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

  final shareIntentService = ShareIntentService();
  await shareIntentService.captureInitialIntent();
  await sweepExpiredPosts(
    postRepo: postRepository,
    mediaFileManager: mediaFileManager,
  );

  runApp(
    MyApp(
      repository: repository,
      contactRepository: contactRepository,
      contactRequestRepository: contactRequestRepository,
      contactRequestListener: contactRequestListener,
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
      reactionListener: reactionListener,
      profileUpdateListener: profileUpdateListener,
      messageRouter: messageRouter,
      pendingMessageRetrier: pendingMessageRetrier,
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
      groupMessageListener: groupMessageListener,
      groupInviteListener: groupInviteListener,
      groupKeyUpdateListener: groupKeyUpdateListener,
      groupConversationTracker: groupConversationTracker,
      introductionRepository: introductionRepository,
      introductionListener: introductionListener,
      shareIntentService: shareIntentService,
    ),
  );
  StartupTiming.instance.mark('run_app_called');
}

class MyApp extends StatefulWidget {
  final IdentityRepositoryImpl repository;
  final ContactRepositoryImpl contactRepository;
  final ContactRequestRepositoryImpl contactRequestRepository;
  final ContactRequestListener contactRequestListener;
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
  final ReactionListener reactionListener;
  final ProfileUpdateListener profileUpdateListener;
  final IncomingMessageRouter messageRouter;
  final PendingMessageRetrier pendingMessageRetrier;
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
  final GroupMessageListener groupMessageListener;
  final GroupInviteListener groupInviteListener;
  final GroupKeyUpdateListener groupKeyUpdateListener;
  final ActiveConversationTracker groupConversationTracker;
  final IntroductionRepositoryImpl introductionRepository;
  final IntroductionListener introductionListener;
  final ShareIntentService shareIntentService;

  static final navigatorKey = GlobalKey<NavigatorState>();

  const MyApp({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
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
    required this.reactionListener,
    required this.profileUpdateListener,
    required this.messageRouter,
    required this.pendingMessageRetrier,
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
    required this.groupMessageListener,
    required this.groupInviteListener,
    required this.groupKeyUpdateListener,
    required this.groupConversationTracker,
    required this.introductionRepository,
    required this.introductionListener,
    required this.shareIntentService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isResuming = false;
  NotificationRouteTarget? _deferredNotificationRouteTarget;
  late final PostNotificationOpenCoordinator _postNotificationOpenCoordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _postNotificationOpenCoordinator = PostNotificationOpenCoordinator(
      pendingTargetStore: widget.pendingPostTargetStore,
      postRepository: widget.postRepository,
      appShellController: widget.appShellController,
      revealPostsSurface: _revealPostsSurface,
    );
    _setupPushListeners();
    _setupNotificationTapHandler();
    _setupShareIntentHandling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_flushDeferredNotificationRouteTarget());
    });
    unawaited(_handleInitialLocalNotificationLaunch());
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
      conversationTracker: widget.conversationTracker,
      audioRecorderService: widget.audioRecorderService,
      reactionRepository: widget.reactionRepository,
      reactionListener: widget.reactionListener,
      groupRepository: widget.groupRepository,
      groupMessageRepository: widget.groupMessageRepository,
      groupMessageListener: widget.groupMessageListener,
      groupConversationTracker: widget.groupConversationTracker,
      introductionRepository: widget.introductionRepository,
    );
  }

  void _setupNotificationTapHandler() {
    widget.notificationService.onNotificationTap = _onNotificationTap;
  }

  Future<void> _handleInitialLocalNotificationLaunch() async {
    try {
      await routeInitialLocalNotificationOpen(
        consumeInitialPayload: widget.notificationService.consumeInitialPayload,
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
    try {
      await routeNotificationPayload(
        payload: payload,
        onRouteTarget: _handleNotificationRouteTarget,
      );
    } catch (e) {
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
      await _postNotificationOpenCoordinator.handleRouteTarget(
        routeTarget: routeTarget,
        drainOfflineInbox: widget.p2pService.drainOfflineInbox,
      );
      return;
    }

    switch (routeTarget.kind) {
      case NotificationRouteTargetKind.intros:
        navigator.push(
          buildOrbitSlideUpRoute(
            builder: (_) => OrbitWired(
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
              groupMessageListener: widget.groupMessageListener,
              groupInviteListener: widget.groupInviteListener,
              groupConversationTracker: widget.groupConversationTracker,
              introductionRepository: widget.introductionRepository,
              introductionListener: widget.introductionListener,
              appShellController: widget.appShellController,
              pendingPostTargetStore: widget.pendingPostTargetStore,
              postsPrivacySettingsRepository:
                  widget.postsPrivacySettingsRepository,
              initialFilterTab: 'intros',
            ),
          ),
        );
        return;
      case NotificationRouteTargetKind.group:
        final group = await widget.groupRepository.getGroup(
          routeTarget.groupId!,
        );
        if (group == null) {
          return;
        }
        navigator.push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group,
              groupRepo: widget.groupRepository,
              msgRepo: widget.groupMessageRepository,
              groupMessageListener: widget.groupMessageListener,
              bridge: widget.bridge,
              identityRepo: widget.repository,
              contactRepo: widget.contactRepository,
              p2pService: widget.p2pService,
              groupConversationTracker: widget.groupConversationTracker,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              audioRecorderService: widget.audioRecorderService,
              reactionRepo: widget.reactionRepository,
            ),
          ),
        );
        return;
      case NotificationRouteTargetKind.conversation:
        final contact = await widget.contactRepository.getContact(
          routeTarget.peerId!,
        );
        if (contact == null) {
          return;
        }
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
            ),
          ),
        );
        return;
      case NotificationRouteTargetKind.post:
      case NotificationRouteTargetKind.postComment:
        return;
    }
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Orderly teardown: retriers → listeners → router → service → bridge
    widget.keyExchangeRetrier.dispose();
    widget.pendingMessageRetrier.dispose();
    widget.introductionListener.dispose();
    widget.groupKeyUpdateListener.dispose();
    widget.groupInviteListener.dispose();
    widget.groupMessageListener.dispose();
    widget.profileUpdateListener.dispose();
    widget.reactionListener.dispose();
    widget.postListener.dispose();
    widget.postCommentListener.dispose();
    widget.postReactionListener.dispose();
    widget.postPresenceListener.dispose();
    widget.postPassListener.dispose();
    widget.chatMessageListener.dispose();
    widget.contactRequestListener.dispose();
    _postNotificationOpenCoordinator.dispose();
    widget.contactPresenceSnapshotRepository.dispose();
    widget.postRepository.dispose();
    widget.messageRouter.dispose();
    widget.p2pService.dispose();
    widget.bridge.dispose();
    widget.audioRecorderService.dispose();
    widget.notificationService.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[LIFECYCLE] AppLifecycleState changed → ${state.name}');
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_STATE_CHANGED',
      details: {'state': state.name},
    );

    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  Future<void> _onResumed() async {
    if (_isResuming) {
      debugPrint('[LIFECYCLE] _onResumed() skipped — already resuming');
      return;
    }
    _isResuming = true;
    debugPrint('[LIFECYCLE] _onResumed() starting handleAppResumed...');

    try {
      await handleAppResumed(
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        contactRepo: widget.contactRepository,
        identityRepo: widget.repository,
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        reactionRepo: widget.reactionRepository,
        nearbyLocationService: widget.nearbyLocationService,
      );
      await sweepExpiredPosts(
        postRepo: widget.postRepository,
        mediaFileManager: widget.mediaFileManager,
      );
    } finally {
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
          details: {'messageId': message.messageId},
        );
        unawaited(widget.p2pService.drainOfflineInbox());
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
        unawaited(
          routeRemoteNotificationOpen(
            data: message.data,
            onRouteTarget: _handleNotificationRouteTarget,
            onMissingRouteTarget: widget.p2pService.drainOfflineInbox,
          ),
        );
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
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: StartupRouter(
        repository: widget.repository,
        contactRepository: widget.contactRepository,
        contactRequestRepository: widget.contactRequestRepository,
        contactRequestListener: widget.contactRequestListener,
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
        groupMessageListener: widget.groupMessageListener,
        groupInviteListener: widget.groupInviteListener,
        groupConversationTracker: widget.groupConversationTracker,
        introductionRepository: widget.introductionRepository,
        introductionListener: widget.introductionListener,
        shareIntentService: widget.shareIntentService,
        appShellController: widget.appShellController,
        pendingPostTargetStore: widget.pendingPostTargetStore,
        postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
        contactPresenceSnapshotRepository:
            widget.contactPresenceSnapshotRepository,
        nearbyLocationService: widget.nearbyLocationService,
        onNotificationRouteTarget: _handleNotificationRouteTarget,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
