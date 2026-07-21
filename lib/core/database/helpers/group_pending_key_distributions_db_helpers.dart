import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import 'group_parent_write_guard.dart';
import '../../../features/groups/domain/models/group_pending_key_distribution.dart';

const _pendingKeyDistributionExactFields = <String>[
  'id',
  'group_id',
  'peer_id',
  'transport_peer_id',
  'device_id',
  'key_epoch',
  'status',
  'attempts',
  'last_error',
  'created_at',
  'updated_at',
  'finalized_at',
];

String get _pendingKeyDistributionExactWhere =>
    _pendingKeyDistributionExactFields
        .map((field) => '"$field" IS ?')
        .join(' AND ');

List<Object?> _pendingKeyDistributionExactArgs(Map<String, Object?> expected) =>
    _pendingKeyDistributionExactFields.map((field) => expected[field]).toList();

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
    final inserted = await dbInsertOrdinaryGroupOwnedRow(
      db,
      table: 'group_pending_key_distributions',
      row: row,
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_DISTRIBUTION_DB_INSERT_SUCCESS',
      details: {'id': _safeId(id)},
    );
    return inserted;
  }

  final current = existing.single;
  if (current['status'] != groupPendingKeyDistributionStatusPending) {
    // Terminal (distributed / unreachable): a re-enqueue does not reopen it.
    return false;
  }

  // A later rotation re-deferred the same (group, peer): refresh the epoch
  // provenance + target binding, but DO NOT reset `attempts` (INV-D4: never mask
  // exhaustion).
  await dbUpdateOrdinaryGroupOwnedRows(
    db,
    table: 'group_pending_key_distributions',
    groupId: row['group_id'] as String? ?? '',
    values: {
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

/// (Re)opens a distribution row to PENDING for re-delivery, OVERRIDING a terminal
/// (distributed / unreachable) status and resetting attempts/last_error/
/// finalized_at. Unlike [dbUpsertGroupPendingKeyDistribution] this deliberately
/// re-arms an exhausted/finalized row — it is for when the member's DEVICE SET
/// changed (a sibling device was admitted), so the prior exhaustion (which was
/// for the OLD device set) must not block re-distributing the current key to the
/// now-larger device set. NOT for stale rotation re-enqueues (those keep using
/// the exhaustion-preserving upsert).
Future<void> dbReopenGroupPendingKeyDistributionForRedelivery(
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
    await dbInsertOrdinaryGroupOwnedRow(
      db,
      table: 'group_pending_key_distributions',
      row: row,
    );
    return;
  }
  await dbUpdateOrdinaryGroupOwnedRows(
    db,
    table: 'group_pending_key_distributions',
    groupId: row['group_id'] as String? ?? '',
    values: {
      'status': groupPendingKeyDistributionStatusPending,
      'key_epoch': row['key_epoch'] ?? existing.single['key_epoch'],
      'transport_peer_id':
          row['transport_peer_id'] ?? existing.single['transport_peer_id'],
      'device_id': row['device_id'] ?? existing.single['device_id'],
      'attempts': 0,
      'last_error': null,
      'finalized_at': null,
      'updated_at': row['updated_at'],
    },
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<Map<String, Object?>?> dbLoadGroupPendingKeyDistribution(
  Database db,
  String id,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_distributions.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM group_pending_key_distributions '
    'WHERE id = ? AND $parent LIMIT 1',
    [id],
  );
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupKeyDistributionsForPeer(
  Database db, {
  required String peerId,
  String? groupId,
  int limit = 50,
}) async {
  final where = StringBuffer('status = ? AND peer_id = ?');
  final args = <Object?>[groupPendingKeyDistributionStatusPending, peerId];
  if (groupId != null) {
    where.write(' AND group_id = ?');
    args.add(groupId);
  }
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_distributions.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_key_distributions '
    'WHERE ${where.toString()} AND $parent '
    'ORDER BY created_at ASC, id ASC LIMIT ?',
    [...args, limit],
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupKeyDistributionsForGroup(
  Database db, {
  required String groupId,
  int limit = 50,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_distributions.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_pending_key_distributions '
    'WHERE status = ? AND group_id = ? AND $parent '
    'ORDER BY created_at ASC, id ASC LIMIT ?',
    [groupPendingKeyDistributionStatusPending, groupId, limit],
  );
}

Future<void> dbRecordGroupPendingKeyDistributionAttempt(
  Database db,
  String id, {
  required String? lastError,
  required String updatedAt,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_distributions.group_id',
  );
  await db.rawUpdate(
    '''
UPDATE group_pending_key_distributions
SET attempts = attempts + 1,
    last_error = ?,
    updated_at = ?
WHERE id = ? AND status = ? AND $parent
''',
    [lastError, updatedAt, id, groupPendingKeyDistributionStatusPending],
  );
}

Future<bool> dbRecordGroupPendingKeyDistributionAttemptIfExact(
  Database db,
  Map<String, Object?> expected, {
  required String? lastError,
  required String updatedAt,
}) async {
  final groupId = expected['group_id'] as String? ?? '';
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_distributions.group_id',
  );
  final updated = await db.rawUpdate(
    '''
UPDATE group_pending_key_distributions
SET attempts = attempts + 1,
    last_error = ?,
    updated_at = ?
WHERE ($_pendingKeyDistributionExactWhere) AND group_id = ? AND $parent
''',
    [
      lastError,
      updatedAt,
      ..._pendingKeyDistributionExactArgs(expected),
      groupId,
    ],
  );
  return updated == 1;
}

Future<void> dbFinalizeGroupPendingKeyDistribution(
  Database db,
  String id, {
  required String status,
  required String lastError,
  required String finalizedAt,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_distributions.group_id',
  );
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
WHERE id = ? AND finalized_at IS NULL AND $parent
''',
    [status, lastError, lastError, finalizedAt, finalizedAt, id],
  );
}

Future<bool> dbFinalizeGroupPendingKeyDistributionIfExact(
  Database db,
  Map<String, Object?> expected, {
  required String status,
  required String lastError,
  required String finalizedAt,
}) async {
  final groupId = expected['group_id'] as String? ?? '';
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_pending_key_distributions.group_id',
  );
  final updated = await db.rawUpdate(
    '''
UPDATE group_pending_key_distributions
SET status = ?,
    last_error = CASE WHEN ? = '' THEN last_error ELSE ? END,
    updated_at = ?,
    finalized_at = ?
WHERE ($_pendingKeyDistributionExactWhere) AND group_id = ? AND $parent
''',
    [
      status,
      lastError,
      lastError,
      finalizedAt,
      finalizedAt,
      ..._pendingKeyDistributionExactArgs(expected),
      groupId,
    ],
  );
  return updated == 1;
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
