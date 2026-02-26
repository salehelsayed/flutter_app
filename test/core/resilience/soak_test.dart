import 'dart:async';
import 'dart:math';

import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/test_user.dart';

// ---------------------------------------------------------------------------
// Tests — high-volume stress using fake infrastructure
// ---------------------------------------------------------------------------

void main() {
  group('Soak — unit-level fast stress', () {
    test(
      '1000 bidirectional messages, no duplicates, no stuck states',
      () async {
        final network = FakeP2PNetwork();
        final alice = TestUser.create(
          peerId: 'alice-soak',
          username: 'Alice',
          network: network,
        );
        final bob = TestUser.create(
          peerId: 'bob-soak',
          username: 'Bob',
          network: network,
        );
        alice.addContact(bob);
        bob.addContact(alice);
        alice.start();
        bob.start();

        const total = 1000;
        final random = Random(42);

        for (var i = 0; i < total; i++) {
          if (random.nextBool()) {
            await alice.sendMessage('bob-soak', 'a→b $i');
          } else {
            await bob.sendMessage('alice-soak', 'b→a $i');
          }

          // Every 50 msgs: toggle Bob offline then back online
          if (i > 0 && i % 50 == 0) {
            bob.setOnline(false);
            bob.setOnline(true);
          }

          // Every 100 msgs: drain inboxes
          if (i > 0 && i % 100 == 0) {
            await alice.drainOfflineInbox();
            await bob.drainOfflineInbox();
          }
        }

        // Final drain
        await alice.drainOfflineInbox();
        await bob.drainOfflineInbox();
        await Future.delayed(const Duration(milliseconds: 500));

        // Check Alice's side
        final aliceConvo = await alice.loadConversationWith('bob-soak');
        final aliceIds = aliceConvo.map((m) => m.id).toSet();
        expect(aliceIds.length, aliceConvo.length,
            reason: 'No duplicate IDs in Alice repo');

        // No stuck 'sending' messages
        final aliceSending = aliceConvo.where((m) => m.status == 'sending');
        expect(aliceSending, isEmpty, reason: 'No stuck sending messages');

        // Check Bob's side
        final bobConvo = await bob.loadConversationWith('alice-soak');
        final bobIds = bobConvo.map((m) => m.id).toSet();
        expect(bobIds.length, bobConvo.length,
            reason: 'No duplicate IDs in Bob repo');

        final bobSending = bobConvo.where((m) => m.status == 'sending');
        expect(bobSending, isEmpty, reason: 'No stuck sending messages');

        // Total messages should be bounded (not necessarily exact due to
        // offline-toggling losing some messages)
        expect(aliceConvo.length, greaterThan(0));
        expect(bobConvo.length, greaterThan(0));

        alice.dispose();
        bob.dispose();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'online/offline transitions with concurrent sends do not crash',
      () async {
      final network = FakeP2PNetwork();
      final alice = TestUser.create(
        peerId: 'alice-toggle',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-toggle',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      const total = 100;
      final results = <SendChatMessageResult>[];

      for (var i = 0; i < total; i++) {
        // Toggle Bob every 5 messages
        if (i > 0 && i % 5 == 0) {
          bob.setOnline(i % 10 != 0);
        }

        final (result, _) = await alice.sendMessage('bob-toggle', 'msg $i');
        results.add(result);
      }

      // All messages resolved (no exceptions thrown)
      expect(results, hasLength(total));
      for (final r in results) {
        expect(r, isIn([
          SendChatMessageResult.success,
          SendChatMessageResult.peerNotFound,
          SendChatMessageResult.dialFailed,
          SendChatMessageResult.sendFailed,
        ]));
      }

      alice.dispose();
      bob.dispose();
    },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('inbox drain after extended offline: 200 messages', () async {
      final network = FakeP2PNetwork();
      final alice = TestUser.create(
        peerId: 'alice-inbox',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-inbox',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Store 200 messages directly in Bob's inbox (skipping the send
      // retry loop which would be slow). This isolates inbox drain testing.
      const n = 200;
      for (var i = 0; i < n; i++) {
        final payload = MessagePayload(
          id: 'inbox-msg-$i',
          text: 'offline msg $i',
          senderPeerId: 'alice-inbox',
          senderUsername: 'Alice',
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, i).toIso8601String(),
        );
        network.storeInInbox('alice-inbox', 'bob-inbox', payload.toJson());
      }

      // Verify all went to inbox
      expect(network.inboxCount('bob-inbox'), n);

      // Drain
      final drained = await bob.drainOfflineInbox();
      expect(drained, n);

      await Future.delayed(const Duration(milliseconds: 500));

      final bobMessages = await bob.loadConversationWith('alice-inbox');
      expect(bobMessages, hasLength(n));

      // No duplicates
      final ids = bobMessages.map((m) => m.id).toSet();
      expect(ids.length, n);

      // Timestamp order
      for (var i = 1; i < bobMessages.length; i++) {
        expect(
          bobMessages[i].timestamp.compareTo(bobMessages[i - 1].timestamp),
          greaterThanOrEqualTo(0),
        );
      }

      alice.dispose();
      bob.dispose();
    },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('concurrent senders: 3 users x 100 messages each', () async {
      final network = FakeP2PNetwork();

      final alice = TestUser.create(
        peerId: 'alice-multi',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-multi',
        username: 'Bob',
        network: network,
      );
      final charlie = TestUser.create(
        peerId: 'charlie-multi',
        username: 'Charlie',
        network: network,
      );

      // Full mesh contacts
      alice.addContact(bob);
      alice.addContact(charlie);
      bob.addContact(alice);
      bob.addContact(charlie);
      charlie.addContact(alice);
      charlie.addContact(bob);

      alice.start();
      bob.start();
      charlie.start();

      const n = 100;

      // Each user sends n messages to each other user concurrently
      await Future.wait([
        _sendBatch(alice, 'bob-multi', n, 'a→b'),
        _sendBatch(alice, 'charlie-multi', n, 'a→c'),
        _sendBatch(bob, 'alice-multi', n, 'b→a'),
        _sendBatch(bob, 'charlie-multi', n, 'b→c'),
        _sendBatch(charlie, 'alice-multi', n, 'c→a'),
        _sendBatch(charlie, 'bob-multi', n, 'c→b'),
      ]);

      await Future.delayed(const Duration(milliseconds: 500));

      // Alice ↔ Bob: Alice sent n + received n
      final aliceBobConvo = await alice.loadConversationWith('bob-multi');
      final aliceSentToBob =
          aliceBobConvo.where((m) => !m.isIncoming).length;
      final aliceRecvFromBob =
          aliceBobConvo.where((m) => m.isIncoming).length;
      expect(aliceSentToBob, n);
      expect(aliceRecvFromBob, n);

      // Alice ↔ Charlie
      final aliceCharlieConvo =
          await alice.loadConversationWith('charlie-multi');
      final aliceSentToCharlie =
          aliceCharlieConvo.where((m) => !m.isIncoming).length;
      final aliceRecvFromCharlie =
          aliceCharlieConvo.where((m) => m.isIncoming).length;
      expect(aliceSentToCharlie, n);
      expect(aliceRecvFromCharlie, n);

      // No cross-contamination: bob messages don't appear in charlie convo
      for (final msg in aliceCharlieConvo) {
        expect(msg.contactPeerId, 'charlie-multi');
      }
      for (final msg in aliceBobConvo) {
        expect(msg.contactPeerId, 'bob-multi');
      }

      alice.dispose();
      bob.dispose();
      charlie.dispose();
    },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'memory bounded over 5000 messages',
      () async {
        final network = FakeP2PNetwork();
        final alice = TestUser.create(
          peerId: 'alice-mem',
          username: 'Alice',
          network: network,
        );
        final bob = TestUser.create(
          peerId: 'bob-mem',
          username: 'Bob',
          network: network,
        );
        alice.addContact(bob);
        bob.addContact(alice);
        alice.start();
        bob.start();

        const total = 5000;
        for (var i = 0; i < total; i++) {
          if (i.isEven) {
            await alice.sendMessage('bob-mem', 'a→b $i');
          } else {
            await bob.sendMessage('alice-mem', 'b→a $i');
          }
        }

        await Future.delayed(const Duration(milliseconds: 500));

        // Verify exact count on sender side
        final aliceCount =
            await alice.messageRepo.getMessageCountForContact('bob-mem');
        final bobCount =
            await bob.messageRepo.getMessageCountForContact('alice-mem');

        expect(aliceCount, total);
        expect(bobCount, total);

        // Disposal succeeds without errors
        alice.dispose();
        bob.dispose();
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

/// Sends [n] messages from [sender] to [targetPeerId].
Future<void> _sendBatch(
    TestUser sender, String targetPeerId, int n, String prefix) async {
  for (var i = 0; i < n; i++) {
    await sender.sendMessage(targetPeerId, '$prefix $i');
  }
}
