import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/group_message.dart';
import '../models/group_message_receipt.dart';
import '../models/group_multi_device_policy.dart';
import '../models/group_thread_preview.dart';
import '../models/group_thread_summary.dart';
import '../utils/group_message_ordering.dart';
import 'group_thread_preview_repository.dart';
import 'group_thread_summary_repository.dart';
import 'group_message_repository.dart';

typedef RunGroupInboxPageTransaction =
    Future<void> Function({
      required String groupId,
      required String nextCursor,
      required Future<void> Function(GroupMessageRepository transactionRepo)
      apply,
      required List<GroupMessageReceipt> receipts,
      required List<String> markReadMessageIds,
    });

/// Implementation of GroupMessageRepository using constructor-injected DB helper functions.
class GroupMessageRepositoryImpl
    implements
        GroupMessageRepository,
        GroupThreadSummaryRepository,
        GroupThreadPreviewRepository,
        GroupMembershipRepairDeletionRepository,
        GroupOutgoingLocalMessageChangeSource {
  final Future<void> Function(Map<String, Object?> row) dbInsertGroupMessage;
  final Future<List<Map<String, Object?>>> Function(
    String groupId, {
    int limit,
    int offset,
  })
  dbLoadGroupMessagesPage;
  final Future<Map<String, Object?>?> Function(String id) dbLoadGroupMessage;
  final Future<Map<String, Object?>?> Function(
    String groupId,
    String senderPeerId,
    String logicalDeliveryId,
  )?
  dbLoadGroupMessageByLogicalDeliveryIdFn;
  final Future<Map<String, Object?>?> Function(String groupId)
  dbLoadLatestGroupMessage;
  final Future<String?> Function(String groupId, String senderPeerId)?
  dbLoadLatestRemovalTimestampForSenderFn;
  final Future<void> Function(String id, String status)
  dbUpdateGroupMessageStatus;
  final Future<int> Function(String groupId) dbCountGroupMessages;
  final Future<int> Function(String groupId) dbCountUnreadGroupMessages;
  final Future<int> Function() dbCountTotalUnreadGroupMessages;
  final Future<int> Function(String groupId) dbMarkGroupMessagesAsRead;
  final Future<void> Function(String id) dbDeleteGroupMessage;
  final Future<void> Function(String id)?
  dbDeleteGroupMessageForMembershipRepairFn;
  final Future<bool> Function(
    String groupId,
    String senderPeerId,
    String text,
    String timestamp,
  )
  dbExistsGroupMessageByContent;
  final Future<int> Function(String groupId) dbDeleteGroupMessagesForGroup;
  final Future<List<Map<String, Object?>>> Function(List<String> groupIds)
  dbLoadGroupThreadSummaries;
  // 161 db-persistence-5 (QUERY half): the batched preview aggregate (counts +
  // last_outgoing_at + latest row). NULLABLE with a per-id fallback so the
  // non-main.dart `GroupMessageRepositoryImpl(` callsites (tests / integration
  // harnesses) keep compiling untouched (round-3 F6).
  final Future<List<Map<String, Object?>>> Function(List<String> groupIds)?
  dbLoadGroupThreadPreviewsFn;
  final Future<List<Map<String, dynamic>>> Function()?
  dbLoadFailedOutgoingGroupMessagesFn;
  final Future<List<Map<String, dynamic>>> Function()?
  dbLoadRetryableOutgoingGroupMessagesFn;
  final Future<int> Function({DateTime? olderThan})?
  dbRecoverStuckSendingGroupMessagesFn;
  final Future<List<Map<String, dynamic>>> Function({int limit})?
  dbLoadGroupMessagesWithFailedInboxStore;
  final Future<void> Function(String id, {required bool stored})?
  dbUpdateGroupMessageInboxStoredFn;
  final Future<void> Function(String id, String? payload)?
  dbUpdateGroupMessageInboxRetryPayloadFn;
  final Future<void> Function(String id, String? envelope)?
  dbUpdateGroupMessageWireEnvelopeFn;
  final Future<void> Function(
    String id, {
    required int nextEligibleAtMs,
    required bool markTerminal,
  })?
  dbRecordGroupMessageRetryFailureFn;
  final Future<int> Function()? dbClearGroupMessageRetryBackoffFn;
  final Future<void> Function(String id)? dbResetGroupMessageRetryStateFn;
  final Future<String?> Function(String groupId)? dbLoadGroupInboxCursorFn;
  final Future<List<Map<String, Object?>>> Function(
    String groupId,
    String messageId, {
    String? receiptType,
  })?
  dbLoadGroupMessageReceiptsFn;
  final RunGroupInboxPageTransaction? dbRunGroupInboxPageTransactionFn;
  final StreamController<GroupOutgoingLocalMessageChange>
  _outgoingLocalMessageChangesController =
      StreamController<GroupOutgoingLocalMessageChange>.broadcast();

  GroupMessageRepositoryImpl({
    required this.dbInsertGroupMessage,
    required this.dbLoadGroupMessagesPage,
    required this.dbLoadGroupMessage,
    this.dbLoadGroupMessageByLogicalDeliveryIdFn,
    required this.dbLoadLatestGroupMessage,
    this.dbLoadLatestRemovalTimestampForSenderFn,
    required this.dbUpdateGroupMessageStatus,
    required this.dbCountGroupMessages,
    required this.dbCountUnreadGroupMessages,
    required this.dbCountTotalUnreadGroupMessages,
    required this.dbMarkGroupMessagesAsRead,
    required this.dbDeleteGroupMessage,
    this.dbDeleteGroupMessageForMembershipRepairFn,
    required this.dbExistsGroupMessageByContent,
    required this.dbDeleteGroupMessagesForGroup,
    required this.dbLoadGroupThreadSummaries,
    this.dbLoadGroupThreadPreviewsFn,
    this.dbLoadFailedOutgoingGroupMessagesFn,
    this.dbLoadRetryableOutgoingGroupMessagesFn,
    this.dbRecoverStuckSendingGroupMessagesFn,
    this.dbLoadGroupMessagesWithFailedInboxStore,
    this.dbUpdateGroupMessageInboxStoredFn,
    this.dbUpdateGroupMessageInboxRetryPayloadFn,
    this.dbUpdateGroupMessageWireEnvelopeFn,
    this.dbRecordGroupMessageRetryFailureFn,
    this.dbClearGroupMessageRetryBackoffFn,
    this.dbResetGroupMessageRetryStateFn,
    this.dbLoadGroupInboxCursorFn,
    this.dbLoadGroupMessageReceiptsFn,
    this.dbRunGroupInboxPageTransactionFn,
  });

  @override
  Stream<GroupOutgoingLocalMessageChange> get outgoingLocalMessageChanges =>
      _outgoingLocalMessageChangesController.stream;

  void _emitOutgoingStatusChangeIfNeeded({
    required GroupMessage? previous,
    required GroupMessage saved,
  }) {
    if (previous == null || saved.isIncoming) return;
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
  Future<bool> existsByMessageId(String messageId) async {
    final row = await dbLoadGroupMessage(messageId);
    return row != null;
  }

  @override
  Future<String?> getInboxCursor(String groupId) async {
    final fn = dbLoadGroupInboxCursorFn;
    return fn == null ? null : fn(groupId);
  }

  @override
  Future<List<GroupMessageReceipt>> getReceiptsForMessage(
    String groupId,
    String messageId, {
    String? receiptType,
  }) async {
    final fn = dbLoadGroupMessageReceiptsFn;
    if (fn == null) return const [];
    final rows = await fn(groupId, messageId, receiptType: receiptType);
    return rows.map(GroupMessageReceipt.fromMap).toList(growable: false);
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
    final fn = dbRunGroupInboxPageTransactionFn;
    if (fn == null) {
      throw StateError(
        'GroupMessageRepositoryImpl.runInboxPageTransaction requires '
        'dbRunGroupInboxPageTransactionFn',
      );
    }
    await fn(
      groupId: groupId,
      nextCursor: nextCursor,
      apply: apply,
      receipts: receipts,
      markReadMessageIds: markReadMessageIds,
    );
  }

  @override
  Future<List<GroupMessage>> getFailedOutgoingMessages() async {
    final fn = dbLoadFailedOutgoingGroupMessagesFn;
    if (fn == null) return const [];
    final rows = await fn();
    final messages = rows.map((row) => GroupMessage.fromMap(row));
    return orderGroupMessagesForTimeline(messages);
  }

  @override
  Future<List<GroupMessage>> getRetryableOutgoingMessages() async {
    final fn =
        dbLoadRetryableOutgoingGroupMessagesFn ??
        dbLoadFailedOutgoingGroupMessagesFn;
    if (fn == null) return const [];
    final rows = await fn();
    final messages = rows.map((row) => GroupMessage.fromMap(row));
    return orderGroupMessagesForTimeline(messages);
  }

  @override
  Future<void> recordRetryFailure(
    String id, {
    required DateTime nextEligibleAt,
    required bool markTerminal,
  }) async {
    final fn = dbRecordGroupMessageRetryFailureFn;
    if (fn == null) return;
    await fn(
      id,
      nextEligibleAtMs: nextEligibleAt.toUtc().millisecondsSinceEpoch,
      markTerminal: markTerminal,
    );
    _emitOutgoingRowsChangedIfNeeded(1);
  }

  @override
  Future<int> clearRetryBackoff() async {
    final fn = dbClearGroupMessageRetryBackoffFn;
    if (fn == null) return 0;
    final count = await fn();
    _emitOutgoingRowsChangedIfNeeded(count);
    return count;
  }

  @override
  Future<void> resetRetryStateForManualRetry(String id) async {
    final fn = dbResetGroupMessageRetryStateFn;
    if (fn == null) return;
    await fn(id);
    _emitOutgoingRowsChangedIfNeeded(1);
  }

  @override
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async {
    final fn = dbRecoverStuckSendingGroupMessagesFn;
    if (fn == null) return 0;
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    final count = await fn(olderThan: cutoff);
    _emitOutgoingRowsChangedIfNeeded(count);
    return count;
  }

  @override
  Future<int> transitionSendingToFailed() async {
    final fn = dbRecoverStuckSendingGroupMessagesFn;
    if (fn == null) return 0;
    final count = await fn();
    _emitOutgoingRowsChangedIfNeeded(count);
    return count;
  }

  @override
  Future<void> saveMessage(GroupMessage message) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MSG_REPO_SAVE_START',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
      },
    );

    try {
      final previousRow = await dbLoadGroupMessage(message.id);
      final previous = previousRow == null
          ? null
          : GroupMessage.fromMap(previousRow);
      await dbInsertGroupMessage(message.toMap());
      _emitOutgoingStatusChangeIfNeeded(previous: previous, saved: message);

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MSG_REPO_SAVE_SUCCESS',
        details: {
          'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MSG_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await dbLoadGroupMessagesPage(
      groupId,
      limit: limit,
      offset: offset,
    );
    final messages = rows.map((row) => GroupMessage.fromMap(row));
    return orderGroupMessagesForTimeline(messages);
  }

  @override
  Future<GroupMessage?> getMessage(String id) async {
    final row = await dbLoadGroupMessage(id);
    if (row == null) return null;
    return GroupMessage.fromMap(row);
  }

  @override
  Future<GroupMessage?> getMessageByLogicalDeliveryId(
    String groupId,
    String senderPeerId,
    String logicalDeliveryId,
  ) async {
    final normalizedLogicalDeliveryId = logicalDeliveryId.trim();
    if (normalizedLogicalDeliveryId.isEmpty) {
      return null;
    }
    final fn = dbLoadGroupMessageByLogicalDeliveryIdFn;
    if (fn == null) return null;
    final row = await fn(groupId, senderPeerId, normalizedLogicalDeliveryId);
    if (row == null) return null;
    return GroupMessage.fromMap(row);
  }

  @override
  Future<GroupMessage?> getLatestMessage(String groupId) async {
    final row = await dbLoadLatestGroupMessage(groupId);
    if (row == null) return null;
    return GroupMessage.fromMap(row);
  }

  @override
  Future<DateTime?> getLatestRemovalTimestampForSender(
    String groupId,
    String senderPeerId,
  ) async {
    final dbFn = dbLoadLatestRemovalTimestampForSenderFn;
    if (dbFn != null) {
      final raw = await dbFn(groupId, senderPeerId);
      return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    }

    final messages = await getMessagesPage(groupId, limit: 500);
    final removalPrefix = 'sys-member_removed:$groupId:$senderPeerId:';
    final cutoffPrefix =
        '$groupRemovalCutoffMessageIdPrefix:$groupId:$senderPeerId:';
    for (final message in messages.reversed) {
      if (message.id.startsWith(removalPrefix) ||
          message.id.startsWith(cutoffPrefix)) {
        return message.timestamp.toUtc();
      }
    }
    return null;
  }

  @override
  Future<DateTime?> getLatestSystemEventTimestampForTarget(
    String groupId, {
    required String eventType,
    required String targetId,
  }) async {
    final prefix = 'sys-$eventType:$groupId:$targetId:';
    const pageSize = 500;
    var offset = 0;
    DateTime? latest;
    while (true) {
      final messages = await getMessagesPage(
        groupId,
        limit: pageSize,
        offset: offset,
      );
      for (final message in messages) {
        if (!message.id.startsWith(prefix)) {
          continue;
        }
        final timestamp = message.timestamp.toUtc();
        if (latest == null || timestamp.isAfter(latest)) {
          latest = timestamp;
        }
      }
      if (messages.length < pageSize) {
        break;
      }
      offset += messages.length;
    }
    return latest;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final previousRow = await dbLoadGroupMessage(id);
    final previous = previousRow == null
        ? null
        : GroupMessage.fromMap(previousRow);
    await dbUpdateGroupMessageStatus(id, status);
    if (previous == null || previous.isIncoming || previous.status == status) {
      return;
    }
    _outgoingLocalMessageChangesController.add(
      GroupOutgoingLocalMessageChange.status(
        groupId: previous.groupId,
        messageId: previous.id,
        status: status,
      ),
    );
  }

  @override
  Future<int> getMessageCount(String groupId) async {
    return dbCountGroupMessages(groupId);
  }

  @override
  Future<int> getUnreadCount(String groupId) async {
    // Unread counts are device-local: each install tracks what *it* has seen.
    assert(isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet.unreadCounters));
    return dbCountUnreadGroupMessages(groupId);
  }

  @override
  Future<int> getTotalUnreadCount() async {
    assert(isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet.unreadCounters));
    return dbCountTotalUnreadGroupMessages();
  }

  @override
  Future<void> markAsRead(String groupId) async {
    assert(isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet.unreadCounters));
    await dbMarkGroupMessagesAsRead(groupId);
  }

  @override
  Future<void> deleteMessage(String id) async {
    await dbDeleteGroupMessage(id);
  }

  @override
  Future<void> deleteMessageForMembershipRepair(String id) async {
    final repairDelete = dbDeleteGroupMessageForMembershipRepairFn;
    if (repairDelete != null) {
      await repairDelete(id);
      return;
    }
    await dbDeleteGroupMessage(id);
  }

  @override
  Future<int> deleteMessagesForGroup(String groupId) async {
    return dbDeleteGroupMessagesForGroup(groupId);
  }

  @override
  Future<bool> existsByContent(
    String groupId,
    String senderPeerId,
    String text,
    DateTime timestamp,
  ) async {
    return dbExistsGroupMessageByContent(
      groupId,
      senderPeerId,
      text,
      timestamp.toUtc().toIso8601String(),
    );
  }

  @override
  Future<GroupThreadSummary> getGroupThreadSummary(String groupId) async {
    final summaries = await getGroupThreadSummaries([groupId]);
    return summaries[groupId] ?? GroupThreadSummary(groupId: groupId);
  }

  @override
  Future<Map<String, GroupThreadSummary>> getGroupThreadSummaries(
    Iterable<String> groupIds,
  ) async {
    final ids = groupIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, GroupThreadSummary>{};

    final rows = await dbLoadGroupThreadSummaries(ids);
    final summaries = <String, GroupThreadSummary>{};
    for (final row in rows) {
      final groupId = row['group_id'] as String;
      summaries[groupId] = GroupThreadSummary(
        groupId: groupId,
        unreadCount: row['unread_count'] as int? ?? 0,
        latestMessage: row['latest_id'] == null
            ? null
            : GroupMessage.fromMap({
                'id': row['latest_id'],
                'group_id': row['latest_group_id'],
                'sender_peer_id': row['latest_sender_peer_id'],
                'transport_peer_id': row['latest_transport_peer_id'],
                'sender_username': row['latest_sender_username'],
                'text': row['latest_text'],
                'timestamp': row['latest_timestamp'],
                'quoted_message_id': row['latest_quoted_message_id'],
                'key_generation': row['latest_key_generation'],
                'status': row['latest_status'],
                'is_incoming': row['latest_is_incoming'],
                'read_at': row['latest_read_at'],
                'created_at': row['latest_created_at'],
              }),
      );
    }
    for (final groupId in ids) {
      summaries.putIfAbsent(
        groupId,
        () => GroupThreadSummary(groupId: groupId),
      );
    }
    return summaries;
  }

  @override
  Future<GroupThreadPreview> getGroupThreadPreview(String groupId) async {
    final previews = await getGroupThreadPreviews([groupId]);
    return previews[groupId] ?? GroupThreadPreview(groupId: groupId);
  }

  @override
  Future<Map<String, GroupThreadPreview>> getGroupThreadPreviews(
    Iterable<String> groupIds,
  ) async {
    final ids = groupIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, GroupThreadPreview>{};

    final previewFn = dbLoadGroupThreadPreviewsFn;
    final previews = <String, GroupThreadPreview>{};
    if (previewFn != null) {
      final rows = await previewFn(ids);
      for (final row in rows) {
        final id = row['group_id'] as String;
        final lastOutgoingRaw = row['last_outgoing_at'] as String?;
        previews[id] = GroupThreadPreview(
          groupId: id,
          messageCount: row['message_count'] as int? ?? 0,
          unreadCount: row['unread_count'] as int? ?? 0,
          lastOutgoingAt: lastOutgoingRaw == null
              ? null
              : DateTime.tryParse(lastOutgoingRaw),
          latestMessage: row['latest_id'] == null
              ? null
              : GroupMessage.fromMap({
                  'id': row['latest_id'],
                  'group_id': row['latest_group_id'],
                  'sender_peer_id': row['latest_sender_peer_id'],
                  'transport_peer_id': row['latest_transport_peer_id'],
                  'sender_username': row['latest_sender_username'],
                  'text': row['latest_text'],
                  'timestamp': row['latest_timestamp'],
                  'quoted_message_id': row['latest_quoted_message_id'],
                  'key_generation': row['latest_key_generation'],
                  'status': row['latest_status'],
                  'is_incoming': row['latest_is_incoming'],
                  'read_at': row['latest_read_at'],
                  'created_at': row['latest_created_at'],
                }),
        );
      }
    } else {
      // Fallback for impls constructed without the batched helper: per-id
      // counts + latest (no last_outgoing_at) via the always-present helpers.
      for (final id in ids) {
        final latestRow = await dbLoadLatestGroupMessage(id);
        previews[id] = GroupThreadPreview(
          groupId: id,
          messageCount: await dbCountGroupMessages(id),
          unreadCount: await dbCountUnreadGroupMessages(id),
          latestMessage: latestRow == null
              ? null
              : GroupMessage.fromMap(latestRow),
        );
      }
    }
    for (final id in ids) {
      previews.putIfAbsent(id, () => GroupThreadPreview(groupId: id));
    }
    return previews;
  }

  @override
  Future<List<GroupMessage>> getMessagesWithFailedInboxStore({
    int limit = 20,
  }) async {
    final fn = dbLoadGroupMessagesWithFailedInboxStore;
    if (fn == null) return const [];
    final rows = await fn(limit: limit);
    return rows.map((row) => GroupMessage.fromMap(row)).toList();
  }

  @override
  Future<void> updateInboxStored(String id, {required bool stored}) async {
    final fn = dbUpdateGroupMessageInboxStoredFn;
    if (fn == null) return;
    await fn(id, stored: stored);
  }

  @override
  Future<void> updateInboxRetryPayload(String id, String? payload) async {
    final fn = dbUpdateGroupMessageInboxRetryPayloadFn;
    if (fn == null) return;
    await fn(id, payload);
  }

  @override
  Future<void> updateWireEnvelope(String id, String? envelope) async {
    final fn = dbUpdateGroupMessageWireEnvelopeFn;
    if (fn == null) return;
    await fn(id, envelope);
  }
}
