import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import 'group_parent_write_guard.dart';
import '../../../features/groups/domain/models/group_history_gap_repair.dart';

const _historyGapRepairExactFields = <String>[
  'group_id',
  'gap_id',
  'missing_after_message_id',
  'missing_before_message_id',
  'expected_range_hash',
  'expected_head_message_id',
  'candidate_source_peer_ids_json',
  'attempted_source_peer_ids_json',
  'repaired_message_ids_json',
  'status',
  'failure_reason',
  'created_at',
  'updated_at',
  'repaired_at',
  'failed_at',
];

String get _historyGapRepairExactWhere =>
    _historyGapRepairExactFields.map((field) => '"$field" IS ?').join(' AND ');

List<Object?> _historyGapRepairExactArgs(Map<String, Object?> expected) =>
    _historyGapRepairExactFields.map((field) => expected[field]).toList();

Future<bool> dbUpsertGroupHistoryGapRepair(
  Database db,
  Map<String, Object?> row,
) async {
  final groupId = row['group_id'] as String;
  final gapId = row['gap_id'] as String;
  final existing = await db.query(
    'group_history_gap_repairs',
    where: 'group_id = ? AND gap_id = ?',
    whereArgs: [groupId, gapId],
    limit: 1,
  );

  if (existing.isEmpty) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_HISTORY_GAP_REPAIR_DB_INSERT_START',
      details: {'groupId': _safeId(groupId), 'gapId': _safeId(gapId)},
    );
    final inserted = await dbInsertOrdinaryGroupOwnedRow(
      db,
      table: 'group_history_gap_repairs',
      row: row,
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_HISTORY_GAP_REPAIR_DB_INSERT_SUCCESS',
      details: {'groupId': _safeId(groupId), 'gapId': _safeId(gapId)},
    );
    return inserted;
  }

  final current = existing.single;
  final currentStatus = current['status'] as String?;
  if (currentStatus == groupHistoryGapRepairStatusRepaired ||
      currentStatus == groupHistoryGapRepairStatusFailed) {
    return false;
  }

  await dbUpdateOrdinaryGroupOwnedRows(
    db,
    table: 'group_history_gap_repairs',
    groupId: groupId,
    values: {
      'missing_after_message_id': row['missing_after_message_id'],
      'missing_before_message_id': row['missing_before_message_id'],
      'expected_range_hash': row['expected_range_hash'],
      'expected_head_message_id': row['expected_head_message_id'],
      'candidate_source_peer_ids_json': row['candidate_source_peer_ids_json'],
      'updated_at': row['updated_at'],
    },
    where: 'group_id = ? AND gap_id = ?',
    whereArgs: [groupId, gapId],
  );
  return false;
}

Future<void> dbSaveGroupHistoryGapRepair(
  Database db,
  Map<String, Object?> row,
) async {
  await dbInsertOrdinaryGroupOwnedRow(
    db,
    table: 'group_history_gap_repairs',
    row: row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<bool> dbReplaceGroupHistoryGapRepairIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> replacement,
}) async {
  final groupId = expected['group_id'] as String? ?? '';
  final gapId = expected['gap_id'] as String? ?? '';
  if (groupId.isEmpty ||
      gapId.isEmpty ||
      replacement['group_id'] != groupId ||
      replacement['gap_id'] != gapId) {
    return false;
  }
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_history_gap_repairs.group_id',
  );
  final values = <String, Object?>{
    for (final field in _historyGapRepairExactFields)
      if (field != 'group_id' && field != 'gap_id') field: replacement[field],
  };
  final updated = await db.update(
    'group_history_gap_repairs',
    values,
    where:
        '($_historyGapRepairExactWhere) AND group_id = ? AND gap_id = ? AND $parent',
    whereArgs: [..._historyGapRepairExactArgs(expected), groupId, gapId],
  );
  return updated == 1;
}

Future<Map<String, Object?>?> dbLoadGroupHistoryGapRepair(
  Database db, {
  required String groupId,
  required String gapId,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_history_gap_repairs.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM group_history_gap_repairs '
    'WHERE group_id = ? AND gap_id = ? AND $parent LIMIT 1',
    [groupId, gapId],
  );
  return rows.isEmpty ? null : rows.single;
}

Future<Map<String, Object?>?> dbLoadLatestGroupHistoryGapRepair(
  Database db, {
  required String groupId,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_history_gap_repairs.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM group_history_gap_repairs '
    'WHERE group_id = ? AND $parent '
    'ORDER BY updated_at DESC, gap_id ASC LIMIT 1',
    [groupId],
  );
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>> dbLoadVisibleGroupHistoryGapRepairs(
  Database db, {
  required String groupId,
  int limit = 20,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_history_gap_repairs.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM group_history_gap_repairs '
    'WHERE group_id = ? AND status IN (?, ?, ?) AND $parent '
    'ORDER BY updated_at DESC, gap_id ASC LIMIT ?',
    [
      groupId,
      groupHistoryGapRepairStatusDetected,
      groupHistoryGapRepairStatusRepairing,
      groupHistoryGapRepairStatusFailed,
      limit,
    ],
  );
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
