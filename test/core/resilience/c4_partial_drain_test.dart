import 'dart:async';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';

// ---------------------------------------------------------------------------
// ThrowAfterNMessageRepo — throws on all saves after the Nth
// ---------------------------------------------------------------------------

class ThrowAfterNMessageRepo implements MessageRepository {
  final InMemoryMessageRepository _inner = InMemoryMessageRepository();
  final int throwAfterN;
  int _saveCount = 0;
  bool throwEnabled = true;

  ThrowAfterNMessageRepo({required this.throwAfterN});

  int get count => _inner.count;

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    _saveCount++;
    if (throwEnabled && _saveCount > throwAfterN) {
      throw Exception(
          'ThrowAfterNMessageRepo: save #$_saveCount exceeds threshold $throwAfterN');
    }
    return _inner.saveMessage(message);
  }

  @override
  Future<bool> messageExists(String id) => _inner.messageExists(id);

  @override
  Future<List<ConversationMessage>> getMessagesForContact(String cid) =>
      _inner.getMessagesForContact(cid);

  @override
  Future<ConversationMessage?> getLatestMessageForContact(String cid) =>
      _inner.getLatestMessageForContact(cid);

  @override
  Future<void> updateMessageStatus(String id, String status) =>
      _inner.updateMessageStatus(id, status);

  @override
  Future<int> getMessageCountForContact(String cid) =>
      _inner.getMessageCountForContact(cid);

  @override
  Future<int> markConversationAsRead(String cid) =>
      _inner.markConversationAsRead(cid);

  @override
  Future<int> getUnreadCountForContact(String cid) =>
      _inner.getUnreadCountForContact(cid);

  @override
  Future<int> getTotalUnreadCount() => _inner.getTotalUnreadCount();

  @override
  Future<int> getTotalUnreadCountExcludingArchived() =>
      _inner.getTotalUnreadCountExcludingArchived();

  @override
  Future<int> deleteMessagesForContact(String cid) =>
      _inner.deleteMessagesForContact(cid);

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() =>
      _inner.getFailedOutgoingMessages();

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) =>
      _inner.getUnackedOutgoingMessages(olderThan: olderThan);

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String cid, {
    int limit = 50,
    String? beforeTimestamp,
  }) =>
      _inner.getMessagesPage(cid, limit: limit, beforeTimestamp: beforeTimestamp);
}

// ---------------------------------------------------------------------------
// ThrowOnNthMessageRepo — throws only on the Nth save, succeeds for all others
// ---------------------------------------------------------------------------

class ThrowOnNthMessageRepo implements MessageRepository {
  final InMemoryMessageRepository _inner = InMemoryMessageRepository();
  final int throwOnN;
  int _saveCount = 0;

  ThrowOnNthMessageRepo({required this.throwOnN});

  int get count => _inner.count;

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    _saveCount++;
    if (_saveCount == throwOnN) {
      throw Exception(
          'ThrowOnNthMessageRepo: transient failure on save #$_saveCount');
    }
    return _inner.saveMessage(message);
  }

  @override
  Future<bool> messageExists(String id) => _inner.messageExists(id);

  @override
  Future<List<ConversationMessage>> getMessagesForContact(String cid) =>
      _inner.getMessagesForContact(cid);

  @override
  Future<ConversationMessage?> getLatestMessageForContact(String cid) =>
      _inner.getLatestMessageForContact(cid);

  @override
  Future<void> updateMessageStatus(String id, String status) =>
      _inner.updateMessageStatus(id, status);

  @override
  Future<int> getMessageCountForContact(String cid) =>
      _inner.getMessageCountForContact(cid);

  @override
  Future<int> markConversationAsRead(String cid) =>
      _inner.markConversationAsRead(cid);

  @override
  Future<int> getUnreadCountForContact(String cid) =>
      _inner.getUnreadCountForContact(cid);

  @override
  Future<int> getTotalUnreadCount() => _inner.getTotalUnreadCount();

  @override
  Future<int> getTotalUnreadCountExcludingArchived() =>
      _inner.getTotalUnreadCountExcludingArchived();

  @override
  Future<int> deleteMessagesForContact(String cid) =>
      _inner.deleteMessagesForContact(cid);

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() =>
      _inner.getFailedOutgoingMessages();

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) =>
      _inner.getUnackedOutgoingMessages(olderThan: olderThan);

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String cid, {
    int limit = 50,
    String? beforeTimestamp,
  }) =>
      _inner.getMessagesPage(cid, limit: limit, beforeTimestamp: beforeTimestamp);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _alicePeerId = 'alice-peer-id';
const _bobPeerId = 'bob-peer-id';
const _bobUsername = 'Bob';

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

/// Builds a v1 chat_message JSON envelope from Bob → Alice.
String _buildMessageJson(int index) {
  final payload = MessagePayload(
    id: 'msg-$index',
    text: 'message $index',
    senderPeerId: _bobPeerId,
    senderUsername: _bobUsername,
    timestamp: DateTime.utc(2026, 1, 1, 0, 0, index).toIso8601String(),
  );
  return payload.toJson();
}

/// Injects a ChatMessage into the listener's stream via the P2P service.
ChatMessage _makeChatMessage(int index) {
  return ChatMessage(
    from: _bobPeerId,
    to: _alicePeerId,
    content: _buildMessageJson(index),
    timestamp: DateTime.utc(2026, 1, 1, 0, 0, index).toIso8601String(),
    isIncoming: true,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('C4 — partial drain / repo failure resilience', () {
    test('first N messages persist, remaining throw — listener continues',
        () async {
      final repo = ThrowAfterNMessageRepo(throwAfterN: 5);
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(_makeContact(_bobPeerId, _bobUsername));

      final network = FakeP2PNetwork();
      final p2p = FakeP2PService(peerId: _alicePeerId, network: network);

      final listener = ChatMessageListener(
        chatMessageStream: p2p.messageStream,
        messageRepo: repo,
        contactRepo: contactRepo,
      );
      listener.start();

      // Inject 10 messages
      for (var i = 0; i < 10; i++) {
        p2p.injectIncomingMessage(_makeChatMessage(i));
      }

      // Allow async processing
      await Future.delayed(const Duration(milliseconds: 200));

      // First 5 persisted, remaining 5 threw — listener continued
      expect(repo.count, 5);

      listener.dispose();
      p2p.dispose();
    });

    test('recovery: re-inject failed messages after repo heals, dedup works',
        () async {
      final repo = ThrowAfterNMessageRepo(throwAfterN: 5);
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(_makeContact(_bobPeerId, _bobUsername));

      final network = FakeP2PNetwork();
      final p2p = FakeP2PService(peerId: _alicePeerId, network: network);

      final listener = ChatMessageListener(
        chatMessageStream: p2p.messageStream,
        messageRepo: repo,
        contactRepo: contactRepo,
      );
      listener.start();

      // First batch: 10 messages, 5 succeed, 5 throw
      for (var i = 0; i < 10; i++) {
        p2p.injectIncomingMessage(_makeChatMessage(i));
      }
      await Future.delayed(const Duration(milliseconds: 200));
      expect(repo.count, 5);

      // Heal the repo
      repo.throwEnabled = false;

      // Re-inject same 10 messages (same IDs)
      for (var i = 0; i < 10; i++) {
        p2p.injectIncomingMessage(_makeChatMessage(i));
      }
      await Future.delayed(const Duration(milliseconds: 200));

      // First 5 are deduped (messageExists → true), last 5 are now saved
      expect(repo.count, 10);

      listener.dispose();
      p2p.dispose();
    });

    test(
        'inbox drain with partial failure loses messages (documents at-most-once)',
        () async {
      final repo = ThrowAfterNMessageRepo(throwAfterN: 5);
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(_makeContact(_bobPeerId, _bobUsername));

      final network = FakeP2PNetwork();
      final aliceP2P = FakeP2PService(peerId: _alicePeerId, network: network);

      final listener = ChatMessageListener(
        chatMessageStream: aliceP2P.messageStream,
        messageRepo: repo,
        contactRepo: contactRepo,
      );
      listener.start();

      // Store 10 messages in Alice's inbox (from Bob)
      for (var i = 0; i < 10; i++) {
        network.storeInInbox(_bobPeerId, _alicePeerId, _buildMessageJson(i));
      }
      expect(network.inboxCount(_alicePeerId), 10);

      // Drain inbox — retrieves all 10 (deletes from inbox), injects them
      final drained = await aliceP2P.drainOfflineInboxCount();
      expect(drained, 10);

      // Inbox is now empty (at-most-once: retrieve = delete)
      expect(network.inboxCount(_alicePeerId), 0);

      await Future.delayed(const Duration(milliseconds: 200));

      // Only 5 persisted (repo threw on 6-10)
      expect(repo.count, 5);

      // Second drain returns 0 — those 5 messages are permanently lost
      final secondDrain = await aliceP2P.drainOfflineInboxCount();
      expect(secondDrain, 0);

      listener.dispose();
      aliceP2P.dispose();
    });

    test('transient failure: only the Nth message lost', () async {
      final repo = ThrowOnNthMessageRepo(throwOnN: 6);
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(_makeContact(_bobPeerId, _bobUsername));

      final network = FakeP2PNetwork();
      final p2p = FakeP2PService(peerId: _alicePeerId, network: network);

      final listener = ChatMessageListener(
        chatMessageStream: p2p.messageStream,
        messageRepo: repo,
        contactRepo: contactRepo,
      );
      listener.start();

      // Inject 10 messages
      for (var i = 0; i < 10; i++) {
        p2p.injectIncomingMessage(_makeChatMessage(i));
      }
      await Future.delayed(const Duration(milliseconds: 200));

      // 9 out of 10 saved (message #5, 0-indexed, was the 6th save and threw)
      expect(repo.count, 9);

      // Verify the 6th message (index 5) is missing
      final exists = await repo.messageExists('msg-5');
      expect(exists, isFalse);

      listener.dispose();
      p2p.dispose();
    });

    test('100 messages with throw at 50: exactly 50 persisted', () async {
      final repo = ThrowAfterNMessageRepo(throwAfterN: 50);
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(_makeContact(_bobPeerId, _bobUsername));

      final network = FakeP2PNetwork();
      final p2p = FakeP2PService(peerId: _alicePeerId, network: network);

      final listener = ChatMessageListener(
        chatMessageStream: p2p.messageStream,
        messageRepo: repo,
        contactRepo: contactRepo,
      );
      listener.start();

      for (var i = 0; i < 100; i++) {
        p2p.injectIncomingMessage(_makeChatMessage(i));
      }
      await Future.delayed(const Duration(milliseconds: 500));

      expect(repo.count, 50);

      listener.dispose();
      p2p.dispose();
    });
  });
}
