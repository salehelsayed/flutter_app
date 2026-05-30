import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../../shared/fakes/chaos_p2p_network.dart';
import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../shared/fakes/lifecycle_bridge.dart';
import '../../shared/fakes/test_user.dart';

class _DiscoverMissProbeConnectedP2PService implements P2PService {
  final FakeP2PService _inner;
  final bool failFirstSendAfterProbe;
  int probeRelayCallCount = 0;
  int sendMessageWithReplyCallCount = 0;
  bool _failedFirstPostProbeSend = false;

  _DiscoverMissProbeConnectedP2PService(
    this._inner, {
    this.failFirstSendAfterProbe = false,
  });

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
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendMessageWithReplyCallCount++;
    if (failFirstSendAfterProbe &&
        probeRelayCallCount > 0 &&
        !_failedFirstPostProbeSend) {
      _failedFirstPostProbeSend = true;
      return const SendMessageResult(sent: false);
    }
    return _inner.sendMessageWithReply(peerId, message, timeoutMs: timeoutMs);
  }

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) =>
      _inner.startNode(privateKeyBase64, peerId);

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) =>
      _inner.startNodeCore(privateKeyBase64, peerId);

  @override
  Future<void> warmBackground() => _inner.warmBackground();

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
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async =>
      false;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) => _inner.sendLocalMessage(
    peerId,
    message,
    fromPeerId,
    timeoutMs: timeoutMs,
  );

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
  String? get lastRecoveryMethod => _inner.lastRecoveryMethod;

  @override
  void dispose() {}
}

void main() {
  group('Fault injection: FakeP2PNetwork hooks', () {
    late FakeP2PNetwork network;
    late TestUser alice;
    late TestUser bob;

    setUp(() {
      network = FakeP2PNetwork();
      alice = TestUser.create(
        peerId: 'alice',
        username: 'Alice',
        network: network,
      );
      bob = TestUser.create(peerId: 'bob', username: 'Bob', network: network);
      alice.addContact(bob);
      bob.addContact(alice);
      bob.start();
    });

    tearDown(() {
      alice.dispose();
      bob.dispose();
    });

    test(
      '1. Local peer offline mid-send falls to relay/inbox with no stuck state',
      () async {
        // Bob is initially a local WiFi peer
        alice.p2pService.localPeers.add('bob');
        alice.p2pService.localSendResult = false; // WiFi send fails

        alice.start();

        // Send should fall through to relay path and succeed
        final (result, msg) = await alice.sendMessage('bob', 'hello via relay');

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(
          network.deliverCallCount,
          greaterThanOrEqualTo(1),
          reason: 'Should have attempted relay delivery after WiFi failure',
        );
      },
    );

    test('3. Delayed ACK does not cause duplicate delivery', () async {
      // Add a 100ms ACK delay
      network.ackDelay = const Duration(milliseconds: 100);
      alice.start();

      final receivedMessages = <dynamic>[];
      final sub = bob.p2pService.messageStream.listen(receivedMessages.add);

      final (result, _) = await alice.sendMessage('bob', 'single message');

      expect(result, SendChatMessageResult.success);
      // Give stream time to propagate
      await Future.delayed(const Duration(milliseconds: 50));

      // Receiver should have exactly 1 message (no duplicate from delay)
      expect(receivedMessages, hasLength(1));

      await sub.cancel();
    });

    test(
      '4. Missing ACK (first send fails) falls to inbox with no duplicate',
      () async {
        // Single send attempt fails — with maxAttempts=1, falls to inbox
        alice.p2pService.sendFailCount = 1;
        alice.start();

        final (result, _) = await alice.sendMessage('bob', 'retry message');

        // Send still succeeds because inbox fallback stores the message
        expect(result, SendChatMessageResult.success);
        expect(
          network.storeInInboxCallCount,
          greaterThanOrEqualTo(1),
          reason:
              'Should have fallen through to inbox after single attempt failed',
        );
      },
    );

    test(
      '9. sendFailCount=2 causes single dial failure then inbox fallback',
      () async {
        // With maxAttempts=1, only 1 dial attempt is made. sendFailCount=2 means
        // that attempt fails, so the message falls to inbox.
        alice.p2pService.sendFailCount = 2;
        alice.start();

        final (result, msg) = await alice.sendMessage(
          'bob',
          'resilient message',
        );

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        // With only 1 attempt, direct delivery fails → inbox fallback
        expect(
          network.storeInInboxCallCount,
          greaterThanOrEqualTo(1),
          reason:
              'Should have fallen through to inbox after failed dial attempt',
        );
      },
    );

    test('deliveryFails=true causes send to fall through to inbox', () async {
      network.deliveryFails = true;
      alice.start();

      final (result, msg) = await alice.sendMessage('bob', 'inbox fallback');

      // When relay delivery fails, it should try inbox fallback
      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(
        network.storeInInboxCallCount,
        greaterThanOrEqualTo(1),
        reason: 'Should have fallen through to inbox',
      );
    });

    test(
      'duplicateOnDeliver injects two copies into receiver stream',
      () async {
        network.duplicateOnDeliver = true;
        alice.start();

        final receivedMessages = <dynamic>[];
        final sub = bob.p2pService.messageStream.listen(receivedMessages.add);

        final (result, _) = await alice.sendMessage('bob', 'dup test');

        expect(result, SendChatMessageResult.success);
        await Future.delayed(const Duration(milliseconds: 50));

        // With duplicateOnDeliver, the network injects the message twice
        expect(
          receivedMessages,
          hasLength(2),
          reason: 'Network should have injected a duplicate',
        );

        await sub.cancel();
      },
    );

    test('deliverCallCount tracks deliver() invocations', () async {
      alice.start();

      expect(network.deliverCallCount, 0);
      await alice.sendMessage('bob', 'msg1');
      final countAfterFirst = network.deliverCallCount;
      expect(countAfterFirst, greaterThanOrEqualTo(1));

      await alice.sendMessage('bob', 'msg2');
      expect(network.deliverCallCount, greaterThan(countAfterFirst));
    });

    test('resetCounters resets all tracking state', () async {
      network.deliveryFails = true;
      network.ackDelay = const Duration(milliseconds: 10);
      network.duplicateOnDeliver = true;
      network.deliverCallCount = 5;
      network.storeInInboxCallCount = 3;

      network.resetCounters();

      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      expect(network.deliveryFails, isFalse);
      expect(network.ackDelay, isNull);
      expect(network.duplicateOnDeliver, isFalse);
    });
  });

  group('Fault injection: ChaosP2PNetwork hooks', () {
    late ChaosP2PNetwork network;
    late TestUser alice;
    late TestUser bob;

    setUp(() {
      network = ChaosP2PNetwork(config: const ChaosConfig(seed: 42));
      alice = TestUser.create(
        peerId: 'alice',
        username: 'Alice',
        network: network,
      );
      bob = TestUser.create(peerId: 'bob', username: 'Bob', network: network);
      alice.addContact(bob);
      bob.addContact(alice);
      bob.start();
      alice.start();
    });

    tearDown(() {
      alice.dispose();
      bob.dispose();
    });

    test('5. ChaosP2PNetwork drop does not cause stuck state', () async {
      // Force drop the next message
      network.forceDropNext = true;

      final (result, _) = await alice.sendMessage('bob', 'dropped message');

      // The send should complete (not hang) — either through inbox or failure
      expect(
        result,
        isNotNull,
        reason: 'Send should complete, not hang after drop',
      );
      expect(network.droppedMessages, hasLength(1));
      expect(network.totalAttempted, greaterThanOrEqualTo(1));
    });

    test('10. ChaosP2PNetwork duplicateRate=1.0 sends duplicates', () async {
      // Create a network with 100% duplication
      final dupNetwork = ChaosP2PNetwork(
        config: const ChaosConfig(duplicateRate: 1.0, seed: 42),
      );

      final dupAlice = TestUser.create(
        peerId: 'alice-dup',
        username: 'AliceDup',
        network: dupNetwork,
      );
      final dupBob = TestUser.create(
        peerId: 'bob-dup',
        username: 'BobDup',
        network: dupNetwork,
      );
      dupAlice.addContact(dupBob);
      dupBob.addContact(dupAlice);
      dupBob.start();
      dupAlice.start();

      final receivedMessages = <dynamic>[];
      final sub = dupBob.p2pService.messageStream.listen(receivedMessages.add);

      await dupAlice.sendMessage('bob-dup', 'dup check');
      await Future.delayed(const Duration(milliseconds: 50));

      // With 100% duplication, receiver gets 2 copies (original + duplicate)
      expect(
        receivedMessages.length,
        greaterThanOrEqualTo(2),
        reason: 'Receiver should see duplicate messages from chaos network',
      );
      expect(dupNetwork.deliveredCount, greaterThanOrEqualTo(1));

      await sub.cancel();
      dupAlice.dispose();
      dupBob.dispose();
    });

    test('forceDropNext only drops the very next message', () async {
      network.forceDropNext = true;

      // First deliver is dropped
      final dropped = await network.deliver(
        'alice',
        'bob',
        'should be dropped',
      );
      expect(dropped, isFalse);
      expect(network.droppedMessages, contains('should be dropped'));

      // Second deliver should succeed (forceDropNext reset to false)
      final delivered = await network.deliver('alice', 'bob', 'should succeed');
      expect(delivered, isTrue);
      expect(network.forceDropNext, isFalse);
    });

    test('totalAttempted tracks all attempts including drops', () async {
      expect(network.totalAttempted, 0);

      network.forceDropNext = true;
      await network.deliver('alice', 'bob', 'msg1');
      expect(network.totalAttempted, 1);

      await network.deliver('alice', 'bob', 'msg2');
      expect(network.totalAttempted, 2);
    });
  });

  group('Phase 4: long-running personal discoverability recovery', () {
    late FakeP2PNetwork network;
    late TestUser alice;
    late TestUser bob;

    setUp(() {
      network = FakeP2PNetwork();
      alice = TestUser.create(
        peerId: 'alice-phase4',
        username: 'Alice',
        network: network,
      );
      bob = TestUser.create(
        peerId: 'bob-phase4',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();
    });

    tearDown(() {
      alice.dispose();
      bob.dispose();
    });

    test(
      'expired personal discoverability plus live relay still sends without inbox',
      () async {
        final staleRelayPath = _DiscoverMissProbeConnectedP2PService(
          alice.p2pService,
        );

        final (result, message) = await sendChatMessage(
          p2pService: staleRelayPath,
          messageRepo: alice.messageRepo,
          targetPeerId: bob.peerId,
          text: 'phase4 stale discoverability live send',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          bridge: alice.bridge,
          recipientMlKemPublicKey: 'test-mlkem-pk-${bob.peerId}',
        );
        await Future<void>.delayed(Duration.zero);

        final deliveredToBob = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(
          message!.transport,
          equals('direct'),
          reason:
              'The fake network marks the recovered live path as direct; '
              'the regression contract here is live-send without inbox fallback',
        );
        expect(staleRelayPath.probeRelayCallCount, 1);
        expect(network.deliverCallCount, 1);
        expect(network.storeInInboxCallCount, 0);
        expect(
          deliveredToBob.where(
            (msg) =>
                msg.isIncoming &&
                msg.text == 'phase4 stale discoverability live send',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'post-recovery send does not require simulator restart to regain live path',
      () async {
        bob.setOnline(false);

        final (offlineResult, offlineMessage) = await alice.sendMessage(
          bob.peerId,
          'phase4 offline fallback before recovery',
        );

        expect(offlineResult, SendChatMessageResult.success);
        expect(offlineMessage, isNotNull);
        expect(offlineMessage!.transport, equals('inbox'));
        expect(network.storeInInboxCallCount, 1);

        bob.setOnline(true);
        network.resetCounters();

        final recoveredRelayPath = _DiscoverMissProbeConnectedP2PService(
          alice.p2pService,
        );

        final (recoveredResult, recoveredMessage) = await sendChatMessage(
          p2pService: recoveredRelayPath,
          messageRepo: alice.messageRepo,
          targetPeerId: bob.peerId,
          text: 'phase4 recovered live send without restart',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          bridge: alice.bridge,
          recipientMlKemPublicKey: 'test-mlkem-pk-${bob.peerId}',
        );
        await Future<void>.delayed(Duration.zero);

        final deliveredToBob = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );

        expect(recoveredResult, SendChatMessageResult.success);
        expect(recoveredMessage, isNotNull);
        expect(
          recoveredMessage!.transport,
          equals('direct'),
          reason:
              'The fake network marks the recovered live path as direct; '
              'the regression contract here is live-send without inbox fallback',
        );
        expect(recoveredRelayPath.probeRelayCallCount, 1);
        expect(network.deliverCallCount, 1);
        expect(network.storeInInboxCallCount, 0);
        expect(
          deliveredToBob.where(
            (msg) =>
                msg.isIncoming &&
                msg.text == 'phase4 recovered live send without restart',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'relay probe retries one live send before falling back to inbox',
      () async {
        final staleRelayPath = _DiscoverMissProbeConnectedP2PService(
          alice.p2pService,
          failFirstSendAfterProbe: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: staleRelayPath,
          messageRepo: alice.messageRepo,
          targetPeerId: bob.peerId,
          text: 'phase4 post-probe retry avoids inbox fallback',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          bridge: alice.bridge,
          recipientMlKemPublicKey: 'test-mlkem-pk-${bob.peerId}',
        );
        await Future<void>.delayed(Duration.zero);

        final deliveredToBob = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, equals('direct'));
        expect(staleRelayPath.probeRelayCallCount, 1);
        expect(staleRelayPath.sendMessageWithReplyCallCount, 2);
        expect(network.deliverCallCount, 1);
        expect(network.storeInInboxCallCount, 0);
        expect(
          deliveredToBob.where(
            (msg) =>
                msg.isIncoming &&
                msg.text == 'phase4 post-probe retry avoids inbox fallback',
          ),
          hasLength(1),
        );
      },
    );
  });

  group('Fault injection: LifecycleBridge hooks', () {
    late LifecycleBridge bridge;
    late P2PServiceImpl service;

    setUp(() {
      bridge = LifecycleBridge();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );
    });

    tearDown(() {
      service.dispose();
    });

    test(
      '2. Relay disconnect triggers recovery and comes back online',
      () async {
        // Start online
        await service.startNodeCore(testBase64Key, testPeerId);
        expect(healthFromState(service.currentState), ConnectionHealth.online);

        // Simulate relay drop → phase goes degraded
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;

        // Health check should trigger recovery path
        await service.performImmediateHealthCheck();

        // After one health check with pollsUntilCircuitReady=1, should recover
        expect(healthFromState(service.currentState), ConnectionHealth.online);
        expect(bridge.relayReconnectCallCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      '6. Lost relay reservation: relay:reconnect fails but handleAppResumed completes',
      () async {
        await service.startNodeCore(testBase64Key, testPeerId);

        // Simulate relay reservation being lost
        bridge.simulateRelayReservationLost();

        // handleAppResumed should complete without throwing
        final result = await handleAppResumed(
          bridge: bridge,
          p2pService: service,
        );

        // The result should still be non-null (handleAppResumed catches errors)
        expect(
          result,
          isNotNull,
          reason: 'handleAppResumed should complete even with relay failure',
        );

        // Bridge was healthy (only relay:reconnect fails)
        expect(result, isTrue);

        // Verify the relay:reconnect was attempted
        expect(bridge.relayReconnectCallCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      '7. No overlapping health-check side effects: concurrent handleAppResumed',
      () async {
        await service.startNodeCore(testBase64Key, testPeerId);

        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;

        // Fire two concurrent handleAppResumed calls
        final resume1 = handleAppResumed(bridge: bridge, p2pService: service);
        final resume2 = handleAppResumed(bridge: bridge, p2pService: service);

        // Both should complete without crash/deadlock
        final results = await Future.wait([resume1, resume2]);

        expect(
          results,
          everyElement(isNotNull),
          reason: 'Both concurrent resumes should complete',
        );

        // No exceptions means no crash/deadlock
      },
    );

    test('8. Timer cleanup: dispose succeeds cleanly after recovery', () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      await handleAppResumed(bridge: bridge, p2pService: service);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Dispose should succeed cleanly with no lingering timers/futures
      // If there were lingering timers, this would throw or hang
      service.dispose();

      // Create a fresh service to verify no crash on re-creation
      final newService = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );
      expect(newService.currentState.isStarted, isFalse);
      newService.dispose();
    });

    test('nodeStartFails causes node:start to return error', () async {
      bridge.nodeStartFails = true;

      final response = await bridge.send(
        jsonEncode({'cmd': 'node:start', 'payload': {}}),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed['ok'], isFalse);
      expect(parsed['errorMessage'], contains('injected fault'));
    });

    test('peerDialFails causes peer:dial to return error', () async {
      bridge.peerDialFails = true;

      final response = await bridge.send(
        jsonEncode({
          'cmd': 'peer:dial',
          'payload': {'peerId': 'somePeer'},
        }),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed['ok'], isFalse);
      expect(parsed['connected'], isFalse);
    });

    test('nodeStatusDelay adds artificial delay to node:status', () async {
      bridge.phase = 'online';
      bridge.nodeStatusDelay = const Duration(milliseconds: 100);

      final start = DateTime.now();
      await bridge.send(jsonEncode({'cmd': 'node:status', 'payload': {}}));
      final elapsed = DateTime.now().difference(start);

      expect(
        elapsed.inMilliseconds,
        greaterThanOrEqualTo(80),
        reason: 'node:status should be delayed by ~100ms',
      );
    });

    test('messageSendFailCount: first N sends fail then succeed', () async {
      bridge.messageSendFailCount = 2;

      // First send: fails
      final r1 = await bridge.send(
        jsonEncode({'cmd': 'message:send', 'payload': {}}),
      );
      expect((jsonDecode(r1) as Map)['ok'], isFalse);

      // Second send: fails
      final r2 = await bridge.send(
        jsonEncode({'cmd': 'message:send', 'payload': {}}),
      );
      expect((jsonDecode(r2) as Map)['ok'], isFalse);

      // Third send: succeeds
      final r3 = await bridge.send(
        jsonEncode({'cmd': 'message:send', 'payload': {}}),
      );
      expect((jsonDecode(r3) as Map)['ok'], isTrue);
    });

    test(
      'simulateFullRecovery resets all faults and fires addresses updated',
      () async {
        // Set up various faults
        bridge.relayReservationLost = true;
        bridge.peerDialFails = true;
        bridge.nodeStartFails = true;
        bridge.nodeStatusDelay = const Duration(seconds: 1);
        bridge.messageSendFailCount = 5;
        bridge.bridgeUnhealthy = true;
        bridge.phase = 'degraded';

        bool addressesUpdatedFired = false;
        bridge.onAddressesUpdated = (_, _) {
          addressesUpdatedFired = true;
        };

        bridge.simulateFullRecovery();

        expect(bridge.relayReservationLost, isFalse);
        expect(bridge.peerDialFails, isFalse);
        expect(bridge.nodeStartFails, isFalse);
        expect(bridge.nodeStatusDelay, isNull);
        expect(bridge.messageSendFailCount, 0);
        expect(bridge.bridgeUnhealthy, isFalse);
        expect(bridge.phase, 'online');
        expect(addressesUpdatedFired, isTrue);
      },
    );

    test('reset() clears all counters and fault flags', () {
      bridge.phase = 'degraded';
      bridge.nodeStatusCallCount = 10;
      bridge.peerDialCallCount = 5;
      bridge.relayReconnectCallCount = 3;
      bridge.messageSendCallCount = 7;
      bridge.relayReservationLost = true;
      bridge.peerDialFails = true;
      bridge.nodeStartFails = true;
      bridge.nodeStatusDelay = const Duration(seconds: 1);
      bridge.messageSendFailCount = 5;
      bridge.bridgeUnhealthy = true;
      bridge.eventChannelDead = true;

      bridge.reset();

      expect(bridge.phase, 'startup');
      expect(bridge.nodeStatusCallCount, 0);
      expect(bridge.peerDialCallCount, 0);
      expect(bridge.relayReconnectCallCount, 0);
      expect(bridge.messageSendCallCount, 0);
      expect(bridge.relayReservationLost, isFalse);
      expect(bridge.peerDialFails, isFalse);
      expect(bridge.nodeStartFails, isFalse);
      expect(bridge.nodeStatusDelay, isNull);
      expect(bridge.messageSendFailCount, 0);
      expect(bridge.bridgeUnhealthy, isFalse);
      expect(bridge.eventChannelDead, isFalse);
    });
  });

  // =========================================================================
  // Phase 5: Event-driven recovery with fault injection
  // =========================================================================

  group('Phase 5: Fault injection with event-driven recovery', () {
    late LifecycleBridge bridge;
    late P2PServiceImpl service;

    setUp(() {
      bridge = LifecycleBridge();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );
    });

    tearDown(() {
      service.dispose();
    });

    test('lost reservation retries in place before watchdog restart', () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Configure: relay reservation lost, escalation enabled
      bridge.useStructuredRecoveryResponse = true;
      bridge.simulateRefreshEscalation = true;
      bridge.refreshFailuresBeforeWatchdog = 3;
      bridge.simulateRelayReservationLost();
      bridge.pollsUntilCircuitReady = 1;

      // First two health checks: in-place refresh fails
      await service.performImmediateHealthCheck();
      expect(
        service.consecutiveRefreshFailures,
        1,
        reason: 'First refresh failure should increment counter',
      );

      await service.performImmediateHealthCheck();
      expect(
        service.consecutiveRefreshFailures,
        2,
        reason: 'Second refresh failure should increment counter',
      );

      // Third health check: threshold reached, watchdog kicks in
      await service.performImmediateHealthCheck();

      // After watchdog success, the node should be recovering
      expect(
        service.lastRecoveryMethod,
        equals('watchdog_restart'),
        reason: 'Should escalate to watchdog after 3 refresh failures',
      );
      expect(
        service.consecutiveRefreshFailures,
        0,
        reason: 'Counter should reset after watchdog success',
      );
    });

    test(
      'bridge healthy but first relay dead still recovers through second relay',
      () async {
        // Start online
        await service.startNodeCore(testBase64Key, testPeerId);
        expect(healthFromState(service.currentState), ConnectionHealth.online);

        // Simulate first relay failing but bridge being healthy
        bridge.simulateBackground();
        // First relay:reconnect fails (relay reservation lost)
        bridge.relayReservationLost = true;
        bridge.pollsUntilCircuitReady = 1;

        // First health check: relay:reconnect fails
        await service.performImmediateHealthCheck();
        expect(service.consecutiveRefreshFailures, 1);
        expect(
          healthFromState(service.currentState),
          ConnectionHealth.degraded,
        );

        // Simulate second relay becoming available — clear the fault
        bridge.relayReservationLost = false;

        // Second health check: relay:reconnect succeeds through second relay
        await service.performImmediateHealthCheck();
        expect(
          service.consecutiveRefreshFailures,
          0,
          reason: 'Counter should reset after successful recovery',
        );

        // Node may still be recovering (pollsUntilCircuitReady handling)
        // but the relay:reconnect itself succeeded
        expect(
          bridge.relayReconnectCallCount,
          greaterThanOrEqualTo(2),
          reason: 'Should have tried relay:reconnect at least twice',
        );
      },
    );
  });
}
