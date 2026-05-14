import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/models/group_thread_summary.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_thread_summary_repository.dart';
import 'package:flutter_app/features/groups/domain/utils/group_message_ordering.dart';

/// In-memory [GroupMessageRepository] for integration tests.
class InMemoryGroupMessageRepository
    implements GroupMessageRepository, GroupThreadSummaryRepository {
  final Map<String, GroupMessage> _messages = {};
  final Map<String, String> _inboxCursors = {};
  final Map<String, GroupMessageReceipt> _receipts = {};
  final Set<String> failSaveMessageIds = {};
  bool failInboxPageTransaction = false;

  Iterable<GroupMessage> get _visibleMessages => _messages.values.where(
    (message) => !isGroupRemovalCutoffMessageId(message.id),
  );

  @override
  Future<void> saveMessage(GroupMessage message) async {
    if (failSaveMessageIds.contains(message.id)) {
      throw StateError('simulated save failure for ${message.id}');
    }
    _messages[message.id] = message;
  }

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    var messages = _visibleMessages.where((m) => m.groupId == groupId).toList();
    messages.sort(compareGroupMessagesDescending);
    // Apply offset and limit, then reverse to ASC order
    final page = messages.skip(offset).take(limit).toList();
    return orderGroupMessagesForTimeline(page.reversed);
  }

  @override
  Future<GroupMessage?> getMessage(String id) async {
    return _messages[id];
  }

  @override
  Future<GroupMessage?> getLatestMessage(String groupId) async {
    final messages = _visibleMessages
        .where((m) => m.groupId == groupId)
        .toList();
    if (messages.isEmpty) return null;
    messages.sort(compareGroupMessagesDescending);
    return messages.first;
  }

  @override
  Future<DateTime?> getLatestRemovalTimestampForSender(
    String groupId,
    String senderPeerId,
  ) async {
    final removalPrefix = 'sys-member_removed:$groupId:$senderPeerId:';
    final cutoffPrefix =
        '$groupRemovalCutoffMessageIdPrefix:$groupId:$senderPeerId:';
    final messages = _messages.values
        .where(
          (message) =>
              message.groupId == groupId &&
              (message.id.startsWith(removalPrefix) ||
                  message.id.startsWith(cutoffPrefix)),
        )
        .toList();
    if (messages.isEmpty) return null;
    messages.sort(compareGroupMessagesDescending);
    return messages.first.timestamp.toUtc();
  }

  @override
  Future<DateTime?> getLatestSystemEventTimestampForTarget(
    String groupId, {
    required String eventType,
    required String targetId,
  }) async {
    final prefix = 'sys-$eventType:$groupId:$targetId:';
    final messages = _messages.values
        .where(
          (message) =>
              message.groupId == groupId && message.id.startsWith(prefix),
        )
        .toList();
    if (messages.isEmpty) return null;
    messages.sort(compareGroupMessagesDescending);
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
    return _visibleMessages.where((m) => m.groupId == groupId).length;
  }

  @override
  Future<int> getUnreadCount(String groupId) async {
    return _visibleMessages
        .where((m) => m.groupId == groupId && m.isIncoming && m.readAt == null)
        .length;
  }

  @override
  Future<int> getTotalUnreadCount() async {
    return _visibleMessages
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
    return _visibleMessages.any(
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
    failed.sort(compareGroupMessagesAscending);
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
        _visibleMessages.where((message) => message.groupId == groupId).toList()
          ..sort(compareGroupMessagesDescending);
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
          _visibleMessages
              .where((message) => message.groupId == groupId)
              .toList()
            ..sort(compareGroupMessagesDescending);
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
    eligible.sort(compareGroupMessagesAscending);
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

  @override
  Future<String?> getInboxCursor(String groupId) async =>
      _inboxCursors[groupId];

  @override
  Future<List<GroupMessageReceipt>> getReceiptsForMessage(
    String groupId,
    String messageId, {
    String? receiptType,
  }) async {
    final receipts = _receipts.values
        .where(
          (receipt) =>
              receipt.groupId == groupId &&
              receipt.messageId == messageId &&
              (receiptType == null || receipt.receiptType == receiptType),
        )
        .toList();
    receipts.sort((a, b) {
      final typeCompare = a.receiptType.compareTo(b.receiptType);
      if (typeCompare != 0) return typeCompare;
      return a.memberPeerId.compareTo(b.memberPeerId);
    });
    return receipts;
  }

  @override
  Future<void> runInboxPageTransaction({
    required String groupId,
    required String nextCursor,
    required Future<void> Function(GroupMessageRepository transactionRepo)
    apply,
    List<GroupMessageReceipt> receipts = const [],
    List<String> markReadMessageIds = const [],
  }) async {
    final messageSnapshot = Map<String, GroupMessage>.from(_messages);
    final cursorSnapshot = Map<String, String>.from(_inboxCursors);
    final receiptSnapshot = Map<String, GroupMessageReceipt>.from(_receipts);
    try {
      await apply(this);
      if (failInboxPageTransaction) {
        throw StateError('simulated inbox transaction failure');
      }
      for (final receipt in receipts) {
        _receipts[_receiptKey(receipt)] = receipt;
      }
      final now = DateTime.now().toUtc();
      for (final messageId in markReadMessageIds) {
        final message = _messages[messageId];
        if (message != null && message.groupId == groupId) {
          _messages[messageId] = message.copyWith(
            readAt: message.readAt ?? now,
          );
        }
      }
      _inboxCursors[groupId] = nextCursor;
    } catch (_) {
      _messages
        ..clear()
        ..addAll(messageSnapshot);
      _inboxCursors
        ..clear()
        ..addAll(cursorSnapshot);
      _receipts
        ..clear()
        ..addAll(receiptSnapshot);
      rethrow;
    }
  }

  int get count => _visibleMessages.length;

  String _receiptKey(GroupMessageReceipt receipt) =>
      '${receipt.groupId}:${receipt.messageId}:${receipt.receiptType}:${receipt.memberPeerId}';
}
