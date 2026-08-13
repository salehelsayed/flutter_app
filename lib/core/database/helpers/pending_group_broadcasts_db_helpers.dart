import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'group_exit_intents_db_helpers.dart';
import 'group_parent_write_guard.dart';

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;

const _table = 'pending_group_broadcasts';
const _pendingBroadcastExactFields = <String>[
  'id',
  'group_id',
  'kind',
  'sys_text',
  'recipient_peer_ids',
  'event_at',
  'source_message_id',
  'created_at',
  'updated_at',
];

String get _pendingBroadcastExactWhere =>
    _pendingBroadcastExactFields.map((field) => '"$field" IS ?').join(' AND ');

/// Inserts a pending broadcast, idempotently: a row sharing the same
/// `(group_id, source_message_id)` is left untouched (no duplicate re-push).
Future<void> dbInsertPendingGroupBroadcast(
  Database db,
  Map<String, Object?> row,
) async {
  await dbWriteTransaction(
    db,
    (transaction) =>
        dbInsertPendingGroupBroadcastWithExecutor(transaction, row),
  );
}

/// Commits a frozen physical-recipient authority set as one durable fact.
/// Any conflicting existing target rolls the whole set back.
Future<bool> dbInsertPendingGroupBroadcastsAtomically(
  Database db,
  List<Map<String, Object?>> rows,
) async {
  if (rows.isEmpty) return false;
  try {
    return await dbWriteTransaction(db, (transaction) async {
      for (final row in rows) {
        await dbInsertPendingGroupBroadcastWithExecutor(transaction, row);
        final existing = await transaction.query(
          _table,
          where: 'group_id = ? AND source_message_id = ?',
          whereArgs: <Object?>[row['group_id'], row['source_message_id']],
          limit: 1,
        );
        if (existing.length != 1 ||
            !_samePendingBroadcastRow(existing.single, row)) {
          throw StateError('protected authority row conflict');
        }
      }
      return true;
    });
  } catch (_) {
    return false;
  }
}

bool _samePendingBroadcastRow(
  Map<String, Object?> existing,
  Map<String, Object?> expected,
) {
  for (final field in _pendingBroadcastExactFields) {
    if (existing[field] != expected[field]) return false;
  }
  return true;
}

/// Transaction-body variant for atomic authority producers.
Future<void> dbInsertPendingGroupBroadcastWithExecutor(
  DatabaseExecutor transaction,
  Map<String, Object?> row,
) async {
  final groupId = row['group_id'] as String;
  final sourceMessageId = row['source_message_id'] as String?;
  if (!await dbAllowsOrdinaryGroupWrite(transaction, groupId)) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_BROADCAST_DB_INSERT_REFUSED_PARENT',
      details: {'groupId': _safeId(groupId)},
    );
    return;
  }
  if (sourceMessageId != null && sourceMessageId.isNotEmpty) {
    final existing = await transaction.query(
      _table,
      where: 'group_id = ? AND source_message_id = ?',
      whereArgs: [groupId, sourceMessageId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final existingKind = existing.first['kind'] as String?;
      final incomingKind = row['kind'] as String?;
      if (existingKind == 'member_role_updated_prepared' &&
          incomingKind == 'member_role_updated') {
        if (!await dbAllowsPendingRoleBroadcastMutation(
          transaction,
          groupId: groupId,
          existingKind: existingKind,
          incomingKind: incomingKind!,
        )) {
          emitFlowEvent(
            layer: 'DB',
            event: 'PENDING_GROUP_BROADCAST_DB_ACTIVATION_REFUSED_EXIT',
            details: {'groupId': _safeId(groupId)},
          );
          return;
        }
        // Activation replaces every authoritative field, including the row
        // id, so exact verification and later removal refer to one payload.
        await dbUpdateOrdinaryGroupOwnedRows(
          transaction,
          table: _table,
          groupId: groupId,
          values: row,
          where: 'group_id = ? AND source_message_id = ?',
          whereArgs: [groupId, sourceMessageId],
        );
        emitFlowEvent(
          layer: 'DB',
          event: 'PENDING_GROUP_BROADCAST_DB_ACTIVATED',
          details: {'groupId': _safeId(groupId)},
        );
        return;
      }
      emitFlowEvent(
        layer: 'DB',
        event: 'PENDING_GROUP_BROADCAST_DB_INSERT_DEDUP',
        details: {'groupId': _safeId(groupId)},
      );
      return;
    }
  }

  final incomingKind = row['kind'] as String?;
  if (incomingKind != null &&
      !await dbAllowsPendingRoleBroadcastMutation(
        transaction,
        groupId: groupId,
        incomingKind: incomingKind,
      )) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_BROADCAST_DB_INSERT_REFUSED_EXIT',
      details: {'groupId': _safeId(groupId)},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_INSERT_START',
    details: {'groupId': _safeId(groupId)},
  );
  await dbInsertOrdinaryGroupOwnedRow(
    transaction,
    table: _table,
    row: row,
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
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_group_broadcasts.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM $_table '
    'WHERE group_id = ? AND $parent '
    'ORDER BY created_at ASC',
    [groupId],
  );
}

Future<List<Map<String, Object?>>> dbLoadAllPendingGroupBroadcasts(
  Database db,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_group_broadcasts.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM $_table WHERE $parent ORDER BY created_at ASC',
  );
}

Future<int> dbCountPendingGroupBroadcastsForGroup(
  Database db,
  String groupId,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_group_broadcasts.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM $_table WHERE group_id = ? AND $parent',
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

Future<bool> dbDeletePendingGroupBroadcastIfExact(
  Database db,
  Map<String, Object?> expected,
) async {
  final groupId = expected['group_id'] as String? ?? '';
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_group_broadcasts.group_id',
  );
  final deleted = await db.delete(
    _table,
    where: '($_pendingBroadcastExactWhere) AND group_id = ? AND $parent',
    whereArgs: [
      ..._pendingBroadcastExactFields.map((field) => expected[field]),
      groupId,
    ],
  );
  return deleted == 1;
}

/// Atomically removes one physical survivor from an exact protected row.
/// Zero survivors retires the row; a stale compare changes nothing.
Future<bool> dbRemovePendingGroupBroadcastRecipientIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required String recipientPeerId,
  required String updatedAt,
}) {
  return dbWriteTransaction(db, (transaction) async {
    final rows = await transaction.query(
      _table,
      where: 'id = ?',
      whereArgs: [expected['id']],
      limit: 1,
    );
    if (rows.length != 1) return false;
    for (final field in _pendingBroadcastExactFields) {
      if (rows.single[field] != expected[field]) return false;
    }
    final rawRecipients = expected['recipient_peer_ids'] as String? ?? '[]';
    final decoded = jsonDecode(rawRecipients);
    if (decoded is! List ||
        decoded.any((value) => value is! String) ||
        !decoded.contains(recipientPeerId)) {
      return false;
    }
    final survivors = decoded.cast<String>()
      ..removeWhere((value) => value == recipientPeerId);
    if (survivors.isEmpty) {
      return await transaction.delete(
            _table,
            where: 'id = ?',
            whereArgs: [expected['id']],
          ) ==
          1;
    }
    return await transaction.update(
          _table,
          {
            'recipient_peer_ids': jsonEncode(survivors),
            'updated_at': updatedAt,
          },
          where: 'id = ?',
          whereArgs: [expected['id']],
        ) ==
        1;
  });
}

Future<void> dbDeletePendingGroupBroadcastsForGroup(
  Database db,
  String groupId,
) async {
  final deleted = await db.delete(
    _table,
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCAST_DB_DELETE_GROUP',
    details: {'groupId': _safeId(groupId), 'deleted': deleted},
  );
}
