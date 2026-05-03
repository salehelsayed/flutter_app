import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../../../features/groups/domain/models/group_history_gap_repair.dart';

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
    await db.insert('group_history_gap_repairs', row);
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_HISTORY_GAP_REPAIR_DB_INSERT_SUCCESS',
      details: {'groupId': _safeId(groupId), 'gapId': _safeId(gapId)},
    );
    return true;
  }

  final current = existing.single;
  final currentStatus = current['status'] as String?;
  if (currentStatus == groupHistoryGapRepairStatusRepaired ||
      currentStatus == groupHistoryGapRepairStatusFailed) {
    return false;
  }

  await db.update(
    'group_history_gap_repairs',
    {
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
  await db.insert(
    'group_history_gap_repairs',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadGroupHistoryGapRepair(
  Database db, {
  required String groupId,
  required String gapId,
}) async {
  final rows = await db.query(
    'group_history_gap_repairs',
    where: 'group_id = ? AND gap_id = ?',
    whereArgs: [groupId, gapId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<Map<String, Object?>?> dbLoadLatestGroupHistoryGapRepair(
  Database db, {
  required String groupId,
}) async {
  final rows = await db.query(
    'group_history_gap_repairs',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'updated_at DESC, gap_id ASC',
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>> dbLoadVisibleGroupHistoryGapRepairs(
  Database db, {
  required String groupId,
  int limit = 20,
}) {
  return db.query(
    'group_history_gap_repairs',
    where: 'group_id = ? AND status IN (?, ?, ?)',
    whereArgs: [
      groupId,
      groupHistoryGapRepairStatusDetected,
      groupHistoryGapRepairStatusRepairing,
      groupHistoryGapRepairStatusFailed,
    ],
    orderBy: 'updated_at DESC, gap_id ASC',
    limit: limit,
  );
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
