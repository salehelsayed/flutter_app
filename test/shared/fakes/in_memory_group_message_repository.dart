import 'dart:async';

import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/models/group_thread_preview.dart';
import 'package:flutter_app/features/groups/domain/models/group_thread_summary.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_thread_preview_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_thread_summary_repository.dart';
import 'package:flutter_app/features/groups/domain/utils/group_message_ordering.dart';

bool _sameExactOutgoingRetryTuple(
  GroupMessage current,
  GroupMessage expected,
) =>
    current.id == expected.id &&
    current.groupId == expected.groupId &&
    current.senderPeerId == expected.senderPeerId &&
    current.transportPeerId == expected.transportPeerId &&
    current.senderUsername == expected.senderUsername &&
    current.text == expected.text &&
    current.timestamp.toUtc() == expected.timestamp.toUtc() &&
    current.lastSendAttemptAt?.toUtc() == expected.lastSendAttemptAt?.toUtc() &&
    current.quotedMessageId == expected.quotedMessageId &&
    current.logicalDeliveryId == expected.logicalDeliveryId &&
    current.keyGeneration == expected.keyGeneration &&
    current.status == expected.status &&
    current.isIncoming == expected.isIncoming &&
    current.isForwarded == expected.isForwarded &&
    current.privateMediaPolicy == expected.privateMediaPolicy &&
    current.mediaReceivedAt == expected.mediaReceivedAt &&
    current.mediaExpiresAt == expected.mediaExpiresAt &&
    current.mediaLastCheckedAt == expected.mediaLastCheckedAt &&
    current.mediaConsumedAt == expected.mediaConsumedAt &&
    current.mediaExpiredAt == expected.mediaExpiredAt &&
    current.mediaCleanupPending == expected.mediaCleanupPending &&
    current.createdAt.toUtc() == expected.createdAt.toUtc() &&
    current.wireEnvelope == expected.wireEnvelope &&
    current.inboxStored == expected.inboxStored &&
    current.inboxRetryPayload == expected.inboxRetryPayload &&
    current.retryAttemptCount == expected.retryAttemptCount &&
    current.nextEligibleAt?.toUtc() == expected.nextEligibleAt?.toUtc();

/// In-memory [GroupMessageRepository] for integration tests.
class InMemoryGroupMessageRepository
    implements
        GroupMessageRepository,
        GroupThreadSummaryRepository,
        GroupThreadPreviewRepository,
        GroupInboxStoreRetryCompletionRepository,
        GroupMembershipRepairDeletionRepository,
        GroupConversationReadEventSource,
        GroupOutgoingLocalMessageChangeSource,
        GroupMessageLocalDeletionAuthority {
  final Map<String, GroupMessage> _messages = {};
  final Map<String, String> _inboxCursors = {};
  final Map<String, GroupMessageReceipt> _receipts = {};
  final Set<String> _localDeletionTombstones = {};

  /// 235: tombstone `message_id -> group_id` identity, mirroring the
  /// migration-069 journal (kept beside the legacy id set so IR-020 replay
  /// behavior is unchanged).
  final Map<String, String> _localDeletionGroupIds = {};
  final StreamController<GroupOutgoingLocalMessageChange>
  _outgoingLocalMessageChangesController =
      StreamController<GroupOutgoingLocalMessageChange>.broadcast();
  final StreamController<String> _groupConversationReadController =
      StreamController<String>.broadcast();
  final Set<String> failSaveMessageIds = {};
  bool failInboxPageTransaction = false;

  /// 161 spies: every `getMessagesPage` call as `(groupId, limit)` and the
  /// number of batched `getGroupThreadPreviews` calls, so the feed tests can
  /// prove the collapsed group feed uses ONE batched preview + bounded
  /// per-pending windows (never the unbounded `limit:200` per-group loop).
  final List<(String, int)> getMessagesPageCallLog = <(String, int)>[];
  int getGroupThreadPreviewsCallCount = 0;

  Iterable<GroupMessage> get _visibleMessages => _messages.values.where(
    (message) => !isGroupRemovalCutoffMessageId(message.id),
  );

  @override
  Stream<GroupOutgoingLocalMessageChange> get outgoingLocalMessageChanges =>
      _outgoingLocalMessageChangesController.stream;

  @override
  Stream<String> get groupConversationReadStream =>
      _groupConversationReadController.stream;

  void _emitOutgoingStatusChangeIfNeeded({
    required GroupMessage? previous,
    required GroupMessage saved,
  }) {
    if (previous == null) {
      if (!saved.isIncoming && saved.status == 'sending') {
        _outgoingLocalMessageChangesController.add(
          GroupOutgoingLocalMessageChange.inserted(
            groupId: saved.groupId,
            messageId: saved.id,
          ),
        );
      }
      return;
    }
    if (saved.isIncoming) return;
    if (previous.status == saved.status) return;
    _outgoingLocalMessageChangesController.add(
      GroupOutgoingLocalMessageChange.status(
        groupId: saved.groupId,
        messageId: saved.id,
        status: saved.status,
      ),
    );
  }

  void _emitOutgoingRowsChangedIfNeeded(int count) {
    if (count <= 0) return;
    _outgoingLocalMessageChangesController.add(
      const GroupOutgoingLocalMessageChange.rowsChanged(),
    );
  }

  @override
  Future<void> saveMessage(GroupMessage message) async {
    if (failSaveMessageIds.contains(message.id)) {
      throw StateError('simulated save failure for ${message.id}');
    }
    if (_localDeletionTombstones.contains(message.id)) {
      return;
    }
    final previous = _messages[message.id];
    _messages[message.id] = message;
    _emitOutgoingStatusChangeIfNeeded(previous: previous, saved: message);
  }

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    getMessagesPageCallLog.add((groupId, limit));
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
  Future<GroupMessage?> getMessageByLogicalDeliveryId(
    String groupId,
    String senderPeerId,
    String logicalDeliveryId,
  ) async {
    final normalizedLogicalDeliveryId = logicalDeliveryId.trim();
    if (normalizedLogicalDeliveryId.isEmpty) return null;
    final matches = _visibleMessages
        .where(
          (message) =>
              message.groupId == groupId &&
              message.senderPeerId == senderPeerId &&
              message.logicalDeliveryId == normalizedLogicalDeliveryId,
        )
        .toList();
    if (matches.isEmpty) return null;
    matches.sort(compareGroupMessagesAscending);
    return matches.first;
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
      if (!msg.isIncoming && msg.status != status) {
        _outgoingLocalMessageChangesController.add(
          GroupOutgoingLocalMessageChange.status(
            groupId: msg.groupId,
            messageId: msg.id,
            status: status,
          ),
        );
      }
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
    var markedCount = 0;
    for (final entry in _messages.entries.toList()) {
      final m = entry.value;
      if (m.groupId == groupId && m.isIncoming && m.readAt == null) {
        _messages[entry.key] = m.copyWith(readAt: now);
        markedCount++;
      }
    }
    if (markedCount > 0) {
      _groupConversationReadController.add(groupId);
    }
  }

  @override
  Future<void> deleteMessage(String id) async {
    final removed = _messages.remove(id);
    if (removed != null) {
      _localDeletionTombstones.add(id);
      _localDeletionGroupIds[id] = removed.groupId;
    }
  }

  @override
  Future<String?> getLocalDeletionGroupId(String messageId) async =>
      _localDeletionGroupIds[messageId];

  @override
  Future<GroupMessageLocalDeletionState> getGroupMessageLocalDeletionState(
    String messageId,
  ) async => _localDeletionTombstones.contains(messageId)
      ? GroupMessageLocalDeletionState.deleted
      : GroupMessageLocalDeletionState.knownClear;

  /// 235 test seam: seeds a tombstone identity directly.
  void seedLocalDeletion({required String messageId, required String groupId}) {
    _localDeletionTombstones.add(messageId);
    _localDeletionGroupIds[messageId] = groupId;
  }

  @override
  Future<void> deleteMessageForMembershipRepair(String id) async {
    final removed = _messages.remove(id);
    _emitOutgoingRowsChangedIfNeeded(removed == null ? 0 : 1);
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
  Future<List<GroupMessage>> getRetryableOutgoingMessages() async {
    final now = DateTime.now().toUtc();
    final retryable = _messages.values
        .where(
          (m) =>
              !m.isIncoming &&
              (m.status == 'failed' || m.status == 'pending') &&
              (m.nextEligibleAt == null || !m.nextEligibleAt!.isAfter(now)),
        )
        .toList();
    retryable.sort(compareGroupMessagesAscending);
    return retryable;
  }

  @override
  Future<void> recordRetryFailure(
    String id, {
    required DateTime nextEligibleAt,
    required bool markTerminal,
  }) async {
    final msg = _messages[id];
    if (msg == null || msg.isIncoming) return;
    if (msg.status != 'failed' && msg.status != 'pending') return;
    _messages[id] = msg.copyWith(
      retryAttemptCount: msg.retryAttemptCount + 1,
      nextEligibleAt: nextEligibleAt,
      status: markTerminal ? GroupMessage.statusSendFailed : msg.status,
    );
    _emitOutgoingRowsChangedIfNeeded(1);
  }

  @override
  Future<int> clearRetryBackoff() async {
    var count = 0;
    for (final entry in _messages.entries.toList()) {
      final msg = entry.value;
      if (!msg.isIncoming &&
          (msg.status == 'failed' || msg.status == 'pending') &&
          msg.nextEligibleAt != null) {
        _messages[entry.key] = msg.copyWith(nextEligibleAt: null);
        count++;
      }
    }
    _emitOutgoingRowsChangedIfNeeded(count);
    return count;
  }

  @override
  Future<void> resetRetryStateForManualRetry(String id) async {
    final msg = _messages[id];
    if (msg == null || msg.isIncoming) return;
    if (msg.status != GroupMessage.statusSendFailed) return;
    _messages[id] = msg.copyWith(
      status: 'failed',
      retryAttemptCount: 0,
      nextEligibleAt: null,
    );
    _emitOutgoingRowsChangedIfNeeded(1);
  }

  @override
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    var count = 0;
    for (final entry in _messages.entries.toList()) {
      final msg = entry.value;
      final attemptedAt = msg.lastSendAttemptAt ?? msg.timestamp;
      if (!msg.isIncoming &&
          msg.status == 'sending' &&
          attemptedAt.isBefore(cutoff)) {
        _messages[entry.key] = msg.copyWith(status: 'failed');
        count++;
      }
    }
    _emitOutgoingRowsChangedIfNeeded(count);
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
    _emitOutgoingRowsChangedIfNeeded(count);
    return count;
  }

  @override
  Future<int> deleteMessagesForGroup(String groupId) async {
    final toRemove = _messages.entries
        .where((e) => e.value.groupId == groupId)
        .toList();
    for (final entry in toRemove) {
      _messages.remove(entry.key);
      _localDeletionTombstones.add(entry.key);
      _localDeletionGroupIds[entry.key] = entry.value.groupId;
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

  GroupThreadPreview _previewFor(String groupId) {
    final messages = _visibleMessages
        .where((message) => message.groupId == groupId)
        .toList();
    if (messages.isEmpty) return GroupThreadPreview(groupId: groupId);
    messages.sort(compareGroupMessagesDescending);
    DateTime? lastOutgoingAt;
    for (final message in messages) {
      if (!message.isIncoming) {
        final ts = message.timestamp;
        if (lastOutgoingAt == null || ts.isAfter(lastOutgoingAt)) {
          lastOutgoingAt = ts;
        }
      }
    }
    return GroupThreadPreview(
      groupId: groupId,
      messageCount: messages.length,
      unreadCount: messages
          .where((message) => message.isIncoming && message.readAt == null)
          .length,
      lastOutgoingAt: lastOutgoingAt,
      latestMessage: messages.first,
    );
  }

  @override
  Future<GroupThreadPreview> getGroupThreadPreview(String groupId) async =>
      _previewFor(groupId);

  @override
  Future<Map<String, GroupThreadPreview>> getGroupThreadPreviews(
    Iterable<String> groupIds,
  ) async {
    getGroupThreadPreviewsCallCount++;
    return {
      for (final groupId in groupIds.toSet()) groupId: _previewFor(groupId),
    };
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
              // 210b: mirrors dbLoadGroupMessagesWithFailedInboxStore — the
              // repush lane also self-heals 'queued_offline' rows.
              (m.status == 'sent' ||
                  m.status == 'pending' ||
                  m.status == 'queued_offline') &&
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
  Future<bool> completeInboxStoreRetry(GroupMessage expected) async {
    final current = _messages[expected.id];
    if (current == null || !_sameExactOutgoingRetryTuple(current, expected)) {
      return false;
    }
    final completed = current.copyWith(
      inboxStored: true,
      inboxRetryPayload: null,
      status: 'sent',
    );
    _messages[expected.id] = completed;
    _emitOutgoingStatusChangeIfNeeded(previous: current, saved: completed);
    return true;
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
