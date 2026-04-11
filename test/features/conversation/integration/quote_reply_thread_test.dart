/// Integration test: Quote-reply thread.
///
/// Verifies quotedMessageId propagation through send -> receive -> persist,
/// MessagePayload round-trip, and thread grouping.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;

  setUp(() {
    network = FakeP2PNetwork();

    alice = TestUser.create(
      peerId: '12D3KooWAlicePeerId00000000001',
      username: 'Alice',
      network: network,
    );
    bob = TestUser.create(
      peerId: '12D3KooWBobPeerIdxxx00000000002',
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

  group('Quote-reply thread', () {
    test(
      '5a. Alice sends, Bob quotes — reply arrives with quotedMessageId',
      () async {
        final bobReceived = <ConversationMessage>[];
        final bobSub = bob.chatListener.incomingMessageStream.listen(
          (msg) => bobReceived.add(msg),
        );

        // Alice sends original message
        final (r1, sentMsg) = await alice.sendMessage(bob.peerId, 'Hello Bob!');
        expect(r1, SendChatMessageResult.success);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bobReceived.length, 1);
        final aliceMessageId = bobReceived.first.id;

        // Bob quotes Alice's message
        final aliceReceived = <ConversationMessage>[];
        final aliceSub = alice.chatListener.incomingMessageStream.listen(
          (msg) => aliceReceived.add(msg),
        );

        final (r2, _) = await bob.sendQuoteReply(
          alice.peerId,
          'Great to hear from you!',
          aliceMessageId,
        );
        expect(r2, SendChatMessageResult.success);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(aliceReceived.length, 1);
        expect(aliceReceived.first.quotedMessageId, aliceMessageId);
        expect(aliceReceived.first.text, 'Great to hear from you!');

        // Bob's repo has correct quotedMessageId
        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        final bobQuoteMsg = bobConvo
            .where((m) => m.quotedMessageId != null)
            .first;
        expect(bobQuoteMsg.quotedMessageId, aliceMessageId);

        await bobSub.cancel();
        await aliceSub.cancel();
      },
    );

    test('5b. MessagePayload round-trip preserves quotedMessageId', () {
      final payload = MessagePayload(
        id: 'msg-001',
        text: 'Reply to you',
        senderPeerId: 'sender-1',
        senderUsername: 'Sender',
        timestamp: '2026-01-01T00:00:00Z',
        quotedMessageId: 'orig-uuid',
      );

      final json = payload.toJson();
      final parsed = MessagePayload.fromJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.quotedMessageId, 'orig-uuid');
      expect(parsed.id, 'msg-001');
      expect(parsed.text, 'Reply to you');
    });

    test('5c. Message without quote has null quotedMessageId', () async {
      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      await alice.sendMessage(bob.peerId, 'No quote here');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bobReceived.length, 1);
      expect(bobReceived.first.quotedMessageId, isNull);

      await sub.cancel();
    });

    test('5d. Quote chain: A -> B quotes A -> C quotes B', () async {
      // This uses Alice and Bob. Alice sends msg-A, Bob quotes to msg-B,
      // Alice quotes Bob's msg-B to msg-C.

      final bobReceived = <ConversationMessage>[];
      final bobSub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );
      final aliceReceived = <ConversationMessage>[];
      final aliceSub = alice.chatListener.incomingMessageStream.listen(
        (msg) => aliceReceived.add(msg),
      );

      // msg-A: Alice -> Bob (no quote)
      await alice.sendMessage(bob.peerId, 'Original message');
      await Future.delayed(const Duration(milliseconds: 50));
      final msgAId = bobReceived.last.id;

      // msg-B: Bob quotes msg-A -> Alice
      await bob.sendQuoteReply(alice.peerId, 'Replying to A', msgAId);
      await Future.delayed(const Duration(milliseconds: 50));
      final msgBId = aliceReceived.last.id;
      expect(aliceReceived.last.quotedMessageId, msgAId);

      // msg-C: Alice quotes msg-B -> Bob
      await alice.sendQuoteReply(bob.peerId, 'Replying to B', msgBId);
      await Future.delayed(const Duration(milliseconds: 50));
      final msgC = bobReceived.last;
      expect(msgC.quotedMessageId, msgBId);

      await bobSub.cancel();
      await aliceSub.cancel();
    });

    test('5e. groupMessagesIntoThreads preserves quotedMessageId', () {
      final now = DateTime.now().toUtc();
      final messages = [
        ConversationMessage(
          id: 'msg-1',
          contactPeerId: 'contact-1',
          senderPeerId: 'contact-1',
          text: 'First message',
          timestamp: now.subtract(const Duration(minutes: 2)).toIso8601String(),
          status: 'delivered',
          isIncoming: true,
          createdAt: now.toIso8601String(),
          quotedMessageId: null,
        ),
        ConversationMessage(
          id: 'msg-2',
          contactPeerId: 'contact-1',
          senderPeerId: 'own-peer',
          text: 'Quote reply',
          timestamp: now.subtract(const Duration(minutes: 1)).toIso8601String(),
          status: 'delivered',
          isIncoming: false,
          createdAt: now.toIso8601String(),
          quotedMessageId: 'msg-1',
        ),
      ];

      final threads = groupMessagesIntoThreads(
        allMessages: messages,
        contactUsernames: {'contact-1': 'Contact'},
      );

      expect(threads.length, 1);
      final thread = threads.first;
      expect(thread.messages.length, 2);
      expect(thread.messages[0].quotedMessageId, isNull);
      expect(thread.messages[1].quotedMessageId, 'msg-1');
    });

    test('5f. Quote references non-existent message ID (graceful)', () async {
      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      // Alice quotes a non-existent message
      final (result, _) = await alice.sendQuoteReply(
        bob.peerId,
        'Quoting ghost',
        'non-existent-uuid',
      );
      expect(result, SendChatMessageResult.success);
      await Future.delayed(const Duration(milliseconds: 50));

      // Message persists normally
      expect(bobReceived.length, 1);
      expect(bobReceived.first.quotedMessageId, 'non-existent-uuid');
      expect(bobReceived.first.text, 'Quoting ghost');

      await sub.cancel();
    });

    test(
      '5g. offline inbox quote reply preserves quotedMessageId after receiver restart',
      () async {
        final bobReceived = <ConversationMessage>[];
        final bobSub = bob.chatListener.incomingMessageStream.listen(
          bobReceived.add,
        );

        final (initialResult, _) = await alice.sendMessage(
          bob.peerId,
          'Original for offline quote',
        );
        expect(initialResult, SendChatMessageResult.success);
        await Future.delayed(const Duration(milliseconds: 50));

        final originalId = bobReceived.single.id;
        expect(originalId, isNotEmpty);

        bob.setOnline(false);

        final (offlineResult, _) = await alice.sendQuoteReply(
          bob.peerId,
          'Reply after restart',
          originalId,
        );
        expect(offlineResult, SendChatMessageResult.success);
        expect(network.inboxCount(bob.peerId), 1);

        await bobSub.cancel();

        final persistedBobRepo = bob.messageRepo;
        final persistedBobContacts = bob.contactRepo;
        bob.dispose();

        bob = TestUser.create(
          peerId: '12D3KooWBobPeerIdxxx00000000002',
          username: 'Bob',
          network: network,
          messageRepo: persistedBobRepo,
          contactRepo: persistedBobContacts,
        );
        bob.start();
        bob.setOnline(true);

        final drained = await bob.drainOfflineInbox();
        expect(drained, 1);
        await Future.delayed(const Duration(milliseconds: 50));

        final bobConvo = await bob.loadConversationWith(alice.peerId);
        expect(bobConvo, hasLength(2));

        final restoredReply = bobConvo.last;
        expect(restoredReply.text, 'Reply after restart');
        expect(restoredReply.quotedMessageId, originalId);
      },
    );
  });
}
