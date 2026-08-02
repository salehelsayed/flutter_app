import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import 'group_parent_write_guard.dart';

/// Inserts a buffered reaction, or refreshes it in place when a row with the
/// same deterministic id already exists (dedup by reaction id / INV-R5).
Future<Map<String, Object?>> dbUpsertGroupPendingReaction(
  Database db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String;
  final groupId = row['group_id'] as String;
  final existing = await db.query(
    'group_pending_reactions',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );

  if (existing.isEmpty) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_REACTION_DB_INSERT_START',
      details: {'id': _safeId(id), 'groupId': _safeId(groupId)},
    );
    await dbInsertOrdinaryGroupOwnedRow(
      db,
      table: 'group_pending_reactions',
      row: row,
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_REACTION_DB_INSERT_SUCCESS',
      details: {'id': _safeId(id), 'groupId': _safeId(groupId)},
    );
    return row;
  }

  await dbUpdateOrdinaryGroupOwnedRows(
    db,
    table: 'group_pending_reactions',
    groupId: groupId,
    values: {
      'group_id': row['group_id'],
      'message_id': row['message_id'],
      'sender_peer_id': row['sender_peer_id'],
      'transport_peer_id': row['transport_peer_id'],
      'sender_device_id': row['sender_device_id'],
      'sender_public_key': row['sender_public_key'],
      'reaction_json': row['reaction_json'],
      'received_at': row['received_at'],
      'updated_at': row['updated_at'],
    },
    where: 'id = ?',
    whereArgs: [id],
  );
  final loaded = await db.query(
    'group_pending_reactions',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return loaded.isEmpty ? row : loaded.single;
}

/// Loads buffered reactions targeting a specific message, oldest-first.
Future<List<Map<String, Object?>>> dbLoadGroupPendingReactionsForMessage(
  Database db, {
  required String groupId,
  required String messageId,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_reactions.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_reactions '
    'WHERE group_id = ? AND message_id = ? AND $parent '
    'ORDER BY received_at ASC, id ASC',
    [groupId, messageId],
  );
}

/// Loads all buffered reactions, oldest-first (used by the startup flush).
Future<List<Map<String, Object?>>> dbLoadGroupPendingReactions(
  Database db, {
  int limit = 200,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_reactions.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_reactions '
    'WHERE $parent ORDER BY received_at ASC, id ASC LIMIT ?',
    [limit],
  );
}

/// Deletes a buffered reaction by id after terminal handling succeeds. Returns
/// the number of rows removed; the application-layer in-process claim prevents
/// overlapping flushes without sacrificing crash retryability (INV-R5).
Future<int> dbDeleteGroupPendingReaction(Database db, String id) {
  return db.delete('group_pending_reactions', where: 'id = ?', whereArgs: [id]);
}

/// Evicts oldest rows beyond [maxRows] for a group (per-group cap / INV-R5).
Future<void> dbPruneGroupPendingReactions(
  Database db,
  String groupId, {
  required int maxRows,
}) async {
  if (maxRows < 1) return;
  await db.rawDelete(
    '''
DELETE FROM group_pending_reactions
WHERE group_id = ?
  AND id IN (
    SELECT id
    FROM group_pending_reactions
    WHERE group_id = ?
    ORDER BY received_at DESC, id DESC
    LIMIT -1 OFFSET ?
  )
''',
    [groupId, groupId, maxRows],
  );
}

/// Deletes buffered reactions older than [olderThanIso] (TTL / INV-R5).
Future<void> dbDeleteExpiredGroupPendingReactions(
  Database db, {
  required String olderThanIso,
}) async {
  await db.delete(
    'group_pending_reactions',
    where: 'received_at < ?',
    whereArgs: [olderThanIso],
  );
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
