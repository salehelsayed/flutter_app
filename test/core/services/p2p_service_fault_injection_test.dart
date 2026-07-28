import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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
import '../local_discovery/fake_local_p2p_service.dart';

Future<List<Map<String, dynamic>>> _captureFlowEvents(
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

class _ThrowingInboxStagingRepository extends InMemoryInboxStagingRepository {
  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    throw StateError('injected LAN stage failure');
  }
}

class _DiscoverMissProbeConnectedP2PService implements P2PService {
  final FakeP2PService _inner;
  int probeRelayCallCount = 0;
  int sendMessageWithReplyCallCount = 0;

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
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendMessageWithReplyCallCount++;
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
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) => _inner.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);

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
  }) async => false;

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
    bool enc = false,
    String? encScheme,
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

    // FDC-03: the SERIAL relay-probe→inbox tail was REMOVED. The former
    // "probe recovers the live path" tests (expired-discoverability live send,
    // post-recovery-without-restart, one-probe-attempt-then-inbox) are RETIRED —
    // that mechanism no longer exists. A discover-miss send to a peer with no
    // live circuit now takes durable INBOX custody via the concurrent copy
    // (probeRelayCallCount == 0); live relay recovery for a CIRCUIT peer is
    // FDC-02's in-race relay-live leg (covered in the send-orchestration suite).
    // This consolidated lock pins the fault-injection recovery contract: a
    // discover-miss send is never lost and reaches the recipient on drain.
    test('discover-miss send to an online peer takes durable inbox custody '
        'without the relay probe, and drains to the recipient', () async {
      final staleRelayPath = _DiscoverMissProbeConnectedP2PService(
        alice.p2pService,
      );

      final (result, message) = await sendChatMessage(
        p2pService: staleRelayPath,
        messageRepo: alice.messageRepo,
        targetPeerId: bob.peerId,
        text: 'phase4 discover-miss durable inbox custody',
        senderPeerId: alice.peerId,
        senderUsername: alice.username,
        bridge: alice.bridge,
        recipientMlKemPublicKey: 'test-mlkem-pk-${bob.peerId}',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // Custody, not live delivery — the probe tail is gone.
      expect(message!.transport, equals('inbox'));
      // TC-03 owns the probe-tail mutation. This fixture short-circuits on
      // concurrent custody. Its production mutation is the exact one-line
      // replacement:
      // `return persistInboxAccepted(recordInboxAttempt: false);`
      // → `await persistInboxAccepted(recordInboxAttempt: false);`
      // so control falls through to the sequential inbox store.
      expect(staleRelayPath.probeRelayCallCount, 0);
      expect(
        network.storeInInboxCallCount,
        1,
        reason: 'DTR05-MUTATION concurrent-custody-store-count',
      );

      // The recipient receives exactly one copy on drain.
      await bob.drainOfflineInbox();
      await Future<void>.delayed(Duration.zero);
      final deliveredToBob = await bob.messageRepo.getMessagesForContact(
        alice.peerId,
      );
      expect(
        deliveredToBob.where(
          (msg) =>
              msg.isIncoming &&
              msg.text == 'phase4 discover-miss durable inbox custody',
        ),
        hasLength(1),
      );
    });
  });

  group('Fault injection: LAN durable staging', () {
    test(
      'LAN staging write failure produces rejected commit and falls back to in-memory emit',
      () async {
        final bridge = LifecycleBridge();
        final localP2P = FakeLocalP2PService();
        final repo = _ThrowingInboxStagingRepository();
        final service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                fail('staging failures must not replay');
              },
        );
        addTearDown(service.dispose);

        final emitted = <ChatMessage>[];
        final sub = service.messageStream.listen(emitted.add);
        addTearDown(sub.cancel);

        late LanInboundDecision decision;
        final events = await _captureFlowEvents(() async {
          decision = await Future<LanInboundDecision>.sync(
            () => localP2P.inboundChatCommitHandler!(
              LocalChatMessage(
                from: 'remote-peer',
                to: 'self-peer',
                content: jsonEncode({
                  'type': 'chat_message',
                  'version': '1',
                  'payload': {
                    'id': 'msg-lan-stage-fail',
                    'text': 'stage fail fallback',
                    'senderPeerId': 'remote-peer',
                    'senderUsername': 'Alice',
                    'timestamp': '2026-04-01T00:00:00.000Z',
                  },
                }),
                timestamp: DateTime.utc(2026, 4),
                isIncoming: true,
              ),
              nonce: 'n-stage-fail',
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });

        expect(decision.isRejected, isTrue);
        expect(decision.reason, 'staging_error');
        expect(emitted, hasLength(1));
        expect(emitted.single.transport, 'wifi');
        expect(
          events.any(
            (event) => event['event'] == 'P2P_SERVICE_LAN_STAGE_ERROR',
          ),
          isTrue,
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
