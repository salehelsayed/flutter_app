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
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '_support/canonical_runtime_device_test_lease.dart';
import '_support/direct_inbox_custody_db_bindings.dart';
import '_support/fake_secure_key_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'conversation-bridge-device-test',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('Send message through real Go bridge', (tester) async {
    print('\n========================================');
    print('CONVERSATION BRIDGE TEST');
    print('========================================\n');

    // 1. Open real encrypted DB
    final secureKeyStore = FakeSecureKeyStore();
    final dbName =
        'conversation_bridge_test_${DateTime.now().millisecondsSinceEpoch}.db';
    final db = await openEncryptedDatabase(
      secureKeyStore: secureKeyStore,
      dbName: dbName,
      version: currentIdentityDatabaseVersion,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
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

    final custodyDb = DirectInboxCustodyDbBindings(db);
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
      dbStageOutgoingOrdinaryAttempt:
          ({required expectedRow, required stagedRow, required kind}) =>
              dbStageOutgoingOrdinaryAttempt(
                db,
                expectedRow: expectedRow,
                stagedRow: stagedRow,
                kind: kind,
              ),
      dbStageOutgoingDirectTextInboxCustody: custodyDb.stage,
      dbLoadDirectInboxCustodyOutbox: custodyDb.load,
      dbLoadDirectInboxCustodyOutboxForMessage: custodyDb.loadForMessage,
      dbLoadDirectInboxCustodyOutboxOwnerForMessageId:
          custodyDb.loadOwnerForMessageId,
      dbRecordDirectInboxCustodyFailureIfExact: custodyDb.recordFailureIfExact,
      dbCompleteAcceptedDirectInboxCustodyIfExact:
          custodyDb.completeAcceptedIfExact,
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

    final bridge = GoBridgeClient();
    try {
      await bridge.initialize();
      print('[TEST] Bridge initialized');
    } catch (e) {
      print('[TEST] ERROR: Bridge initialization failed: $e');
      rethrow;
    }

    final p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );

    // 3. Generate identity via real bridge
    print('[TEST] Generating identity via real bridge...');
    final genResponse = await bridge.send(
      jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
    );
    final genResult = jsonDecode(genResponse) as Map<String, dynamic>;
    expect(genResult['ok'], true, reason: 'identity.generate should succeed');

    final identity = genResult['identity'] as Map<String, dynamic>;
    final peerId = identity['peerId'] as String;
    final privateKey = identity['privateKey'] as String;
    print('[TEST] Identity generated: ${peerId.substring(0, 20)}...');

    // 4. Add a valid but unreachable contact.
    final targetGenResponse = await bridge.send(
      jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
    );
    final targetGenResult =
        jsonDecode(targetGenResponse) as Map<String, dynamic>;
    expect(
      targetGenResult['ok'],
      true,
      reason: 'second identity.generate should succeed',
    );
    final targetIdentity = targetGenResult['identity'] as Map<String, dynamic>;
    final targetPeerId = targetIdentity['peerId'] as String;
    final targetMlKemResponse = await bridge.send(
      jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
    );
    final targetMlKemResult =
        jsonDecode(targetMlKemResponse) as Map<String, dynamic>;
    expect(
      targetMlKemResult['ok'],
      true,
      reason: 'target mlkem.keygen should succeed',
    );
    final targetMlKemPublicKey = targetMlKemResult['publicKey'] as String;
    await contactRepo.addContact(
      ContactModel(
        peerId: targetPeerId,
        publicKey: targetIdentity['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'FakeTarget',
        signature: 'sig-fake-target',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: targetMlKemPublicKey,
      ),
    );
    print(
      '[TEST] Valid unreachable contact added: ${targetPeerId.substring(0, 20)}...',
    );

    // 5. Start real P2P node
    print('[TEST] Starting P2P node...');
    // This test isolates the send path. Avoid background warm tasks started by
    // startNode(), which can overlap with the immediate send attempt.
    final started = await p2pService.startNodeCore(privateKey, peerId);
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
      bridge: bridge,
      recipientMlKemPublicKey: targetMlKemPublicKey,
    );

    print('[TEST] Send result: $result');
    print('[TEST] Message: $msg');

    // The message should be persisted regardless of delivery outcome.
    // With a real relay, inbox store succeeds → 'inboxed' custody.
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
    // With relay: 'inboxed' (inbox custody accepted) or 'delivered' (live ack)
    // Without relay: 'failed' (all retries exhausted)
    expect(
      stored.first.status,
      anyOf('delivered', 'inboxed', 'failed'),
      reason:
          'Status should be delivered, inboxed custody, or failed (no relay)',
    );

    if (result == SendChatMessageResult.success) {
      print('[TEST] PASS: Message accepted by live or inbox transport');
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
