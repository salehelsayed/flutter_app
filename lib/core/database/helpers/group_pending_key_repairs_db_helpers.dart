import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import 'group_parent_write_guard.dart';
import '../../../features/groups/domain/models/group_pending_key_repair.dart';

const _pendingKeyRepairExactFields = <String>[
  'id',
  'group_id',
  'message_id',
  'sender_peer_id',
  'transport_peer_id',
  'payload_type',
  'key_epoch',
  'replay_envelope_json',
  'status',
  'trigger_count',
  'attempts',
  'last_error',
  'created_at',
  'updated_at',
  'finalized_at',
];

String get _pendingKeyRepairExactWhere =>
    _pendingKeyRepairExactFields.map((field) => '"$field" IS ?').join(' AND ');

List<Object?> _pendingKeyRepairExactArgs(Map<String, Object?> expected) =>
    _pendingKeyRepairExactFields.map((field) => expected[field]).toList();

Future<bool> dbUpsertGroupPendingKeyRepair(
  Database db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String;
  final existing = await db.query(
    'group_pending_key_repairs',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );

  if (existing.isEmpty) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_REPAIR_DB_INSERT_START',
      details: {'id': _safeId(id)},
    );
    final inserted = await dbInsertOrdinaryGroupOwnedRow(
      db,
      table: 'group_pending_key_repairs',
      row: row,
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_REPAIR_DB_INSERT_SUCCESS',
      details: {'id': _safeId(id)},
    );
    return inserted;
  }

  final current = existing.single;
  if (current['status'] != groupPendingKeyRepairStatusPendingKey) {
    return false;
  }

  await dbUpdateOrdinaryGroupOwnedRows(
    db,
    table: 'group_pending_key_repairs',
    groupId: row['group_id'] as String? ?? '',
    values: {
      'sender_peer_id': row['sender_peer_id'] ?? current['sender_peer_id'],
      'transport_peer_id':
          row['transport_peer_id'] ?? current['transport_peer_id'],
      'replay_envelope_json':
          current['replay_envelope_json'] ?? row['replay_envelope_json'],
      'updated_at': row['updated_at'],
    },
    where: 'id = ?',
    whereArgs: [id],
  );
  return false;
}

Future<Map<String, Object?>?> dbLoadGroupPendingKeyRepair(
  Database db,
  String id,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM group_pending_key_repairs '
    'WHERE id = ? AND $parent LIMIT 1',
    [id],
  );
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupKeyRepairsForEpoch(
  Database db, {
  required String groupId,
  required int keyEpoch,
  int limit = 50,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_key_repairs '
    'WHERE group_id = ? AND key_epoch = ? AND status = ? AND $parent '
    'ORDER BY created_at ASC, id ASC LIMIT ?',
    [groupId, keyEpoch, groupPendingKeyRepairStatusPendingKey, limit],
  );
}

Future<List<Map<String, Object?>>> dbLoadAllPendingGroupKeyRepairs(
  Database db, {
  int limit = 200,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_key_repairs '
    'WHERE status = ? AND $parent '
    'ORDER BY created_at ASC, id ASC LIMIT ?',
    [groupPendingKeyRepairStatusPendingKey, limit],
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupKeyRepairsForGroup(
  Database db, {
  required String groupId,
  int limit = 100,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_key_repairs '
    'WHERE group_id = ? AND status = ? AND $parent '
    'ORDER BY created_at ASC, id ASC LIMIT ?',
    [groupId, groupPendingKeyRepairStatusPendingKey, limit],
  );
}

Future<void> dbDeleteGroupPendingKeyRepair(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_PENDING_KEY_REPAIR_DB_DELETE',
    details: {'id': _safeId(id)},
  );
  await db.delete(
    'group_pending_key_repairs',
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<bool> dbDeleteGroupPendingKeyRepairIfExact(
  Database db,
  Map<String, Object?> expected,
) async {
  final groupId = expected['group_id'] as String? ?? '';
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  final deleted = await db.delete(
    'group_pending_key_repairs',
    where: '($_pendingKeyRepairExactWhere) AND group_id = ? AND $parent',
    whereArgs: [..._pendingKeyRepairExactArgs(expected), groupId],
  );
  return deleted == 1;
}

Future<void> dbRecordGroupPendingKeyRepairAttempt(
  Database db,
  String id, {
  required String? lastError,
  required String updatedAt,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  await db.rawUpdate(
    '''
UPDATE group_pending_key_repairs
SET attempts = attempts + 1,
    last_error = ?,
    updated_at = ?
WHERE id = ? AND status = ? AND $parent
''',
    [lastError, updatedAt, id, groupPendingKeyRepairStatusPendingKey],
  );
}

Future<bool> dbRecordGroupPendingKeyRepairAttemptIfExact(
  Database db,
  Map<String, Object?> expected, {
  required String? lastError,
  required String updatedAt,
}) async {
  final groupId = expected['group_id'] as String? ?? '';
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  final updated = await db.rawUpdate(
    '''
UPDATE group_pending_key_repairs
SET attempts = attempts + 1,
    last_error = ?,
    updated_at = ?
WHERE ($_pendingKeyRepairExactWhere) AND group_id = ? AND $parent
''',
    [lastError, updatedAt, ..._pendingKeyRepairExactArgs(expected), groupId],
  );
  return updated == 1;
}

Future<void> dbFinalizeGroupPendingKeyRepair(
  Database db,
  String id, {
  required String status,
  required String lastError,
  required String finalizedAt,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  await db.rawUpdate(
    '''
UPDATE group_pending_key_repairs
SET status = ?,
    last_error = CASE
      WHEN ? = '' THEN last_error
      ELSE ?
    END,
    updated_at = ?,
    finalized_at = ?
WHERE id = ? AND finalized_at IS NULL AND $parent
''',
    [status, lastError, lastError, finalizedAt, finalizedAt, id],
  );
}

Future<bool> dbFinalizeGroupPendingKeyRepairIfExact(
  Database db,
  Map<String, Object?> expected, {
  required String status,
  required String lastError,
  required String finalizedAt,
}) async {
  final groupId = expected['group_id'] as String? ?? '';
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_repairs.group_id',
  );
  final updated = await db.rawUpdate(
    '''
UPDATE group_pending_key_repairs
SET status = ?,
    last_error = CASE WHEN ? = '' THEN last_error ELSE ? END,
    updated_at = ?,
    finalized_at = ?
WHERE ($_pendingKeyRepairExactWhere) AND group_id = ? AND $parent
''',
    [
      status,
      lastError,
      lastError,
      finalizedAt,
      finalizedAt,
      ..._pendingKeyRepairExactArgs(expected),
      groupId,
    ],
  );
  return updated == 1;
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
