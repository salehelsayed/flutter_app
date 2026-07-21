import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

class GroupPendingBroadcastRepositoryImpl
    implements
        GroupPendingBroadcastRepository,
        GroupPendingBroadcastExactRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsert;
  final Future<List<Map<String, Object?>>> Function(String groupId)
  dbLoadForGroup;
  final Future<List<Map<String, Object?>>> Function() dbLoadAll;
  final Future<int> Function(String groupId) dbCountForGroup;
  final Future<void> Function(String id) dbDelete;
  final Future<bool> Function(Map<String, Object?> expected)? dbDeleteIfExact;
  final Future<void> Function(String groupId)? dbDeleteForGroup;

  GroupPendingBroadcastRepositoryImpl({
    required this.dbInsert,
    required this.dbLoadForGroup,
    required this.dbLoadAll,
    required this.dbCountForGroup,
    required this.dbDelete,
    this.dbDeleteIfExact,
    this.dbDeleteForGroup,
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
}
