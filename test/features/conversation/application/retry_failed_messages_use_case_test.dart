import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart'
    as p2p;
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../core/bridge/fake_bridge.dart';

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
      'retries message without ML-KEM key using plaintext fallback',
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

        expect(count, 1);
        expect(
          p2pService.sendMessageWithReplyCallCount,
          greaterThanOrEqualTo(1),
        );
      },
    );

    test(
      'retries message when contact is missing using plaintext fallback',
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

        expect(count, 1);
        expect(
          p2pService.sendMessageWithReplyCallCount,
          greaterThanOrEqualTo(1),
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

      // Verify the saved message has transport='inbox' and status='delivered'
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'delivered');
      expect(saved.transport, 'inbox');
      expect(saved.wireEnvelope, isNull);
    });

    test(
      'retryFailedMessages skips storeInInbox when message transport '
      'is already inbox',
      () async {
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
      },
    );

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
