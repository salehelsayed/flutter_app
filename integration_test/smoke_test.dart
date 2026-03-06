import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'dart:io';

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> _store = {};
  @override
  Future<String?> read(String key) async => _store[key];
  @override
  Future<void> write(String key, String value) async => _store[key] = value;
  @override
  Future<void> delete(String key) async => _store.remove(key);
  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

    final secureKeyStore = _FakeSecureKeyStore();

    print('[TEST] Step 1: Initialize database...');
    final db = await openEncryptedDatabase(
      secureKeyStore: secureKeyStore,
      dbName: 'smoke_test.db',
      version: 11,
      onCreate: (db, version) async {
        await runIdentityTableMigration(db);
        await runMessagesTableMigration(db);
        await runMlKemKeysMigration(db);
        await runSecretNullChecksMigration(db);
        await runReadAtColumnMigration(db);
        await runArchiveColumnsMigration(db);
        await runBlockColumnsMigration(db);
        await runQuotedMessageIdMigration(db);
        await runMediaAttachmentsMigration(db);
        await runAvatarVersionMigration(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await runMessagesTableMigration(db);
        if (oldVersion < 3) await runMlKemKeysMigration(db);
        if (oldVersion < 5) await runSecretNullChecksMigration(db);
        if (oldVersion < 6) await runReadAtColumnMigration(db);
        if (oldVersion < 7) await runArchiveColumnsMigration(db);
        if (oldVersion < 8) await runBlockColumnsMigration(db);
        if (oldVersion < 9) await runQuotedMessageIdMigration(db);
        if (oldVersion < 10) await runMediaAttachmentsMigration(db);
        if (oldVersion < 11) await runAvatarVersionMigration(db);
      },
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
          dbLoadMessagesPage(db, contactPeerId,
              limit: limit, beforeTimestamp: beforeTimestamp),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
    );

    final mediaAttachmentRepository = MediaAttachmentRepositoryImpl(
      dbInsertMediaAttachment: (row) => dbInsertMediaAttachment(db, row),
      dbLoadMediaForMessage: (messageId) =>
          dbLoadMediaForMessage(db, messageId),
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

    print('[TEST] Step 3: Initialize Go bridge...');
    final bridge = GoBridgeClient();
    try {
      await bridge.initialize();
      print('[TEST] Bridge initialized successfully');
    } catch (e) {
      print('[TEST] ERROR: Bridge initialization failed: $e');
      rethrow;
    }

    final p2pService = P2PServiceImpl(bridge: bridge);
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
        home: StartupRouter(
          repository: repository,
          contactRepository: contactRepository,
          contactRequestRepository: contactRequestRepository,
          contactRequestListener: contactRequestListener,
          messageRepository: messageRepository,
          mediaAttachmentRepository: mediaAttachmentRepository,
          chatMessageListener: chatMessageListener,
          bridge: bridge,
          p2pService: p2pService,
          mediaFileManager: MediaFileManager(),
          secureKeyStore: secureKeyStore,
          imageProcessor: ImageProcessor(),
        ),
      ),
    );

    // Wait for initial load with a bounded loop (screen has ongoing animations).
    print('[TEST] Step 5: Wait for app to load...');
    final newUserButton = find.text("I'm new here");
    for (var i = 0; i < 20 && newUserButton.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

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
      expect(identityRow['mnemonic12'], isNull,
          reason: 'mnemonic12 should be null in DB (stored in secure storage)');
      expect(identityRow['private_key'], isNull,
          reason: 'private_key should be null in DB (stored in secure storage)');

      // Read mnemonic from secure storage
      final mnemonic = await secureKeyStore.read('identity_mnemonic12');
      print('Mnemonic (stored in secure storage): $mnemonic');
      print('========================================\n');

      expect(mnemonic, isNotNull,
          reason: 'mnemonic12 should exist in secure storage');
      expect(mnemonic, isNot(contains('demo seed phrase')));
      expect(mnemonic!.split(' ').length, equals(12));

      print('[TEST] PASS: Real BIP39 mnemonic generated!');
    } else {
      print('[TEST] ERROR: No identity found in database');
      fail('Identity not created');
    }

    // Cleanup
    contactRequestListener.dispose();
    chatMessageListener.dispose();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
  });
}
