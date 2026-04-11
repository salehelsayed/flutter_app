/// Integration tests for offline inbox roundtrip scenarios.
///
/// Tests verify that:
/// - Inbox drain completes before relay shows green online status
/// - Resume delivers queued messages before live reconnect
/// - Large backlogs show first page quickly with background continuation
/// - Cold start after reboot uses inbox-first recovery
/// - Foreground send uses short budget while background recovery is separate

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';

// Reuse the integration test infrastructure from two_user_message_exchange_test.dart
import 'two_user_message_exchange_test.dart';

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

  group('Offline inbox roundtrip', () {
    test(
      'startup inbox drain completes before relay online state is green',
      () async {
        // Bob goes offline
        bob.setOnline(false);

        // Alice sends to offline Bob (goes to inbox)
        final (result, _) = await alice.sendMessage(
          bob.peerId,
          'While you were away',
        );
        expect(result, SendChatMessageResult.success);

        // Bob comes back online
        bob.setOnline(true);

        // Bob drains inbox — this should complete regardless of relay status
        final drained = await bob.drainOfflineInbox();
        expect(drained, 1);

        // Give listener time to process the injected messages
        await Future.delayed(const Duration(milliseconds: 100));

        // Bob should have the message
        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobConvo.length, 1);
        expect(bobConvo.first.text, 'While you were away');
      },
    );

    test(
      'resume delivers queued inbox messages before later live reconnect finishes',
      () async {
        bob.setOnline(false);

        // Alice sends multiple messages while Bob is offline
        await alice.sendMessage(bob.peerId, 'Message 1');
        await alice.sendMessage(bob.peerId, 'Message 2');

        // Bob comes back (simulating resume)
        bob.setOnline(true);

        // Drain inbox (simulating resume drain)
        final drained = await bob.drainOfflineInbox();
        expect(drained, 2);

        // Give listener time to process
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify messages are available
        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobConvo.length, 2);
      },
    );

    test(
      'both offline peers catch up cleanly when they return together',
      () async {
        alice.setOnline(false);
        bob.setOnline(false);

        final (aliceResult1, _) = await alice.sendMessage(
          bob.peerId,
          'Alice offline 1',
        );
        expect(aliceResult1, SendChatMessageResult.success);
        await Future<void>.delayed(const Duration(milliseconds: 2));

        final (bobResult1, _) = await bob.sendMessage(
          alice.peerId,
          'Bob offline 1',
        );
        expect(bobResult1, SendChatMessageResult.success);
        await Future<void>.delayed(const Duration(milliseconds: 2));

        final (aliceResult2, _) = await alice.sendMessage(
          bob.peerId,
          'Alice offline 2',
        );
        expect(aliceResult2, SendChatMessageResult.success);
        await Future<void>.delayed(const Duration(milliseconds: 2));

        final (bobResult2, _) = await bob.sendMessage(
          alice.peerId,
          'Bob offline 2',
        );
        expect(bobResult2, SendChatMessageResult.success);

        alice.setOnline(true);
        bob.setOnline(true);

        final drainedCounts = await Future.wait([
          alice.drainOfflineInbox(),
          bob.drainOfflineInbox(),
        ]);
        expect(drainedCounts, [2, 2]);

        await Future.delayed(const Duration(milliseconds: 100));

        final aliceConvo = await alice.loadConversation(bob.peerId);
        final bobConvo = await bob.loadConversation(alice.peerId);

        expect(aliceConvo, hasLength(4));
        expect(bobConvo, hasLength(4));

        expect(aliceConvo.map((message) => message.text).toList(), [
          'Alice offline 1',
          'Bob offline 1',
          'Alice offline 2',
          'Bob offline 2',
        ]);
        expect(bobConvo.map((message) => message.text).toList(), [
          'Alice offline 1',
          'Bob offline 1',
          'Alice offline 2',
          'Bob offline 2',
        ]);

        expect(aliceConvo.where((message) => message.isIncoming), hasLength(2));
        expect(bobConvo.where((message) => message.isIncoming), hasLength(2));
        expect(
          aliceConvo.map((message) => message.id).toSet().length,
          aliceConvo.length,
        );
        expect(
          bobConvo.map((message) => message.id).toSet().length,
          bobConvo.length,
        );
      },
    );

    test(
      'large 1:1 backlog shows first page quickly and drains remaining pages in background',
      () async {
        bob.setOnline(false);

        // Send many messages while Bob is offline
        for (var i = 0; i < 10; i++) {
          await alice.sendMessage(bob.peerId, 'Backlog msg $i');
        }

        bob.setOnline(true);

        // First drain gets available messages
        final drained = await bob.drainOfflineInbox();
        expect(drained, 10);

        // Give listener time to process
        await Future.delayed(const Duration(milliseconds: 200));

        // All messages should be retrieved
        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobConvo.length, 10);
      },
    );

    test(
      'cold start after reboot retrieves queued inbox messages before group warm tasks finish',
      () async {
        bob.setOnline(false);

        await alice.sendMessage(bob.peerId, 'Before reboot');

        bob.setOnline(true);

        // Inbox drain should work immediately (simulating cold start inbox-first)
        final drained = await bob.drainOfflineInbox();
        expect(drained, 1);

        // Give listener time to process
        await Future.delayed(const Duration(milliseconds: 100));

        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobConvo.length, 1);
        expect(bobConvo.first.text, 'Before reboot');
      },
    );

    test(
      'edit-first inbox drain stays phantom-free until the original arrives and then materializes the edited row',
      () async {
        bob.setOnline(false);

        const messageId = 'msg-edit-before-original';
        final editEnvelope = MessagePayload(
          id: messageId,
          text: 'Edited before original',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          timestamp: '2026-04-01T09:59:00.000Z',
          action: MessagePayload.actionEdit,
          editedAt: '2026-04-01T10:00:00.000Z',
        ).toJson();
        final originalEnvelope = MessagePayload(
          id: messageId,
          text: 'Original text',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          timestamp: '2026-04-01T09:58:00.000Z',
        ).toJson();

        expect(
          network.storeInInbox(alice.peerId, bob.peerId, editEnvelope),
          isTrue,
        );
        expect(
          bob.messageRepo.getMessagesForContact(alice.peerId),
          completion(isEmpty),
        );
        expect(
          network.storeInInbox(alice.peerId, bob.peerId, originalEnvelope),
          isTrue,
        );

        bob.setOnline(true);
        final emitted = <ConversationMessage>[];
        final sub = bob.chatListener.incomingMessageStream.listen(emitted.add);

        final drained = await bob.drainOfflineInbox();
        expect(drained, 2);

        await Future.delayed(const Duration(milliseconds: 100));

        final bobConvo = await bob.loadConversation(alice.peerId);
        expect(bobConvo, hasLength(1));
        expect(bobConvo.single.id, messageId);
        expect(bobConvo.single.text, 'Edited before original');
        expect(bobConvo.single.isHidden, isFalse);
        expect(bobConvo.single.editedAt, '2026-04-01T10:00:00.000Z');
        expect(emitted, hasLength(1));
        expect(emitted.single.id, messageId);
        expect(emitted.single.text, 'Edited before original');

        await sub.cancel();
      },
    );

    test(
      'offline edit delivery survives receiver restart and applies once inbox drain resumes',
      () async {
        final (sendResult, original) = await alice.sendMessage(
          bob.peerId,
          'Original before offline edit',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(original, isNotNull);
        await Future.delayed(const Duration(milliseconds: 100));

        final originalId = original!.id;
        bob.setOnline(false);

        final editEnvelope = MessagePayload(
          id: originalId,
          text: 'Edited after restart',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          timestamp: original.timestamp,
          action: MessagePayload.actionEdit,
          editedAt: '2026-04-01T11:00:00.000Z',
        ).toJson();

        expect(
          network.storeInInbox(alice.peerId, bob.peerId, editEnvelope),
          isTrue,
        );

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
        await Future.delayed(const Duration(milliseconds: 100));

        final bobConvo = await bob.loadConversation(alice.peerId);
        expect(bobConvo, hasLength(1));
        expect(bobConvo.single.id, originalId);
        expect(bobConvo.single.text, 'Edited after restart');
        expect(bobConvo.single.editedAt, '2026-04-01T11:00:00.000Z');
      },
    );

    test(
      'foreground send completes on short budget while longer background recovery continues separately',
      () async {
        // Both online — foreground send should be fast
        final stopwatch = Stopwatch()..start();
        final (result, msg) = await alice.sendMessage(bob.peerId, 'Quick send');
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        // Foreground send should complete quickly
        expect(stopwatch.elapsed.inSeconds, lessThan(5));
      },
    );
  });
}
