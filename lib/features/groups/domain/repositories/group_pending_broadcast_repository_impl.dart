import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

class GroupPendingBroadcastRepositoryImpl
    implements GroupPendingBroadcastRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsert;
  final Future<List<Map<String, Object?>>> Function(String groupId)
  dbLoadForGroup;
  final Future<List<Map<String, Object?>>> Function() dbLoadAll;
  final Future<int> Function(String groupId) dbCountForGroup;
  final Future<void> Function(String id) dbDelete;

  GroupPendingBroadcastRepositoryImpl({
    required this.dbInsert,
    required this.dbLoadForGroup,
    required this.dbLoadAll,
    required this.dbCountForGroup,
    required this.dbDelete,
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
}
