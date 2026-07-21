import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';
import 'group_messages_db_helpers.dart';
import 'group_parent_write_guard.dart';

const _table = 'group_exit_intents';
const _pendingTable = 'pending_group_broadcasts';
const _leaveNoticeKind = 'member_removed_exit_intent';
const _preparedRoleKind = 'member_role_updated_prepared';
const _activeRoleKind = 'member_role_updated';

const _queued = 'queued';
const _leaveNoticePending = 'leave_notice_pending';
const _leaveNoticeAttempted = 'leave_notice_attempted';
const _rotationClaimed = 'rotation_claimed';
const _nativeLeavePending = 'native_leave_pending';
const _cleanupPending = 'cleanup_pending';

enum DbGroupExitIntentMutationDisposition {
  committed,
  alreadyCurrent,
  absent,
  refusedConflict,
  refusedInvalidTransition,
  refusedIdentityChanged,
  refusedParentAbsent,
  refusedDissolved,
  refusedSelfRemoved,
  refusedSelfMissing,
  refusedMembershipChanged,
  refusedLastAdmin,
  refusedRoleBroadcastPresent,
  refusedNoticeMissing,
  refusedTimelineConflict,
  retiredStaleMembership,
  cleanupAlreadyComplete,
}

class DbGroupExitIntentMutationResult {
  const DbGroupExitIntentMutationResult({
    required this.disposition,
    this.current,
  });

  final DbGroupExitIntentMutationDisposition disposition;
  final Map<String, Object?>? current;

  bool get committed =>
      disposition == DbGroupExitIntentMutationDisposition.committed;
}

Future<bool> dbHasGroupExitIntentsTable(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const [_table],
  );
  return rows.isNotEmpty;
}

Future<bool> dbHasGroupExitIntentForGroup(
  DatabaseExecutor db,
  String groupId,
) async {
  if (!await dbHasGroupExitIntentsTable(db)) return false;
  final rows = await db.query(
    _table,
    columns: const ['group_id'],
    where: 'group_id = ?',
    whereArgs: [groupId],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Ordering guard shared by role preparation/activation and the atomic exit
/// claim. A pre-v103 partial schema retains its legacy behavior.
Future<bool> dbAllowsPendingRoleBroadcastMutation(
  DatabaseExecutor db, {
  required String groupId,
  required String incomingKind,
  String? existingKind,
}) async {
  if (!_isRoleKind(incomingKind) || !await dbHasGroupExitIntentsTable(db)) {
    return true;
  }
  final rows = await db.query(
    _table,
    columns: const ['state'],
    where: 'group_id = ?',
    whereArgs: [groupId],
    limit: 1,
  );
  if (rows.isEmpty) return true;
  return existingKind == _preparedRoleKind &&
      incomingKind == _activeRoleKind &&
      rows.single['state'] == _queued;
}

Future<Map<String, Object?>?> dbLoadGroupExitIntentForGroup(
  DatabaseExecutor db,
  String groupId,
) async {
  final rows = await db.query(
    _table,
    where: 'group_id = ?',
    whereArgs: [groupId],
    limit: 1,
  );
  return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
}

Future<List<Map<String, Object?>>> dbLoadAllGroupExitIntents(
  DatabaseExecutor db,
) async {
  final rows = await db.query(_table, orderBy: 'updated_at ASC, group_id ASC');
  return rows.map(Map<String, Object?>.from).toList(growable: false);
}

Future<DbGroupExitIntentMutationResult> dbEnqueueGroupExitIntent(
  Database db,
  Map<String, Object?> row,
) async {
  if (!_isValidQueuedInsert(row)) {
    return const DbGroupExitIntentMutationResult(
      disposition:
          DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
    );
  }
  return dbWriteTransaction(db, (transaction) async {
    final current = await _load(transaction, row['group_id'] as String);
    if (current != null) {
      if (_sameRow(current, row)) {
        return DbGroupExitIntentMutationResult(
          disposition: DbGroupExitIntentMutationDisposition.alreadyCurrent,
          current: current,
        );
      }
      final currentAuthority = await _loadAuthority(transaction, current);
      if (currentAuthority.shape != _AuthorityShape.differentMembership) {
        return DbGroupExitIntentMutationResult(
          disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
          current: current,
        );
      }
      await _deleteExactNotice(transaction, current);
      if (await _deleteIntentCas(transaction, current) != 1) {
        return DbGroupExitIntentMutationResult(
          disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
          current: await _load(transaction, row['group_id'] as String),
        );
      }
    }

    final authority = await _loadAuthority(transaction, row);
    final refused = _authorityRefusal(authority);
    if (refused != null) {
      return DbGroupExitIntentMutationResult(disposition: refused);
    }

    try {
      final inserted = await transaction.insert(
        _table,
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (inserted == 0) {
        return const DbGroupExitIntentMutationResult(
          disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
        );
      }
    } on DatabaseException {
      return DbGroupExitIntentMutationResult(
        disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
        current: await _load(transaction, row['group_id'] as String),
      );
    }
    return DbGroupExitIntentMutationResult(
      disposition: DbGroupExitIntentMutationDisposition.committed,
      current: Map<String, Object?>.from(row),
    );
  });
}

Future<DbGroupExitIntentMutationResult> dbCancelQueuedGroupExitIntent(
  Database db, {
  required Map<String, Object?> expected,
  required String updatedAt,
}) async {
  _requireTimestamp(updatedAt, 'updatedAt');
  return dbWriteTransaction(db, (transaction) async {
    final current = await _load(transaction, expected['group_id'] as String);
    final conflict = _casConflict(current, expected, requiredState: _queued);
    if (conflict != null) return conflict;

    final authority = await _loadAuthority(transaction, current!);
    if (authority.shape == _AuthorityShape.differentMembership) {
      await _deleteExactNotice(transaction, current);
      await _deleteIntentCas(transaction, current);
      return const DbGroupExitIntentMutationResult(
        disposition:
            DbGroupExitIntentMutationDisposition.retiredStaleMembership,
      );
    }
    final refused = _authorityRefusal(authority);
    if (refused != null) {
      return DbGroupExitIntentMutationResult(
        disposition: refused,
        current: current,
      );
    }

    final deleted = await _deleteIntentCas(transaction, current);
    if (deleted != 1) {
      return DbGroupExitIntentMutationResult(
        disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
        current: await _load(transaction, expected['group_id'] as String),
      );
    }
    return const DbGroupExitIntentMutationResult(
      disposition: DbGroupExitIntentMutationDisposition.committed,
    );
  });
}

Future<DbGroupExitIntentMutationResult> dbAdvanceGroupExitIntent(
  Database db, {
  required Map<String, Object?> expected,
  required String nextState,
  required String updatedAt,
  String? lastErrorCode,
}) async {
  _requireTimestamp(updatedAt, 'updatedAt');
  final expectedState = expected['state'] as String?;
  if (!_isLegalPostNoticeTransition(expectedState, nextState)) {
    return DbGroupExitIntentMutationResult(
      disposition:
          DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
      current: await _load(db, expected['group_id'] as String),
    );
  }
  final boundedError = _validateErrorCode(lastErrorCode);

  return dbWriteTransaction(db, (transaction) async {
    final current = await _load(transaction, expected['group_id'] as String);
    final already = _alreadyAdvanced(current, expected, nextState);
    if (already != null) return already;
    final conflict = _casConflict(
      current,
      expected,
      requiredState: expectedState!,
    );
    if (conflict != null) return conflict;

    final authority = await _loadAuthority(transaction, current!);
    if (authority.shape == _AuthorityShape.differentMembership) {
      await _deleteExactNotice(transaction, current);
      await _deleteIntentCas(transaction, current);
      return const DbGroupExitIntentMutationResult(
        disposition:
            DbGroupExitIntentMutationDisposition.retiredStaleMembership,
      );
    }
    final refused = _authorityRefusal(authority);
    if (refused != null) {
      return DbGroupExitIntentMutationResult(
        disposition: refused,
        current: current,
      );
    }

    final replacement = Map<String, Object?>.from(current)
      ..['state'] = nextState
      ..['revision'] = (current['revision'] as int) + 1
      ..['updated_at'] = updatedAt
      ..['last_error_code'] = boundedError;
    final changed = await _updateIntentCas(transaction, current, replacement);
    if (changed != 1) {
      return DbGroupExitIntentMutationResult(
        disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
        current: await _load(transaction, expected['group_id'] as String),
      );
    }
    return DbGroupExitIntentMutationResult(
      disposition: DbGroupExitIntentMutationDisposition.committed,
      current: replacement,
    );
  });
}

Future<DbGroupExitIntentMutationResult> dbPrepareGroupExitLeaveNotice(
  Database db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> timelineRow,
  required Map<String, Object?> pendingBroadcastRow,
  required String updatedAt,
}) async {
  _requireTimestamp(updatedAt, 'updatedAt');
  if (!_validNoticePayload(expected, timelineRow, pendingBroadcastRow)) {
    return DbGroupExitIntentMutationResult(
      disposition:
          DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
      current: await _load(db, expected['group_id'] as String),
    );
  }

  try {
    return await dbWriteTransaction(db, (transaction) async {
      final groupId = expected['group_id'] as String;
      final current = await _load(transaction, groupId);
      final already = _alreadyAdvanced(current, expected, _leaveNoticePending);
      if (already != null) return already;
      final conflict = _casConflict(current, expected, requiredState: _queued);
      if (conflict != null) return conflict;

      final authority = await _loadAuthority(transaction, current!);
      if (authority.shape == _AuthorityShape.differentMembership) {
        await _deleteIntentCas(transaction, current);
        return const DbGroupExitIntentMutationResult(
          disposition:
              DbGroupExitIntentMutationDisposition.retiredStaleMembership,
        );
      }
      final refused = _authorityRefusal(authority);
      if (refused != null) {
        return DbGroupExitIntentMutationResult(
          disposition: refused,
          current: current,
        );
      }

      if (await _isExactSelfSoleAdmin(transaction, current)) {
        return DbGroupExitIntentMutationResult(
          disposition: DbGroupExitIntentMutationDisposition.refusedLastAdmin,
          current: current,
        );
      }

      final roleRows = await transaction.query(
        _pendingTable,
        columns: const ['id'],
        where: 'group_id = ? AND kind IN (?, ?)',
        whereArgs: [groupId, _preparedRoleKind, _activeRoleKind],
        limit: 1,
      );
      if (roleRows.isNotEmpty) {
        return DbGroupExitIntentMutationResult(
          disposition:
              DbGroupExitIntentMutationDisposition.refusedRoleBroadcastPresent,
          current: current,
        );
      }

      final eventAt = DateTime.parse(
        pendingBroadcastRow['event_at'] as String,
      ).toUtc();
      final watermarkRaw = authority.group?['last_membership_event_at'];
      if (watermarkRaw is String &&
          !eventAt.isAfter(DateTime.parse(watermarkRaw).toUtc())) {
        return DbGroupExitIntentMutationResult(
          disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
          current: current,
        );
      }

      final existingTimeline = await transaction.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: [timelineRow['id']],
        limit: 1,
      );
      if (existingTimeline.isNotEmpty &&
          !_containsExactValues(existingTimeline.single, timelineRow)) {
        return DbGroupExitIntentMutationResult(
          disposition:
              DbGroupExitIntentMutationDisposition.refusedTimelineConflict,
          current: current,
        );
      }
      final existingPending = await transaction.query(
        _pendingTable,
        where: 'id = ? OR (group_id = ? AND source_message_id = ?)',
        whereArgs: [
          pendingBroadcastRow['id'],
          groupId,
          pendingBroadcastRow['source_message_id'],
        ],
        limit: 1,
      );
      if (existingPending.isNotEmpty) {
        return DbGroupExitIntentMutationResult(
          disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
          current: current,
        );
      }

      if (existingTimeline.isEmpty &&
          !await dbInsertGroupMessage(transaction, timelineRow)) {
        throw const _RollbackMutation(
          DbGroupExitIntentMutationDisposition.refusedTimelineConflict,
        );
      }
      final pendingInserted = await dbInsertOrdinaryGroupOwnedRow(
        transaction,
        table: _pendingTable,
        row: pendingBroadcastRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (!pendingInserted) {
        throw const _RollbackMutation(
          DbGroupExitIntentMutationDisposition.refusedConflict,
        );
      }

      final replacement = Map<String, Object?>.from(current)
        ..['state'] = _leaveNoticePending
        ..['source_event_id'] = pendingBroadcastRow['source_message_id']
        ..['event_at'] = pendingBroadcastRow['event_at']
        ..['revision'] = (current['revision'] as int) + 1
        ..['updated_at'] = updatedAt
        ..['last_error_code'] = null;
      if (await _updateIntentCas(transaction, current, replacement) != 1) {
        throw const _RollbackMutation(
          DbGroupExitIntentMutationDisposition.refusedConflict,
        );
      }
      return DbGroupExitIntentMutationResult(
        disposition: DbGroupExitIntentMutationDisposition.committed,
        current: replacement,
      );
    });
  } on _RollbackMutation catch (rollback) {
    return DbGroupExitIntentMutationResult(
      disposition: rollback.disposition,
      current: await _load(db, expected['group_id'] as String),
    );
  }
}

Future<DbGroupExitIntentMutationResult> dbCompleteGroupExitLeaveNotice(
  Database db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> pendingBroadcastRow,
  required String completionCode,
  required String updatedAt,
}) async {
  _requireTimestamp(updatedAt, 'updatedAt');
  final boundedCode = _validateErrorCode(completionCode);
  if (boundedCode == null ||
      expected['state'] != _leaveNoticePending ||
      !_sameNoticeIdentity(expected, pendingBroadcastRow)) {
    return DbGroupExitIntentMutationResult(
      disposition:
          DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
      current: await _load(db, expected['group_id'] as String),
    );
  }

  try {
    return await dbWriteTransaction(db, (transaction) async {
      final groupId = expected['group_id'] as String;
      final current = await _load(transaction, groupId);
      final already = _alreadyAdvanced(
        current,
        expected,
        _leaveNoticeAttempted,
      );
      if (already != null) return already;
      final conflict = _casConflict(
        current,
        expected,
        requiredState: _leaveNoticePending,
      );
      if (conflict != null) return conflict;

      final authority = await _loadAuthority(transaction, current!);
      if (authority.shape == _AuthorityShape.differentMembership) {
        await _deleteExactNotice(transaction, current);
        await _deleteIntentCas(transaction, current);
        return const DbGroupExitIntentMutationResult(
          disposition:
              DbGroupExitIntentMutationDisposition.retiredStaleMembership,
        );
      }
      final refused = _authorityRefusal(authority);
      if (refused != null) {
        return DbGroupExitIntentMutationResult(
          disposition: refused,
          current: current,
        );
      }

      final pending = await transaction.query(
        _pendingTable,
        where: 'id = ?',
        whereArgs: [pendingBroadcastRow['id']],
        limit: 1,
      );
      if (pending.isEmpty ||
          !_containsExactValues(pending.single, pendingBroadcastRow)) {
        return DbGroupExitIntentMutationResult(
          disposition:
              DbGroupExitIntentMutationDisposition.refusedNoticeMissing,
          current: current,
        );
      }
      final deleted = await _deleteExactMap(
        transaction,
        _pendingTable,
        pendingBroadcastRow,
      );
      if (deleted != 1) {
        throw const _RollbackMutation(
          DbGroupExitIntentMutationDisposition.refusedNoticeMissing,
        );
      }

      final replacement = Map<String, Object?>.from(current)
        ..['state'] = _leaveNoticeAttempted
        ..['revision'] = (current['revision'] as int) + 1
        ..['updated_at'] = updatedAt
        ..['last_error_code'] = boundedCode;
      if (await _updateIntentCas(transaction, current, replacement) != 1) {
        throw const _RollbackMutation(
          DbGroupExitIntentMutationDisposition.refusedConflict,
        );
      }
      return DbGroupExitIntentMutationResult(
        disposition: DbGroupExitIntentMutationDisposition.committed,
        current: replacement,
      );
    });
  } on _RollbackMutation catch (rollback) {
    return DbGroupExitIntentMutationResult(
      disposition: rollback.disposition,
      current: await _load(db, expected['group_id'] as String),
    );
  }
}

Future<DbGroupExitIntentMutationResult> dbCleanupOrRetireGroupExitIntent(
  Database db, {
  required Map<String, Object?> expected,
  required String updatedAt,
}) async {
  _requireTimestamp(updatedAt, 'updatedAt');
  return dbWriteTransaction(db, (transaction) async {
    final groupId = expected['group_id'] as String;
    final current = await _load(transaction, groupId);
    final conflict = _casConflict(
      current,
      expected,
      requiredState: _cleanupPending,
    );
    if (conflict != null) return conflict;

    final authority = await _loadAuthority(transaction, current!);
    if (authority.shape == _AuthorityShape.parentAbsent) {
      await _deleteExactNotice(transaction, current);
      await _deleteIntentCas(transaction, current);
      return const DbGroupExitIntentMutationResult(
        disposition:
            DbGroupExitIntentMutationDisposition.cleanupAlreadyComplete,
      );
    }
    if (authority.shape == _AuthorityShape.differentMembership) {
      await _deleteExactNotice(transaction, current);
      await _deleteIntentCas(transaction, current);
      return const DbGroupExitIntentMutationResult(
        disposition:
            DbGroupExitIntentMutationDisposition.retiredStaleMembership,
      );
    }
    final refused = _authorityRefusal(authority);
    if (refused != null) {
      return DbGroupExitIntentMutationResult(
        disposition: refused,
        current: current,
      );
    }

    await dbDeleteGroupMessagesForGroup(transaction, groupId);
    for (final table in const <String>[
      'group_members',
      'group_keys',
      'group_key_rotation_drafts',
      'group_rejoin_state',
      'pending_group_broadcasts',
      'group_pending_key_repairs',
      'group_pending_key_distributions',
      'group_pending_membership_messages',
      'group_history_gap_repairs',
      'group_pending_reactions',
      'pending_sibling_devices',
    ]) {
      if (await _tableExists(transaction, table)) {
        await transaction.delete(
          table,
          where: 'group_id = ?',
          whereArgs: [groupId],
        );
      }
    }
    if (await _tableExists(transaction, 'group_reaction_replay_outbox')) {
      await transaction.delete(
        'group_reaction_replay_outbox',
        where: "group_id = ? AND delivery_status IN ('pending', 'failed')",
        whereArgs: [groupId],
      );
    }
    await transaction.delete('groups', where: 'id = ?', whereArgs: [groupId]);
    if (await _deleteIntentCas(transaction, current) != 1) {
      throw StateError('group exit intent changed during serialized cleanup');
    }
    return const DbGroupExitIntentMutationResult(
      disposition: DbGroupExitIntentMutationDisposition.committed,
    );
  });
}

Future<DbGroupExitIntentMutationResult> dbRetireExactGroupExitIntent(
  Database db,
  Map<String, Object?> expected,
) async {
  return dbWriteTransaction(db, (transaction) async {
    final current = await _load(transaction, expected['group_id'] as String);
    final conflict = _casConflict(
      current,
      expected,
      requiredState: expected['state'] as String? ?? '',
    );
    if (conflict != null) return conflict;
    await _deleteExactNotice(transaction, current!);
    if (await _deleteIntentCas(transaction, current) != 1) {
      return DbGroupExitIntentMutationResult(
        disposition: DbGroupExitIntentMutationDisposition.refusedConflict,
        current: await _load(transaction, expected['group_id'] as String),
      );
    }
    return const DbGroupExitIntentMutationResult(
      disposition: DbGroupExitIntentMutationDisposition.committed,
    );
  });
}

Future<int> dbTerminalizeGroupExitIntentForGroup(Database db, String groupId) {
  return dbWriteTransaction(db, (transaction) async {
    final current = await _load(transaction, groupId);
    if (current == null) return 0;
    await _deleteExactNotice(transaction, current);
    return transaction.delete(
      _table,
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
  });
}

Future<Map<String, Object?>?> _load(DatabaseExecutor db, String groupId) async {
  final rows = await db.query(
    _table,
    where: 'group_id = ?',
    whereArgs: [groupId],
    limit: 1,
  );
  return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
}

/// Repeats the final reversible last-admin check inside the same write
/// transaction that claims the signed leave notice. Inbound membership
/// projection does not share the runner's in-process lock, so only this SQL
/// boundary can make "other admin removed" and "notice claimed" choose one
/// durable order.
Future<bool> _isExactSelfSoleAdmin(
  DatabaseExecutor db,
  Map<String, Object?> intent,
) async {
  final rows = await db.rawQuery(
    '''
    SELECT self.role AS self_role,
           (
             SELECT COUNT(*)
             FROM group_members AS admins
             WHERE admins.group_id = self.group_id
               AND admins.role = 'admin'
           ) AS admin_count
    FROM group_members AS self
    WHERE self.group_id = ? AND self.peer_id = ?
    LIMIT 1
    ''',
    <Object?>[intent['group_id'], intent['self_peer_id']],
  );
  if (rows.isEmpty || rows.single['self_role'] != 'admin') return false;
  return (rows.single['admin_count'] as int) <= 1;
}

enum _AuthorityShape {
  exact,
  identityChanged,
  parentAbsent,
  dissolved,
  selfRemoved,
  selfMissing,
  differentMembership,
}

class _Authority {
  const _Authority(this.shape, {this.group});

  final _AuthorityShape shape;
  final Map<String, Object?>? group;
}

Future<_Authority> _loadAuthority(
  DatabaseExecutor db,
  Map<String, Object?> intent,
) async {
  final groupId = intent['group_id'] as String;
  final peerId = intent['self_peer_id'] as String;
  final joinedAt = intent['self_joined_at'] as String;

  final groups = await db.query(
    'groups',
    columns: const <String>[
      'id',
      'is_dissolved',
      'self_removed_at',
      'last_membership_event_at',
    ],
    where: 'id = ?',
    whereArgs: [groupId],
    limit: 1,
  );
  if (groups.isEmpty) return const _Authority(_AuthorityShape.parentAbsent);
  final group = Map<String, Object?>.from(groups.single);
  if ((group['is_dissolved'] as int? ?? 0) != 0) {
    return _Authority(_AuthorityShape.dissolved, group: group);
  }
  if (group['self_removed_at'] != null) {
    return _Authority(_AuthorityShape.selfRemoved, group: group);
  }

  final identity = await db.query(
    'identity',
    columns: const ['peer_id'],
    where: 'id = 1',
    limit: 1,
  );
  if (identity.isEmpty || identity.single['peer_id'] != peerId) {
    return _Authority(_AuthorityShape.identityChanged, group: group);
  }

  final members = await db.query(
    'group_members',
    columns: const ['joined_at'],
    where: 'group_id = ? AND peer_id = ?',
    whereArgs: [groupId, peerId],
    limit: 1,
  );
  if (members.isEmpty) {
    return _Authority(_AuthorityShape.selfMissing, group: group);
  }
  if (!_sameInstant(members.single['joined_at'], joinedAt)) {
    return _Authority(_AuthorityShape.differentMembership, group: group);
  }
  return _Authority(_AuthorityShape.exact, group: group);
}

bool _sameInstant(Object? left, Object? right) {
  if (left is! String || right is! String) return false;
  try {
    return DateTime.parse(
      left,
    ).toUtc().isAtSameMomentAs(DateTime.parse(right).toUtc());
  } on FormatException {
    return false;
  }
}

DbGroupExitIntentMutationDisposition? _authorityRefusal(_Authority authority) =>
    switch (authority.shape) {
      _AuthorityShape.exact => null,
      _AuthorityShape.identityChanged =>
        DbGroupExitIntentMutationDisposition.refusedIdentityChanged,
      _AuthorityShape.parentAbsent =>
        DbGroupExitIntentMutationDisposition.refusedParentAbsent,
      _AuthorityShape.dissolved =>
        DbGroupExitIntentMutationDisposition.refusedDissolved,
      _AuthorityShape.selfRemoved =>
        DbGroupExitIntentMutationDisposition.refusedSelfRemoved,
      _AuthorityShape.selfMissing =>
        DbGroupExitIntentMutationDisposition.refusedSelfMissing,
      _AuthorityShape.differentMembership =>
        DbGroupExitIntentMutationDisposition.refusedMembershipChanged,
    };

DbGroupExitIntentMutationResult? _casConflict(
  Map<String, Object?>? current,
  Map<String, Object?> expected, {
  required String requiredState,
}) {
  if (current == null) {
    return const DbGroupExitIntentMutationResult(
      disposition: DbGroupExitIntentMutationDisposition.absent,
    );
  }
  if (expected['state'] != requiredState) {
    return DbGroupExitIntentMutationResult(
      disposition:
          DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
      current: current,
    );
  }
  if (!_sameCas(current, expected)) {
    return DbGroupExitIntentMutationResult(
      disposition: current['intent_id'] != expected['intent_id']
          ? DbGroupExitIntentMutationDisposition.refusedConflict
          : DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
      current: current,
    );
  }
  return null;
}

DbGroupExitIntentMutationResult? _alreadyAdvanced(
  Map<String, Object?>? current,
  Map<String, Object?> expected,
  String nextState,
) {
  if (current != null &&
      current['intent_id'] == expected['intent_id'] &&
      current['state'] == nextState &&
      current['revision'] == (expected['revision'] as int? ?? -1) + 1) {
    return DbGroupExitIntentMutationResult(
      disposition: DbGroupExitIntentMutationDisposition.alreadyCurrent,
      current: current,
    );
  }
  return null;
}

bool _sameCas(Map<String, Object?> current, Map<String, Object?> expected) =>
    current['group_id'] == expected['group_id'] &&
    current['intent_id'] == expected['intent_id'] &&
    current['state'] == expected['state'] &&
    current['revision'] == expected['revision'];

Future<int> _updateIntentCas(
  DatabaseExecutor db,
  Map<String, Object?> expected,
  Map<String, Object?> replacement,
) {
  return db.update(
    _table,
    replacement,
    where: 'group_id = ? AND intent_id = ? AND state = ? AND revision = ?',
    whereArgs: [
      expected['group_id'],
      expected['intent_id'],
      expected['state'],
      expected['revision'],
    ],
  );
}

Future<int> _deleteIntentCas(
  DatabaseExecutor db,
  Map<String, Object?> expected,
) {
  return db.delete(
    _table,
    where: 'group_id = ? AND intent_id = ? AND state = ? AND revision = ?',
    whereArgs: [
      expected['group_id'],
      expected['intent_id'],
      expected['state'],
      expected['revision'],
    ],
  );
}

Future<int> _deleteExactNotice(
  DatabaseExecutor db,
  Map<String, Object?> intent,
) async {
  final sourceEventId = intent['source_event_id'] as String?;
  final eventAt = intent['event_at'] as String?;
  if (sourceEventId == null || eventAt == null) return 0;
  return db.delete(
    _pendingTable,
    where:
        'id = ? AND group_id = ? AND kind = ? '
        'AND source_message_id = ? AND event_at = ?',
    whereArgs: [
      intent['pending_broadcast_id'],
      intent['group_id'],
      _leaveNoticeKind,
      sourceEventId,
      eventAt,
    ],
  );
}

Future<int> _deleteExactMap(
  DatabaseExecutor db,
  String table,
  Map<String, Object?> expected,
) {
  final where = expected.keys.map((key) => '"$key" IS ?').join(' AND ');
  return db.delete(table, where: where, whereArgs: expected.values.toList());
}

bool _isValidQueuedInsert(Map<String, Object?> row) {
  return row['group_id'] is String &&
      (row['group_id'] as String).isNotEmpty &&
      row['intent_id'] is String &&
      (row['intent_id'] as String).isNotEmpty &&
      row['self_peer_id'] is String &&
      (row['self_peer_id'] as String).isNotEmpty &&
      row['self_joined_at'] is String &&
      (row['self_joined_at'] as String).isNotEmpty &&
      row['state'] == _queued &&
      row['pending_broadcast_id'] is String &&
      (row['pending_broadcast_id'] as String).isNotEmpty &&
      row['source_event_id'] == null &&
      row['event_at'] == null &&
      row['revision'] == 0 &&
      row['last_error_code'] == null &&
      row['created_at'] is String &&
      row['updated_at'] is String;
}

bool _validNoticePayload(
  Map<String, Object?> expected,
  Map<String, Object?> timeline,
  Map<String, Object?> pending,
) {
  if (expected['state'] != _queued ||
      pending['kind'] != _leaveNoticeKind ||
      pending['id'] != expected['pending_broadcast_id'] ||
      pending['group_id'] != expected['group_id'] ||
      timeline['group_id'] != expected['group_id'] ||
      pending['source_message_id'] is! String ||
      (pending['source_message_id'] as String).isEmpty ||
      pending['event_at'] is! String ||
      timeline['timestamp'] is! String) {
    return false;
  }
  try {
    return DateTime.parse(timeline['timestamp'] as String).toUtc() ==
        DateTime.parse(pending['event_at'] as String).toUtc();
  } on FormatException {
    return false;
  }
}

bool _sameNoticeIdentity(
  Map<String, Object?> intent,
  Map<String, Object?> pending,
) =>
    pending['id'] == intent['pending_broadcast_id'] &&
    pending['group_id'] == intent['group_id'] &&
    pending['kind'] == _leaveNoticeKind &&
    pending['source_message_id'] == intent['source_event_id'] &&
    pending['event_at'] == intent['event_at'];

bool _isLegalPostNoticeTransition(String? current, String next) =>
    (current != null && current == next) ||
    (current == _leaveNoticeAttempted && next == _rotationClaimed) ||
    (current == _rotationClaimed && next == _nativeLeavePending) ||
    (current == _nativeLeavePending && next == _cleanupPending);

bool _isRoleKind(String kind) =>
    kind == _preparedRoleKind || kind == _activeRoleKind;

bool _containsExactValues(
  Map<String, Object?> stored,
  Map<String, Object?> expected,
) {
  for (final entry in expected.entries) {
    if (stored[entry.key] != entry.value) return false;
  }
  return true;
}

bool _sameRow(Map<String, Object?> current, Map<String, Object?> expected) =>
    current.length == expected.length &&
    _containsExactValues(current, expected);

String? _validateErrorCode(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 64 ||
      !RegExp(r'^[a-z0-9_:\-]+$').hasMatch(trimmed)) {
    throw ArgumentError.value(value, 'lastErrorCode', 'invalid bounded code');
  }
  return trimmed;
}

void _requireTimestamp(String value, String name) {
  try {
    DateTime.parse(value);
  } on FormatException {
    throw ArgumentError.value(value, name, 'must be an ISO-8601 timestamp');
  }
}

Future<bool> _tableExists(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    [table],
  );
  return rows.isNotEmpty;
}

class _RollbackMutation implements Exception {
  const _RollbackMutation(this.disposition);

  final DbGroupExitIntentMutationDisposition disposition;
}
