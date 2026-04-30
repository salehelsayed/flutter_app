import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_thread_summary.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_thread_summary_repository.dart';

/// In-memory [GroupMessageRepository] for integration tests.
class InMemoryGroupMessageRepository
    implements GroupMessageRepository, GroupThreadSummaryRepository {
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
    var messages = _messages.values.where((m) => m.groupId == groupId).toList();
    messages.sort(_compareMessagesDescending);
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
    messages.sort(_compareMessagesDescending);
    return messages.first;
  }

  @override
  Future<DateTime?> getLatestRemovalTimestampForSender(
    String groupId,
    String senderPeerId,
  ) async {
    final removalPrefix = 'sys-member_removed:$groupId:$senderPeerId:';
    final messages = _messages.values
        .where(
          (message) =>
              message.groupId == groupId &&
              message.id.startsWith(removalPrefix),
        )
        .toList();
    if (messages.isEmpty) return null;
    messages.sort(_compareMessagesDescending);
    return messages.first.timestamp.toUtc();
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
        .where((m) => m.groupId == groupId && m.isIncoming && m.readAt == null)
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
    String groupId,
    String senderPeerId,
    String text,
    DateTime timestamp,
  ) async {
    return _messages.values.any(
      (m) =>
          m.groupId == groupId &&
          m.senderPeerId == senderPeerId &&
          m.text == text &&
          m.timestamp == timestamp,
    );
  }

  @override
  Future<bool> existsByMessageId(String messageId) async {
    return _messages.containsKey(messageId);
  }

  @override
  Future<List<GroupMessage>> getFailedOutgoingMessages() async {
    final failed = _messages.values
        .where((m) => !m.isIncoming && m.status == 'failed')
        .toList();
    failed.sort(_compareMessagesAscending);
    return failed;
  }

  @override
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    var count = 0;
    for (final entry in _messages.entries.toList()) {
      final msg = entry.value;
      if (!msg.isIncoming &&
          msg.status == 'sending' &&
          msg.timestamp.isBefore(cutoff)) {
        _messages[entry.key] = msg.copyWith(status: 'failed');
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> transitionSendingToFailed() async {
    var count = 0;
    for (final entry in _messages.entries.toList()) {
      final msg = entry.value;
      if (!msg.isIncoming && msg.status == 'sending') {
        _messages[entry.key] = msg.copyWith(status: 'failed');
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> deleteMessagesForGroup(String groupId) async {
    final toRemove = _messages.entries
        .where((e) => e.value.groupId == groupId)
        .toList();
    for (final entry in toRemove) {
      _messages.remove(entry.key);
    }
    return toRemove.length;
  }

  @override
  Future<GroupThreadSummary> getGroupThreadSummary(String groupId) async {
    final messages =
        _messages.values.where((message) => message.groupId == groupId).toList()
          ..sort(_compareMessagesDescending);
    return GroupThreadSummary(
      groupId: groupId,
      unreadCount: messages
          .where((message) => message.isIncoming && message.readAt == null)
          .length,
      latestMessage: messages.isEmpty ? null : messages.first,
    );
  }

  @override
  Future<Map<String, GroupThreadSummary>> getGroupThreadSummaries(
    Iterable<String> groupIds,
  ) async {
    final summaries = <String, GroupThreadSummary>{};
    for (final groupId in groupIds.toSet()) {
      final messages =
          _messages.values
              .where((message) => message.groupId == groupId)
              .toList()
            ..sort(_compareMessagesDescending);
      summaries[groupId] = GroupThreadSummary(
        groupId: groupId,
        unreadCount: messages
            .where((message) => message.isIncoming && message.readAt == null)
            .length,
        latestMessage: messages.isEmpty ? null : messages.first,
      );
    }
    return summaries;
  }

  @override
  Future<List<GroupMessage>> getMessagesWithFailedInboxStore({
    int limit = 20,
  }) async {
    final eligible = _messages.values
        .where(
          (m) =>
              !m.isIncoming &&
              !m.inboxStored &&
              (m.status == 'sent' || m.status == 'pending') &&
              m.inboxRetryPayload != null,
        )
        .toList();
    eligible.sort(_compareMessagesAscending);
    return eligible.take(limit).toList();
  }

  @override
  Future<void> updateInboxStored(String id, {required bool stored}) async {
    final msg = _messages[id];
    if (msg != null) {
      _messages[id] = msg.copyWith(inboxStored: stored);
    }
  }

  @override
  Future<void> updateInboxRetryPayload(String id, String? payload) async {
    final msg = _messages[id];
    if (msg != null) {
      _messages[id] = msg.copyWith(inboxRetryPayload: payload);
    }
  }

  @override
  Future<void> updateWireEnvelope(String id, String? envelope) async {
    final msg = _messages[id];
    if (msg != null) {
      _messages[id] = msg.copyWith(wireEnvelope: envelope);
    }
  }

  int get count => _messages.length;
}

int _compareMessagesAscending(GroupMessage a, GroupMessage b) {
  final timestampCompare = a.timestamp.compareTo(b.timestamp);
  if (timestampCompare != 0) return timestampCompare;
  return a.id.compareTo(b.id);
}

int _compareMessagesDescending(GroupMessage a, GroupMessage b) {
  final timestampCompare = b.timestamp.compareTo(a.timestamp);
  if (timestampCompare != 0) return timestampCompare;
  return b.id.compareTo(a.id);
}
