import 'dart:async';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/bridge/fake_bridge.dart';
import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';
import '../../shared/fakes/test_user.dart';

// ---------------------------------------------------------------------------
// _AckDropP2PService — wraps FakeP2PService, drops ACKs on demand
// ---------------------------------------------------------------------------

/// P2P service that can simulate lost ACKs.
///
/// When [dropAcks] is true, [sendMessageWithReply] delivers the message
/// to the network (the receiver gets it) but returns a null reply — as if
/// the ACK packet was lost on the wire.
class _AckDropP2PService implements P2PService {
  final FakeP2PService _inner;
  bool dropAcks = true;

  /// When true, [sendMessageWithReply] returns sent: false (total failure).
  bool totalFailure = false;

  _AckDropP2PService(this._inner);

  @override
  NodeState get currentState => _inner.currentState;

  @override
  Stream<NodeState> get stateStream => _inner.stateStream;

  @override
  Stream<ChatMessage> get messageStream => _inner.messageStream;

  @override
  Future<bool> sendMessage(String peerId, String message) =>
      _inner.sendMessage(peerId, message);

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (totalFailure) {
      // Simulate complete send failure (message never reaches peer).
      return const SendMessageResult(sent: false);
    }

    // Deliver the message to the network (receiver gets it).
    final result = await _inner.sendMessageWithReply(targetPeerId, message);

    if (dropAcks && result.sent) {
      // Message delivered, but ACK lost — return sent:true, reply:null.
      return const SendMessageResult(sent: true, reply: null);
    }
    return result;
  }

  @override
  Future<bool> startNode(String pk, String pid) => _inner.startNode(pk, pid);

  @override
  Future<bool> stopNode() => _inner.stopNode();

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) =>
      _inner.discoverPeer(peerId, timeoutMs: timeoutMs);

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) => _inner.dialPeer(peerId, addresses: addresses, timeoutMs: timeoutMs);

  @override
  Future<bool> storeInInbox(String toPeerId, String message) =>
      _inner.storeInInbox(toPeerId, message);

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) =>
      _inner.retrieveInbox(timeoutMs: timeoutMs);

  @override
  Future<bool> registerPushToken(String token, String platform) =>
      _inner.registerPushToken(token, platform);

  @override
  Future<void> performImmediateHealthCheck() =>
      _inner.performImmediateHealthCheck();

  @override
  Future<void> drainOfflineInbox() => _inner.drainOfflineInbox();

  @override
  Future<RelayProbeResult> probeRelay(String peerId) =>
      _inner.probeRelay(peerId);

  @override
  bool isConnectedToPeer(String peerId) => _inner.isConnectedToPeer(peerId);

  @override
  bool isLocalPeer(String peerId) => _inner.isLocalPeer(peerId);

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String msg,
    String from, {
    int? timeoutMs,
  }) => _inner.sendLocalMessage(peerId, msg, from, timeoutMs: timeoutMs);

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  Future<bool> startNodeCore(String pk, String pid) =>
      _inner.startNodeCore(pk, pid);

  @override
  Future<void> warmBackground() => _inner.warmBackground();

  @override
  String? get lastRecoveryMethod => _inner.lastRecoveryMethod;

  @override
  void dispose() => _inner.dispose();
}

// ---------------------------------------------------------------------------
// _ConnectedAckDropP2PService — same as above but isConnectedToPeer → true
// ---------------------------------------------------------------------------

class _ConnectedAckDropP2PService extends _AckDropP2PService {
  _ConnectedAckDropP2PService(super.inner);

  @override
  bool isConnectedToPeer(String peerId) => true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('C2 — ACK drop resilience', () {
    late FakeP2PNetwork network;
    late InMemoryMessageRepository aliceRepo;
    late InMemoryContactRepository aliceContactRepo;
    late _AckDropP2PService aliceP2P;
    late TestUser bob;
    late PassthroughCryptoBridge encryptBridge;

    const alicePeerId = 'alice-peer-id';
    const aliceUsername = 'Alice';
    const bobMlKemKey = 'test-mlkem-pk-bob';

    setUp(() {
      network = FakeP2PNetwork();

      encryptBridge = PassthroughCryptoBridge();

      // Alice: custom P2PService with ACK dropping
      final innerAlice = FakeP2PService(peerId: alicePeerId, network: network);
      aliceP2P = _AckDropP2PService(innerAlice);
      aliceRepo = InMemoryMessageRepository();
      aliceContactRepo = InMemoryContactRepository();

      // Bob: standard TestUser
      bob = TestUser.create(
        peerId: 'bob-peer-id',
        username: 'Bob',
        network: network,
      );

      // Cross-add contacts
      bob.addContact(
        TestUser.create(
          peerId: alicePeerId,
          username: aliceUsername,
          network: network,
        ),
      );
      aliceContactRepo.addTestContact(_makeContact(bob.peerId, bob.username));

      bob.start();
    });

    tearDown(() {
      bob.dispose();
      aliceP2P.dispose();
    });

    test(
      'message persisted with status "delivered" when inbox store succeeds',
      () async {
        aliceP2P.dropAcks = true;

        final (result, msg) = await sendChatMessage(
          p2pService: aliceP2P,
          messageRepo: aliceRepo,
          targetPeerId: bob.peerId,
          text: 'Hello Bob',
          senderPeerId: alicePeerId,
          senderUsername: aliceUsername,
          bridge: encryptBridge,
          recipientMlKemPublicKey: bobMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(
          msg!.status,
          'delivered',
        ); // ACK lost → inbox safety net → delivered

        // Exactly 1 message — no duplicates
        expect(aliceRepo.count, 1);
      },
    );

    test('receiver gets the message despite ACK loss', () async {
      aliceP2P.dropAcks = true;

      // Give Bob's listener time to process
      final bobReceived = Completer<void>();
      bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived.isCompleted) bobReceived.complete();
      });

      await sendChatMessage(
        p2pService: aliceP2P,
        messageRepo: aliceRepo,
        targetPeerId: bob.peerId,
        text: 'Hello Bob',
        senderPeerId: alicePeerId,
        senderUsername: aliceUsername,
        bridge: encryptBridge,
        recipientMlKemPublicKey: bobMlKemKey,
      );

      await bobReceived.future.timeout(const Duration(seconds: 2));

      final bobMessages = await bob.loadConversationWith(alicePeerId);
      expect(bobMessages, hasLength(1));
      expect(bobMessages.first.text, 'Hello Bob');
    });

    test('no duplicate when retrier re-sends after recovery', () async {
      aliceP2P.dropAcks = true;

      // First send: ACK dropped → status 'sent'
      final (_, msg1) = await sendChatMessage(
        p2pService: aliceP2P,
        messageRepo: aliceRepo,
        targetPeerId: bob.peerId,
        text: 'Hello Bob',
        senderPeerId: alicePeerId,
        senderUsername: aliceUsername,
        messageId: 'fixed-uuid-1',
        timestamp: '2026-01-01T00:00:00.000Z',
        bridge: encryptBridge,
        recipientMlKemPublicKey: bobMlKemKey,
      );
      expect(msg1!.status, 'delivered'); // ACK lost → inbox safety net

      // Simulate retrier marking it failed, then attempting re-send
      await aliceRepo.updateMessageStatus('fixed-uuid-1', 'failed');

      // Stop dropping ACKs for the retry
      aliceP2P.dropAcks = false;

      // Re-send with same messageId (retrier behavior)
      final (result2, msg2) = await sendChatMessage(
        p2pService: aliceP2P,
        messageRepo: aliceRepo,
        targetPeerId: bob.peerId,
        text: 'Hello Bob',
        senderPeerId: alicePeerId,
        senderUsername: aliceUsername,
        messageId: 'fixed-uuid-1',
        timestamp: '2026-01-01T00:00:00.000Z',
        bridge: encryptBridge,
        recipientMlKemPublicKey: bobMlKemKey,
      );

      expect(result2, SendChatMessageResult.success);
      expect(msg2!.status, 'delivered');

      // Still exactly 1 message (same ID → INSERT OR REPLACE)
      expect(aliceRepo.count, 1);

      final messages = await aliceRepo.getMessagesForContact(bob.peerId);
      expect(messages.first.status, 'delivered');
    });

    test(
      'ACK drop on fast path results in status "delivered" when inbox succeeds',
      () async {
        // Use the connected variant so fast path fires
        final innerAlice = FakeP2PService(
          peerId: alicePeerId,
          network: network,
        );
        final connectedP2P = _ConnectedAckDropP2PService(innerAlice);
        connectedP2P.dropAcks = true;

        final fastRepo = InMemoryMessageRepository();

        final (result, msg) = await sendChatMessage(
          p2pService: connectedP2P,
          messageRepo: fastRepo,
          targetPeerId: bob.peerId,
          text: 'fast path hello',
          senderPeerId: alicePeerId,
          senderUsername: aliceUsername,
          bridge: encryptBridge,
          recipientMlKemPublicKey: bobMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(
          msg!.status,
          'delivered',
        ); // ACK lost on fast path → inbox safety net

        connectedP2P.dispose();
      },
    );

    test('3 total failures fall through to inbox fallback', () async {
      aliceP2P.totalFailure = true;

      final (result, msg) = await sendChatMessage(
        p2pService: aliceP2P,
        messageRepo: aliceRepo,
        targetPeerId: bob.peerId,
        text: 'please reach bob',
        senderPeerId: alicePeerId,
        senderUsername: aliceUsername,
        bridge: encryptBridge,
        recipientMlKemPublicKey: bobMlKemKey,
      );

      // All 3 retries fail → inbox fallback → delivered (product rule)
      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.status, 'delivered');
      expect(msg.transport, 'inbox');

      // Verify inbox has the message for bob to drain
      expect(network.inboxCount(bob.peerId), 1);
    });
  });
}

ContactModel _makeContact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: 'test-mlkem-pk-$peerId',
  );
}
