import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';
import '../../utils/flow_event_emitter.dart';
import 'group_event_log_db_helpers.dart';
import 'group_notification_display_outbox_db_helpers.dart';
import 'group_notification_reconciliation_outbox_db_helpers.dart';
import 'pending_group_broadcasts_db_helpers.dart';

/// Inserts a group into the database.
Future<void> dbInsertGroup(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await dbWriteTransaction(db, (txn) async {
      final hasRemovalAuthority = await _hasSelfRemovedAtColumn(txn);
      final existing = await txn.query(
        'groups',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final committedRow = Map<String, Object?>.from(row);
      if (hasRemovalAuthority && existing.isNotEmpty) {
        _preserveGroupAuthority(committedRow, existing.single);
      } else if (hasRemovalAuthority &&
          await _hasRetainedSelfRemovalFloor(txn, id)) {
        throw StateError(
          'Ordinary group creation cannot cross a retained self-removal floor.',
        );
      } else if (!hasRemovalAuthority) {
        // Focused legacy/upgrade fixtures can legitimately exercise this
        // helper before v102. Do not send the future model column to SQLite.
        committedRow.remove('self_removed_at');
      }
      await txn.insert(
        'groups',
        committedRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all groups from the database, ordered by created_at DESC.
Future<List<Map<String, Object?>>> dbLoadAllGroups(Database db) async {
  emitFlowEvent(layer: 'DB', event: 'GROUPS_DB_LOAD_ALL_START', details: {});

  try {
    final results = await db.query('groups', orderBy: 'created_at DESC');

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ALL_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single group by ID.
Future<Map<String, Object?>?> dbLoadGroup(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_LOAD_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    final results = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUPS_DB_LOAD_FOUND',
        details: {'id': id.length > 8 ? id.substring(0, 8) : id},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUPS_DB_LOAD_NOT_FOUND',
        details: {'id': id.length > 8 ? id.substring(0, 8) : id},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates a group in the database (full row replace).
Future<void> dbUpdateGroup(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_UPDATE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await dbWriteTransaction(db, (txn) async {
      await _updateGroupRowPreservingAuthority(txn, row);
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_UPDATE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_UPDATE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Atomically authors one protected group-metadata transition.
///
/// The caller's pre-edit group, complete roster, and latest key epoch are
/// requalified in this transaction. Only an exact match may advance the group
/// row and expose its immutable recipient rows plus authenticated PREPARED
/// history. COMPLETE is deliberately excluded: strict native group-config sync
/// must succeed after this transaction before authenticated recovery appends it.
Future<void> dbCommitProtectedGroupMetadataAuthority(
  Database db, {
  required Map<String, Object?> expectedGroupRow,
  required List<Map<String, Object?>> expectedMemberRows,
  required int expectedLatestKeyGeneration,
  required Map<String, Object?> groupRow,
  required List<Map<String, Object?>> pendingBroadcastRows,
  required String authorityPreparedSourcePeerId,
  required String authorityPreparedSourceEventId,
  required String authorityPreparedSourceTimestamp,
  required Map<String, Object?> authorityPreparedPayload,
}) async {
  final groupId = expectedGroupRow['id'];
  if (groupId is! String ||
      groupId.isEmpty ||
      groupRow['id'] != groupId ||
      expectedLatestKeyGeneration <= 0 ||
      expectedMemberRows.any((row) => row['group_id'] != groupId) ||
      pendingBroadcastRows.any((row) => row['group_id'] != groupId) ||
      !_isMetadataOnlyGroupTransition(expectedGroupRow, groupRow) ||
      authorityPreparedSourcePeerId.isEmpty ||
      authorityPreparedSourceEventId.isEmpty ||
      authorityPreparedSourceTimestamp.isEmpty ||
      authorityPreparedPayload.isEmpty) {
    throw ArgumentError('invalid protected metadata authority transaction');
  }

  await dbWriteTransaction(db, (transaction) async {
    final storedGroups = await transaction.query(
      'groups',
      where: 'id = ?',
      whereArgs: <Object?>[groupId],
      limit: 1,
    );
    if (storedGroups.length != 1 ||
        !_sameExpectedRow(storedGroups.single, expectedGroupRow)) {
      throw StateError('protected metadata group authority changed');
    }

    final storedMembers = await transaction.query(
      'group_members',
      where: 'group_id = ?',
      whereArgs: <Object?>[groupId],
      orderBy: 'peer_id ASC',
    );
    final expectedMembers = expectedMemberRows.toList(growable: false)
      ..sort(
        (left, right) =>
            (left['peer_id'] as String).compareTo(right['peer_id'] as String),
      );
    if (!_sameExpectedRows(storedMembers, expectedMembers)) {
      throw StateError('protected metadata roster authority changed');
    }

    final latestKeys = await transaction.query(
      'group_keys',
      columns: const <String>['key_generation'],
      where: 'group_id = ?',
      whereArgs: <Object?>[groupId],
      orderBy: 'key_generation DESC',
      limit: 1,
    );
    if (latestKeys.length != 1 ||
        latestKeys.single['key_generation'] != expectedLatestKeyGeneration) {
      throw StateError('protected metadata key authority changed');
    }

    if (!await _updateGroupRowPreservingAuthority(transaction, groupRow)) {
      throw StateError('protected metadata parent disappeared');
    }
    for (final row in pendingBroadcastRows) {
      await dbInsertPendingGroupBroadcastWithExecutor(transaction, row);
      final stored = await transaction.query(
        'pending_group_broadcasts',
        where: 'group_id = ? AND source_message_id = ?',
        whereArgs: <Object?>[row['group_id'], row['source_message_id']],
        limit: 1,
      );
      if (stored.length != 1 || !_sameExpectedRow(stored.single, row)) {
        throw StateError('protected metadata broadcast conflict');
      }
    }
    await dbAppendGroupEventLogEntryInTransaction(
      transaction,
      groupId: groupId,
      eventType: 'protected_authority_prepared',
      sourcePeerId: authorityPreparedSourcePeerId,
      sourceEventId: authorityPreparedSourceEventId,
      sourceTimestamp: authorityPreparedSourceTimestamp,
      payload: authorityPreparedPayload,
    );
  });
}

const _protectedMetadataFields = <String>{
  'name',
  'description',
  'avatar_blob_id',
  'avatar_mime',
  'avatar_path',
  'last_metadata_event_at',
};

bool _isMetadataOnlyGroupTransition(
  Map<String, Object?> expected,
  Map<String, Object?> updated,
) {
  final fields = <String>{...expected.keys, ...updated.keys};
  for (final field in fields) {
    if (_protectedMetadataFields.contains(field)) continue;
    if (!expected.containsKey(field) || !updated.containsKey(field)) {
      return false;
    }
    if (expected[field] != updated[field]) return false;
  }
  return true;
}

bool _sameExpectedRows(
  List<Map<String, Object?>> stored,
  List<Map<String, Object?>> expected,
) {
  if (stored.length != expected.length) return false;
  for (var index = 0; index < stored.length; index++) {
    if (!_sameExpectedRow(stored[index], expected[index])) return false;
  }
  return true;
}

bool _sameExpectedRow(
  Map<String, Object?> stored,
  Map<String, Object?> expected,
) {
  for (final entry in expected.entries) {
    if (!stored.containsKey(entry.key) || stored[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// Atomically commits a terminal dissolved-group row and retires every
/// notification-display marker owned by that exact group.
///
/// The group row is updated first inside the transaction. A missing group or
/// any cleanup failure aborts the transaction, so callers never observe a
/// dissolved row whose pre-existing display custody survived this commit.
Future<void> dbCommitDissolvedGroupAndDeleteNotificationDisplayOutbox(
  Database db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String? ?? '';
  if (id.trim().isEmpty) {
    throw ArgumentError.value(id, 'row[id]', 'must be a non-empty String');
  }
  if (row['is_dissolved'] != 1) {
    throw ArgumentError.value(
      row['is_dissolved'],
      'row[is_dissolved]',
      'must be 1 for a terminal dissolve commit',
    );
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_DISSOLVE_COMMIT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await dbWriteTransaction(db, (txn) async {
      final updated = await _updateGroupRowPreservingAuthority(txn, row);
      if (!updated) {
        throw StateError('cannot dissolve a missing group');
      }
      await dbDeleteGroupNotificationDisplayOutboxForGroup(
        txn,
        id,
        preserveReadyCustody: true,
      );
      await dbEnqueueGroupNotificationReconciliationOutbox(txn, groupId: id);
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_DISSOLVE_COMMIT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_DISSOLVE_COMMIT_ERROR',
      details: {'id': id, 'error': e.toString()},
    );
    rethrow;
  }
}

/// Atomically closes a protected dissolve after every exact physical delivery
/// has strict relay custody.
///
/// Modern callers retire each accepted target row as a durable custody receipt
/// before entering this transaction; rowless PREPARED discovery owns the crash
/// gap before terminal completion. [expectedBroadcastRows] remains available
/// for exact retirement of legacy rows in the same terminal transaction.
Future<void> dbCommitProtectedDissolvedGroup(
  Database db, {
  required Map<String, Object?> groupRow,
  required List<Map<String, Object?>> expectedBroadcastRows,
  required String authorityCompleteSourcePeerId,
  required String authorityCompleteSourceEventId,
  required String authorityCompleteSourceTimestamp,
  required Map<String, Object?> authorityCompletePayload,
}) async {
  final groupId = groupRow['id'] as String? ?? '';
  if (groupId.trim().isEmpty || groupRow['is_dissolved'] != 1) {
    throw ArgumentError('protected dissolve requires a terminal group row');
  }
  if (authorityCompleteSourcePeerId.isEmpty ||
      authorityCompleteSourceEventId.isEmpty ||
      authorityCompleteSourceTimestamp.isEmpty ||
      authorityCompletePayload.isEmpty ||
      expectedBroadcastRows.any(
        (row) =>
            row['group_id'] != groupId || row['kind'] != 'group_authority_v1',
      )) {
    throw ArgumentError('invalid protected dissolve authority transaction');
  }

  await dbWriteTransaction(db, (transaction) async {
    final updated = await _updateGroupRowPreservingAuthority(
      transaction,
      groupRow,
    );
    if (!updated) {
      throw StateError('cannot dissolve a missing group');
    }
    await dbDeleteGroupNotificationDisplayOutboxForGroup(
      transaction,
      groupId,
      preserveReadyCustody: true,
    );
    await dbEnqueueGroupNotificationReconciliationOutbox(
      transaction,
      groupId: groupId,
    );
    await dbAppendGroupEventLogEntryInTransaction(
      transaction,
      groupId: groupId,
      eventType: 'protected_authority_complete',
      sourcePeerId: authorityCompleteSourcePeerId,
      sourceEventId: authorityCompleteSourceEventId,
      sourceTimestamp: authorityCompleteSourceTimestamp,
      payload: authorityCompletePayload,
    );
    for (final expected in expectedBroadcastRows) {
      await dbDeleteProtectedGroupAuthorityBroadcastIfExactInTransaction(
        transaction,
        groupId: groupId,
        expected: expected,
      );
    }
  });
}

/// Dedicated authenticated-membership seam. Ordinary full-row writes never
/// clear a removal marker or advance its membership watermark; this exact CAS
/// is intentionally the only low-level replacement that may do both.
Future<bool> dbReplaceAcceptedGroupAuthority(
  Database db, {
  required Map<String, Object?> row,
  required String expectedSelfRemovedAt,
  required String acceptedMembershipEventAt,
  required String? acceptedMembershipEventId,
}) {
  final groupId = row['id'] as String? ?? '';
  return dbWriteTransaction(db, (txn) async {
    final existing = await txn.query(
      'groups',
      where: 'id = ? AND self_removed_at = ?',
      whereArgs: [groupId, expectedSelfRemovedAt],
      limit: 1,
    );
    if (existing.isEmpty) return false;

    final acceptedAt = DateTime.tryParse(acceptedMembershipEventAt)?.toUtc();
    final markerAt = DateTime.tryParse(expectedSelfRemovedAt)?.toUtc();
    final currentAt = DateTime.tryParse(
      existing.single['last_membership_event_at'] as String? ?? '',
    )?.toUtc();
    if (acceptedAt == null ||
        markerAt == null ||
        !acceptedAt.isAfter(markerAt) ||
        (currentAt != null && !acceptedAt.isAfter(currentAt))) {
      return false;
    }

    final committedRow = Map<String, Object?>.from(row)
      ..['self_removed_at'] = null
      ..['last_membership_event_at'] = acceptedAt.toIso8601String()
      ..['last_membership_event_id'] = acceptedMembershipEventId;
    final updated = await txn.update(
      'groups',
      committedRow,
      where: 'id = ? AND self_removed_at = ?',
      whereArgs: [groupId, expectedSelfRemovedAt],
    );
    return updated == 1;
  });
}

/// Monotonically advances the protected membership watermark without exposing
/// it to ordinary full-row metadata writes.
Future<bool> dbAdvanceGroupMembershipWatermark(
  Database db, {
  required String groupId,
  required String eventAt,
  required String? eventId,
}) {
  return dbWriteTransaction(db, (txn) async {
    final rows = await txn.query(
      'groups',
      columns: const ['last_membership_event_at', 'last_membership_event_id'],
      where: 'id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final incoming = DateTime.tryParse(eventAt)?.toUtc();
    if (incoming == null) return false;
    final stored = DateTime.tryParse(
      rows.single['last_membership_event_at'] as String? ?? '',
    )?.toUtc();
    if (stored != null) {
      if (incoming.isBefore(stored)) return false;
      if (incoming.isAtSameMomentAs(stored)) {
        final storedId = rows.single['last_membership_event_id'] as String?;
        if (eventId == null ||
            storedId == null ||
            eventId.compareTo(storedId) <= 0) {
          return false;
        }
      }
    }
    return await txn.update(
          'groups',
          {
            'last_membership_event_at': incoming.toIso8601String(),
            'last_membership_event_id': eventId,
          },
          where: 'id = ?',
          whereArgs: [groupId],
        ) ==
        1;
  });
}

void _preserveGroupAuthority(
  Map<String, Object?> target,
  Map<String, Object?> stored,
) {
  target['self_removed_at'] = stored['self_removed_at'];
  target['last_membership_event_at'] = stored['last_membership_event_at'];
  target['last_membership_event_id'] = stored['last_membership_event_id'];
}

Future<bool> _updateGroupRowPreservingAuthority(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String? ?? '';
  final existing = await db.query(
    'groups',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  if (existing.isEmpty) return false;
  final committedRow = Map<String, Object?>.from(row);
  if (await _hasSelfRemovedAtColumn(db)) {
    _preserveGroupAuthority(committedRow, existing.single);
  } else {
    committedRow.remove('self_removed_at');
  }
  return await db.update(
        'groups',
        committedRow,
        where: 'id = ?',
        whereArgs: [id],
      ) ==
      1;
}

Future<bool> _hasSelfRemovedAtColumn(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(groups)');
  return columns.any((row) => row['name'] == 'self_removed_at');
}

Future<bool> _hasRetainedSelfRemovalFloor(
  DatabaseExecutor db,
  String groupId,
) async {
  final eventLog = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'group_event_log' LIMIT 1",
  );
  if (eventLog.isEmpty) return false;
  final rows = await db.query(
    'group_event_log',
    columns: const ['id'],
    where: 'group_id = ? AND event_type = ?',
    whereArgs: [groupId, 'local_self_removed_freshness_floor'],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Deletes a group by ID.
Future<void> dbDeleteGroup(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_DELETE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await dbWriteTransaction(db, (txn) async {
      await dbDeleteGroupNotificationDisplayOutboxForGroup(
        txn,
        id,
        preserveReadyCustody: true,
      );
      await txn.delete('groups', where: 'id = ?', whereArgs: [id]);
      await dbEnqueueGroupNotificationReconciliationOutbox(txn, groupId: id);
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_DELETE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the count of groups.
Future<int> dbCountGroups(Database db) async {
  try {
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM groups');
    return Sqflite.firstIntValue(result) ?? 0;
  } catch (e) {
    return 0;
  }
}

/// Archives a group by ID.
Future<void> dbArchiveGroup(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_ARCHIVE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate(
      'UPDATE groups SET is_archived = 1, archived_at = ? WHERE id = ?',
      [now, id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_ARCHIVE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_ARCHIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Unarchives a group by ID.
Future<void> dbUnarchiveGroup(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_UNARCHIVE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.rawUpdate(
      'UPDATE groups SET is_archived = 0, archived_at = NULL WHERE id = ?',
      [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_UNARCHIVE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_UNARCHIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads only active (non-archived) groups.
Future<List<Map<String, Object?>>> dbLoadActiveGroups(Database db) async {
  emitFlowEvent(layer: 'DB', event: 'GROUPS_DB_LOAD_ACTIVE_START', details: {});

  try {
    final results = await db.rawQuery(
      'SELECT * FROM groups WHERE is_archived = 0 ORDER BY created_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ACTIVE_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ACTIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
