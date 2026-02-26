import 'dart:async';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/chaos_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';
import '../../shared/fakes/test_user.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _alicePeerId = 'alice-peer-id';
const _bobPeerId = 'bob-peer-id';

ContactModel _makeContact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
  );
}

/// Creates a TestUser wired to a ChaosP2PNetwork.
_TestPair _setup(ChaosConfig config) {
  final network = ChaosP2PNetwork(config: config);

  final alice = TestUser.create(
    peerId: _alicePeerId,
    username: 'Alice',
    network: network,
  );
  final bob = TestUser.create(
    peerId: _bobPeerId,
    username: 'Bob',
    network: network,
  );

  alice.addContact(bob);
  bob.addContact(alice);

  alice.start();
  bob.start();

  return _TestPair(alice: alice, bob: bob, network: network);
}

class _TestPair {
  final TestUser alice;
  final TestUser bob;
  final ChaosP2PNetwork network;

  _TestPair({required this.alice, required this.bob, required this.network});

  void dispose() {
    alice.dispose();
    bob.dispose();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Network chaos resilience', () {
    test('100% duplicates rejected by dedup layer', () async {
      final pair = _setup(const ChaosConfig(
        duplicateRate: 1.0,
        seed: 42,
      ));

      const n = 10;
      for (var i = 0; i < n; i++) {
        await pair.alice.sendMessage(_bobPeerId, 'msg $i');
      }

      await Future.delayed(const Duration(milliseconds: 300));

      // Bob's listener deduplicates — exactly N messages
      final bobMessages = await pair.bob.loadConversationWith(_alicePeerId);
      expect(bobMessages, hasLength(n));

      // Alice persisted exactly N outgoing messages
      final aliceMessages = await pair.alice.loadConversationWith(_bobPeerId);
      expect(aliceMessages, hasLength(n));

      pair.dispose();
    });

    test('reordered messages arrive shuffled but DB sorts by timestamp',
        () async {
      final pair = _setup(const ChaosConfig(
        reorderBufferSize: 5,
        seed: 99,
      ));

      const n = 10;
      for (var i = 0; i < n; i++) {
        await pair.alice.sendMessage(_bobPeerId, 'msg $i');
      }

      // Flush any partial buffer
      await pair.network.flushReorderBuffer();
      await Future.delayed(const Duration(milliseconds: 300));

      final bobMessages = await pair.bob.loadConversationWith(_alicePeerId);
      expect(bobMessages, hasLength(n));

      // Messages are in timestamp order (loadConversationWith sorts by timestamp)
      for (var i = 1; i < bobMessages.length; i++) {
        expect(
          bobMessages[i].timestamp.compareTo(bobMessages[i - 1].timestamp),
          greaterThanOrEqualTo(0),
          reason: 'Messages should be in timestamp order',
        );
      }

      pair.dispose();
    });

    test('delayed messages all arrive within bounded time', () async {
      final pair = _setup(const ChaosConfig(
        maxDelay: Duration(milliseconds: 100),
        seed: 7,
      ));

      const n = 10;
      for (var i = 0; i < n; i++) {
        await pair.alice.sendMessage(_bobPeerId, 'msg $i');
      }

      // Wait longer than max delay for all messages to propagate
      await Future.delayed(const Duration(milliseconds: 500));

      final bobMessages = await pair.bob.loadConversationWith(_alicePeerId);
      expect(bobMessages, hasLength(n));

      pair.dispose();
    });

    test('dropped messages trigger inbox fallback on sender', () async {
      final pair = _setup(const ChaosConfig(
        dropRate: 1.0, // drop every message
        seed: 1,
      ));

      // When deliver returns false, sendMessageWithReply returns sent:false.
      // After 3 retries, sendChatMessage falls through to inbox fallback.
      final (result, msg) = await pair.alice.sendMessage(_bobPeerId, 'hello');

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.transport, 'inbox');
      expect(msg.status, 'delivered');

      // The message was stored in inbox
      expect(pair.network.inboxCount(_bobPeerId), 1);

      pair.dispose();
    });

    test('combined chaos: 20 messages with all behaviors active', () async {
      final pair = _setup(const ChaosConfig(
        duplicateRate: 0.3,
        reorderBufferSize: 4,
        maxDelay: Duration(milliseconds: 50),
        dropRate: 0.2,
        seed: 42,
      ));

      const n = 20;
      for (var i = 0; i < n; i++) {
        await pair.alice.sendMessage(_bobPeerId, 'msg $i');
      }

      // Flush reorder buffer
      await pair.network.flushReorderBuffer();
      await Future.delayed(const Duration(milliseconds: 500));

      // Alice always persists her own messages (N total)
      final aliceMessages = await pair.alice.loadConversationWith(_bobPeerId);
      expect(aliceMessages, hasLength(n));

      // Bob receives (N - dropped) messages, no duplicates
      final bobMessages = await pair.bob.loadConversationWith(_alicePeerId);
      final droppedCount = pair.network.droppedMessages.length;

      // Messages that were dropped by the network would have been sent to
      // inbox by the sender's fallback. Bob hasn't drained inbox yet, so
      // received = N - dropped (only direct deliveries counted here).
      // The key assertion: NO duplicates
      final bobIds = bobMessages.map((m) => m.id).toSet();
      expect(bobIds.length, bobMessages.length,
          reason: 'No duplicate IDs in Bob repo');

      // All messages in timestamp order
      for (var i = 1; i < bobMessages.length; i++) {
        expect(
          bobMessages[i].timestamp.compareTo(bobMessages[i - 1].timestamp),
          greaterThanOrEqualTo(0),
        );
      }

      pair.dispose();
    });

    test('chaos does not corrupt message content', () async {
      final pair = _setup(const ChaosConfig(
        duplicateRate: 0.5,
        reorderBufferSize: 3,
        maxDelay: Duration(milliseconds: 30),
        seed: 123,
      ));

      const n = 15;
      for (var i = 0; i < n; i++) {
        await pair.alice.sendMessage(_bobPeerId, 'message content $i');
      }

      await pair.network.flushReorderBuffer();
      await Future.delayed(const Duration(milliseconds: 500));

      final bobMessages = await pair.bob.loadConversationWith(_alicePeerId);

      for (final msg in bobMessages) {
        // Every message should have correct sender/contact peers
        expect(msg.senderPeerId, _alicePeerId);
        expect(msg.contactPeerId, _alicePeerId);
        expect(msg.isIncoming, isTrue);

        // Text content matches pattern
        expect(msg.text, matches(RegExp(r'^message content \d+$')));
      }

      pair.dispose();
    });
  });
}
