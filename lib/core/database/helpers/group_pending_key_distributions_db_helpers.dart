import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../../../features/groups/domain/models/group_pending_key_distribution.dart';

Future<bool> dbUpsertGroupPendingKeyDistribution(
  Database db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String;
  final existing = await db.query(
    'group_pending_key_distributions',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );

  if (existing.isEmpty) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_DISTRIBUTION_DB_INSERT_START',
      details: {'id': _safeId(id)},
    );
    await db.insert('group_pending_key_distributions', row);
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_DISTRIBUTION_DB_INSERT_SUCCESS',
      details: {'id': _safeId(id)},
    );
    return true;
  }

  final current = existing.single;
  if (current['status'] != groupPendingKeyDistributionStatusPending) {
    // Terminal (distributed / unreachable): a re-enqueue does not reopen it.
    return false;
  }

  // A later rotation re-deferred the same (group, peer): refresh the epoch
  // provenance + target binding, but DO NOT reset `attempts` (INV-D4: never mask
  // exhaustion).
  await db.update(
    'group_pending_key_distributions',
    {
      'key_epoch': row['key_epoch'] ?? current['key_epoch'],
      'transport_peer_id':
          row['transport_peer_id'] ?? current['transport_peer_id'],
      'device_id': row['device_id'] ?? current['device_id'],
      'updated_at': row['updated_at'],
    },
    where: 'id = ?',
    whereArgs: [id],
  );
  return false;
}

Future<Map<String, Object?>?> dbLoadGroupPendingKeyDistribution(
  Database db,
  String id,
) async {
  final rows = await db.query(
    'group_pending_key_distributions',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupKeyDistributionsForPeer(
  Database db, {
  required String peerId,
  String? groupId,
  int limit = 50,
}) {
  final where = StringBuffer('status = ? AND peer_id = ?');
  final args = <Object?>[groupPendingKeyDistributionStatusPending, peerId];
  if (groupId != null) {
    where.write(' AND group_id = ?');
    args.add(groupId);
  }
  return db.query(
    'group_pending_key_distributions',
    where: where.toString(),
    whereArgs: args,
    orderBy: 'created_at ASC, id ASC',
    limit: limit,
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupKeyDistributionsForGroup(
  Database db, {
  required String groupId,
  int limit = 50,
}) {
  return db.query(
    'group_pending_key_distributions',
    where: 'status = ? AND group_id = ?',
    whereArgs: [groupPendingKeyDistributionStatusPending, groupId],
    orderBy: 'created_at ASC, id ASC',
    limit: limit,
  );
}

Future<void> dbRecordGroupPendingKeyDistributionAttempt(
  Database db,
  String id, {
  required String? lastError,
  required String updatedAt,
}) async {
  await db.rawUpdate(
    '''
UPDATE group_pending_key_distributions
SET attempts = attempts + 1,
    last_error = ?,
    updated_at = ?
WHERE id = ? AND status = ?
''',
    [lastError, updatedAt, id, groupPendingKeyDistributionStatusPending],
  );
}

Future<void> dbFinalizeGroupPendingKeyDistribution(
  Database db,
  String id, {
  required String status,
  required String lastError,
  required String finalizedAt,
}) async {
  await db.rawUpdate(
    '''
UPDATE group_pending_key_distributions
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
