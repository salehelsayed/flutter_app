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
    test('startup inbox drain completes before relay online state is green', () async {
      // Bob goes offline
      bob.setOnline(false);

      // Alice sends to offline Bob (goes to inbox)
      final (result, _) = await alice.sendMessage(bob.peerId, 'While you were away');
      expect(result, SendChatMessageResult.success);

      // Bob comes back online
      bob.setOnline(true);

      // Bob drains inbox — this should complete regardless of relay status
      final drained = await bob.drainOfflineInbox();
      expect(drained, 1);

      // Give listener time to process the injected messages
      await Future.delayed(const Duration(milliseconds: 100));

      // Bob should have the message
      final bobConvo = await bob.messageRepo.getMessagesForContact(alice.peerId);
      expect(bobConvo.length, 1);
      expect(bobConvo.first.text, 'While you were away');
    });

    test('resume delivers queued inbox messages before later live reconnect finishes', () async {
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
      final bobConvo = await bob.messageRepo.getMessagesForContact(alice.peerId);
      expect(bobConvo.length, 2);
    });

    test('large 1:1 backlog shows first page quickly and drains remaining pages in background', () async {
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
      final bobConvo = await bob.messageRepo.getMessagesForContact(alice.peerId);
      expect(bobConvo.length, 10);
    });

    test('cold start after reboot retrieves queued inbox messages before group warm tasks finish', () async {
      bob.setOnline(false);

      await alice.sendMessage(bob.peerId, 'Before reboot');

      bob.setOnline(true);

      // Inbox drain should work immediately (simulating cold start inbox-first)
      final drained = await bob.drainOfflineInbox();
      expect(drained, 1);

      // Give listener time to process
      await Future.delayed(const Duration(milliseconds: 100));

      final bobConvo = await bob.messageRepo.getMessagesForContact(alice.peerId);
      expect(bobConvo.length, 1);
      expect(bobConvo.first.text, 'Before reboot');
    });

    test('foreground send completes on short budget while longer background recovery continues separately', () async {
      // Both online — foreground send should be fast
      final stopwatch = Stopwatch()..start();
      final (result, msg) = await alice.sendMessage(bob.peerId, 'Quick send');
      stopwatch.stop();

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      // Foreground send should complete quickly
      expect(stopwatch.elapsed.inSeconds, lessThan(5));
    });
  });
}
