import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

/// In-memory [GroupMessageRepository] for integration tests.
class InMemoryGroupMessageRepository implements GroupMessageRepository {
  final Map<String, GroupMessage> _messages = {};

  @override
  Future<void> saveMessage(GroupMessage message) async {
    _messages[message.id] = message;
  }

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    var messages = _messages.values
        .where((m) => m.groupId == groupId)
        .toList();
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    // Apply offset and limit, then reverse to ASC order
    final page = messages.skip(offset).take(limit).toList();
    return page.reversed.toList();
  }

  @override
  Future<GroupMessage?> getMessage(String id) async {
    return _messages[id];
  }

  @override
  Future<GroupMessage?> getLatestMessage(String groupId) async {
    final messages = _messages.values
        .where((m) => m.groupId == groupId)
        .toList();
    if (messages.isEmpty) return null;
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messages.first;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final msg = _messages[id];
    if (msg != null) {
      _messages[id] = msg.copyWith(status: status);
    }
  }

  @override
  Future<int> getMessageCount(String groupId) async {
    return _messages.values.where((m) => m.groupId == groupId).length;
  }

  @override
  Future<int> getUnreadCount(String groupId) async {
    return _messages.values
        .where((m) =>
            m.groupId == groupId && m.isIncoming && m.readAt == null)
        .length;
  }

  @override
  Future<int> getTotalUnreadCount() async {
    return _messages.values
        .where((m) => m.isIncoming && m.readAt == null)
        .length;
  }

  @override
  Future<void> markAsRead(String groupId) async {
    final now = DateTime.now().toUtc();
    for (final entry in _messages.entries.toList()) {
      final m = entry.value;
      if (m.groupId == groupId && m.isIncoming && m.readAt == null) {
        _messages[entry.key] = m.copyWith(readAt: now);
      }
    }
  }

  @override
  Future<void> deleteMessage(String id) async {
    _messages.remove(id);
  }

  @override
  Future<bool> existsByContent(
      String groupId, String senderPeerId, String text, DateTime timestamp) async {
    return _messages.values.any((m) =>
        m.groupId == groupId &&
        m.senderPeerId == senderPeerId &&
        m.text == text &&
        m.timestamp == timestamp);
  }

  int get count => _messages.length;
}
