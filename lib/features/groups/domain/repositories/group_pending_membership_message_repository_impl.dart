import '../models/group_pending_membership_message.dart';
import 'group_pending_membership_message_repository.dart';

class GroupPendingMembershipMessageRepositoryImpl
    implements GroupPendingMembershipMessageRepository {
  final Future<Map<String, Object?>> Function(Map<String, Object?> row)
  dbUpsertGroupPendingMembershipMessage;
  final Future<List<Map<String, Object?>>> Function({int limit})
  dbLoadGroupPendingMembershipMessages;
  final Future<List<Map<String, Object?>>> Function({
    required String groupId,
    required Iterable<String> senderPeerIds,
    int limit,
  })
  dbLoadGroupPendingMembershipMessagesForSenders;
  final Future<void> Function(String id) dbDeleteGroupPendingMembershipMessage;
  final Future<void> Function({
    required String groupId,
    required String messageId,
  })
  dbDeleteGroupPendingMembershipMessageByGroupAndMessageId;
  final Future<void> Function(String groupId, {required int maxRows})
  dbPruneGroupPendingMembershipMessages;

  GroupPendingMembershipMessageRepositoryImpl({
    required this.dbUpsertGroupPendingMembershipMessage,
    required this.dbLoadGroupPendingMembershipMessages,
    required this.dbLoadGroupPendingMembershipMessagesForSenders,
    required this.dbDeleteGroupPendingMembershipMessage,
    required this.dbDeleteGroupPendingMembershipMessageByGroupAndMessageId,
    required this.dbPruneGroupPendingMembershipMessages,
  });

  @override
  Future<GroupPendingMembershipMessage> savePendingMessage(
    GroupPendingMembershipMessage message,
  ) async {
    final row = await dbUpsertGroupPendingMembershipMessage(message.toMap());
    return GroupPendingMembershipMessage.fromMap(row);
  }

  @override
  Future<List<GroupPendingMembershipMessage>> getPendingMessages({
    int limit = 200,
  }) async {
    final rows = await dbLoadGroupPendingMembershipMessages(limit: limit);
    return rows.map(GroupPendingMembershipMessage.fromMap).toList();
  }

  @override
  Future<List<GroupPendingMembershipMessage>>
  getPendingMessagesForGroupAndSenders({
    required String groupId,
    required Iterable<String> senderPeerIds,
    int limit = 50,
  }) async {
    final rows = await dbLoadGroupPendingMembershipMessagesForSenders(
      groupId: groupId,
      senderPeerIds: senderPeerIds,
      limit: limit,
    );
    return rows.map(GroupPendingMembershipMessage.fromMap).toList();
  }

  @override
  Future<void> deletePendingMessage(String id) {
    return dbDeleteGroupPendingMembershipMessage(id);
  }

  @override
  Future<void> deletePendingMessageByGroupAndMessageId({
    required String groupId,
    required String messageId,
  }) {
    return dbDeleteGroupPendingMembershipMessageByGroupAndMessageId(
      groupId: groupId,
      messageId: messageId,
    );
  }

  @override
  Future<void> pruneGroup(String groupId, {required int maxRows}) {
    return dbPruneGroupPendingMembershipMessages(groupId, maxRows: maxRows);
  }
}
