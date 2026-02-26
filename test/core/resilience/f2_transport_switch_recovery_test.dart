import 'dart:async';

import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/lifecycle_bridge.dart';
import '../../shared/fakes/test_user.dart';

void main() {
  group('F2 -- Transport switch recovery', () {
    late FakeP2PNetwork network;
    late TestUser alice;
    late TestUser bob;

    setUp(() {
      network = FakeP2PNetwork();

      alice = TestUser.create(
        peerId: 'alice-peer-id',
        username: 'Alice',
        network: network,
      );

      bob = TestUser.create(
        peerId: 'bob-peer-id',
        username: 'Bob',
        network: network,
      );

      // Cross-add contacts
      alice.addContact(bob);
      bob.addContact(alice);

      // Start listeners so Bob processes incoming messages
      bob.start();
    });

    tearDown(() {
      alice.dispose();
      bob.dispose();
    });

    // -----------------------------------------------------------------------
    // Test 1: WiFi online -> WiFi drop -> relay takes over -> delivered
    // -----------------------------------------------------------------------
    test('WiFi online -> WiFi drop -> relay takes over -> message delivered via relay',
        () async {
      final aliceP2P = alice.p2pService as FakeP2PService;

      // -- Phase 1: WiFi available, send via WiFi --
      aliceP2P.localPeers.add(bob.peerId);
      aliceP2P.simulateTransportSwitch('wifi');

      final bobReceived1 = Completer<void>();
      var sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived1.isCompleted) bobReceived1.complete();
      });

      final (result1, msg1) =
          await alice.sendMessage(bob.peerId, 'Hello over WiFi');

      expect(result1, SendChatMessageResult.success);
      expect(msg1, isNotNull);
      expect(msg1!.transport, 'wifi');

      await bobReceived1.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Phase 2: WiFi drops, send via relay --
      aliceP2P.localPeers.remove(bob.peerId);
      aliceP2P.simulateTransportSwitch('relay');

      final bobReceived2 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived2.isCompleted) bobReceived2.complete();
      });

      final (result2, msg2) =
          await alice.sendMessage(bob.peerId, 'Hello over relay');

      expect(result2, SendChatMessageResult.success);
      expect(msg2, isNotNull);
      expect(msg2!.transport, 'relay');

      await bobReceived2.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Assert: both messages delivered, correct transports --
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(2));
      expect(bobMessages[0].text, 'Hello over WiFi');
      expect(bobMessages[1].text, 'Hello over relay');

      final aliceMessages =
          await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceMessages, hasLength(2));
      expect(aliceMessages[0].transport, 'wifi');
      expect(aliceMessages[1].transport, 'relay');
    });

    // -----------------------------------------------------------------------
    // Test 2: Relay drop (background) -> handleAppResumed -> recovery ->
    //         messages delivered
    // -----------------------------------------------------------------------
    test('relay drop (background) -> handleAppResumed -> recovery -> messages delivered',
        () async {
      final aliceP2P = alice.p2pService as FakeP2PService;

      // -- Phase 1: Send a message over relay while online --
      final bobReceived1 = Completer<void>();
      var sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived1.isCompleted) bobReceived1.complete();
      });

      final (result1, msg1) =
          await alice.sendMessage(bob.peerId, 'Before background');

      expect(result1, SendChatMessageResult.success);
      expect(msg1!.transport, 'relay');

      await bobReceived1.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Phase 2: Simulate background (Bob goes offline, relay drops) --
      bob.setOnline(false);

      // Alice sends while Bob is offline -> falls to inbox
      final (result2, msg2) =
          await alice.sendMessage(bob.peerId, 'During background');

      expect(result2, SendChatMessageResult.success);
      expect(msg2, isNotNull);
      expect(msg2!.transport, 'inbox');

      // Verify inbox has the message
      expect(network.inboxCount(bob.peerId), 1);

      // -- Phase 3: Bob comes back online, drains inbox --
      bob.setOnline(true);

      // Use a LifecycleBridge to simulate the resume flow
      final bridge = LifecycleBridge();
      bridge.phase = 'online';
      bridge.pollsUntilCircuitReady = 1;
      final service = P2PServiceImpl(bridge: bridge);
      await service.startNodeCore(testBase64Key, testPeerId);

      // Simulate background then resume
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      final bridgeOk = await handleAppResumed(
        bridge: bridge,
        p2pService: service,
      );

      expect(bridgeOk, isTrue, reason: 'Bridge should be healthy after resume');
      expect(healthFromState(service.currentState), ConnectionHealth.online,
          reason: 'Should be back online after handleAppResumed');

      // Bob drains his inbox
      final bobReceived2 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived2.isCompleted) bobReceived2.complete();
      });

      final drained = await bob.drainOfflineInbox();
      expect(drained, 1, reason: 'Should have drained 1 inbox message');

      await bobReceived2.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Assert: Bob has both messages --
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(2));
      expect(bobMessages[0].text, 'Before background');
      expect(bobMessages[1].text, 'During background');

      service.dispose();
    });

    // -----------------------------------------------------------------------
    // Test 3: Full cycle with bounded timing
    // wifi -> relay -> background -> resume -> relay -> wifi again
    // -----------------------------------------------------------------------
    test('full cycle: wifi -> relay -> background -> resume -> relay -> wifi with bounded timing',
        () async {
      final aliceP2P = alice.p2pService as FakeP2PService;
      final transports = <String?>[];

      // -- Message 1: WiFi --
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived1 = Completer<void>();
      var sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived1.isCompleted) bobReceived1.complete();
      });

      final (r1, m1) = await alice.sendMessage(bob.peerId, 'msg1-wifi');
      expect(r1, SendChatMessageResult.success);
      transports.add(m1!.transport);
      await bobReceived1.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Message 2: relay (WiFi dropped) --
      aliceP2P.localPeers.remove(bob.peerId);

      final bobReceived2 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived2.isCompleted) bobReceived2.complete();
      });

      final (r2, m2) = await alice.sendMessage(bob.peerId, 'msg2-relay');
      expect(r2, SendChatMessageResult.success);
      transports.add(m2!.transport);
      await bobReceived2.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Message 3: inbox (Bob backgrounded) --
      bob.setOnline(false);

      final (r3, m3) = await alice.sendMessage(bob.peerId, 'msg3-inbox');
      expect(r3, SendChatMessageResult.success);
      transports.add(m3!.transport);

      // -- Simulate resume with bounded timing --
      final sw = Stopwatch()..start();

      bob.setOnline(true);

      // Use LifecycleBridge for the recovery path
      final bridge = LifecycleBridge();
      bridge.phase = 'online';
      bridge.pollsUntilCircuitReady = 1;
      final service = P2PServiceImpl(bridge: bridge);
      await service.startNodeCore(testBase64Key, testPeerId);

      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;
      bridge.markRecoveryStart();

      await handleAppResumed(bridge: bridge, p2pService: service);
      bridge.simulateRecoveryComplete();

      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(5000),
          reason: 'Recovery must complete within 5 seconds');
      expect(bridge.lastRecoveryDuration, isNotNull);
      expect(bridge.phase, 'online');

      // Bob drains inbox
      final bobReceived3 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived3.isCompleted) bobReceived3.complete();
      });

      await bob.drainOfflineInbox();
      await bobReceived3.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Message 4: relay again (Bob back online, no WiFi) --
      final bobReceived4 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived4.isCompleted) bobReceived4.complete();
      });

      final (r4, m4) = await alice.sendMessage(bob.peerId, 'msg4-relay');
      expect(r4, SendChatMessageResult.success);
      transports.add(m4!.transport);
      await bobReceived4.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Message 5: WiFi restored --
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived5 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived5.isCompleted) bobReceived5.complete();
      });

      final (r5, m5) = await alice.sendMessage(bob.peerId, 'msg5-wifi');
      expect(r5, SendChatMessageResult.success);
      transports.add(m5!.transport);
      await bobReceived5.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Assert transport sequence --
      expect(transports, ['wifi', 'relay', 'inbox', 'relay', 'wifi']);

      // -- Assert all 5 messages delivered to Bob, no duplicates --
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(5));
      expect(bobMessages.map((m) => m.text).toList(), [
        'msg1-wifi',
        'msg2-relay',
        'msg3-inbox',
        'msg4-relay',
        'msg5-wifi',
      ]);

      // Alice has exactly 5 messages
      final aliceMessages =
          await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceMessages, hasLength(5));

      service.dispose();
    });

    // -----------------------------------------------------------------------
    // Test 4: No stuck "connecting" state after transport switch
    // -----------------------------------------------------------------------
    test('no stuck "connecting" state after transport switch — recovery completes within bounded time',
        () async {
      final bridge = LifecycleBridge();
      bridge.phase = 'online';
      bridge.pollsUntilCircuitReady = 1;
      final service = P2PServiceImpl(bridge: bridge);

      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Simulate transport switch: background (relay drop)
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      // Start timer
      final sw = Stopwatch()..start();

      // Resume recovery
      await handleAppResumed(bridge: bridge, p2pService: service);

      sw.stop();

      // Assert: not stuck in degraded/connecting
      expect(healthFromState(service.currentState), ConnectionHealth.online,
          reason: 'Should not be stuck in connecting/degraded');
      expect(sw.elapsedMilliseconds, lessThan(5000),
          reason: 'Recovery must not take indefinitely');

      // Verify state is fully online with circuit addresses
      expect(service.currentState.isStarted, isTrue);
      expect(service.currentState.circuitAddresses, isNotEmpty);

      // Repeat: multiple transport switches should all recover quickly
      for (var i = 0; i < 3; i++) {
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;

        final cycleWatch = Stopwatch()..start();
        await handleAppResumed(bridge: bridge, p2pService: service);
        cycleWatch.stop();

        expect(healthFromState(service.currentState), ConnectionHealth.online,
            reason: 'Should be online after cycle ${i + 1}');
        expect(cycleWatch.elapsedMilliseconds, lessThan(5000),
            reason: 'Recovery cycle ${i + 1} must be bounded');
      }

      service.dispose();
    });

    // -----------------------------------------------------------------------
    // Test 5: Messages sent during transition are not lost
    //         (inbox fallback catches them)
    // -----------------------------------------------------------------------
    test('messages sent during transition are not lost — inbox fallback catches them',
        () async {
      final aliceP2P = alice.p2pService as FakeP2PService;

      // -- Phase 1: Send via WiFi --
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived1 = Completer<void>();
      var sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived1.isCompleted) bobReceived1.complete();
      });

      final (r1, m1) = await alice.sendMessage(bob.peerId, 'wifi-msg');
      expect(r1, SendChatMessageResult.success);
      expect(m1!.transport, 'wifi');
      await bobReceived1.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Phase 2: Both WiFi and relay fail (Bob fully offline) --
      aliceP2P.localPeers.remove(bob.peerId);
      bob.setOnline(false);

      // Alice sends during transition — all relay attempts fail, falls to inbox
      final (r2, m2) =
          await alice.sendMessage(bob.peerId, 'transition-msg-1');

      expect(r2, SendChatMessageResult.success,
          reason: 'Should succeed via inbox fallback');
      expect(m2, isNotNull);
      expect(m2!.transport, 'inbox');

      // Send another during transition
      final (r3, m3) =
          await alice.sendMessage(bob.peerId, 'transition-msg-2');

      expect(r3, SendChatMessageResult.success);
      expect(m3!.transport, 'inbox');

      // -- Phase 3: Verify inbox has both messages --
      expect(network.inboxCount(bob.peerId), 2);

      // -- Phase 4: Bob comes back, drains inbox --
      bob.setOnline(true);

      final inboxMessages = <String>[];
      sub = bob.chatListener.incomingMessageStream.listen((msg) {
        inboxMessages.add(msg.text);
      });

      final drained = await bob.drainOfflineInbox();
      expect(drained, 2, reason: 'Should drain both inbox messages');

      // Allow stream propagation
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      // -- Assert: no messages lost --
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(3));
      expect(bobMessages[0].text, 'wifi-msg');
      expect(bobMessages[1].text, 'transition-msg-1');
      expect(bobMessages[2].text, 'transition-msg-2');

      // Alice has exactly 3 messages, no duplicates
      final aliceMessages =
          await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceMessages, hasLength(3));

      // No messages left in inbox
      expect(network.inboxCount(bob.peerId), 0);
    });

    // -----------------------------------------------------------------------
    // Test 6: No duplicate messages appear after recovery
    // -----------------------------------------------------------------------
    test('no duplicate messages after recovery', () async {
      final aliceP2P = alice.p2pService as FakeP2PService;

      // Send over WiFi
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived1 = Completer<void>();
      var sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived1.isCompleted) bobReceived1.complete();
      });

      final (r1, _) = await alice.sendMessage(bob.peerId, 'unique-msg-1');
      expect(r1, SendChatMessageResult.success);
      await bobReceived1.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // WiFi drops, send over relay
      aliceP2P.localPeers.remove(bob.peerId);

      final bobReceived2 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived2.isCompleted) bobReceived2.complete();
      });

      final (r2, _) = await alice.sendMessage(bob.peerId, 'unique-msg-2');
      expect(r2, SendChatMessageResult.success);
      await bobReceived2.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // Bob goes offline, send to inbox
      bob.setOnline(false);
      final (r3, _) = await alice.sendMessage(bob.peerId, 'unique-msg-3');
      expect(r3, SendChatMessageResult.success);

      // Bob comes back, drains inbox
      bob.setOnline(true);

      final bobReceived3 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived3.isCompleted) bobReceived3.complete();
      });

      await bob.drainOfflineInbox();
      await bobReceived3.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // WiFi comes back, send another
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived4 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived4.isCompleted) bobReceived4.complete();
      });

      final (r4, _) = await alice.sendMessage(bob.peerId, 'unique-msg-4');
      expect(r4, SendChatMessageResult.success);
      await bobReceived4.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // -- Assert: exactly 4 messages on each side, no duplicates --
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(4));

      final bobTexts = bobMessages.map((m) => m.text).toList();
      expect(bobTexts, [
        'unique-msg-1',
        'unique-msg-2',
        'unique-msg-3',
        'unique-msg-4',
      ]);

      // Verify uniqueness: no duplicate message IDs
      final bobIds = bobMessages.map((m) => m.id).toSet();
      expect(bobIds.length, 4, reason: 'All message IDs should be unique');

      final aliceMessages =
          await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceMessages, hasLength(4));

      final aliceIds = aliceMessages.map((m) => m.id).toSet();
      expect(aliceIds.length, 4, reason: 'All Alice message IDs should be unique');
    });

    // -----------------------------------------------------------------------
    // Test 7: LifecycleBridge recovery timing is tracked correctly
    // -----------------------------------------------------------------------
    test('LifecycleBridge tracks recovery timing', () async {
      final bridge = LifecycleBridge();
      bridge.phase = 'online';

      // No recovery yet
      expect(bridge.lastRecoveryDuration, isNull);

      // Simulate background
      bridge.simulateBackground();
      expect(bridge.phase, 'degraded');

      // Mark recovery start
      bridge.markRecoveryStart();

      // Small delay to make duration measurable
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Complete recovery
      bridge.simulateRecoveryComplete();

      expect(bridge.phase, 'online');
      expect(bridge.lastRecoveryDuration, isNotNull);
      expect(bridge.lastRecoveryDuration!.inMilliseconds, greaterThanOrEqualTo(0));
      expect(bridge.addressesPushFired, isTrue);
    });

    // -----------------------------------------------------------------------
    // Test 8: FakeP2PService transport mode and connected peers
    // -----------------------------------------------------------------------
    test('FakeP2PService transport mode and connected peers integration',
        () async {
      final aliceP2P = alice.p2pService as FakeP2PService;

      // Default state
      expect(aliceP2P.transportMode, 'relay');
      expect(aliceP2P.isOnline, isTrue);
      expect(aliceP2P.connectedPeers, isEmpty);
      expect(aliceP2P.isConnectedToPeer(bob.peerId), isFalse);

      // Add connected peer
      aliceP2P.connectedPeers.add(bob.peerId);
      expect(aliceP2P.isConnectedToPeer(bob.peerId), isTrue);

      // Simulate transport switch to wifi
      aliceP2P.localPeers.add(bob.peerId);
      aliceP2P.simulateTransportSwitch('wifi');
      expect(aliceP2P.transportMode, 'wifi');
      expect(aliceP2P.localPeers.contains(bob.peerId), isTrue,
          reason: 'WiFi switch should keep local peers (caller added them)');

      // Simulate transport switch away from wifi clears localPeers
      aliceP2P.simulateTransportSwitch('relay');
      expect(aliceP2P.transportMode, 'relay');
      expect(aliceP2P.localPeers, isEmpty,
          reason: 'Non-WiFi transport should clear local peers');

      // Go offline
      aliceP2P.setOnline(false);
      expect(aliceP2P.isOnline, isFalse);

      aliceP2P.setOnline(true);
      expect(aliceP2P.isOnline, isTrue);
    });
  });
}
