import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../../../features/groups/domain/models/group_pending_key_repair.dart';

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
    await db.insert('group_pending_key_repairs', row);
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_REPAIR_DB_INSERT_SUCCESS',
      details: {'id': _safeId(id)},
    );
    return true;
  }

  final current = existing.single;
  if (current['status'] != groupPendingKeyRepairStatusPendingKey) {
    return false;
  }

  await db.update(
    'group_pending_key_repairs',
    {
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
  final rows = await db.query(
    'group_pending_key_repairs',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupKeyRepairsForEpoch(
  Database db, {
  required String groupId,
  required int keyEpoch,
  int limit = 50,
}) {
  return db.query(
    'group_pending_key_repairs',
    where: 'group_id = ? AND key_epoch = ? AND status = ?',
    whereArgs: [groupId, keyEpoch, groupPendingKeyRepairStatusPendingKey],
    orderBy: 'created_at ASC, id ASC',
    limit: limit,
  );
}

Future<void> dbRecordGroupPendingKeyRepairAttempt(
  Database db,
  String id, {
  required String? lastError,
  required String updatedAt,
}) async {
  await db.rawUpdate(
    '''
UPDATE group_pending_key_repairs
SET attempts = attempts + 1,
    last_error = ?,
    updated_at = ?
WHERE id = ? AND status = ?
''',
    [lastError, updatedAt, id, groupPendingKeyRepairStatusPendingKey],
  );
}

Future<void> dbFinalizeGroupPendingKeyRepair(
  Database db,
  String id, {
  required String status,
  required String lastError,
  required String finalizedAt,
}) async {
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
WHERE id = ? AND finalized_at IS NULL
''',
    [status, lastError, lastError, finalizedAt, finalizedAt, id],
  );
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
