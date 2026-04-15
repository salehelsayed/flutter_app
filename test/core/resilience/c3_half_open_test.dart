import 'dart:async';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
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
// _HalfOpenP2PService — currentState reports an existing connected peer
// (stale cache), but sendMessageWithReply() returns sent:false for the
// first N calls.
// ---------------------------------------------------------------------------

class _HalfOpenP2PService implements P2PService {
  final FakeP2PService _inner;
  final String connectedPeerId;

  /// Number of sendMessageWithReply calls that return sent:false
  /// (simulating a dead connection). After this many failures,
  /// calls delegate to the inner service.
  int fastPathFailCount;
  int _failsRemaining;

  _HalfOpenP2PService(
    this._inner, {
    required this.connectedPeerId,
    this.fastPathFailCount = 1,
  }) : _failsRemaining = fastPathFailCount;

  @override
  NodeState get currentState => _inner.currentState.copyWith(
    connections: [
      p2p.ConnectionState(
        peerId: connectedPeerId,
        multiaddrs: const ['/ip4/127.0.0.1/tcp/4001'],
        direction: 'outbound',
        status: 'connected',
      ),
    ],
  );

  @override
  bool isConnectedToPeer(String peerId) => true; // stale — always "connected"

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (_failsRemaining > 0) {
      _failsRemaining--;
      return const SendMessageResult(sent: false);
    }
    return _inner.sendMessageWithReply(targetPeerId, message);
  }

  // --- Delegates -----------------------------------------------------------

  @override
  Stream<NodeState> get stateStream => _inner.stateStream;

  @override
  Stream<ChatMessage> get messageStream => _inner.messageStream;

  @override
  Future<bool> sendMessage(String peerId, String message) =>
      _inner.sendMessage(peerId, message);

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
  Future<bool> storeInInbox(String toPeerId, String message, {int? timeoutMs}) =>
      _inner.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);

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

class _DiscoverMissProbeConnectedP2PService implements P2PService {
  final FakeP2PService _inner;
  int probeRelayCallCount = 0;

  _DiscoverMissProbeConnectedP2PService(this._inner);

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async {
    probeRelayCallCount++;
    return RelayProbeResult.connected;
  }

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
  }) =>
      _inner.sendMessageWithReply(targetPeerId, message, timeoutMs: timeoutMs);

  @override
  Future<bool> startNode(String pk, String pid) => _inner.startNode(pk, pid);

  @override
  Future<bool> stopNode() => _inner.stopNode();

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) => _inner.dialPeer(peerId, addresses: addresses, timeoutMs: timeoutMs);

  @override
  Future<bool> storeInInbox(String toPeerId, String message, {int? timeoutMs}) =>
      _inner.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);

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
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('C3 — Half-open connection resilience', () {
    late FakeP2PNetwork network;
    late InMemoryMessageRepository aliceRepo;
    late InMemoryContactRepository aliceContactRepo;
    late TestUser bob;
    late PassthroughCryptoBridge encryptBridge;

    const alicePeerId = 'alice-peer-id';
    const aliceUsername = 'Alice';
    const bobMlKemKey = 'test-mlkem-pk-bob';

    setUp(() {
      network = FakeP2PNetwork();

      encryptBridge = PassthroughCryptoBridge();

      aliceRepo = InMemoryMessageRepository();
      aliceContactRepo = InMemoryContactRepository();

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
      aliceContactRepo.addTestContact(
        ContactModel(
          peerId: bob.peerId,
          publicKey: 'pk-${bob.peerId}',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: bob.username,
          signature: 'sig-${bob.peerId}',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          mlKemPublicKey: bobMlKemKey,
        ),
      );

      bob.start();
    });

    tearDown(() {
      bob.dispose();
    });

    test(
      'fast path failure falls through to direct live send before inbox',
      () async {
        final innerAlice = FakeP2PService(
          peerId: alicePeerId,
          network: network,
        );
        final halfOpen = _HalfOpenP2PService(
          innerAlice,
          connectedPeerId: bob.peerId,
          fastPathFailCount: 1,
        );

        final bobReceived = Completer<void>();
        bob.chatListener.incomingMessageStream.listen((_) {
          if (!bobReceived.isCompleted) bobReceived.complete();
        });

        final (result, msg) = await sendChatMessage(
          p2pService: halfOpen,
          messageRepo: aliceRepo,
          targetPeerId: bob.peerId,
          text: 'Hello through half-open',
          senderPeerId: alicePeerId,
          senderUsername: aliceUsername,
          bridge: encryptBridge,
          recipientMlKemPublicKey: bobMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(msg!.status, 'delivered');
        expect(msg.transport, 'direct');
        expect(network.inboxCount(bob.peerId), 0);

        await bobReceived.future.timeout(const Duration(seconds: 2));
        final bobMessages = await bob.loadConversationWith(alicePeerId);
        expect(bobMessages, hasLength(1));
        expect(bobMessages.first.text, 'Hello through half-open');

        // No duplicates
        expect(aliceRepo.count, 1);

        halfOpen.dispose();
      },
    );

    test('all 4 send attempts fail, message stored in inbox', () async {
      final innerAlice = FakeP2PService(peerId: alicePeerId, network: network);
      // 1 fast path + 3 retries = 4 total failures
      final halfOpen = _HalfOpenP2PService(
        innerAlice,
        connectedPeerId: bob.peerId,
        fastPathFailCount: 4,
      );

      final (result, msg) = await sendChatMessage(
        p2pService: halfOpen,
        messageRepo: aliceRepo,
        targetPeerId: bob.peerId,
        text: 'Inbox fallback after half-open',
        senderPeerId: alicePeerId,
        senderUsername: aliceUsername,
        bridge: encryptBridge,
        recipientMlKemPublicKey: bobMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.status, 'delivered');
      expect(msg.transport, 'inbox');

      // Inbox has the message for Bob to drain
      expect(network.inboxCount(bob.peerId), 1);

      // No duplicates on Alice's side
      expect(aliceRepo.count, 1);

      halfOpen.dispose();
    });

    test(
      'discover miss plus probe-connected relay stays live instead of falling to inbox',
      () async {
        final innerAlice = FakeP2PService(
          peerId: alicePeerId,
          network: network,
        );
        final probeP2P = _DiscoverMissProbeConnectedP2PService(innerAlice);

        final bobReceived = Completer<void>();
        bob.chatListener.incomingMessageStream.listen((_) {
          if (!bobReceived.isCompleted) bobReceived.complete();
        });

        final (result, msg) = await sendChatMessage(
          p2pService: probeP2P,
          messageRepo: aliceRepo,
          targetPeerId: bob.peerId,
          text: 'Hello after discover miss',
          senderPeerId: alicePeerId,
          senderUsername: aliceUsername,
          bridge: encryptBridge,
          recipientMlKemPublicKey: bobMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(msg!.status, 'delivered');
        expect(msg.transport, 'direct');
        expect(probeP2P.probeRelayCallCount, 1);
        expect(network.inboxCount(bob.peerId), 0);

        await bobReceived.future.timeout(const Duration(seconds: 2));
        final bobMessages = await bob.loadConversationWith(alicePeerId);
        expect(bobMessages, hasLength(1));
        expect(bobMessages.first.text, 'Hello after discover miss');

        probeP2P.dispose();
      },
    );
  });
}
