import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/test_user.dart';
import '../../shared/fakes/in_memory_message_repository.dart';

/// Minimal Bridge that handles message.decrypt with a pre-canned response.
class _FakeDecryptBridge implements Bridge {
  Map<String, dynamic> decryptResponse = {'ok': true, 'plaintext': '{}'};
  int decryptCallCount = 0;

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    if (req['cmd'] == 'message.decrypt') {
      decryptCallCount++;
      return jsonEncode(decryptResponse);
    }
    return jsonEncode({'ok': true});
  }

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String>, List<String>)? onAddressesUpdated;
}

void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;

  setUp(() {
    network = FakeP2PNetwork();
    alice = TestUser.create(
        peerId: 'alice-peer', username: 'Alice', network: network);
    bob = TestUser.create(
        peerId: 'bob-peer', username: 'Bob', network: network);
    alice.addContact(bob);
    bob.addContact(alice);
    alice.start();
    bob.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  group('Inbox round-trip tests', () {
    test('1.1 Store → retrieve basic flow', () async {
      // Bob online → direct delivery succeeds
      final delivered = await network.deliver(
          'alice-peer', 'bob-peer', 'direct message');
      expect(delivered, isTrue);

      // Bob goes offline → store in inbox
      bob.setOnline(false);
      final stored = network.storeInInbox(
          'alice-peer', 'bob-peer', 'offline message');
      expect(stored, isTrue);

      // Verify inbox has the message
      final inbox = network.retrieveInbox('bob-peer');
      expect(inbox, hasLength(1));
      expect(inbox.first['from'], 'alice-peer');
      expect(inbox.first['message'], 'offline message');
    });

    test('1.2 Retrieve on resume — full drain → listener → persist pipeline',
        () async {
      bob.setOnline(false);

      // Alice stores a message in Bob's inbox
      final payload = MessagePayload(
        id: 'msg-00001-inbox-test',
        text: 'Hello from inbox',
        senderPeerId: 'alice-peer',
        senderUsername: 'Alice',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );
      network.storeInInbox('alice-peer', 'bob-peer', payload.toJson());

      // Bob comes online and drains inbox
      bob.setOnline(true);
      final drained = await bob.drainOfflineInbox();
      expect(drained, 1);

      // Allow listener to process the message
      await Future<void>.delayed(Duration.zero);

      // Verify message was persisted via ChatMessageListener → handleIncomingChatMessage
      final messages = await bob.messageRepo.getMessagesForContact('alice-peer');
      expect(messages, hasLength(1));
      expect(messages.first.text, 'Hello from inbox');
      expect(messages.first.id, 'msg-00001-inbox-test');
      expect(messages.first.isIncoming, isTrue);
    });

    test('1.3 Inbox store failure — sends fail when both direct and inbox fail',
        () async {
      // Disable inbox on the network
      network.inboxDisabled = true;

      // Bob goes offline (direct delivery will fail)
      bob.setOnline(false);

      // Alice sends message — discover/dial fails + inbox fails
      final (result, message) = await alice.sendMessage(
        'bob-peer',
        'this will fail',
      );

      // sendChatMessage returns the specific failure reason (peerNotFound or sendFailed)
      expect(result,
          anyOf(SendChatMessageResult.sendFailed, SendChatMessageResult.peerNotFound));
      expect(message, isNotNull);
      expect(message!.status, 'failed');

      // Verify failed message was persisted
      final aliceMessages =
          await alice.messageRepo.getMessagesForContact('bob-peer');
      expect(aliceMessages, hasLength(1));
      expect(aliceMessages.first.status, 'failed');
    });

    test('1.4 Inbox retrieve timing — cleared after retrieval, batches independent',
        () async {
      // Store 1 message
      network.storeInInbox('alice-peer', 'bob-peer', 'msg-1');
      var inbox = network.retrieveInbox('bob-peer');
      expect(inbox, hasLength(1));

      // After retrieval, inbox is empty
      inbox = network.retrieveInbox('bob-peer');
      expect(inbox, isEmpty);

      // Store 2 messages, retrieve both
      network.storeInInbox('alice-peer', 'bob-peer', 'msg-2');
      network.storeInInbox('alice-peer', 'bob-peer', 'msg-3');
      inbox = network.retrieveInbox('bob-peer');
      expect(inbox, hasLength(2));

      // Inbox is empty again
      inbox = network.retrieveInbox('bob-peer');
      expect(inbox, isEmpty);

      // Store another message independently
      network.storeInInbox('alice-peer', 'bob-peer', 'msg-4');
      inbox = network.retrieveInbox('bob-peer');
      expect(inbox, hasLength(1));
      expect(inbox.first['message'], 'msg-4');
    });

    test('1.5 Multiple messages queued (5 messages while offline)', () async {
      bob.setOnline(false);

      // Alice stores 5 messages in Bob's inbox
      for (var i = 1; i <= 5; i++) {
        final payload = MessagePayload(
          id: 'msg-0000$i-batch',
          text: 'Message $i',
          senderPeerId: 'alice-peer',
          senderUsername: 'Alice',
          timestamp: DateTime.now()
              .toUtc()
              .add(Duration(seconds: i))
              .toIso8601String(),
        );
        network.storeInInbox('alice-peer', 'bob-peer', payload.toJson());
      }

      // Bob comes online and drains inbox
      bob.setOnline(true);
      final drained = await bob.drainOfflineInbox();
      expect(drained, 5);

      // Allow listener to process all messages
      await Future<void>.delayed(Duration.zero);

      // Verify all 5 messages persisted
      final messages = await bob.messageRepo.getMessagesForContact('alice-peer');
      expect(messages, hasLength(5));
      expect(messages.map((m) => m.id).toList(),
          ['msg-00001-batch', 'msg-00002-batch', 'msg-00003-batch',
           'msg-00004-batch', 'msg-00005-batch']);
    });

    test('1.6 Encrypted inbox messages (v2 envelope)', () async {
      // Create a separate Bob with bridge + ML-KEM secret key for v2 decrypt
      final decryptBridge = _FakeDecryptBridge();
      final bobWithCrypto = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
        bridge: decryptBridge,
        getOwnMlKemSecretKey: () async => 'test-mlkem-secret-key',
      );
      bobWithCrypto.addContact(alice);
      bobWithCrypto.start();

      // Build inner payload that the bridge "decrypts" to
      final innerPayload = MessagePayload(
        id: 'enc-msg-0001',
        text: 'Secret message',
        senderPeerId: 'alice-peer',
        senderUsername: 'Alice',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      // Configure the fake bridge to return this inner payload as "decrypted" plaintext
      decryptBridge.decryptResponse = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': innerPayload.id,
          'text': innerPayload.text,
          'senderPeerId': innerPayload.senderPeerId,
          'senderUsername': innerPayload.senderUsername,
          'timestamp': innerPayload.timestamp,
        }),
      };

      // Build a v2 encrypted envelope (simulated — no real crypto)
      final v2Envelope = MessagePayload.buildEncryptedEnvelope(
        senderPeerId: 'alice-peer',
        kem: 'fake-kem-ciphertext',
        ciphertext: 'fake-aes-ciphertext',
        nonce: 'fake-nonce',
      );

      // Store the v2 envelope in Bob's inbox while he's offline
      bob.setOnline(false);
      network.storeInInbox('alice-peer', 'bob-peer', v2Envelope);

      // Bob (with crypto) drains inbox — should decrypt v2 envelope
      network.register(bobWithCrypto.p2pService);
      final drained = await bobWithCrypto.drainOfflineInbox();
      expect(drained, 1);

      await Future<void>.delayed(Duration.zero);

      // Verify the bridge was asked to decrypt
      expect(decryptBridge.decryptCallCount, 1);

      // Verify the decrypted message was persisted
      final messages =
          await bobWithCrypto.messageRepo.getMessagesForContact('alice-peer');
      expect(messages, hasLength(1));
      expect(messages.first.text, 'Secret message');
      expect(messages.first.id, 'enc-msg-0001');

      bobWithCrypto.dispose();
    });

    test('1.7 Connection type fallback chain (P2P → relay → inbox)', () async {
      // Scenario A: Bob online → direct delivery → success
      final (resultA, messageA) = await alice.sendMessage(
        'bob-peer',
        'direct message',
      );
      expect(resultA, SendChatMessageResult.success);
      expect(messageA, isNotNull);
      expect(messageA!.transport, 'relay');

      // Scenario B: Bob offline, discovery fails → inbox fallback → success
      bob.setOnline(false);
      final (resultB, messageB) = await alice.sendMessage(
        'bob-peer',
        'inbox fallback message',
      );
      expect(resultB, SendChatMessageResult.success);
      expect(messageB, isNotNull);
      expect(messageB!.transport, 'inbox');

      // Scenario C: Bob offline, inbox disabled → full failure
      network.inboxDisabled = true;
      final (resultC, messageC) = await alice.sendMessage(
        'bob-peer',
        'will fail completely',
      );
      expect(resultC,
          anyOf(SendChatMessageResult.sendFailed, SendChatMessageResult.peerNotFound));
      expect(messageC, isNotNull);
      expect(messageC!.status, 'failed');
    });

    test('1.8 Race between direct send and inbox store', () async {
      // Add a delivery delay so we can toggle Bob offline during delivery
      network.deliveryDelay = const Duration(milliseconds: 50);

      // Start the send in parallel with taking Bob offline
      final sendFuture = alice.sendMessage('bob-peer', 'race message');

      // Wait a bit then take Bob offline (after discover/dial but during send)
      await Future<void>.delayed(const Duration(milliseconds: 10));
      bob.setOnline(false);

      final (result, message) = await sendFuture;

      // The message should eventually succeed (either via direct or inbox fallback)
      // Because FakeP2PService discover/dial check hasPeer synchronously,
      // if Bob goes offline after the initial discover, the send attempt may
      // fail and fall back to inbox.
      expect(
        result,
        anyOf(SendChatMessageResult.success, SendChatMessageResult.sendFailed),
      );

      // If it succeeded via inbox, verify the inbox path worked
      if (result == SendChatMessageResult.success && message != null) {
        expect(message.transport, anyOf('relay', 'inbox'));
      }

      // Clean up: remove delivery delay for other tests
      network.deliveryDelay = null;
    });
  });

  group('Inbox edge cases', () {
    test('drain empty inbox returns 0', () async {
      final drained = await bob.drainOfflineInbox();
      expect(drained, 0);
    });

    test('inbox messages from unknown sender are rejected by listener',
        () async {
      bob.setOnline(false);

      // Store message from a peer that isn't in Bob's contacts
      final payload = MessagePayload(
        id: 'unknown-msg',
        text: 'Unknown sender message',
        senderPeerId: 'charlie-peer',
        senderUsername: 'Charlie',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );
      network.storeInInbox('charlie-peer', 'bob-peer', payload.toJson());

      bob.setOnline(true);
      await bob.drainOfflineInbox();
      await Future<void>.delayed(Duration.zero);

      // Message should NOT be persisted (unknown sender)
      final messages =
          await bob.messageRepo.getMessagesForContact('charlie-peer');
      expect(messages, isEmpty);
    });

    test('duplicate inbox message is rejected by listener', () async {
      bob.setOnline(false);

      final payload = MessagePayload(
        id: 'dup-msg-00001-test',
        text: 'First copy',
        senderPeerId: 'alice-peer',
        senderUsername: 'Alice',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );
      final envelope = payload.toJson();

      // Store the same message twice in inbox
      network.storeInInbox('alice-peer', 'bob-peer', envelope);
      network.storeInInbox('alice-peer', 'bob-peer', envelope);

      bob.setOnline(true);
      final drained = await bob.drainOfflineInbox();
      expect(drained, 2); // Both injected into stream

      await Future<void>.delayed(Duration.zero);

      // Only 1 message persisted (second is a duplicate)
      final messages =
          await bob.messageRepo.getMessagesForContact('alice-peer');
      expect(messages, hasLength(1));
      expect(messages.first.id, 'dup-msg-00001-test');
    });
  });
}
