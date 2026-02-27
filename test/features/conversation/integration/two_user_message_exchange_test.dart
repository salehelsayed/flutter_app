/// Integration test: Two users exchange messages with each other.
///
/// Simulates a full bidirectional message exchange:
///   Alice sends "Hello Bob!" -> P2P network -> Bob receives & persists
///   Bob sends "Hi Alice!" -> P2P network -> Alice receives & persists
///   Both users load their conversations and verify all messages are present.
///
/// This test wires up the full stack per user:
///   FakeP2PService -> ChatMessageListener -> MessageRepository -> use cases
///
/// The two FakeP2PService instances are connected via a FakeP2PNetwork
/// that routes messages between them (simulating the real relay).

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

// ─── Tests ──────────────────────────────────────────────────────────
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

    // Both users add each other as contacts (simulating QR exchange)
    alice.addContact(bob);
    bob.addContact(alice);

    // Start listeners
    alice.start();
    bob.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  group('Two-user message exchange', () {
    test('Alice sends a message and Bob receives it', () async {
      // Subscribe to Bob's incoming stream before sending
      final bobReceived = bob.chatListener.incomingMessageStream.first;

      // Alice sends
      final (result, sentMsg) = await alice.sendMessage(
        bob.peerId,
        'Hello Bob!',
      );

      expect(result, SendChatMessageResult.success);
      expect(sentMsg, isNotNull);
      expect(sentMsg!.text, 'Hello Bob!');
      expect(sentMsg.isIncoming, false);
      expect(sentMsg.status, 'delivered');

      // Wait for Bob's listener to process
      final received = await bobReceived.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('Bob never received the message'),
      );

      expect(received.text, 'Hello Bob!');
      expect(received.isIncoming, true);
      expect(received.senderPeerId, alice.peerId);
      expect(received.contactPeerId, alice.peerId);
      expect(received.status, 'delivered');
    });

    test('Bob replies and Alice receives it', () async {
      final aliceReceived = alice.chatListener.incomingMessageStream.first;

      final (result, sentMsg) = await bob.sendMessage(
        alice.peerId,
        'Hi Alice!',
      );

      expect(result, SendChatMessageResult.success);
      expect(sentMsg, isNotNull);
      expect(sentMsg!.text, 'Hi Alice!');

      final received = await aliceReceived.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('Alice never received the message'),
      );

      expect(received.text, 'Hi Alice!');
      expect(received.isIncoming, true);
      expect(received.senderPeerId, bob.peerId);
    });

    test('Full conversation: both users see all messages in order', () async {
      // Set up stream listeners before sending
      final bobMessages = <ConversationMessage>[];
      final aliceMessages = <ConversationMessage>[];

      final bobSub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobMessages.add(msg),
      );
      final aliceSub = alice.chatListener.incomingMessageStream.listen(
        (msg) => aliceMessages.add(msg),
      );

      // Alice -> Bob: message 1
      final (r1, _) = await alice.sendMessage(
        bob.peerId,
        'Hey Bob, how are you?',
      );
      expect(r1, SendChatMessageResult.success);

      // Wait for delivery
      await Future.delayed(const Duration(milliseconds: 50));

      // Bob -> Alice: message 2
      final (r2, _) = await bob.sendMessage(
        alice.peerId,
        'Great, thanks! You?',
      );
      expect(r2, SendChatMessageResult.success);

      await Future.delayed(const Duration(milliseconds: 50));

      // Alice -> Bob: message 3
      final (r3, _) = await alice.sendMessage(bob.peerId, 'Doing well!');
      expect(r3, SendChatMessageResult.success);

      await Future.delayed(const Duration(milliseconds: 50));

      // Verify Bob received 2 messages from Alice
      expect(bobMessages.length, 2);
      expect(bobMessages[0].text, 'Hey Bob, how are you?');
      expect(bobMessages[1].text, 'Doing well!');

      // Verify Alice received 1 message from Bob
      expect(aliceMessages.length, 1);
      expect(aliceMessages[0].text, 'Great, thanks! You?');

      // --- Load full conversations from DB ---

      // Alice's conversation with Bob: should have 3 messages
      // (2 sent by Alice + 1 received from Bob)
      final aliceConvo = await alice.messageRepo.getMessagesForContact(
        bob.peerId,
      );
      expect(aliceConvo.length, 3);
      expect(aliceConvo[0].text, 'Hey Bob, how are you?');
      expect(aliceConvo[0].isIncoming, false);
      expect(aliceConvo[1].text, 'Great, thanks! You?');
      expect(aliceConvo[1].isIncoming, true);
      expect(aliceConvo[2].text, 'Doing well!');
      expect(aliceConvo[2].isIncoming, false);

      // Bob's conversation with Alice: should have 3 messages
      // (2 received from Alice + 1 sent by Bob)
      final bobConvo = await bob.messageRepo.getMessagesForContact(
        alice.peerId,
      );
      expect(bobConvo.length, 3);
      expect(bobConvo[0].text, 'Hey Bob, how are you?');
      expect(bobConvo[0].isIncoming, true);
      expect(bobConvo[1].text, 'Great, thanks! You?');
      expect(bobConvo[1].isIncoming, false);
      expect(bobConvo[2].text, 'Doing well!');
      expect(bobConvo[2].isIncoming, true);

      await bobSub.cancel();
      await aliceSub.cancel();
    });

    test('Messages from unknown senders are rejected', () async {
      // Create a stranger who is NOT in Bob's contacts
      final stranger = TestUser.create(
        peerId: '12D3KooWStranger00000000000003',
        username: 'Stranger',
        network: network,
      );
      // Stranger has Bob as contact (so V2 encryption works),
      // but Bob does NOT have stranger (so incoming message is rejected)
      stranger.addContact(bob);
      stranger.start();

      // Stranger sends to Bob
      final (result, _) = await stranger.sendMessage(
        bob.peerId,
        'Hey Bob, add me!',
      );
      expect(result, SendChatMessageResult.success);

      // Give listener time to process
      await Future.delayed(const Duration(milliseconds: 100));

      // Bob should have NO messages stored (stranger is not a contact)
      expect(bob.messageRepo.count, 0);

      stranger.dispose();
    });

    test('Duplicate messages are rejected', () async {
      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      // Alice sends a message
      await alice.sendMessage(bob.peerId, 'Hello!');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bobReceived.length, 1);

      // Simulate the same message arriving again (network retry)
      // We need to get the message ID from Bob's stored messages
      final bobMessages = await bob.messageRepo.getMessagesForContact(
        alice.peerId,
      );
      expect(bobMessages.length, 1);
      final originalId = bobMessages.first.id;

      // Inject duplicate via raw P2P (same envelope, same ID)
      final duplicateJson = jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {
          'id': originalId,
          'text': 'Hello!',
          'senderPeerId': alice.peerId,
          'senderUsername': 'Alice',
          'timestamp': '2026-02-09T15:30:00.000Z',
        },
      });

      bob.p2pService.injectIncomingMessage(
        ChatMessage(
          from: alice.peerId,
          to: bob.peerId,
          content: duplicateJson,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Still only 1 message in Bob's DB (duplicate was rejected)
      final afterDupe = await bob.messageRepo.getMessagesForContact(
        alice.peerId,
      );
      expect(afterDupe.length, 1);

      // Listener should have only fired once
      expect(bobReceived.length, 1);

      await sub.cancel();
    });

    test('Contact name propagates when sender changes username', () async {
      // Bob's contact for Alice currently has username "Alice"
      final aliceContactBefore = await bob.contactRepo.getContact(alice.peerId);
      expect(aliceContactBefore!.username, 'Alice');

      // Subscribe to Bob's contactUpdatedStream
      final contactUpdates = <ContactModel>[];
      final contactSub = bob.chatListener.contactUpdatedStream.listen(
        (c) => contactUpdates.add(c),
      );

      // Alice "changes her name" — simulate by sending a message
      // with a different senderUsername. We inject a raw P2P message
      // since TestUser.sendMessage uses the original username.
      final renamedJson = jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {
          'id': 'msg-rename-001',
          'text': 'Hey, I changed my name!',
          'senderPeerId': alice.peerId,
          'senderUsername': 'Alice Renamed',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      });

      bob.p2pService.injectIncomingMessage(
        ChatMessage(
          from: alice.peerId,
          to: bob.peerId,
          content: renamedJson,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Bob's stored contact should now have the updated name
      final aliceContactAfter = await bob.contactRepo.getContact(alice.peerId);
      expect(aliceContactAfter!.username, 'Alice Renamed');

      // contactUpdatedStream should have emitted
      expect(contactUpdates.length, 1);
      expect(contactUpdates.first.username, 'Alice Renamed');
      expect(contactUpdates.first.peerId, alice.peerId);

      await contactSub.cancel();
    });

    test(
      'Messages to offline peer are marked delivered on inbox store',
      () async {
        final offlineUser = TestUser.create(
          peerId: '12D3KooWOfflineUser0000000004',
          username: 'Offline',
          network: network,
        );
        alice.addContact(offlineUser);
        offlineUser.addContact(alice);
        offlineUser.start();
        offlineUser.setOnline(false);

        final offlineReceived =
            offlineUser.chatListener.incomingMessageStream.first;

        final (result, msg) = await alice.sendMessage(
          offlineUser.peerId,
          'Are you there?',
        );

        // Network can't find the peer, so send falls back to inbox storage.
        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        expect(msg!.status, 'delivered');

        // Sender persists delivered status when inbox accepts the message.
        final convo = await alice.messageRepo.getMessagesForContact(
          offlineUser.peerId,
        );
        expect(convo.length, 1);
        expect(convo.first.status, 'delivered');

        // Peer comes back online and drains inbox.
        offlineUser.setOnline(true);
        final drained = await offlineUser.drainOfflineInbox();
        expect(drained, 1);

        final delivered = await offlineReceived.timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              throw StateError('Offline peer never received inbox message'),
        );
        expect(delivered.text, 'Are you there?');
        expect(delivered.isIncoming, true);
        expect(delivered.senderPeerId, alice.peerId);

        await Future.delayed(const Duration(milliseconds: 100));
        final updatedConvo = await alice.messageRepo.getMessagesForContact(
          offlineUser.peerId,
        );
        expect(updatedConvo.length, 1);
        expect(updatedConvo.first.status, 'delivered');

        offlineUser.dispose();
      },
    );
  });
}
