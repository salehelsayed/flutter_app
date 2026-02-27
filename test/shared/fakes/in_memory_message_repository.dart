import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// In-memory [MessageRepository] for integration tests.
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
    final list = _messages.values
        .where((m) => m.contactPeerId == contactPeerId)
        .toList()
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
  Future<int> markConversationAsRead(String contactPeerId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    var count = 0;
    for (final entry in _messages.entries.toList()) {
      final m = entry.value;
      if (m.contactPeerId == contactPeerId && m.isIncoming && m.readAt == null) {
        _messages[entry.key] = m.copyWith(readAt: now);
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async {
    return _messages.values
        .where((m) =>
            m.contactPeerId == contactPeerId &&
            m.isIncoming &&
            m.readAt == null)
        .length;
  }

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
      messages = messages
          .where((m) => m.timestamp.compareTo(beforeTimestamp) < 0)
          .toList();
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
  }) async {
    return _messages.values
        .where((m) =>
            m.status == 'sent' &&
            !m.isIncoming &&
            m.wireEnvelope != null &&
            m.wireEnvelope!.isNotEmpty)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  int get count => _messages.length;
}
