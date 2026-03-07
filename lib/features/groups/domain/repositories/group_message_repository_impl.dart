import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/group_message.dart';
import '../models/group_thread_summary.dart';
import 'group_thread_summary_repository.dart';
import 'group_message_repository.dart';

/// Implementation of GroupMessageRepository using constructor-injected DB helper functions.
class GroupMessageRepositoryImpl
    implements GroupMessageRepository, GroupThreadSummaryRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertGroupMessage;
  final Future<List<Map<String, Object?>>> Function(
    String groupId, {
    int limit,
    int offset,
  }) dbLoadGroupMessagesPage;
  final Future<Map<String, Object?>?> Function(String id) dbLoadGroupMessage;
  final Future<Map<String, Object?>?> Function(String groupId)
      dbLoadLatestGroupMessage;
  final Future<void> Function(String id, String status)
      dbUpdateGroupMessageStatus;
  final Future<int> Function(String groupId) dbCountGroupMessages;
  final Future<int> Function(String groupId) dbCountUnreadGroupMessages;
  final Future<int> Function() dbCountTotalUnreadGroupMessages;
  final Future<int> Function(String groupId) dbMarkGroupMessagesAsRead;
  final Future<void> Function(String id) dbDeleteGroupMessage;
  final Future<bool> Function(
          String groupId, String senderPeerId, String text, String timestamp)
      dbExistsGroupMessageByContent;
  final Future<int> Function(String groupId) dbDeleteGroupMessagesForGroup;
  final Future<List<Map<String, Object?>>> Function(List<String> groupIds)
      dbLoadGroupThreadSummaries;

  GroupMessageRepositoryImpl({
    required this.dbInsertGroupMessage,
    required this.dbLoadGroupMessagesPage,
    required this.dbLoadGroupMessage,
    required this.dbLoadLatestGroupMessage,
    required this.dbUpdateGroupMessageStatus,
    required this.dbCountGroupMessages,
    required this.dbCountUnreadGroupMessages,
    required this.dbCountTotalUnreadGroupMessages,
    required this.dbMarkGroupMessagesAsRead,
    required this.dbDeleteGroupMessage,
    required this.dbExistsGroupMessageByContent,
    required this.dbDeleteGroupMessagesForGroup,
    required this.dbLoadGroupThreadSummaries,
  });

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
      await dbInsertGroupMessage(message.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MSG_REPO_SAVE_SUCCESS',
        details: {
          'id':
              message.id.length > 8 ? message.id.substring(0, 8) : message.id,
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
    return rows.map((row) => GroupMessage.fromMap(row)).toList();
  }

  @override
  Future<GroupMessage?> getMessage(String id) async {
    final row = await dbLoadGroupMessage(id);
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
  Future<void> updateMessageStatus(String id, String status) async {
    await dbUpdateGroupMessageStatus(id, status);
  }

  @override
  Future<int> getMessageCount(String groupId) async {
    return dbCountGroupMessages(groupId);
  }

  @override
  Future<int> getUnreadCount(String groupId) async {
    return dbCountUnreadGroupMessages(groupId);
  }

  @override
  Future<int> getTotalUnreadCount() async {
    return dbCountTotalUnreadGroupMessages();
  }

  @override
  Future<void> markAsRead(String groupId) async {
    await dbMarkGroupMessagesAsRead(groupId);
  }

  @override
  Future<void> deleteMessage(String id) async {
    await dbDeleteGroupMessage(id);
  }

  @override
  Future<int> deleteMessagesForGroup(String groupId) async {
    return dbDeleteGroupMessagesForGroup(groupId);
  }

  @override
  Future<bool> existsByContent(
      String groupId, String senderPeerId, String text, DateTime timestamp) async {
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
                'sender_username': row['latest_sender_username'],
                'text': row['latest_text'],
                'timestamp': row['latest_timestamp'],
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
}
