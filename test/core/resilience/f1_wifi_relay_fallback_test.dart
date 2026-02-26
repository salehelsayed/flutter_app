import 'dart:async';

import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/test_user.dart';

void main() {
  group('F1 — WiFi to relay fallback', () {
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

    test('WiFi send succeeds with transport=wifi', () async {
      final aliceP2P = alice.p2pService as FakeP2PService;
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived = Completer<void>();
      bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived.isCompleted) bobReceived.complete();
      });

      final (result, msg) = await alice.sendMessage(bob.peerId, 'Hello WiFi');

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.transport, 'wifi');
      expect(aliceP2P.localSendCallCount, 1);

      // Bob received the message
      await bobReceived.future.timeout(const Duration(seconds: 2));
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(1));
      expect(bobMessages.first.text, 'Hello WiFi');

      // No duplicates on Alice's side
      expect(alice.messageRepo.count, 1);
    });

    test('WiFi disappears mid-session, next send falls through to relay',
        () async {
      final aliceP2P = alice.p2pService as FakeP2PService;

      // First message: WiFi path
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived1 = Completer<void>();
      final sub1 = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived1.isCompleted) bobReceived1.complete();
      });

      final (result1, msg1) =
          await alice.sendMessage(bob.peerId, 'WiFi message');

      expect(result1, SendChatMessageResult.success);
      expect(msg1, isNotNull);
      expect(msg1!.transport, 'wifi');

      await bobReceived1.future.timeout(const Duration(seconds: 2));
      await sub1.cancel();

      // Second message: remove WiFi, falls to relay
      aliceP2P.localPeers.remove(bob.peerId);

      final bobReceived2 = Completer<void>();
      bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived2.isCompleted) bobReceived2.complete();
      });

      final (result2, msg2) =
          await alice.sendMessage(bob.peerId, 'Relay message');

      expect(result2, SendChatMessageResult.success);
      expect(msg2, isNotNull);
      expect(msg2!.transport, 'relay');

      await bobReceived2.future.timeout(const Duration(seconds: 2));

      // Both messages delivered to Bob, no duplicates
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(2));
      expect(bobMessages[0].text, 'WiFi message');
      expect(bobMessages[1].text, 'Relay message');

      // Alice has exactly 2 messages
      final aliceMessages =
          await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceMessages, hasLength(2));
    });

    test('WiFi send fails (localSendResult=false), falls through to relay',
        () async {
      final aliceP2P = alice.p2pService as FakeP2PService;
      aliceP2P.localPeers.add(bob.peerId);
      aliceP2P.localSendResult = false;

      final bobReceived = Completer<void>();
      bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived.isCompleted) bobReceived.complete();
      });

      final (result, msg) =
          await alice.sendMessage(bob.peerId, 'Fallback to relay');

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.transport, 'relay');
      expect(aliceP2P.localSendCallCount, 1);

      // Bob received via relay
      await bobReceived.future.timeout(const Duration(seconds: 2));
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(1));
      expect(bobMessages.first.text, 'Fallback to relay');

      // No duplicates
      expect(alice.messageRepo.count, 1);
    });

    test('transport stable across WiFi/relay/WiFi transitions', () async {
      final aliceP2P = alice.p2pService as FakeP2PService;

      // Message 1: WiFi
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived1 = Completer<void>();
      var sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived1.isCompleted) bobReceived1.complete();
      });

      final (r1, m1) = await alice.sendMessage(bob.peerId, 'msg1-wifi');
      expect(r1, SendChatMessageResult.success);
      await bobReceived1.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // Message 2: relay (WiFi gone)
      aliceP2P.localPeers.remove(bob.peerId);

      final bobReceived2 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived2.isCompleted) bobReceived2.complete();
      });

      final (r2, m2) = await alice.sendMessage(bob.peerId, 'msg2-relay');
      expect(r2, SendChatMessageResult.success);
      await bobReceived2.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // Message 3: WiFi again
      aliceP2P.localPeers.add(bob.peerId);

      final bobReceived3 = Completer<void>();
      sub = bob.chatListener.incomingMessageStream.listen((_) {
        if (!bobReceived3.isCompleted) bobReceived3.complete();
      });

      final (r3, m3) = await alice.sendMessage(bob.peerId, 'msg3-wifi');
      expect(r3, SendChatMessageResult.success);
      await bobReceived3.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // Assert transport sequence
      final transports = [m1!.transport, m2!.transport, m3!.transport];
      expect(transports, ['wifi', 'relay', 'wifi']);

      // All 3 messages delivered to Bob
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(bobMessages, hasLength(3));

      // Alice has exactly 3 messages
      final aliceMessages =
          await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceMessages, hasLength(3));
    });
  });
}
