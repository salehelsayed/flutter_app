import '../../domain/models/group_pending_reaction.dart';
import '../../domain/repositories/group_pending_reaction_repository.dart';

class GroupPendingReactionRepositoryImpl
    implements GroupPendingReactionRepository {
  final Future<Map<String, Object?>> Function(Map<String, Object?> row)
  dbUpsertGroupPendingReaction;
  final Future<List<Map<String, Object?>>> Function({
    required String groupId,
    required String messageId,
  })
  dbLoadGroupPendingReactionsForMessage;
  final Future<List<Map<String, Object?>>> Function({int limit})
  dbLoadGroupPendingReactions;
  final Future<int> Function(String id) dbDeleteGroupPendingReaction;
  final Future<void> Function(String groupId, {required int maxRows})
  dbPruneGroupPendingReactions;
  final Future<void> Function({required String olderThanIso})
  dbDeleteExpiredGroupPendingReactions;

  GroupPendingReactionRepositoryImpl({
    required this.dbUpsertGroupPendingReaction,
    required this.dbLoadGroupPendingReactionsForMessage,
    required this.dbLoadGroupPendingReactions,
    required this.dbDeleteGroupPendingReaction,
    required this.dbPruneGroupPendingReactions,
    required this.dbDeleteExpiredGroupPendingReactions,
  });

  @override
  Future<GroupPendingReaction> savePendingReaction(
    GroupPendingReaction reaction,
  ) async {
    final row = await dbUpsertGroupPendingReaction(reaction.toMap());
    return GroupPendingReaction.fromMap(row);
  }

  @override
  Future<List<GroupPendingReaction>> getPendingReactionsForMessage({
    required String groupId,
    required String messageId,
  }) async {
    final rows = await dbLoadGroupPendingReactionsForMessage(
      groupId: groupId,
      messageId: messageId,
    );
    return rows.map(GroupPendingReaction.fromMap).toList();
  }

  @override
  Future<List<GroupPendingReaction>> getPendingReactions({
    int limit = 200,
  }) async {
    final rows = await dbLoadGroupPendingReactions(limit: limit);
    return rows.map(GroupPendingReaction.fromMap).toList();
  }

  @override
  Future<int> deletePendingReaction(String id) {
    return dbDeleteGroupPendingReaction(id);
  }

  @override
  Future<void> pruneGroup(String groupId, {required int maxRows}) {
    return dbPruneGroupPendingReactions(groupId, maxRows: maxRows);
  }

  @override
  Future<void> deleteExpired({required DateTime olderThan}) {
    return dbDeleteExpiredGroupPendingReactions(
      olderThanIso: olderThan.toUtc().toIso8601String(),
    );
  }
}
