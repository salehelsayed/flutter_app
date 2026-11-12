import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/data/repositories/delivery_receipt_outbox_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../conversation/domain/repositories/fake_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late Database database;
  late FakeP2PService transport;
  late DateTime now;
  late SqlDeliveryReceiptOutboxRepository repository;
  late DeliveryReceiptOutbox outbox;

  Future<void> open() async {
    database = await databaseFactoryFfiNoIsolate.openDatabase(
      '${directory.path}/receipts.sqlite',
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    repository = SqlDeliveryReceiptOutboxRepository(database);
    outbox = DeliveryReceiptOutbox(
      repository: repository,
      p2pService: () => transport,
      now: () => now,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('receipt-outbox-');
    now = DateTime.utc(2026, 11, 12);
    transport = FakeP2PService(
      initialState: NodeState.stopped,
      sendMessageWithReplyResult: const SendMessageResult(sent: false),
      storeInInboxResult: false,
    );
    await open();
  });
  tearDown(() async {
    transport.dispose();
    groupRecoveryGate.resetForTest();
    if (database.isOpen) await database.close();
    await directory.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> rows() =>
      database.query('delivery_receipt_outbox');

  PendingMessageRetrier retrier({Stream<void>? restored, bool held = false}) =>
      PendingMessageRetrier(
        p2pService: transport,
        messageRepo: FakeMessageRepository(),
        identityRepo: FakeIdentityRepository(),
        contactRepo: FakeContactRepository(),
        bridge: FakeBridge(),
        drainDeliveryReceiptOutboxFn: outbox.drain,
        networkRestoredSignal: restored,
        isExternalRecoveryInProgressFn: () => held,
        retryFailedMessagesOverride: () async => 0,
        retryUnackedMessagesOverride: () async => 0,
        retryDebounce: Duration.zero,
        networkRestoredDebounce: Duration.zero,
        periodicRetryInterval: const Duration(days: 1),
        groupContinuitySweepInterval: const Duration(days: 1),
      );

  test(
    'BL24D1 failed receipt survives SQLite reopen then online settles once',
    () async {
      final sender = await MediaRepositoryRealDbFixture.create(
        singleInstance: false,
        databaseFactoryOverride: databaseFactoryFfiNoIsolate,
      );
      addTearDown(sender.dispose);
      const id = 'original-receipt-target';
      await sender.messageRepo.saveMessage(
        ConversationMessage(
          id: id,
          contactPeerId: 'receipt-receiver',
          senderPeerId: 'receipt-sender',
          text: 'already durable at receiver',
          timestamp: now.toIso8601String(),
          createdAt: now.toIso8601String(),
          status: 'inboxed',
          isIncoming: false,
          wireEnvelope: MessagePayload.buildEncryptedEnvelope(
            id: id,
            senderPeerId: 'receipt-sender',
            senderUsername: 'Sender',
            kem: 'kem',
            ciphertext: 'ciphertext',
            nonce: 'nonce',
          ),
        ),
      );
      expect(
        await outbox.send(
          targetPeerId: 'receipt-sender',
          messageIds: const [id],
        ),
        isFalse,
        reason: 'locally queued is not transport success',
      );
      final initial = (await rows()).single;
      expect(initial['attempt_count'], 1);
      expect(initial['next_attempt_at_ms'], now.millisecondsSinceEpoch + 5000);
      expect((await sender.messageRepo.getMessage(id))!.status, 'inboxed');
      final wire = initial['receipt_payload'] as String;
      expect(wire, transport.lastStoreInInboxMessage);

      await database.close();
      await open();
      expect((await rows()).single, initial);
      final delivered = Completer<void>();
      transport.onStoreInInbox = (peer, payload, {timeoutMs}) async {
        expect(peer, initial['recipient_peer_id']);
        expect(payload, wire);
        await handleDeliveryReceipt(
          message: ChatMessage(
            from: 'receipt-receiver',
            to: peer,
            content: payload,
            timestamp: now.toIso8601String(),
            isIncoming: true,
            transport: 'inbox',
          ),
          messageRepo: sender.messageRepo,
        );
        delivered.complete();
        return true;
      };
      final owner = retrier();
      addTearDown(owner.dispose);
      owner.start();
      // Cold-start before the persisted due time cannot bypass backoff.
      await outbox.drain();
      expect(transport.storeInInboxCallCount, 1);
      now = now.add(const Duration(seconds: 5));
      transport.emitState(
        const NodeState(
          isStarted: true,
          peerId: 'receipt-receiver',
          circuitAddresses: ['/relay'],
        ),
      );
      await delivered.future.timeout(const Duration(seconds: 5));
      await outbox.drain();
      expect(await rows(), isEmpty);
      expect(transport.storeInInboxCallCount, 2);
      expect((await sender.messageRepo.getMessage(id))!.status, 'delivered');
      expect((await sender.messageRepo.getMessage(id))!.wireEnvelope, isNull);
      await outbox.drain();
      expect(transport.storeInInboxCallCount, 2);
    },
  );

  test(
    'BL24D1 persists obligation and attempt before a detached network wait',
    () async {
      final entered = Completer<void>();
      final release = Completer<SendMessageResult>();
      transport.onSendMessageWithReply = (peer, wire, {timeoutMs}) async {
        final pending = (await rows()).single;
        expect(pending['recipient_peer_id'], peer);
        expect(pending['receipt_payload'], wire);
        expect(pending['attempt_count'], 1);
        expect(
          pending['next_attempt_at_ms'],
          now.millisecondsSinceEpoch + 5000,
        );
        entered.complete();
        return release.future;
      };
      final sending = outbox.send(
        targetPeerId: 'sender',
        messageIds: const ['message'],
      );
      try {
        await entered.future.timeout(const Duration(seconds: 5));
        expect((await rows()).single['attempt_count'], 1);
      } finally {
        release.complete(const SendMessageResult(sent: true, acked: true));
        await sending;
      }
      expect(await rows(), isEmpty);
    },
  );

  test(
    'BL24D1 pending duplicate retains payload mutation identity and expiry',
    () async {
      final events = {'original-message': 'original-edit'};
      expect(
        await outbox.send(
          targetPeerId: 'original-physical-recipient',
          messageIds: const ['original-message'],
          mutationEventIds: events,
        ),
        isFalse,
      );
      final initial = (await rows()).single;
      events['original-message'] = 'new-edit-after-enqueue';
      now = now.add(const Duration(seconds: 1));
      expect(
        await outbox.send(
          targetPeerId: 'original-physical-recipient',
          messageIds: const ['original-message'],
          mutationEventIds: const {'original-message': 'original-edit'},
        ),
        isFalse,
      );
      expect((await rows()).single, initial);
      expect(transport.storeInInboxCallCount, 1);
      await database.close();
      await open();
      now = now.add(const Duration(seconds: 4));
      transport.storeInInboxResult = true;
      expect(await outbox.drain(), 1);
      expect(transport.lastStoreInInboxPeerId, 'original-physical-recipient');
      expect(transport.lastStoreInInboxMessage, initial['receipt_payload']);
      expect(
        (jsonDecode(transport.lastStoreInInboxMessage!)
            as Map)['payload']['mutationEventIds'],
        {'original-message': 'original-edit'},
      );
      expect(await rows(), isEmpty);
    },
  );

  test(
    'BL24D1 persisted backoff survives reopen and expiry never sends',
    () async {
      await outbox.send(targetPeerId: 'sender', messageIds: const ['message']);
      final initial = (await rows()).single;
      for (var pass = 0; pass < 3; pass++) {
        expect(await outbox.drain(), 0);
      }
      expect(transport.storeInInboxCallCount, 1);
      now = now.add(const Duration(seconds: 5));
      expect(await outbox.drain(), 0);
      final second = (await rows()).single;
      expect(second['attempt_count'], 2);
      expect(second['next_attempt_at_ms'], now.millisecondsSinceEpoch + 10000);
      await database.close();
      await open();
      expect(await outbox.drain(), 0);
      expect(transport.storeInInboxCallCount, 2);
      now = DateTime.fromMillisecondsSinceEpoch(
        initial['expires_at_ms'] as int,
        isUtc: true,
      );
      expect(await outbox.drain(), 0);
      expect(transport.storeInInboxCallCount, 2);
      expect(await rows(), isEmpty);
    },
  );

  test(
    'BL24D1 restored light pass retries while external recovery holds full pass',
    () async {
      await outbox.send(targetPeerId: 'sender', messageIds: const ['message']);
      final restored = StreamController<void>.broadcast();
      addTearDown(restored.close);
      final owner = retrier(restored: restored.stream, held: true);
      addTearDown(owner.dispose);
      owner.start();
      await outbox.drain();
      now = now.add(const Duration(seconds: 5));
      final accepted = Completer<void>();
      transport.onStoreInInbox = (_, _, {timeoutMs}) async {
        accepted.complete();
        return true;
      };
      restored.add(null);
      await accepted.future.timeout(const Duration(seconds: 5));
      await outbox.drain();
      expect(await rows(), isEmpty);
      expect(transport.storeInInboxCallCount, 2);
    },
  );

  test('BL24D1 resume uses the shared due drain', () async {
    await outbox.send(targetPeerId: 'sender', messageIds: const ['message']);
    now = now.add(const Duration(seconds: 5));
    transport.storeInInboxResult = true;
    await handleAppResumed(
      bridge: FakeBridge(),
      p2pService: transport,
      drainDeliveryReceiptOutboxFn: outbox.drain,
    );
    await outbox.drain();
    expect(await rows(), isEmpty);
    expect(transport.storeInInboxCallCount, 2);
  });

  test('BL24D1 a database refusal cannot send an unowned receipt', () async {
    await database.close();
    expect(
      await outbox.send(targetPeerId: 'sender', messageIds: const ['message']),
      isFalse,
    );
    expect(transport.sendMessageWithReplyCallCount, 0);
    expect(transport.storeInInboxCallCount, 0);
  });
}
