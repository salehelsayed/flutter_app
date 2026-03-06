// Integration test: Conversation send path through the real Go bridge.
//
// Exercises the full DI stack with real components:
//   GoBridgeClient → P2PServiceImpl → sendChatMessage → MessageRepositoryImpl
//
// Unlike the unit-level two_user_message_exchange_test.dart (which uses
// FakeP2PService), this test proves that the real bridge, real encrypted DB,
// and real P2P service are wired correctly for the conversation feature.
//
// Since this runs on a single device, the target peer won't be reachable.
// The test verifies:
//   - The full send codepath executes through the real bridge
//   - The message is persisted in the real encrypted DB
//   - ChatMessageListener is wired to the real event stream

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
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
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

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

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('Send message through real Go bridge', (tester) async {
    print('\n========================================');
    print('CONVERSATION BRIDGE TEST');
    print('========================================\n');

    // 1. Open real encrypted DB
    final secureKeyStore = _FakeSecureKeyStore();
    final db = await openEncryptedDatabase(
      secureKeyStore: secureKeyStore,
      dbName: 'conversation_bridge_test.db',
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

    // 2. Wire real repos + bridge + P2PServiceImpl
    final contactRepo = ContactRepositoryImpl(
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

    final messageRepo = MessageRepositoryImpl(
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

    final bridge = GoBridgeClient();
    try {
      await bridge.initialize();
      print('[TEST] Bridge initialized');
    } catch (e) {
      print('[TEST] ERROR: Bridge initialization failed: $e');
      rethrow;
    }

    final p2pService = P2PServiceImpl(bridge: bridge);

    // 3. Generate identity via real bridge
    print('[TEST] Generating identity via real bridge...');
    final genResponse = await bridge.send(jsonEncode({
      'cmd': 'identity.generate',
      'payload': {},
    }));
    final genResult = jsonDecode(genResponse) as Map<String, dynamic>;
    expect(genResult['ok'], true, reason: 'identity.generate should succeed');

    final identity = genResult['identity'] as Map<String, dynamic>;
    final peerId = identity['peerId'] as String;
    final privateKey = identity['privateKey'] as String;
    print('[TEST] Identity generated: ${peerId.substring(0, 20)}...');

    // 4. Add a fake contact (the target peer — won't be reachable)
    const targetPeerId = '12D3KooWFakeTargetPeerForBridgeTest001';
    await contactRepo.addContact(ContactModel(
      peerId: targetPeerId,
      publicKey: 'pk-fake-target',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'FakeTarget',
      signature: 'sig-fake-target',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
    ));
    print('[TEST] Fake contact added');

    // 5. Start real P2P node
    print('[TEST] Starting P2P node...');
    final started = await p2pService.startNode(privateKey, peerId);
    if (!started) {
      p2pService.dispose();
      bridge.dispose();
      await db.close();
      fail('P2P node failed to start (relay unreachable)');
    }
    print('[TEST] P2P node started');

    // 6. Wire ChatMessageListener to real message stream
    final chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => null,
    );
    chatListener.start();
    print('[TEST] ChatMessageListener started');

    // 7. Send message through real bridge path
    // The target peer is unreachable, so this exercises:
    //   discover (not found) → retry 3x → inbox store fallback
    print('[TEST] Sending message through real bridge...');
    final (result, msg) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: 'Hello from bridge E2E!',
      senderPeerId: peerId,
      senderUsername: 'TestUser',
    );

    print('[TEST] Send result: $result');
    print('[TEST] Message: $msg');

    // The message should be persisted regardless of delivery outcome.
    // With a real relay, inbox store succeeds → 'delivered'.
    // Without relay connectivity, all retries fail → 'failed'.
    // Either way, the message should be in the DB.
    expect(msg, isNotNull, reason: 'Message should be persisted');

    // 8. Verify message persisted in real DB
    final stored = await messageRepo.getMessagesForContact(targetPeerId);
    expect(stored.length, 1, reason: 'Exactly one message should be stored');
    expect(stored.first.text, 'Hello from bridge E2E!');
    expect(stored.first.isIncoming, false);
    expect(stored.first.contactPeerId, targetPeerId);
    expect(stored.first.senderPeerId, peerId);
    print('[TEST] Message verified in DB: status=${stored.first.status}');

    // 9. Verify the message status is reasonable
    // With relay: 'delivered' (inbox accepted)
    // Without relay: 'failed' (all retries exhausted)
    expect(
      stored.first.status,
      anyOf('delivered', 'failed'),
      reason: 'Status should be delivered (inbox) or failed (no relay)',
    );

    if (result == SendChatMessageResult.success) {
      print('[TEST] PASS: Message delivered via inbox fallback');
    } else {
      print('[TEST] PASS: Message persisted as failed (relay unreachable)');
    }

    print('\n========================================');
    print('SUCCESS: Conversation bridge test passed');
    print('========================================\n');

    // Cleanup
    chatListener.dispose();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
  });
}
