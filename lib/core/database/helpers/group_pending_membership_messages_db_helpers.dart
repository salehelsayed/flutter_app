import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import 'group_parent_write_guard.dart';

Future<Map<String, Object?>> dbUpsertGroupPendingMembershipMessage(
  Database db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String;
  final groupId = row['group_id'] as String;
  final messageId = row['message_id'] as String?;
  final existing = messageId != null && messageId.isNotEmpty
      ? await db.query(
          'group_pending_membership_messages',
          where: 'group_id = ? AND message_id = ?',
          whereArgs: [groupId, messageId],
          limit: 1,
        )
      : await db.query(
          'group_pending_membership_messages',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );

  if (existing.isEmpty) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_MEMBERSHIP_MESSAGE_DB_INSERT_START',
      details: {'id': _safeId(id), 'groupId': _safeId(groupId)},
    );
    await dbInsertOrdinaryGroupOwnedRow(
      db,
      table: 'group_pending_membership_messages',
      row: row,
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_MEMBERSHIP_MESSAGE_DB_INSERT_SUCCESS',
      details: {'id': _safeId(id), 'groupId': _safeId(groupId)},
    );
    return row;
  }

  final existingRow = existing.single;
  final existingId = existingRow['id'] as String;
  await dbUpdateOrdinaryGroupOwnedRows(
    db,
    table: 'group_pending_membership_messages',
    groupId: groupId,
    values: {
      'sender_peer_id': row['sender_peer_id'],
      'message_id': row['message_id'],
      'payload_json': row['payload_json'],
      'received_at': row['received_at'],
      'updated_at': row['updated_at'],
    },
    where: 'id = ?',
    whereArgs: [existingId],
  );
  final loaded = await db.query(
    'group_pending_membership_messages',
    where: 'id = ?',
    whereArgs: [existingId],
    limit: 1,
  );
  return loaded.isEmpty ? row : loaded.single;
}

Future<List<Map<String, Object?>>> dbLoadGroupPendingMembershipMessages(
  Database db, {
  int limit = 200,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_membership_messages.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_membership_messages '
    'WHERE $parent ORDER BY received_at ASC, id ASC LIMIT ?',
    [limit],
  );
}

Future<List<Map<String, Object?>>>
dbLoadGroupPendingMembershipMessagesForSenders(
  Database db, {
  required String groupId,
  required Iterable<String> senderPeerIds,
  int limit = 50,
}) async {
  final senders = senderPeerIds
      .where((sender) => sender.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (senders.isEmpty) return Future.value(const <Map<String, Object?>>[]);
  final placeholders = List.filled(senders.length, '?').join(', ');
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_membership_messages.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_membership_messages '
    'WHERE group_id = ? AND sender_peer_id IN ($placeholders) '
    'AND $parent ORDER BY received_at ASC, id ASC LIMIT ?',
    [groupId, ...senders, limit],
  );
}

Future<void> dbDeleteGroupPendingMembershipMessage(
  Database db,
  String id,
) async {
  await db.delete(
    'group_pending_membership_messages',
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<void> dbDeleteGroupPendingMembershipMessageByGroupAndMessageId(
  Database db, {
  required String groupId,
  required String messageId,
}) async {
  await db.delete(
    'group_pending_membership_messages',
    where: 'group_id = ? AND message_id = ?',
    whereArgs: [groupId, messageId],
  );
}

Future<void> dbPruneGroupPendingMembershipMessages(
  Database db,
  String groupId, {
  required int maxRows,
}) async {
  if (maxRows < 1) return;
  await db.rawDelete(
    '''
DELETE FROM group_pending_membership_messages
WHERE group_id = ?
  AND id IN (
    SELECT id
    FROM group_pending_membership_messages
    WHERE group_id = ?
    ORDER BY received_at DESC, id DESC
    LIMIT -1 OFFSET ?
  )
''',
    [groupId, groupId, maxRows],
  );
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
