/// Integration test: Two users exchange messages with each other.
///
/// Simulates a full bidirectional message exchange:
///   Alice sends "Hello Bob!" → P2P network → Bob receives & persists
///   Bob sends "Hi Alice!" → P2P network → Alice receives & persists
///   Both users load their conversations and verify all messages are present.
///
/// This test wires up the full stack per user:
///   FakeP2PService → ChatMessageListener → MessageRepository → use cases
///
/// The two FakeP2PService instances are connected via a FakeP2PNetwork
/// that routes messages between them (simulating the real relay).

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

// ─── Fake P2P Network ───────────────────────────────────────────────
// Routes messages between two FakeP2PService instances.
class FakeP2PNetwork {
  final Map<String, FakeP2PService> _nodes = {};
  final Map<String, List<Map<String, dynamic>>> _inboxes = {};

  void register(FakeP2PService node) {
    _nodes[node.peerId] = node;
  }

  void unregister(String peerId) {
    _nodes.remove(peerId);
  }

  /// Delivers a message from [fromPeerId] to [toPeerId].
  /// Returns true if the target node was found.
  bool deliver(String fromPeerId, String toPeerId, String content) {
    final target = _nodes[toPeerId];
    if (target == null) return false;

    // Simulate incoming message on the target node
    target.injectIncomingMessage(
      ChatMessage(
        from: fromPeerId,
        to: toPeerId,
        content: content,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ),
    );
    return true;
  }

  /// Whether a peer is registered on this network.
  bool hasPeer(String peerId) => _nodes.containsKey(peerId);

  /// Store message for offline delivery.
  bool storeInInbox(String fromPeerId, String toPeerId, String content) {
    final inbox = _inboxes.putIfAbsent(toPeerId, () => []);
    inbox.add({
      'from': fromPeerId,
      'message': content,
      'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
    return true;
  }

  /// Retrieve and clear inbox for a peer.
  List<Map<String, dynamic>> retrieveInbox(String peerId) {
    final messages = _inboxes.remove(peerId) ?? [];
    return List<Map<String, dynamic>>.from(messages);
  }
}

// ─── Fake P2P Service ───────────────────────────────────────────────
// Each user gets their own instance. Sending routes through the network.
class FakeP2PService implements P2PService {
  final String peerId;
  final FakeP2PNetwork network;
  final _messageController = StreamController<ChatMessage>.broadcast();
  bool _online = true;

  FakeP2PService({required this.peerId, required this.network}) {
    network.register(this);
  }

  void setOnline(bool online) {
    _online = online;
    if (online) {
      network.register(this);
    } else {
      network.unregister(peerId);
    }
  }

  void injectIncomingMessage(ChatMessage message) {
    _messageController.add(message);
  }

  @override
  Future<void> drainOfflineInbox() async {
    await drainOfflineInboxCount();
  }

  Future<int> drainOfflineInboxCount() async {
    final messages = await retrieveInbox();
    for (final message in messages) {
      final ts = message['timestamp'];
      final timestamp = ts is int
          ? DateTime.fromMillisecondsSinceEpoch(
              ts,
              isUtc: true,
            ).toIso8601String()
          : DateTime.now().toUtc().toIso8601String();
      injectIncomingMessage(
        ChatMessage(
          from: message['from'] as String,
          to: peerId,
          content: message['message'] as String,
          timestamp: timestamp,
          isIncoming: true,
        ),
      );
    }
    return messages.length;
  }

  @override
  NodeState get currentState => NodeState(isStarted: true, peerId: peerId);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => _messageController.stream;

  @override
  Future<bool> sendMessage(String targetPeerId, String message) async {
    return network.deliver(peerId, targetPeerId, message);
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final delivered = network.deliver(peerId, targetPeerId, message);
    return SendMessageResult(
      sent: delivered,
      reply: delivered ? 'received: $message' : null,
    );
  }

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    if (network.hasPeer(peerId)) {
      return DiscoveredPeer(
        id: peerId,
        addresses: ['/ip4/127.0.0.1/tcp/4001/p2p/$peerId'],
      );
    }
    return null;
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses, int? timeoutMs}) async =>
      network.hasPeer(peerId);

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    return network.storeInInbox(peerId, toPeerId, message);
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async {
    return network.retrieveInbox(peerId);
  }

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async => false;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async => RelayProbeResult.error;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async => false;

  @override
  Future<void> warmBackground() async {}

  @override
  void dispose() {
    _messageController.close();
  }
}

// ─── In-memory Message Repository ───────────────────────────────────
class InMemoryMessageRepository implements MessageRepository {
  final Map<String, ConversationMessage> _messages = {};

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    _messages[message.id] = message;
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final list =
        _messages.values.where((m) => m.contactPeerId == contactPeerId).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final list = await getMessagesForContact(contactPeerId);
    return list.isNotEmpty ? list.last : null;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final msg = _messages[id];
    if (msg != null) {
      _messages[id] = msg.copyWith(status: status);
    }
  }

  @override
  Future<bool> messageExists(String id) async => _messages.containsKey(id);

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    return _messages.values
        .where((m) => m.contactPeerId == contactPeerId)
        .length;
  }

  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async => 0;

  @override
  Future<int> getTotalUnreadCount() async => 0;

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async {
    final keysToRemove = _messages.entries
        .where((e) => e.value.contactPeerId == contactPeerId)
        .map((e) => e.key)
        .toList();
    for (final key in keysToRemove) {
      _messages.remove(key);
    }
    return keysToRemove.length;
  }

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    var messages = _messages.values
        .where((m) => m.contactPeerId == contactPeerId)
        .toList();
    if (beforeTimestamp != null) {
      messages = messages.where((m) => m.timestamp.compareTo(beforeTimestamp) < 0).toList();
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final page = messages.take(limit).toList();
    return page.reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async {
    return _messages.values
        .where((m) => m.status == 'failed' && !m.isIncoming)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  int get count => _messages.length;
}

// ─── In-memory Contact Repository ───────────────────────────────────
class InMemoryContactRepository implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  void addTestContact(ContactModel contact) {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];

  @override
  Future<List<ContactModel>> getAllContacts() async =>
      _contacts.values.toList();

  @override
  Future<void> deleteContact(String peerId) async {
    _contacts.remove(peerId);
  }

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);

  @override
  Future<int> getContactCount() async => _contacts.length;

  @override
  Future<void> archiveContact(String peerId) async {}

  @override
  Future<void> unarchiveContact(String peerId) async {}

  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      _contacts.values.where((c) => !c.isArchived).toList();

  @override
  Future<List<ContactModel>> getArchivedContacts() async =>
      _contacts.values.where((c) => c.isArchived).toList();

  @override
  Future<void> blockContact(String peerId) async {}

  @override
  Future<void> unblockContact(String peerId) async {}

  @override
  Future<void> dismissIntroBanner(String peerId) async {}

  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

// ─── Test User ──────────────────────────────────────────────────────
// Encapsulates the full per-user stack.
class TestUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryMessageRepository messageRepo;
  final InMemoryContactRepository contactRepo;
  final ChatMessageListener chatListener;

  TestUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.messageRepo,
    required this.contactRepo,
    required this.chatListener,
  });

  factory TestUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) {
    final p2p = FakeP2PService(peerId: peerId, network: network);
    final msgRepo = InMemoryMessageRepository();
    final contactRepo = InMemoryContactRepository();
    final listener = ChatMessageListener(
      chatMessageStream: p2p.messageStream,
      messageRepo: msgRepo,
      contactRepo: contactRepo,
    );

    return TestUser._(
      peerId: peerId,
      username: username,
      p2pService: p2p,
      messageRepo: msgRepo,
      contactRepo: contactRepo,
      chatListener: listener,
    );
  }

  /// Adds another user as a contact (simulating QR scan exchange).
  void addContact(TestUser other) {
    contactRepo.addTestContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  /// Sends a message to the target peer.
  Future<(SendChatMessageResult, ConversationMessage?)> sendMessage(
    String targetPeerId,
    String text,
  ) {
    return sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: text,
      senderPeerId: peerId,
      senderUsername: username,
    );
  }

  /// Loads the conversation with a contact.
  Future<List<ConversationMessage>> loadConversation(String contactPeerId) {
    return loadConversation2(
      messageRepo: messageRepo,
      contactPeerId: contactPeerId,
    );
  }

  void start() => chatListener.start();

  void setOnline(bool online) => p2pService.setOnline(online);

  Future<int> drainOfflineInbox() => p2pService.drainOfflineInboxCount();

  void dispose() {
    chatListener.dispose();
    p2pService.dispose();
  }
}

/// Wrapper to avoid name collision with the use case function.
Future<List<ConversationMessage>> loadConversation2({
  required MessageRepository messageRepo,
  required String contactPeerId,
}) {
  return loadConversation(
    messageRepo: messageRepo,
    contactPeerId: contactPeerId,
  );
}

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

      // Alice → Bob: message 1
      final (r1, _) = await alice.sendMessage(
        bob.peerId,
        'Hey Bob, how are you?',
      );
      expect(r1, SendChatMessageResult.success);

      // Wait for delivery
      await Future.delayed(const Duration(milliseconds: 50));

      // Bob → Alice: message 2
      final (r2, _) = await bob.sendMessage(
        alice.peerId,
        'Great, thanks! You?',
      );
      expect(r2, SendChatMessageResult.success);

      await Future.delayed(const Duration(milliseconds: 50));

      // Alice → Bob: message 3
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

    test('existing direct connection wins over rediscovery on repeated sends', () async {
      // First send
      final (r1, _) = await alice.sendMessage(bob.peerId, 'First');
      expect(r1, SendChatMessageResult.success);

      // Second send should reuse the existing path, not re-discover
      final (r2, _) = await alice.sendMessage(bob.peerId, 'Second');
      expect(r2, SendChatMessageResult.success);

      // Both messages should be in Alice's conversation
      final aliceConvo = await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceConvo.length, 2);
      expect(aliceConvo[0].text, 'First');
      expect(aliceConvo[1].text, 'Second');
    });

    test('peer moving from relay to shared wifi uses the fastest available path next', () async {
      // First send via relay
      final (r1, _) = await alice.sendMessage(bob.peerId, 'Via relay');
      expect(r1, SendChatMessageResult.success);

      // Send again — should still work regardless of transport
      final (r2, _) = await alice.sendMessage(bob.peerId, 'Via fastest');
      expect(r2, SendChatMessageResult.success);

      final aliceConvo = await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceConvo.length, 2);
    });

    test(
      'Messages to offline peer are marked delivered after inbox store',
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

        // Sender persists delivered status (inbox accepted by relay).
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

        offlineUser.dispose();
      },
    );
  });
}
