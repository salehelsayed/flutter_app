import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'dart:io';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '../test/shared/fakes/in_memory_post_repository.dart';
import '../test/shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '_support/direct_inbox_custody_db_bindings.dart';
import '_support/fake_secure_key_store.dart';
import '_support/test_db_seeder.dart';
import '../test/shared/fakes/in_memory_feed_cleared_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 80,
    Duration step = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(step);
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }

    expect(finder, findsOneWidget);
  }

  // Desktop platforms need FFI; on mobile, sqflite_sqlcipher has native plugins.
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('Smoke test: New user generates identity', (
    WidgetTester tester,
  ) async {
    print('\n========================================');
    print('SMOKE TEST: New User Identity Generation');
    print('========================================\n');

    final secureKeyStore = FakeSecureKeyStore();
    final dbName = 'smoke_test_${DateTime.now().millisecondsSinceEpoch}.db';
    final postRepository = InMemoryPostRepository();
    final postsPrivacySettingsRepository =
        InMemoryPostsPrivacySettingsRepository();
    final appShellController = AppShellController();
    final pendingPostTargetStore = PendingPostTargetStore();

    print('[TEST] Step 1: Initialize database...');
    // 228 (TC-228-13H): this fixture instantiates the REAL media repository,
    // so it must open at the CURRENT production schema through the shared
    // registry — never a hand-maintained historical migration list.
    final db = await openCurrentProductionE2EDatabase(
      secureKeyStore: secureKeyStore,
      dbName: dbName,
    );
    print('[TEST] Database initialized');

    print('[TEST] Step 2: Create repository...');
    final repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
      secureKeyStore: secureKeyStore,
    );
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
    final contactRequestRepository = ContactRequestRepositoryImpl(
      dbLoadPendingRequests: () => dbLoadPendingRequests(db),
      dbLoadRequest: (peerId) => dbLoadRequest(db, peerId),
      dbUpsertRequest: (row) => dbUpsertRequest(db, row),
      dbUpdateRequestStatus: (peerId, status) =>
          dbUpdateRequestStatus(db, peerId, status),
      dbDeleteRequest: (peerId) => dbDeleteRequest(db, peerId),
      dbRequestExists: (peerId) => dbRequestExists(db, peerId),
    );
    final custodyDb = DirectInboxCustodyDbBindings(db);
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
      dbExistsMessageByContent:
          (contactPeerId, senderPeerId, text, timestamp) =>
              dbExistsMessageByContent(
                db,
                contactPeerId,
                senderPeerId,
                text,
                timestamp,
              ),
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
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbRecoverStuckSendingMessages(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbUpdateWireEnvelope: (id, wireEnvelope) =>
          dbUpdateWireEnvelope(db, id, wireEnvelope),
      dbStageOutgoingDirectTextInboxCustody: custodyDb.stage,
      dbLoadDirectInboxCustodyOutbox: custodyDb.load,
      dbLoadDirectInboxCustodyOutboxForMessage: custodyDb.loadForMessage,
      dbRecordDirectInboxCustodyFailureIfExact: custodyDb.recordFailureIfExact,
      dbCompleteAcceptedDirectInboxCustodyIfExact:
          custodyDb.completeAcceptedIfExact,
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbLoadStuckSendingOutgoingMessages(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
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

    final mediaAttachmentRepository = MediaAttachmentRepositoryImpl(
      dbSaveMediaAttachmentPreservingLocalState: (row) =>
          dbSaveMediaAttachmentPreservingLocalState(db, row),
      dbLoadMediaForMessage: (messageId, ownerLane) =>
          dbLoadMediaForMessage(db, messageId, ownerLane: ownerLane),
      dbLoadMediaById: (id) => dbLoadMediaById(db, id),
      dbLoadMediaForMessages: (messageIds, ownerLane) =>
          dbLoadMediaForMessages(db, messageIds, ownerLane: ownerLane),
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
    );

    print('[TEST] Step 3: Initialize Go bridge...');
    final bridge = GoBridgeClient();
    try {
      await bridge.initialize();
      print('[TEST] Bridge initialized successfully');
    } catch (e) {
      print('[TEST] ERROR: Bridge initialization failed: $e');
      rethrow;
    }

    final p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    final contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnPeerId: () => '',
    );
    final chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async {
        final identity = await repository.loadIdentity();
        return identity?.mlKemSecretKey;
      },
    );

    print('[TEST] Step 4: Build app widget...');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StartupRouter(
          repository: repository,
          feedClearedRepository: InMemoryFeedClearedRepository(),
          contactRepository: contactRepository,
          contactRequestRepository: contactRequestRepository,
          contactRequestListener: contactRequestListener,
          messageRepository: messageRepository,
          postRepository: postRepository,
          mediaAttachmentRepository: mediaAttachmentRepository,
          chatMessageListener: chatMessageListener,
          bridge: bridge,
          p2pService: p2pService,
          mediaFileManager: MediaFileManager(),
          secureKeyStore: secureKeyStore,
          imageProcessor: ImageProcessor(),
          appShellController: appShellController,
          pendingPostTargetStore: pendingPostTargetStore,
          postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        ),
      ),
    );

    // Wait for initial load with a bounded loop (screen has ongoing animations).
    print('[TEST] Step 5: Wait for app to load...');
    final newUserButton = find.text("I'm new here");
    await pumpUntilFound(tester, newUserButton);
    await tester.pump(const Duration(milliseconds: 1300));

    // Look for "I'm new here" button
    print('[TEST] Step 6: Looking for "I\'m new here" button...');

    if (newUserButton.evaluate().isEmpty) {
      print('[TEST] ERROR: Could not find "I\'m new here" button');
      print('[TEST] Current widget tree:');
      debugDumpApp();
      fail('Button not found');
    }

    print('[TEST] Found button, tapping...');
    await tester.ensureVisible(newUserButton.first);
    await tester.tap(newUserButton.first, warnIfMissed: false);
    await tester.pump();

    print('[TEST] Step 7: Waiting for identity generation...');
    // Wait for async operations with a hard timeout.
    Map<String, Object?>? identityRow;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      identityRow = await dbLoadIdentityRow(db);
      if (identityRow != null) {
        break;
      }
    }

    print('[TEST] Step 8: Checking results...');

    if (identityRow != null) {
      print('\n========================================');
      print('SUCCESS! Identity generated:');
      print('========================================');
      print('Peer ID: ${identityRow['peer_id']}');
      print(
        'Public Key: ${identityRow['public_key']?.toString().substring(0, 20)}...',
      );
      print('Created At: ${identityRow['created_at']}');

      // Verify DB secret columns are null (secrets stored in secure storage)
      expect(
        identityRow['mnemonic12'],
        isNull,
        reason: 'mnemonic12 should be null in DB (stored in secure storage)',
      );
      expect(
        identityRow['private_key'],
        isNull,
        reason: 'private_key should be null in DB (stored in secure storage)',
      );

      // Read mnemonic from secure storage
      final mnemonic = await secureKeyStore.read('identity_mnemonic12');
      print('Mnemonic (stored in secure storage): $mnemonic');
      print('========================================\n');

      expect(
        mnemonic,
        isNotNull,
        reason: 'mnemonic12 should exist in secure storage',
      );
      expect(mnemonic, isNot(contains('demo seed phrase')));
      expect(mnemonic!.split(' ').length, equals(12));

      print('[TEST] PASS: Real BIP39 mnemonic generated!');
    } else {
      print('[TEST] ERROR: No identity found in database');
      fail('Identity not created');
    }

    // 228 (TC-228-13H): representative owner-state round-trip through the
    // REAL repository on the CURRENT production schema — direct/group owner
    // plus bookmark and video-resume state survive an encrypted save/load.
    print('[TEST] Step 9: 228 media owner-state round-trip...');
    await mediaAttachmentRepository.saveAttachment(
      const MediaAttachment(
        id: 'smoke-att-direct',
        messageId: 'smoke-msg',
        mime: 'image/jpeg',
        size: 1,
        mediaType: 'image',
        downloadStatus: 'done',
        createdAt: '2026-07-10T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );
    await mediaAttachmentRepository.saveAttachment(
      const MediaAttachment(
        id: 'smoke-att-group',
        messageId: 'smoke-msg',
        mime: 'video/mp4',
        size: 1,
        mediaType: 'video',
        durationMs: 9000,
        downloadStatus: 'done',
        createdAt: '2026-07-10T00:00:01.000Z',
      ),
      owner: MediaOwnerLane.group,
    );
    await mediaAttachmentRepository.setBookmarked(
      'smoke-att-direct',
      bookmarked: true,
    );
    await mediaAttachmentRepository.updatePlaybackPosition(
      'smoke-att-group',
      4200,
    );
    final directBack = await mediaAttachmentRepository.getAttachmentsForMessage(
      'smoke-msg',
      owner: MediaOwnerLane.direct,
    );
    expect(directBack.map((a) => a.id), ['smoke-att-direct']);
    expect(directBack.single.ownerLane, MediaOwnerLane.direct);
    expect(directBack.single.isBookmarked, isTrue);
    final groupBack = await mediaAttachmentRepository.getAttachmentsForMessage(
      'smoke-msg',
      owner: MediaOwnerLane.group,
    );
    expect(groupBack.map((a) => a.id), ['smoke-att-group']);
    expect(groupBack.single.ownerLane, MediaOwnerLane.group);
    expect(groupBack.single.lastPlaybackPositionMs, 4200);
    print('[TEST] PASS: owner-state round-trip on current schema');

    // Cleanup
    contactRequestListener.dispose();
    chatMessageListener.dispose();
    p2pService.dispose();
    bridge.dispose();
    postsPrivacySettingsRepository.dispose();
    await db.close();
  });
}
