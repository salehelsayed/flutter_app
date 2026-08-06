import 'dart:async';

import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/fake_p2p_network.dart';
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

    test(
      'same-WiFi local attempt settles via authenticated direct proof',
      () async {
        final aliceP2P = alice.p2pService;
        aliceP2P.localPeers.add(bob.peerId);

        final bobReceived = Completer<void>();
        bob.chatListener.incomingMessageStream.listen((_) {
          if (!bobReceived.isCompleted) bobReceived.complete();
        });

        final (result, msg) = await alice.sendMessage(bob.peerId, 'Hello WiFi');

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(msg!.transport, 'direct');
        expect(aliceP2P.localSendCallCount, 1);
        expect(
          network.deliverCallCount,
          2,
          reason: 'local WebSocket and authenticated direct must both write',
        );

        // Bob receives one logical row despite both transport writes.
        await bobReceived.future.timeout(const Duration(seconds: 2));
        final bobMessages = await bob.loadConversationWith(alice.peerId);
        expect(
          bobMessages,
          hasLength(1),
          reason: 'receiver message-ID dedup must collapse both copies',
        );
        expect(bobMessages.first.text, 'Hello WiFi');

        // No duplicates on Alice's side
        expect(alice.messageRepo.count, 1);
      },
    );

    test(
      'WiFi disappears mid-session after authenticated direct settled first',
      () async {
        final aliceP2P = alice.p2pService;

        // First message: local write plus authenticated direct proof.
        aliceP2P.localPeers.add(bob.peerId);

        final bobReceived1 = Completer<void>();
        final sub1 = bob.chatListener.incomingMessageStream.listen((_) {
          if (!bobReceived1.isCompleted) bobReceived1.complete();
        });

        final (result1, msg1) = await alice.sendMessage(
          bob.peerId,
          'WiFi message',
        );

        expect(result1, SendChatMessageResult.success);
        expect(msg1, isNotNull);
        expect(msg1!.transport, 'direct');
        expect(aliceP2P.localSendCallCount, 1);
        expect(network.deliverCallCount, 2);

        await bobReceived1.future.timeout(const Duration(seconds: 2));
        await sub1.cancel();

        // Second message: remove WiFi; only authenticated libp2p writes.
        aliceP2P.localPeers.remove(bob.peerId);

        final bobReceived2 = Completer<void>();
        bob.chatListener.incomingMessageStream.listen((_) {
          if (!bobReceived2.isCompleted) bobReceived2.complete();
        });

        final (result2, msg2) = await alice.sendMessage(
          bob.peerId,
          'Relay message',
        );

        expect(result2, SendChatMessageResult.success);
        expect(msg2, isNotNull);
        expect(msg2!.transport, 'direct');
        expect(aliceP2P.localSendCallCount, 1);
        expect(network.deliverCallCount, 3);

        await bobReceived2.future.timeout(const Duration(seconds: 2));

        // Three transport writes produced two logical receiver rows.
        final bobMessages = await bob.loadConversationWith(alice.peerId);
        expect(
          bobMessages,
          hasLength(2),
          reason: 'receiver message-ID dedup must collapse the first dual send',
        );
        expect(bobMessages[0].text, 'WiFi message');
        expect(bobMessages[1].text, 'Relay message');

        // Alice has exactly 2 messages
        final aliceMessages = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(aliceMessages, hasLength(2));
      },
    );

    test(
      'WiFi send fails (localSendResult=false), authenticated direct settles',
      () async {
        final aliceP2P = alice.p2pService;
        aliceP2P.localPeers.add(bob.peerId);
        aliceP2P.localSendResult = false;

        final bobReceived = Completer<void>();
        bob.chatListener.incomingMessageStream.listen((_) {
          if (!bobReceived.isCompleted) bobReceived.complete();
        });

        final (result, msg) = await alice.sendMessage(
          bob.peerId,
          'Fallback to relay',
        );

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(msg!.transport, 'direct');
        expect(aliceP2P.localSendCallCount, 1);

        // Bob received via relay
        await bobReceived.future.timeout(const Duration(seconds: 2));
        final bobMessages = await bob.loadConversationWith(alice.peerId);
        expect(bobMessages, hasLength(1));
        expect(bobMessages.first.text, 'Fallback to relay');

        // No duplicates
        expect(alice.messageRepo.count, 1);
      },
    );

    test(
      'WiFi timeout falls through to direct without duplicate delivery',
      () async {
        final aliceP2P = alice.p2pService;
        aliceP2P.localPeers.add(bob.peerId);
        aliceP2P.localAckDelay =
            interactiveLocalBudget + const Duration(milliseconds: 200);

        final bobReceived = Completer<void>();
        bob.chatListener.incomingMessageStream.listen((_) {
          if (!bobReceived.isCompleted) bobReceived.complete();
        });

        final (result, msg) = await alice.sendMessage(
          bob.peerId,
          'WiFi timeout to direct',
        );

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(msg!.transport, 'direct');
        expect(aliceP2P.localSendCallCount, 1);
        expect(
          aliceP2P.lastLocalTimeoutMs,
          interactiveLocalBudget.inMilliseconds,
        );
        expect(network.storeInInboxCallCount, 0);

        await bobReceived.future.timeout(const Duration(seconds: 2));
        await Future.delayed(
          interactiveLocalBudget + const Duration(milliseconds: 250),
        );

        final bobMessages = await bob.loadConversationWith(alice.peerId);
        expect(bobMessages, hasLength(1));
        expect(bobMessages.first.text, 'WiFi timeout to direct');

        final aliceMessages = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(aliceMessages, hasLength(1));
      },
    );

    test(
      'WiFi timeout with no direct success falls back to inbox once',
      () async {
        final aliceP2P = alice.p2pService;
        aliceP2P.localPeers.add(bob.peerId);
        aliceP2P.localAckDelay =
            interactiveLocalBudget + const Duration(milliseconds: 200);
        aliceP2P.sendFailCount = 1;

        final bobReceived = Completer<void>();
        bob.chatListener.incomingMessageStream.listen((_) {
          if (!bobReceived.isCompleted) bobReceived.complete();
        });

        final (result, msg) = await alice.sendMessage(
          bob.peerId,
          'WiFi timeout to inbox',
        );

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(msg!.transport, 'inbox');
        expect(aliceP2P.localSendCallCount, 1);
        expect(network.storeInInboxCallCount, 1);
        expect(network.inboxCount(bob.peerId), 1);

        final drained = await (bob.p2pService).drainOfflineInboxCount();
        expect(drained, 1);
        await bobReceived.future.timeout(const Duration(seconds: 2));
        await Future.delayed(
          interactiveLocalBudget + const Duration(milliseconds: 250),
        );

        final bobMessages = await bob.loadConversationWith(alice.peerId);
        expect(bobMessages, hasLength(1));
        expect(bobMessages.first.text, 'WiFi timeout to inbox');

        final aliceMessages = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(aliceMessages, hasLength(1));
      },
    );

    test('authenticated transport owns WiFi visibility transitions', () async {
      final aliceP2P = alice.p2pService;

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

      // Local visibility changes which WebSocket attempts run, but only the
      // authenticated libp2p proof owns the persisted transport.
      final transports = [m1!.transport, m2!.transport, m3!.transport];
      expect(transports, ['direct', 'direct', 'direct']);
      expect(aliceP2P.localSendCallCount, 2);
      expect(
        network.deliverCallCount,
        5,
        reason:
            'sends one and three each include local plus authenticated '
            'writes; send two includes only authenticated libp2p',
      );

      // Five transport writes produced three logical receiver rows.
      final bobMessages = await bob.loadConversationWith(alice.peerId);
      expect(
        bobMessages,
        hasLength(3),
        reason: 'receiver message-ID dedup must collapse both dual sends',
      );

      // Alice has exactly 3 messages
      final aliceMessages = await alice.messageRepo.getMessagesForContact(
        bob.peerId,
      );
      expect(aliceMessages, hasLength(3));
    });
  });
}
