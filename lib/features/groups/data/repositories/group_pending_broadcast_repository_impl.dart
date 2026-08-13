import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

class GroupPendingBroadcastRepositoryImpl
    implements
        GroupPendingBroadcastRepository,
        GroupPendingBroadcastExactRepository,
        GroupPendingBroadcastProtectedRecipientRepository,
        GroupPendingBroadcastProtectedBatchRepository,
        GroupPendingBroadcastProtectedAbortRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsert;
  final Future<List<Map<String, Object?>>> Function(String groupId)
  dbLoadForGroup;
  final Future<List<Map<String, Object?>>> Function() dbLoadAll;
  final Future<int> Function(String groupId) dbCountForGroup;
  final Future<void> Function(String id) dbDelete;
  final Future<bool> Function(Map<String, Object?> expected)? dbDeleteIfExact;
  final Future<void> Function(String groupId)? dbDeleteForGroup;
  final Future<bool> Function({
    required Map<String, Object?> expected,
    required String recipientPeerId,
    required String updatedAt,
  })?
  dbRemoveRecipientIfExact;
  final Future<bool> Function({
    required String groupId,
    required List<Map<String, Object?>> rows,
    required String authorityPreparedSourcePeerId,
    required String authorityPreparedSourceEventId,
    required String authorityPreparedSourceTimestamp,
    required Map<String, Object?> authorityPreparedPayload,
  })?
  dbInsertProtectedBatch;
  final Future<ProtectedGroupAuthorityAbortResult> Function({
    required String groupId,
    required List<Map<String, Object?>> expectedRows,
    required String authorityPreparedSourcePeerId,
    required String authorityPreparedSourceEventId,
    required String authorityPreparedSourceTimestamp,
    required Map<String, Object?> authorityPreparedPayload,
    required String authorityAbortedSourcePeerId,
    required String authorityAbortedSourceEventId,
    required String authorityAbortedSourceTimestamp,
    required Map<String, Object?> authorityAbortedPayload,
    required String authorityCompleteSourceEventId,
  })?
  dbAbortProtectedBatch;

  GroupPendingBroadcastRepositoryImpl({
    required this.dbInsert,
    required this.dbLoadForGroup,
    required this.dbLoadAll,
    required this.dbCountForGroup,
    required this.dbDelete,
    this.dbDeleteIfExact,
    this.dbDeleteForGroup,
    this.dbRemoveRecipientIfExact,
    this.dbInsertProtectedBatch,
    this.dbAbortProtectedBatch,
  });

  @override
  Future<void> enqueue(GroupPendingBroadcast broadcast) =>
      dbInsert(broadcast.toMap());

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async {
    final rows = await dbLoadForGroup(groupId);
    return rows.map(GroupPendingBroadcast.fromMap).toList(growable: false);
  }

  @override
  Future<List<GroupPendingBroadcast>> all() async {
    final rows = await dbLoadAll();
    return rows.map(GroupPendingBroadcast.fromMap).toList(growable: false);
  }

  @override
  Future<int> countForGroup(String groupId) => dbCountForGroup(groupId);

  @override
  Future<void> remove(String id) => dbDelete(id);

  @override
  Future<bool> removeIfExact(GroupPendingBroadcast expected) async {
    final exact = dbDeleteIfExact;
    if (exact != null) return exact(expected.toMap());
    final rows = await forGroup(expected.groupId);
    GroupPendingBroadcast? current;
    for (final row in rows) {
      if (row.id == expected.id) {
        current = row;
        break;
      }
    }
    if (current == null || !sameExactGroupPendingBroadcast(current, expected)) {
      return false;
    }
    await remove(expected.id);
    return true;
  }

  @override
  Future<void> removeForGroup(String groupId) async {
    final deleteForGroup = dbDeleteForGroup;
    if (deleteForGroup != null) {
      await deleteForGroup(groupId);
      return;
    }
    final pending = await forGroup(groupId);
    for (final broadcast in pending) {
      await remove(broadcast.id);
    }
  }

  @override
  Future<bool> removeRecipientIfExact(
    GroupPendingBroadcast expected,
    String recipientPeerId,
  ) async {
    final removeRecipient = dbRemoveRecipientIfExact;
    if (removeRecipient == null) return false;
    return removeRecipient(
      expected: expected.toMap(),
      recipientPeerId: recipientPeerId,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<bool> enqueueProtectedBatch(
    List<GroupPendingBroadcast> rows, {
    required String groupId,
    required GroupPendingBroadcastAuthorityFact authorityPrepared,
  }) async {
    final insert = dbInsertProtectedBatch;
    if (insert == null || groupId.isEmpty) return false;
    return insert(
      groupId: groupId,
      rows: rows.map((row) => row.toMap()).toList(growable: false),
      authorityPreparedSourcePeerId: authorityPrepared.sourcePeerId,
      authorityPreparedSourceEventId: authorityPrepared.sourceEventId,
      authorityPreparedSourceTimestamp: authorityPrepared.sourceTimestamp,
      authorityPreparedPayload: authorityPrepared.payload,
    );
  }

  @override
  Future<ProtectedGroupAuthorityAbortResult> abortProtectedBatch(
    List<GroupPendingBroadcast> expectedRows, {
    required String groupId,
    required GroupPendingBroadcastAuthorityFact authorityPrepared,
    required GroupPendingBroadcastAuthorityFact authorityAborted,
    required String authorityCompleteSourceEventId,
  }) async {
    final abort = dbAbortProtectedBatch;
    if (abort == null || groupId.isEmpty) {
      return ProtectedGroupAuthorityAbortResult.conflict;
    }
    return abort(
      groupId: groupId,
      expectedRows: expectedRows
          .map((row) => row.toMap())
          .toList(growable: false),
      authorityPreparedSourcePeerId: authorityPrepared.sourcePeerId,
      authorityPreparedSourceEventId: authorityPrepared.sourceEventId,
      authorityPreparedSourceTimestamp: authorityPrepared.sourceTimestamp,
      authorityPreparedPayload: authorityPrepared.payload,
      authorityAbortedSourcePeerId: authorityAborted.sourcePeerId,
      authorityAbortedSourceEventId: authorityAborted.sourceEventId,
      authorityAbortedSourceTimestamp: authorityAborted.sourceTimestamp,
      authorityAbortedPayload: authorityAborted.payload,
      authorityCompleteSourceEventId: authorityCompleteSourceEventId,
    );
  }
}
