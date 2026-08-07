import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart'
    as p2p;
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

IdentityModel makeIdentity() {
  return IdentityModel(
    peerId: 'my-peer-id',
    publicKey: 'my-pk-base64',
    privateKey: 'my-privkey-base64',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

ConversationMessage makeFailedMessage({
  String id = 'msg-fail-001',
  String contactPeerId = 'peer-target',
  String text = 'Hello',
  String? quotedMessageId,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: text,
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    quotedMessageId: quotedMessageId,
  );
}

ConversationMessage makeFailedDeletedMessage({
  String id = 'msg-delete-fail-001',
  String contactPeerId = 'peer-target',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: '',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    deletedAt: '2026-01-01T00:01:00.000Z',
    deletedByPeerId: 'my-peer-id',
    wireEnvelope: '{"type":"message_deletion","version":"2","encrypted":{}}',
  );
}

ConversationMessage makeFailedLegacyChatMessage({
  String id = 'msg-legacy-chat-001',
  String contactPeerId = 'peer-target',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Legacy leak sentinel',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    wireEnvelope:
        '{"type":"chat_message","version":"1","payload":{"id":"$id","text":"Legacy leak sentinel"}}',
  );
}

ConversationMessage makeFailedLegacyDeletedMessage({
  String id = 'msg-legacy-delete-001',
  String contactPeerId = 'peer-target',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: '',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    deletedAt: '2026-01-01T00:01:00.000Z',
    deletedByPeerId: 'my-peer-id',
    wireEnvelope:
        '{"type":"message_deletion","version":"1","payload":{"messageId":"$id","senderPeerId":"my-peer-id"}}',
  );
}

ConversationMessage makeFailedEditMessage({
  String id = 'msg-edit-fail-001',
  String contactPeerId = 'peer-target',
  String? eventId,
}) {
  final resolvedEventId = eventId ?? 'edit-event-$id';
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'edited text',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    editedAt: '2026-01-01T00:05:00.000Z',
    wireEnvelope:
        '{"type":"chat_message","version":"2","id":"$id","eventId":"$resolvedEventId","senderPeerId":"my-peer-id","encrypted":{"kem":"fake-kem","ciphertext":"{\\"id\\":\\"$id\\",\\"action\\":\\"edit\\",\\"eventId\\":\\"$resolvedEventId\\"}","nonce":"fake-nonce"}}',
  );
}

ConversationMessage makeFailedV2EditWithoutEventId({
  String id = 'msg-v2-edit-without-event-id',
  String contactPeerId = 'peer-target',
}) {
  return makeFailedEditMessage(id: id, contactPeerId: contactPeerId).copyWith(
    wireEnvelope:
        '{"type":"chat_message","version":"2","id":"$id","senderPeerId":"my-peer-id","encrypted":{"kem":"fake-kem","ciphertext":"{\\"id\\":\\"$id\\",\\"action\\":\\"edit\\"}","nonce":"fake-nonce"}}',
  );
}

ConversationMessage makeFailedLegacyEditMessage({
  String id = 'msg-legacy-edit-001',
  String contactPeerId = 'peer-target',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'edited legacy text',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    editedAt: '2026-01-01T00:05:00.000Z',
    wireEnvelope:
        '{"type":"chat_message","version":"1","payload":{"id":"$id","text":"edited legacy text"}}',
  );
}

ContactModel makeContact({
  String peerId = 'peer-target',
  String? mlKemPublicKey = 'test-mlkem-pk',
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'test-pk',
    rendezvous: '/ip4/127.0.0.1/tcp/4001',
    username: 'TestUser',
    signature: 'test-sig',
    scannedAt: '2026-01-01T00:00:00.000Z',
    mlKemPublicKey: mlKemPublicKey,
  );
}

Map<String, dynamic> decodeWirePayload(String wireJson) {
  final envelope = jsonDecode(wireJson) as Map<String, dynamic>;
  final payload = envelope['payload'];
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}

/// 116 P2.2: FakeP2PService whose storeInInbox blocks on a test-held gate so
/// two concurrent retries of the same row can be caught in flight.
class _GatedInboxP2PService extends FakeP2PService {
  final gate = Completer<void>();
  final entered = Completer<void>();

  _GatedInboxP2PService({required super.initialState})
    : super(storeInInboxResult: true);

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCallCount++;
    lastStoreInInboxPeerId = toPeerId;
    lastStoreInInboxMessage = message;
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return storeInInboxResult;
  }
}

/// FakeP2PService subclass that throws on sendMessageWithReply for specific
/// call indices, allowing us to test per-message error resilience.
class _PerMessageThrowingP2PService extends FakeP2PService {
  final Set<int> throwOnCallIndices;
  int _sendWithReplyIndex = 0;

  _PerMessageThrowingP2PService({
    required super.initialState,
    required this.throwOnCallIndices,
    super.discoverPeerResult,
    super.dialPeerResult,
    super.sendMessageWithReplyResult,
    super.storeInInboxResult,
  });

  @override
  Future<p2p.SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendMessageWithReplyCallCount++;
    lastSendMessagePeerId = peerId;
    lastSendMessageContent = message;
    final idx = _sendWithReplyIndex++;
    if (throwOnCallIndices.contains(idx)) {
      throw Exception('sendMessageWithReply error at index $idx');
    }
    return sendMessageWithReplyResult;
  }
}

class _R3RetryDeadlineP2PService extends FakeP2PService {
  _R3RetryDeadlineP2PService({
    required super.initialState,
    required super.sendMessageWithReplyResult,
    this.inboxDelay = Duration.zero,
    this.committedAckDelay = Duration.zero,
  }) : super(storeInInboxResult: false);

  final Duration inboxDelay;
  final Duration committedAckDelay;
  final List<String> callOrder = [];
  final List<int?> sendTimeouts = [];

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    callOrder.add('inbox_start');
    if (inboxDelay > Duration.zero) await Future<void>.delayed(inboxDelay);
    callOrder.add('inbox_done');
    return super.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
  }

  @override
  Future<p2p.SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    callOrder.add('send_start');
    sendTimeouts.add(timeoutMs);
    final nativeBudget = timeoutMs == null
        ? null
        : Duration(milliseconds: timeoutMs);
    if (nativeBudget != null && committedAckDelay > nativeBudget) {
      await Future<void>.delayed(nativeBudget);
      callOrder.add('send_timeout');
      sendMessageWithReplyCallCount++;
      return const p2p.SendMessageResult(sent: false);
    }
    if (committedAckDelay > Duration.zero) {
      await Future<void>.delayed(committedAckDelay);
    }
    callOrder.add('send_done');
    return super.sendMessageWithReply(peerId, message, timeoutMs: timeoutMs);
  }
}

void main() {
  group('retryFailedMessages', () {
    late FakeIdentityRepository identityRepo;
    late FakeMessageRepository messageRepo;
    late FakeContactRepository contactRepo;
    late FakeBridge bridge;

    setUp(() {
      identityRepo = FakeIdentityRepository();
      messageRepo = FakeMessageRepository();
      contactRepo = FakeContactRepository();
      bridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {
            'ok': true,
            'kem': 'fake-kem',
            'ciphertext': 'fake-ct',
            'nonce': 'fake-nonce',
          },
        },
      );
    });

    test('returns 0 when no identity exists', () async {
      // identityRepo has no identity seeded
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 0);
    });

    test('returns 0 when no failed messages exist', () async {
      identityRepo.seed(makeIdentity());
      // messageRepo has no messages seeded
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 0);
    });

    test(
      'TC-342-04b pending direct-text custody never falls through to re-encrypt',
      () async {
        identityRepo.seed(makeIdentity());
        final message = makeFailedMessage().copyWith(
          wireEnvelope: 'message-row-envelope-must-not-own-retry',
        );
        messageRepo
          ..seed(<ConversationMessage>[message])
          ..seedDirectInboxCustody(
            DirectInboxCustodyOutboxEntry(
              recipientPeerId: message.contactPeerId,
              messageId: message.id,
              incarnationId: '0123456789abcdef0123456789abcdef',
              wireEnvelope: 'exact-v108-custody-envelope',
              retryCount: 0,
              lastAttemptAt: null,
              lastErrorCode: null,
              createdAt: '2026-08-06T10:00:00.000Z',
              updatedAt: '2026-08-06T10:00:00.000Z',
            ),
          );
        contactRepo.seed(<ContactModel>[makeContact()]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: false,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          p2pService.storeInInboxLog.single.message,
          'exact-v108-custody-envelope',
        );
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(bridge.sendCallCount, 0);
        final retained = messageRepo.directCustodyRows.values.single;
        expect(retained.retryCount, 1);
        expect(retained.lastErrorCode, DirectInboxCustodyErrorCode.storeFailed);
        expect((await messageRepo.getMessage(message.id))!.status, 'failed');
      },
    );

    test(
      'retries each failed message and calls sendMessageWithReply',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        // sendChatMessage should have called sendMessageWithReply at least once
        expect(
          p2pService.sendMessageWithReplyCallCount,
          greaterThanOrEqualTo(1),
        );
      },
    );

    test(
      'returns success count of 1 when one message retried successfully',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
      },
    );

    test(
      'targeted failed text retry reuses the original row as first delivery',
      () async {
        identityRepo.seed(makeIdentity());
        const failedMessageId = 'msg-failed-text-001';
        const failedTimestamp = '2026-01-01T00:00:00.000Z';
        messageRepo.seed([
          makeFailedMessage(
            id: failedMessageId,
            contactPeerId: 'peer-target',
            text: 'Recover this text',
            quotedMessageId: 'quoted-parent-001',
          ),
        ]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
        );

        final count = await retryFailedMessage(
          messageId: failedMessageId,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 1);
        expect(messageRepo.lastSavedMessage, isNotNull);
        expect(messageRepo.lastSavedMessage!.id, failedMessageId);
        expect(messageRepo.lastSavedMessage!.timestamp, failedTimestamp);
        expect(messageRepo.ordinaryAttemptStages, hasLength(1));
        expect(messageRepo.ordinaryAttemptStages.single.id, failedMessageId);

        final payload = decodeWirePayload(p2pService.lastSendMessageContent!);
        expect(payload['id'], failedMessageId);
        expect(payload['timestamp'], failedTimestamp);
        expect(payload['text'], 'Recover this text');
        expect(payload['quotedMessageId'], 'quoted-parent-001');
        // 116 P1 re-frame: action != edit / editedAt == null is CORRECT for
        // PLAIN rows (no fabricated edit metadata). It is NOT the contract
        // for edit rows — those are covered by the '116 Phase 1 — edit retry
        // fidelity' group below (row-derived action metadata).
        expect(payload['action'], isNot(MessagePayload.actionEdit));
        expect(payload['editedAt'], isNull);
      },
    );

    test(
      'targeted failed text retry is a no-op after the row already settled',
      () async {
        identityRepo.seed(makeIdentity());
        const messageId = 'msg-recovered-text-001';
        messageRepo.seed([
          ConversationMessage(
            id: messageId,
            contactPeerId: 'peer-target',
            senderPeerId: 'my-peer-id',
            text: 'Already recovered',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            transport: 'inbox',
            wireEnvelope: null,
          ),
        ]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessage(
          messageId: messageId,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect((await messageRepo.getMessage(messageId))?.status, 'delivered');
      },
    );

    test(
      'failed delete tombstone retries over direct deletion route when inbox store fails',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedDeletedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: false,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            acked: true,
            reply: 'ack',
          ),
        );

        final events = await captureFlowEvents(() async {
          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: PassthroughCryptoBridge(),
          );
          expect(count, 1);
        });

        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 1);
        expect(
          events.any((event) => event['event'] == 'CHAT_MSG_SEND_START'),
          isFalse,
        );

        final directEnvelope =
            jsonDecode(p2pService.lastSendMessageContent!)
                as Map<String, dynamic>;
        expect(directEnvelope['type'], 'message_deletion');
        expect(directEnvelope['version'], '2');
        expect(directEnvelope.containsKey('payload'), isFalse);

        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'delivered');
        expect(saved.transport, 'direct');
        expect(saved.wireEnvelope, isNull);
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isTrue);
        expect(saved.hiddenAt, saved.deletedAt);
        expect(
          events.any(
            (event) =>
                event['event'] == 'RETRY_FAILED_DELETE_TOMBSTONE_SUCCESS',
          ),
          isTrue,
        );
      },
    );

    test('R2 failed delete retry requires explicit committed ACK', () async {
      Future<ConversationMessage> runOrdinary({
        required String suffix,
        required p2p.SendMessageResult sendResult,
      }) async {
        final repository = FakeMessageRepository();
        final message = makeFailedDeletedMessage(
          id: 'r2-delete-retry-ordinary-$suffix',
        );
        repository.seed([message]);
        final identities = FakeIdentityRepository()..seed(makeIdentity());
        final contacts = FakeContactRepository()
          ..seed([makeContact(peerId: 'peer-target')]);
        final service = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: false,
          sendMessageWithReplyResult: sendResult,
        );

        expect(
          await retryFailedMessages(
            messageRepo: repository,
            identityRepo: identities,
            contactRepo: contacts,
            p2pService: service,
            bridge: PassthroughCryptoBridge(),
          ),
          1,
        );
        expect(service.storeInInboxCallCount, 1);
        expect(service.sendMessageWithReplyCallCount, 1);
        return (await repository.getMessage(message.id))!;
      }

      final replyOnlyOrdinary = await runOrdinary(
        suffix: 'reply-only',
        sendResult: const p2p.SendMessageResult(
          sent: true,
          reply: '{"ack":true}',
          transport: 'direct',
        ),
      );
      expect(replyOnlyOrdinary.status, 'sent');
      expect(replyOnlyOrdinary.transport, 'direct');
      expect(replyOnlyOrdinary.wireEnvelope, isNotNull);
      expect(replyOnlyOrdinary.isHidden, isFalse);
      expect(replyOnlyOrdinary.hiddenAt, isNull);

      final ackedOrdinary = await runOrdinary(
        suffix: 'explicit-ack',
        sendResult: const p2p.SendMessageResult(
          sent: true,
          acked: true,
          reply: '{"ack":true}',
          transport: 'direct',
        ),
      );
      expect(ackedOrdinary.status, 'delivered');
      expect(ackedOrdinary.transport, 'direct');
      expect(ackedOrdinary.wireEnvelope, isNull);
      expect(ackedOrdinary.isHidden, isTrue);
      expect(ackedOrdinary.hiddenAt, ackedOrdinary.deletedAt);

      Future<ConversationMessage> runPrivate({
        required String suffix,
        required p2p.SendMessageResult sendResult,
      }) async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final messageId = 'r2-delete-retry-private-$suffix';
        await fixture.seedDirectParent(messageId, contactPeerId: 'peer-target');
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'sender_peer_id': 'my-peer-id',
            'text': '',
            'status': 'failed',
            'is_incoming': 0,
            'wire_envelope':
                '{"type":"message_deletion","version":"2","encrypted":{}}',
            'deleted_at': '2026-01-01T00:01:00.000Z',
            'deleted_by_peer_id': 'my-peer-id',
            'hidden_at': null,
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'consumed',
            'private_media_received_at_ms': 1000,
            'private_media_terminal_at_ms': 2000,
            'private_media_clock_high_water_ms': 2000,
          },
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        );
        final identities = FakeIdentityRepository()..seed(makeIdentity());
        final contacts = FakeContactRepository()
          ..seed([makeContact(peerId: 'peer-target')]);
        final service = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: false,
          sendMessageWithReplyResult: sendResult,
        );

        expect(
          await retryFailedMessages(
            messageRepo: fixture.messageRepo,
            identityRepo: identities,
            contactRepo: contacts,
            p2pService: service,
            bridge: PassthroughCryptoBridge(),
          ),
          1,
        );
        return (await fixture.messageRepo.getMessage(messageId))!;
      }

      final replyOnlyPrivate = await runPrivate(
        suffix: 'reply-only',
        sendResult: const p2p.SendMessageResult(
          sent: true,
          reply: '{"ack":true}',
          transport: 'relay',
        ),
      );
      expect(replyOnlyPrivate.status, 'sent');
      expect(replyOnlyPrivate.transport, 'relay');
      expect(replyOnlyPrivate.wireEnvelope, isNotNull);
      expect(replyOnlyPrivate.isHidden, isFalse);
      expect(replyOnlyPrivate.hiddenAt, isNull);

      final ackedPrivate = await runPrivate(
        suffix: 'explicit-ack',
        sendResult: const p2p.SendMessageResult(
          sent: true,
          acked: true,
          reply: '{"ack":true}',
          transport: 'relay',
        ),
      );
      expect(ackedPrivate.status, 'delivered');
      expect(ackedPrivate.transport, 'relay');
      expect(ackedPrivate.wireEnvelope, isNull);
      expect(ackedPrivate.isHidden, isTrue);
      expect(ackedPrivate.hiddenAt, ackedPrivate.deletedAt);
    });

    test(
      'R3 failed delete replay reserves committed ACK after inbox failure',
      () {
        fakeAsync((async) {
          const messageId = 'r3-delete-retry-acked';
          final repository = FakeMessageRepository()
            ..seed([makeFailedDeletedMessage(id: messageId)]);
          final identities = FakeIdentityRepository()..seed(makeIdentity());
          final contacts = FakeContactRepository()
            ..seed([makeContact(peerId: 'peer-target')]);
          final service = _R3RetryDeadlineP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id',
            ),
            sendMessageWithReplyResult: const p2p.SendMessageResult(
              sent: true,
              acked: true,
              transport: 'direct',
            ),
            inboxDelay: const Duration(milliseconds: 1200),
            committedAckDelay: const Duration(milliseconds: 2200),
          );
          int? retryCount;
          ConversationMessage? stored;

          retryFailedMessages(
            messageRepo: repository,
            identityRepo: identities,
            contactRepo: contacts,
            p2pService: service,
            bridge: PassthroughCryptoBridge(),
          ).then((value) {
            retryCount = value;
            repository.getMessage(messageId).then((value) => stored = value);
          });
          async.flushMicrotasks();
          expect(service.callOrder, <String>['inbox_start']);

          async.elapse(const Duration(milliseconds: 1200));
          async.flushMicrotasks();
          expect(service.callOrder, <String>[
            'inbox_start',
            'inbox_done',
            'send_start',
          ]);
          expect(
            service.sendTimeouts,
            <int?>[5500],
            reason: 'the live T0 begins only after inbox custody fails',
          );

          async.elapse(const Duration(milliseconds: 2200));
          async.flushMicrotasks();
          expect(retryCount, 1);
          expect(service.callOrder, <String>[
            'inbox_start',
            'inbox_done',
            'send_start',
            'send_done',
          ]);
          expect(stored, isNotNull);
          expect(stored!.status, 'delivered');
          expect(stored!.wireEnvelope, isNull);
        });

        fakeAsync((async) {
          const messageId = 'r3-delete-retry-uncommitted';
          final repository = FakeMessageRepository()
            ..seed([makeFailedDeletedMessage(id: messageId)]);
          final identities = FakeIdentityRepository()..seed(makeIdentity());
          final contacts = FakeContactRepository()
            ..seed([makeContact(peerId: 'peer-target')]);
          final service = _R3RetryDeadlineP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id',
            ),
            sendMessageWithReplyResult: const p2p.SendMessageResult(
              sent: true,
              acked: false,
              transport: 'direct',
            ),
          );
          ConversationMessage? stored;

          retryFailedMessages(
            messageRepo: repository,
            identityRepo: identities,
            contactRepo: contacts,
            p2pService: service,
            bridge: PassthroughCryptoBridge(),
          ).then(
            (_) => repository
                .getMessage(messageId)
                .then((value) => stored = value),
          );
          async.flushMicrotasks();

          expect(service.callOrder, <String>[
            'inbox_start',
            'inbox_done',
            'send_start',
            'send_done',
          ]);
          expect(service.sendTimeouts.single, greaterThan(3000));
          expect(stored, isNotNull);
          expect(stored!.status, 'sent');
          expect(stored!.wireEnvelope, isNotNull);
        });
      },
    );

    test(
      'v2 tombstone inbox custody success is inboxed and keeps the tombstone visible',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedDeletedMessage()]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, makeFailedDeletedMessage().wireEnvelope);
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isFalse);
        expect(saved.hiddenAt, isNull);
      },
    );

    test(
      'emits RETRY_FAILED_MESSAGES_TIMING with total and succeeded counts',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final events = await captureFlowEvents(() async {
          await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'RETRY_FAILED_MESSAGES_TIMING',
        );
        expect(timing['details']['outcome'], 'complete');
        expect(timing['details']['total'], 1);
        expect(timing['details']['succeeded'], 1);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test(
      'returns 0 when all retries fail (sendMessageWithReply not sent)',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        // discoverPeer returns null so sendChatMessage gets peerNotFound
        // and after 3 retries falls back to storeInInbox which also fails
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: null, // peer not found
          dialPeerResult: false,
          sendMessageWithReplyResult: const p2p.SendMessageResult(sent: false),
          storeInInboxResult: false, // inbox fallback also fails
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
      },
    );

    test('continues on per-message error and still tries next message', () async {
      identityRepo.seed(makeIdentity());
      messageRepo.seed([
        makeFailedMessage(id: 'msg-fail-001', contactPeerId: 'peer-a'),
        makeFailedMessage(id: 'msg-fail-002', contactPeerId: 'peer-b'),
      ]);
      contactRepo.seed([
        makeContact(peerId: 'peer-a'),
        makeContact(peerId: 'peer-b'),
      ]);

      // First call to sendMessageWithReply throws, second succeeds.
      // sendChatMessage uses maxAttempts=1 per message, so index 0 is
      // the first message's single attempt, and index 1 is the second
      // message's single attempt. We throw on index 0 (msg 1 fails)
      // and let index 1 succeed (msg 2).
      final p2pService = _PerMessageThrowingP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        throwOnCallIndices: {0},
        discoverPeerResult: const DiscoveredPeer(
          id: 'peer-b',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: false, // inbox fallback fails for msg 1
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // msg-fail-001 failed (single attempt threw + inbox failed), msg-fail-002 succeeded
      expect(count, 1);
    });

    test('returns correct count when multiple messages all succeed', () async {
      identityRepo.seed(makeIdentity());
      messageRepo.seed([
        makeFailedMessage(id: 'msg-fail-001', contactPeerId: 'peer-a'),
        makeFailedMessage(id: 'msg-fail-002', contactPeerId: 'peer-b'),
        makeFailedMessage(id: 'msg-fail-003', contactPeerId: 'peer-c'),
      ]);
      contactRepo.seed([
        makeContact(peerId: 'peer-a'),
        makeContact(peerId: 'peer-b'),
        makeContact(peerId: 'peer-c'),
      ]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        discoverPeerResult: const DiscoveredPeer(
          id: 'any-peer',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 3);
    });

    test('does not retry messages that are not failed', () async {
      identityRepo.seed(makeIdentity());
      // Seed a delivered message and a failed message
      messageRepo.seed([
        ConversationMessage(
          id: 'msg-ok-001',
          contactPeerId: 'peer-a',
          senderPeerId: 'my-peer-id',
          text: 'Already sent',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
        makeFailedMessage(id: 'msg-fail-001', contactPeerId: 'peer-b'),
      ]);
      contactRepo.seed([makeContact(peerId: 'peer-b')]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        discoverPeerResult: const DiscoveredPeer(
          id: 'peer-b',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // Only the failed message should be retried
      expect(count, 1);
    });

    test(
      'returns 0 when node is not running (sendChatMessage fails)',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);

        // Node NOT started -- sendChatMessage returns nodeNotRunning
        final p2pService = FakeP2PService(initialState: NodeState.stopped);

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
      },
    );

    test(
      'does not retry message without ML-KEM key using plaintext fallback',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        // Contact exists but has no ML-KEM public key
        contactRepo.seed([
          makeContact(peerId: 'peer-target', mlKemPublicKey: null),
        ]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'does not retry message when contact is missing using plaintext fallback',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        // No contact seeded — contactRepo returns null → mlKemPublicKey is null

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'does not replay persisted v1 chat wireEnvelope to inbox after restart',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedLegacyChatMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          p2pService.lastStoreInInboxMessage,
          isNot(contains('Legacy leak sentinel')),
        );
        expect(p2pService.lastStoreInInboxMessage, contains('"version":"2"'));
      },
    );

    test(
      'legacy v1 delete tombstone is rebuilt as encrypted v2 when key exists',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedLegacyDeletedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = _GatedInboxP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        );

        final retry = retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );
        await p2pService.entered.future;
        try {
          expect(messageRepo.ordinaryAttemptStages, hasLength(1));
          final staged = await messageRepo.getMessage('msg-legacy-delete-001');
          expect(staged, isNotNull);
          expect(staged!.status, 'sending');
          expect(staged.transport, isNull);
          expect(staged.wireEnvelope, p2pService.lastStoreInInboxMessage);
          expect(staged.wireEnvelope, contains('"version":"2"'));
          expect(staged.isDeleted, isTrue);
          expect(staged.isHidden, isFalse);
        } finally {
          p2pService.gate.complete();
        }
        final count = await retry;

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(
          p2pService.lastStoreInInboxMessage,
          isNot(contains('"version":"1"')),
        );
        expect(
          p2pService.lastStoreInInboxMessage,
          isNot(contains('"payload"')),
        );
        final envelope =
            jsonDecode(p2pService.lastStoreInInboxMessage!)
                as Map<String, dynamic>;
        expect(envelope['type'], 'message_deletion');
        expect(envelope['version'], '2');
        expect(envelope['encrypted'], isA<Map<String, dynamic>>());
        expect(envelope.containsKey('payload'), isFalse);

        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, p2pService.lastStoreInInboxMessage);
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isFalse);
      },
    );

    test(
      'legacy tombstone without recipient key stays failed with explicit telemetry',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedLegacyDeletedMessage()]);
        contactRepo.seed([
          makeContact(peerId: 'peer-target', mlKemPublicKey: null),
        ]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final events = await captureFlowEvents(() async {
          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: PassthroughCryptoBridge(),
          );
          expect(count, 0);
        });

        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(messageRepo.lastSavedMessage, isNull);
        final saved = await messageRepo.getMessage('msg-legacy-delete-001');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, contains('"version":"1"'));

        final unavailable = events.singleWhere(
          (event) =>
              event['event'] == 'RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE',
        );
        expect(
          (unavailable['details'] as Map<String, dynamic>)['reason'],
          'missing_recipient_key',
        );
      },
    );

    test('wire_envelope inbox path sets transport to inbox', () async {
      identityRepo.seed(makeIdentity());
      // Failed message with wire_envelope — should use inbox fast path
      final msgWithEnvelope = ConversationMessage(
        id: 'msg-env-001',
        contactPeerId: 'peer-target',
        senderPeerId: 'my-peer-id',
        text: 'Hello',
        timestamp: '2026-01-01T00:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-01-01T00:00:00.000Z',
        wireEnvelope: '{"type":"chat_message","version":"2","encrypted":{}}',
      );
      messageRepo.seed([msgWithEnvelope]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 1);
      expect(p2pService.storeInInboxCallCount, 1);

      // F6: relay STORE success is custody, not receiver delivery — 'inboxed'
      // with the wire envelope retained for the custody sweep + receipt repair.
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'inboxed');
      expect(saved.transport, 'inbox');
      expect(saved.wireEnvelope, isNotNull);
    });

    test(
      'wire_envelope inbox path preserves GIF metadata for GIF retries',
      () async {
        identityRepo.seed(makeIdentity());
        final msgWithEnvelope = ConversationMessage(
          id: 'msg-gif-env-001',
          contactPeerId: 'peer-target',
          senderPeerId: 'my-peer-id',
          text: '',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-01-01T00:00:00.000Z',
          wireEnvelope: jsonEncode({
            'type': 'chat_message',
            'version': '2',
            'payload': {
              'id': 'msg-gif-env-001',
              'text': '',
              'media': [
                {
                  'id': 'gif-1',
                  'mime': 'image/gif',
                  'size': 4096,
                  'mediaType': 'image',
                },
              ],
            },
          }),
        );
        messageRepo.seed([msgWithEnvelope]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          p2pService.lastStoreInInboxMessage,
          contains('"mime":"image/gif"'),
        );

        // F6: 'inboxed' custody, envelope (incl GIF media metadata) retained.
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, isNotNull);
      },
    );

    test('retryFailedMessages skips storeInInbox when message transport '
        'is already inbox', () async {
      identityRepo.seed(makeIdentity());
      // Simulate the post-crash state: message was successfully stored
      // in inbox but app crashed before DB was updated. On resume,
      // a recovery path re-saved the row with transport='inbox'.
      final msgWithInboxTransport = ConversationMessage(
        id: 'msg-crash-001',
        contactPeerId: 'peer-target',
        senderPeerId: 'my-peer-id',
        text: 'Crash test',
        timestamp: '2026-01-01T00:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-01-01T00:00:00.000Z',
        transport: 'inbox', // already delivered via inbox before crash
        wireEnvelope:
            '{"type":"chat","version":"1","payload":{"id":"msg-crash-001"}}',
      );
      messageRepo.seed([msgWithInboxTransport]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // storeInInbox should NOT be called — message already has transport='inbox'
      expect(p2pService.storeInInboxCallCount, 0);
      // F6: already-inbox is custody, not delivery — settled 'inboxed' with the
      // envelope retained (no send happened), riding the receipt repair.
      expect(count, 1);
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'inboxed');
      expect(saved.wireEnvelope, isNotNull);
    });

    test('calls getFailedOutgoingMessages on messageRepo', () async {
      identityRepo.seed(makeIdentity());
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(messageRepo.getFailedOutgoingCallCount, 1);
    });

    // --- NET-REL-05 R1: concurrent-fallback interaction (regression) ---
    //
    // The new concurrent durable fallback (U-P1P4) settles a low-confidence send
    // as a row with status='delivered', transport='inbox', wireEnvelope=null once
    // the relay takes custody. This is the SAME terminal shape the existing inbox
    // tail produces. These tests pin that such a row is invisible to the failed
    // retrier so the concurrent copy is never sent a SECOND time.
    test('concurrently-inboxed message (delivered/inbox/null-envelope) is NOT '
        'picked up by the failed retrier', () async {
      identityRepo.seed(makeIdentity());
      // The exact row shape persistInboxDelivered writes for a concurrent
      // fallback that took custody: terminal delivered, transport inbox,
      // wireEnvelope cleared.
      messageRepo.seed([
        ConversationMessage(
          id: 'msg-concurrent-inbox-001',
          contactPeerId: 'peer-target',
          senderPeerId: 'my-peer-id',
          text: 'Low-confidence send',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-01-01T00:00:00.000Z',
          transport: 'inbox',
          wireEnvelope: null,
        ),
      ]);
      contactRepo.seed([makeContact(peerId: 'peer-target')]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        discoverPeerResult: const DiscoveredPeer(
          id: 'peer-target',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // NEGATIVE CONTROL: the durable copy must NOT be re-sent. No live send,
      // no second inbox store, nothing retried.
      expect(count, 0);
      expect(p2pService.sendMessageWithReplyCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      // Row is untouched / still delivered (no resave that could regress it).
      expect(
        (await messageRepo.getMessage('msg-concurrent-inbox-001'))?.status,
        'delivered',
      );
    });

    test(
      'failed retrier still prefers inbox-only re-store from persisted '
      'wireEnvelope and does not double-send live alongside concurrent fallback',
      () async {
        identityRepo.seed(makeIdentity());
        // A genuinely failed row that DID persist a safe v2 envelope. The
        // retrier must re-store it via inbox ONLY (one storeInInbox, no live
        // sendMessageWithReply), proving the inbox-first preference is intact
        // and never escalates to a duplicate live send.
        messageRepo.seed([
          ConversationMessage(
            id: 'msg-failed-with-envelope-001',
            contactPeerId: 'peer-target',
            senderPeerId: 'my-peer-id',
            text: 'Hello',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'failed',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            wireEnvelope:
                '{"type":"chat_message","version":"2","encrypted":{}}',
          ),
        ]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
        // Inbox-only re-store: exactly one store, ZERO live sends.
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        // F6: settled custody — 'inboxed'/inbox/envelope-retained. Invisible to
        // the FAILED retrier (status != 'failed'); rides the custody sweep +
        // DeliveryReceiptListener for the receiver-confirmed 'delivered'.
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, isNotNull);
      },
    );
  });

  // ─── 116 Phase 1 — edit retry fidelity through the full-send fallback ───
  // A failed edit retried via the fallback must STAY an edit: row-derived
  // action metadata (EF-1), never caller defaults. Without it the retry goes
  // out as a plain send under the original id, the receiver dedups it by id,
  // and sender/receiver text silently diverge (doc 116 §1).
  group('116 Phase 1 — edit retry fidelity', () {
    late FakeIdentityRepository identityRepo;
    late FakeMessageRepository messageRepo;
    late FakeContactRepository contactRepo;

    setUp(() {
      identityRepo = FakeIdentityRepository()..seed(makeIdentity());
      messageRepo = FakeMessageRepository();
      contactRepo = FakeContactRepository()
        ..seed([makeContact(peerId: 'peer-target')]);
    });

    FakeP2PService makeHealthyDirectInboxDownP2P() => FakeP2PService(
      initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      discoverPeerResult: const DiscoveredPeer(
        id: 'peer-target',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      ),
      dialPeerResult: true,
      sendMessageWithReplyResult: const p2p.SendMessageResult(
        sent: true,
        acked: true,
        reply: 'ack',
      ),
      // Envelope replay fails → the full-send fallback fires.
      storeInInboxResult: false,
    );

    test(
      'cached current edit replays exact bytes with one stable event id',
      () async {
        final failed = makeFailedEditMessage(eventId: 'edit-event-exact');
        messageRepo.seed([failed]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(p2pService.lastStoreInInboxMessage, failed.wireEnvelope);
        final envelope =
            jsonDecode(failed.wireEnvelope!) as Map<String, dynamic>;
        expect(envelope['id'], failed.id);
        expect(envelope['eventId'], 'edit-event-exact');
      },
    );

    test(
      'current edit store failure retains exact envelope without re-encryption',
      () async {
        final failed = makeFailedEditMessage(eventId: 'edit-event-stable');
        messageRepo.seed([failed]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        final events = await captureFlowEvents(() async {
          expect(
            await retryFailedMessages(
              messageRepo: messageRepo,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: p2pService,
              bridge: PassthroughCryptoBridge(),
            ),
            0,
          );
        });

        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastStoreInInboxMessage, failed.wireEnvelope);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(messageRepo.ordinaryAttemptStages, isEmpty);
        expect(
          (await messageRepo.getMessage(failed.id))?.wireEnvelope,
          failed.wireEnvelope,
        );
        expect(
          events.any(
            (event) =>
                event['event'] == 'RETRY_FAILED_EDIT_EXACT_ENVELOPE_RETAINED',
          ),
          isTrue,
        );
      },
    );

    test(
      'v2 legacy edit without event id never replays cached bytes and mints once before transport',
      () async {
        final failed = makeFailedV2EditWithoutEventId();
        messageRepo.seed([failed]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        final events = await captureFlowEvents(() async {
          expect(
            await retryFailedMessages(
              messageRepo: messageRepo,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: p2pService,
              bridge: PassthroughCryptoBridge(),
            ),
            1,
          );
        });

        expect(
          p2pService.storeInInboxLog
              .map((entry) => entry.message)
              .contains(failed.wireEnvelope),
          isFalse,
          reason: 'legacy same-target bytes must not enter relay dedupe',
        );
        expect(
          events.any(
            (event) =>
                event['event'] ==
                'RETRY_FAILED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE',
          ),
          isTrue,
        );
        final rebuilt = p2pService.lastSendMessageContent!;
        final outer = jsonDecode(rebuilt) as Map<String, dynamic>;
        final inner = decodeWirePayload(rebuilt);
        expect(outer['id'], failed.id);
        expect(outer['eventId'], isA<String>());
        expect((outer['eventId'] as String).trim(), isNotEmpty);
        expect(inner['eventId'], outer['eventId']);
        expect(inner['action'], MessagePayload.actionEdit);
        expect(inner['editedAt'], '2026-01-01T00:05:00.000Z');
        expect(inner['timestamp'], '2026-01-01T00:00:00.000Z');
        expect(
          messageRepo.lastSavedMessage?.editedAt,
          '2026-01-01T00:05:00.000Z',
        );
        expect(
          messageRepo.lastSavedMessage?.createdAt,
          '2026-01-01T00:00:00.000Z',
        );
        final stagedOuter =
            jsonDecode(messageRepo.ordinaryAttemptStages.single.wireEnvelope!)
                as Map<String, dynamic>;
        expect(stagedOuter['eventId'], outer['eventId']);
      },
    );

    test(
      'edit metadata survives a fallback attempt that fails terminally',
      () async {
        messageRepo.seed([
          makeFailedV2EditWithoutEventId(id: 'msg-edit-fail-001'),
        ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          // ALL transports fail: no discover, no send, no inbox.
          discoverPeerResult: null,
          dialPeerResult: false,
          sendMessageWithReplyResult: const p2p.SendMessageResult(sent: false),
          storeInInboxResult: false,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 0);
        final row = await messageRepo.getMessage('msg-edit-fail-001');
        expect(row!.status, 'failed');
        expect(
          row.editedAt,
          '2026-01-01T00:05:00.000Z',
          reason: 'a failed fallback attempt must never null the edit metadata',
        );
        // The last persisted envelope must still be an EDIT envelope — the
        // edit must remain recoverable by the next retry cycle.
        final lastEnvelope = decodeWirePayload(
          messageRepo.ordinaryAttemptStages.last.wireEnvelope!,
        );
        expect(lastEnvelope['action'], MessagePayload.actionEdit);
      },
    );

    test(
      'v1-legacy failed edit row reconstructs edit params from the DB row',
      () async {
        messageRepo.seed([makeFailedLegacyEditMessage()]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        final events = await captureFlowEvents(() async {
          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: PassthroughCryptoBridge(),
          );
          expect(count, 1);
        });

        // Leak guard preserved: the v1 envelope never reaches any transport.
        // FDC-03: the rebuilt (NOT legacy) payload now also fires one concurrent
        // durable copy on this unknown-presence retry. The direct send carries
        // the rebuilt edit payload (asserted below) and the inbox attempt carries
        // the same rebuilt jsonString — so no v1 envelope leaks.
        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          events.any(
            (e) =>
                e['event'] == 'RETRY_FAILED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE',
          ),
          isTrue,
        );
        // The rebuilt outgoing payload carries the row's edit metadata.
        final payload = decodeWirePayload(p2pService.lastSendMessageContent!);
        expect(payload['action'], MessagePayload.actionEdit);
        expect(payload['editedAt'], '2026-01-01T00:05:00.000Z');
        expect(payload['id'], 'msg-legacy-edit-001');
        expect(payload['timestamp'], '2026-01-01T00:00:00.000Z');
      },
    );

    test(
      'plain failed retry preserves the original createdAt on the settled row',
      () async {
        messageRepo.seed([makeFailedMessage()]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 1);
        expect(
          messageRepo.lastSavedMessage!.createdAt,
          '2026-01-01T00:00:00.000Z',
          reason: 'the fallback must not re-mint createdAt for retried rows',
        );
      },
    );

    // 116 P2.2 companion PIN (green-on-arrival post-P1): the pre-race
    // guarded attempt stage of a retried edit writes an EDIT envelope.
    // This is the explicit prerequisite the 115 P3 custody sweep inherits:
    // a sweep re-store of an edit row's wire_envelope carries action:edit.
    test(
      'retried edit pre-race envelope persist writes an edit envelope',
      () async {
        messageRepo.seed([
          makeFailedV2EditWithoutEventId(id: 'msg-edit-fail-001'),
        ]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        final persisted = decodeWirePayload(
          messageRepo.ordinaryAttemptStages.single.wireEnvelope!,
        );
        expect(persisted['action'], MessagePayload.actionEdit);
        expect(persisted['editedAt'], '2026-01-01T00:05:00.000Z');
      },
    );
  });

  // ─── 116 Phase 2 — single-flight + settled-skip (EF-3) ──────────────────
  // PendingMessageRetrier periodic + reconnect debounce + app-resume 8c + the
  // UI retry button can overlap: at most ONE retry per message id may be in
  // flight, and a candidate whose row settled between load and execution is
  // skipped, not re-sent.
  group('116 Phase 2 — single-flight and settled-skip', () {
    late FakeIdentityRepository identityRepo;
    late FakeMessageRepository messageRepo;
    late FakeContactRepository contactRepo;

    setUp(() {
      identityRepo = FakeIdentityRepository()..seed(makeIdentity());
      messageRepo = FakeMessageRepository();
      contactRepo = FakeContactRepository()
        ..seed([makeContact(peerId: 'peer-target')]);
    });

    test(
      'concurrent retries of the same failed row send at most once (single-flight per message id)',
      () async {
        messageRepo.seed([makeFailedEditMessage()]);
        final p2pService = _GatedInboxP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        );

        late List<int> results;
        final events = await captureFlowEvents(() async {
          final futures = Future.wait([
            retryFailedMessage(
              messageId: 'msg-edit-fail-001',
              messageRepo: messageRepo,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: p2pService,
              bridge: PassthroughCryptoBridge(),
            ),
            retryFailedMessage(
              messageId: 'msg-edit-fail-001',
              messageRepo: messageRepo,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: p2pService,
              bridge: PassthroughCryptoBridge(),
            ),
          ]);
          // Let both invocations reach the candidate before releasing.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          p2pService.gate.complete();
          results = await futures;
        });

        expect(
          p2pService.storeInInboxCallCount,
          1,
          reason: 'exactly one in-flight retry per message id (EF-3)',
        );
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(results..sort(), [0, 1]);
        expect(
          events
              .where(
                (e) => e['event'] == 'RETRY_FAILED_MESSAGE_SKIPPED_IN_FLIGHT',
              )
              .length,
          1,
        );
      },
    );

    test(
      'retry candidate skips a row that settled between load and execution',
      () async {
        // Stored state: the row already settled 'delivered'. The sweep's loaded
        // list still holds a STALE 'failed' snapshot of the same row.
        final staleSnapshot = makeFailedEditMessage(id: 'msg-stale-001');
        messageRepo.seed([
          staleSnapshot.copyWith(status: 'delivered', wireEnvelope: null),
        ]);
        messageRepo.failedOutgoingOverride = [staleSnapshot];

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final events = await captureFlowEvents(() async {
          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: PassthroughCryptoBridge(),
          );
          expect(count, 0);
        });

        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'a settled row must never be re-sent from a stale snapshot',
        );
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(
          events.any(
            (e) => e['event'] == 'RETRY_FAILED_MESSAGE_SKIPPED_SETTLED',
          ),
          isTrue,
        );
        expect(
          (await messageRepo.getMessage('msg-stale-001'))!.status,
          'delivered',
        );
      },
    );
  });
}
