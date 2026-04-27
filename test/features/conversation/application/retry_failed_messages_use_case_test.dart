import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
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
        expect(messageRepo.wireEnvelopeUpdates, hasLength(1));
        expect(messageRepo.wireEnvelopeUpdates.single.id, failedMessageId);

        final payload = decodeWirePayload(p2pService.lastSendMessageContent!);
        expect(payload['id'], failedMessageId);
        expect(payload['timestamp'], failedTimestamp);
        expect(payload['text'], 'Recover this text');
        expect(payload['quotedMessageId'], 'quoted-parent-001');
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
      'hides delivered outgoing delete tombstones after failed retry stores in inbox',
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
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'delivered');
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isTrue);
        expect(saved.hiddenAt, saved.deletedAt);
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
      'does not replay persisted v1 deletion wireEnvelope to inbox after restart',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedLegacyDeletedMessage()]);

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

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(messageRepo.lastSavedMessage, isNull);
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

      // Verify the saved message has transport='inbox' and status='delivered'
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'delivered');
      expect(saved.transport, 'inbox');
      expect(saved.wireEnvelope, isNull);
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

        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'delivered');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, isNull);
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
      // But the message should still be marked as delivered
      expect(count, 1);
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'delivered');
      expect(saved.wireEnvelope, isNull);
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
  });
}
