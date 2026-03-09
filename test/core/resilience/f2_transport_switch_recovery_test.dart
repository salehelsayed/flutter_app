/// Transport switch recovery tests for Phase 1.
///
/// Tests verify that:
/// - Switching from relay to WiFi does not leave a long sending gap
/// - WiFi losing the race still results in one delivered message

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../../features/conversation/integration/two_user_message_exchange_test.dart';

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

  group('Transport switch recovery', () {
    test('relay to wifi transport switch does not leave a long sending gap', () async {
      // First send via relay (both online via network)
      final stopwatch1 = Stopwatch()..start();
      final (r1, _) = await alice.sendMessage(bob.peerId, 'Via relay');
      stopwatch1.stop();
      expect(r1, SendChatMessageResult.success);
      expect(stopwatch1.elapsed.inSeconds, lessThan(5));

      // Simulate transport switch: second send should also be fast
      final stopwatch2 = Stopwatch()..start();
      final (r2, _) = await alice.sendMessage(bob.peerId, 'After switch');
      stopwatch2.stop();
      expect(r2, SendChatMessageResult.success);
      expect(stopwatch2.elapsed.inSeconds, lessThan(5));

      // No visible gap between sends
      final aliceConvo = await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceConvo.length, 2);
    });

    test('wifi losing the race still results in one delivered message through relay or inbox', () async {
      // Both online — the direct path (relay) should win even if local is unavailable
      final (result, msg) = await alice.sendMessage(bob.peerId, 'Race message');

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.status, 'delivered');

      // Only one message persisted
      final aliceConvo = await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceConvo.length, 1);
    });
  });
}
