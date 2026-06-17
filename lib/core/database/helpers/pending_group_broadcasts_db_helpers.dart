import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;

const _table = 'pending_group_broadcasts';

/// Inserts a pending broadcast, idempotently: a row sharing the same
/// `(group_id, source_message_id)` is left untouched (no duplicate re-push).
Future<void> dbInsertPendingGroupBroadcast(
  Database db,
  Map<String, Object?> row,
) async {
  final groupId = row['group_id'] as String;
  final sourceMessageId = row['source_message_id'] as String?;

  if (sourceMessageId != null && sourceMessageId.isNotEmpty) {
    final existing = await db.query(
      _table,
      where: 'group_id = ? AND source_message_id = ?',
      whereArgs: [groupId, sourceMessageId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'PENDING_GROUP_BROADCAST_DB_INSERT_DEDUP',
        details: {'groupId': _safeId(groupId)},
      );
      return;
    }
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_INSERT_START',
    details: {'groupId': _safeId(groupId)},
  );
  await db.insert(
    _table,
    row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_INSERT_SUCCESS',
    details: {'groupId': _safeId(groupId)},
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupBroadcastsForGroup(
  Database db,
  String groupId,
) async {
  return db.query(
    _table,
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'created_at ASC',
  );
}

Future<List<Map<String, Object?>>> dbLoadAllPendingGroupBroadcasts(
  Database db,
) async {
  return db.query(_table, orderBy: 'created_at ASC');
}

Future<int> dbCountPendingGroupBroadcastsForGroup(
  Database db,
  String groupId,
) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM $_table WHERE group_id = ?',
    [groupId],
  );
  return (rows.first['c'] as int?) ?? 0;
}

Future<void> dbDeletePendingGroupBroadcast(Database db, String id) async {
  await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_DELETE',
    details: {'id': _safeId(id)},
  );
}
