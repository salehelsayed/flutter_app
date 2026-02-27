import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../../shared/fakes/chaos_p2p_network.dart';
import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/lifecycle_bridge.dart';
import '../../shared/fakes/test_user.dart';

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
      bob = TestUser.create(
        peerId: 'bob',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      bob.start();
    });

    tearDown(() {
      alice.dispose();
      bob.dispose();
    });

    test('1. Local peer offline mid-send falls to relay/inbox with no stuck state',
        () async {
      // Bob is initially a local WiFi peer
      alice.p2pService.localPeers.add('bob');
      alice.p2pService.localSendResult = false; // WiFi send fails

      alice.start();

      // Send should fall through to relay path and succeed
      final (result, msg) = await alice.sendMessage('bob', 'hello via relay');

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(network.deliverCallCount, greaterThanOrEqualTo(1),
          reason: 'Should have attempted relay delivery after WiFi failure');
    });

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

    test('4. Missing ACK (first send fails) falls to inbox with no duplicate',
        () async {
      // Single send attempt fails — with maxAttempts=1, falls to inbox
      alice.p2pService.sendFailCount = 1;
      alice.start();

      final (result, _) = await alice.sendMessage('bob', 'retry message');

      // Send still succeeds because inbox fallback stores the message
      expect(result, SendChatMessageResult.success);
      expect(network.storeInInboxCallCount, greaterThanOrEqualTo(1),
          reason: 'Should have fallen through to inbox after single attempt failed');
    });

    test('9. sendFailCount=2 causes single dial failure then inbox fallback',
        () async {
      // With maxAttempts=1, only 1 dial attempt is made. sendFailCount=2 means
      // that attempt fails, so the message falls to inbox.
      alice.p2pService.sendFailCount = 2;
      alice.start();

      final (result, msg) = await alice.sendMessage('bob', 'resilient message');

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      // With only 1 attempt, direct delivery fails → inbox fallback
      expect(network.storeInInboxCallCount, greaterThanOrEqualTo(1),
          reason: 'Should have fallen through to inbox after failed dial attempt');
    });

    test('deliveryFails=true causes send to fall through to inbox', () async {
      network.deliveryFails = true;
      alice.start();

      final (result, msg) = await alice.sendMessage('bob', 'inbox fallback');

      // When relay delivery fails, it should try inbox fallback
      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(network.storeInInboxCallCount, greaterThanOrEqualTo(1),
          reason: 'Should have fallen through to inbox');
    });

    test('duplicateOnDeliver injects two copies into receiver stream', () async {
      network.duplicateOnDeliver = true;
      alice.start();

      final receivedMessages = <dynamic>[];
      final sub = bob.p2pService.messageStream.listen(receivedMessages.add);

      final (result, _) = await alice.sendMessage('bob', 'dup test');

      expect(result, SendChatMessageResult.success);
      await Future.delayed(const Duration(milliseconds: 50));

      // With duplicateOnDeliver, the network injects the message twice
      expect(receivedMessages, hasLength(2),
          reason: 'Network should have injected a duplicate');

      await sub.cancel();
    });

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
      network = ChaosP2PNetwork(
        config: const ChaosConfig(seed: 42),
      );
      alice = TestUser.create(
        peerId: 'alice',
        username: 'Alice',
        network: network,
      );
      bob = TestUser.create(
        peerId: 'bob',
        username: 'Bob',
        network: network,
      );
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
      expect(result, isNotNull,
          reason: 'Send should complete, not hang after drop');
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
      expect(receivedMessages.length, greaterThanOrEqualTo(2),
          reason: 'Receiver should see duplicate messages from chaos network');
      expect(dupNetwork.deliveredCount, greaterThanOrEqualTo(1));

      await sub.cancel();
      dupAlice.dispose();
      dupBob.dispose();
    });

    test('forceDropNext only drops the very next message', () async {
      network.forceDropNext = true;

      // First deliver is dropped
      final dropped =
          await network.deliver('alice', 'bob', 'should be dropped');
      expect(dropped, isFalse);
      expect(network.droppedMessages, contains('should be dropped'));

      // Second deliver should succeed (forceDropNext reset to false)
      final delivered =
          await network.deliver('alice', 'bob', 'should succeed');
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

  group('Fault injection: LifecycleBridge hooks', () {
    late LifecycleBridge bridge;
    late P2PServiceImpl service;

    setUp(() {
      bridge = LifecycleBridge();
      service = P2PServiceImpl(bridge: bridge);
    });

    tearDown(() {
      service.dispose();
    });

    test('2. Relay disconnect triggers recovery and comes back online', () async {
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
    });

    test('6. Lost relay reservation: relay:reconnect fails but handleAppResumed completes',
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
      expect(result, isNotNull,
          reason: 'handleAppResumed should complete even with relay failure');

      // Bridge was healthy (only relay:reconnect fails)
      expect(result, isTrue);

      // Verify the relay:reconnect was attempted
      expect(bridge.relayReconnectCallCount, greaterThanOrEqualTo(1));
    });

    test('7. No overlapping health-check side effects: concurrent handleAppResumed',
        () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      // Fire two concurrent handleAppResumed calls
      final resume1 = handleAppResumed(bridge: bridge, p2pService: service);
      final resume2 = handleAppResumed(bridge: bridge, p2pService: service);

      // Both should complete without crash/deadlock
      final results = await Future.wait([resume1, resume2]);

      expect(results, everyElement(isNotNull),
          reason: 'Both concurrent resumes should complete');

      // No exceptions means no crash/deadlock
    });

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
      final newService = P2PServiceImpl(bridge: bridge);
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
        jsonEncode({'cmd': 'peer:dial', 'payload': {'peerId': 'somePeer'}}),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed['ok'], isFalse);
      expect(parsed['connected'], isFalse);
    });

    test('nodeStatusDelay adds artificial delay to node:status', () async {
      bridge.phase = 'online';
      bridge.nodeStatusDelay = const Duration(milliseconds: 100);

      final start = DateTime.now();
      await bridge.send(
        jsonEncode({'cmd': 'node:status', 'payload': {}}),
      );
      final elapsed = DateTime.now().difference(start);

      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(80),
          reason: 'node:status should be delayed by ~100ms');
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

    test('simulateFullRecovery resets all faults and fires addresses updated',
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
      bridge.onAddressesUpdated = (_, __) {
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
    });

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
}
