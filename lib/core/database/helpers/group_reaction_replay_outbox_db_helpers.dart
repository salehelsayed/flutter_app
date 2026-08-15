import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../services/protected_group_content_contract.dart';
import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'group_event_log_db_helpers.dart';
import 'group_parent_write_guard.dart';
import 'protected_group_content_db_helpers.dart';
import 'protected_group_reaction_target_db_helpers.dart';

const _reactionReplayAuthorityFields = <String>[
  'reaction_id',
  'group_id',
  'message_id',
  'sender_peer_id',
  'emoji',
  'action',
  'inbox_retry_payload',
  'delivery_status',
  'last_error',
  'created_at',
  'updated_at',
];

bool _sameReactionReplayAuthority(
  Map<String, Object?> current,
  Map<String, Object?> expected,
) {
  for (final field in _reactionReplayAuthorityFields) {
    if (current[field] != expected[field]) return false;
  }
  return true;
}

bool _isExactStrictReactionRetryRecipientShrink(
  String previousRaw,
  String replacementRaw,
) {
  try {
    final previous = ProtectedGroupContentRetryManifest.decode(previousRaw);
    final replacement = ProtectedGroupContentRetryManifest.decode(
      replacementRaw,
    );
    if (previous.groupId != replacement.groupId ||
        previous.replayEnvelope != replacement.replayEnvelope ||
        previous.contentEventId != replacement.contentEventId ||
        previous.payloadType != protectedGroupContentReactionPayloadType ||
        replacement.payloadType != previous.payloadType ||
        previous.pendingRecipientPeerIds.length !=
            replacement.pendingRecipientPeerIds.length + 1 ||
        previous.fullRecipientPeerIds.length !=
            replacement.fullRecipientPeerIds.length) {
      return false;
    }
    for (var index = 0; index < previous.fullRecipientPeerIds.length; index++) {
      if (previous.fullRecipientPeerIds[index] !=
          replacement.fullRecipientPeerIds[index]) {
        return false;
      }
    }
    final prior = previous.pendingRecipientPeerIds.toSet();
    final next = replacement.pendingRecipientPeerIds.toSet();
    return prior.containsAll(next) && prior.difference(next).length == 1;
  } catch (_) {
    return false;
  }
}

/// Plan 319: returns whether a row now exists. The group-parent write guard
/// silently inserts zero rows for a self-removed parent; swallowing that made
/// callers claim custody that was never staged.
Future<bool> dbUpsertGroupReactionReplayOutboxEntry(
  Database db,
  Map<String, Object?> row,
) async {
  final reactionId = row['reaction_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPSERT_START',
    details: {
      'reactionId': reactionId.length > 8
          ? reactionId.substring(0, 8)
          : reactionId,
    },
  );

  try {
    final inserted = await dbInsertOrdinaryGroupOwnedRow(
      db,
      table: 'group_reaction_replay_outbox',
      row: row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPSERT_SUCCESS',
      details: {
        'reactionId': reactionId.length > 8
            ? reactionId.substring(0, 8)
            : reactionId,
        'inserted': inserted,
      },
    );
    return inserted;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Plan 319: atomically promote a `needs_build` row to `pending` with its
/// freshly built payload. Returns false when the row is gone (swept by a group
/// exit, self-removal, or message deletion mid-build).
Future<bool> dbAttachGroupReactionReplayOutboxPayload(
  Database db, {
  required String reactionId,
  required String inboxRetryPayload,
  required String updatedAt,
}) async {
  final updated = await db.update(
    'group_reaction_replay_outbox',
    <String, Object?>{
      'inbox_retry_payload': inboxRetryPayload,
      'delivery_status': 'pending',
      'last_error': null,
      'updated_at': updatedAt,
    },
    where: 'reaction_id = ? AND delivery_status = ?',
    whereArgs: <Object?>[reactionId, 'needs_build'],
  );
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_ATTACH_PAYLOAD',
    details: {'updated': updated},
  );
  return updated > 0;
}

Future<Map<String, Object?>?> dbLoadGroupReactionReplayOutboxEntry(
  Database db,
  String reactionId,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_reaction_replay_outbox.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM group_reaction_replay_outbox '
    'WHERE reaction_id = ? AND $parent LIMIT 1',
    [reactionId],
  );
  if (rows.isEmpty) return null;
  return rows.first;
}

Future<Map<String, Object?>?>
dbLoadLatestGroupReactionReplayOutboxEntryForTarget(
  Database db, {
  required String groupId,
  required String messageId,
  required String senderPeerId,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_reaction_replay_outbox.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM group_reaction_replay_outbox '
    'WHERE group_id = ? AND message_id = ? AND sender_peer_id = ? '
    'AND $parent ORDER BY created_at DESC, rowid DESC LIMIT 1',
    [groupId, messageId, senderPeerId],
  );
  if (rows.isEmpty) return null;
  return rows.first;
}

Future<List<Map<String, Object?>>>
dbLoadRetryableGroupReactionReplayOutboxEntries(
  Database db, {
  int limit = 20,
  bool strictContentOnly = false,
  int offset = 0,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_LOAD_RETRYABLE_START',
    details: {'limit': limit},
  );

  try {
    final parent = await dbOrdinaryGroupParentPredicate(
      db,
      groupIdExpression: 'group_reaction_replay_outbox.group_id',
    );
    final rows = await db.rawQuery(
      'SELECT * FROM group_reaction_replay_outbox '
      'WHERE delivery_status IN (?, ?, ?) '
      "AND (? = 0 OR instr(inbox_retry_payload, 'group_content_v1') > 0) "
      'AND $parent '
      'ORDER BY created_at ASC, reaction_id ASC LIMIT ? OFFSET ?',
      [
        'pending',
        'failed',
        'needs_build',
        strictContentOnly ? 1 : 0,
        limit,
        offset,
      ],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_LOAD_RETRYABLE_SUCCESS',
      details: {'count': rows.length},
    );

    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_LOAD_RETRYABLE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<void> dbUpdateGroupReactionReplayOutboxEntryStatus(
  Database db,
  String reactionId, {
  required String deliveryStatus,
  String? lastError,
  required String updatedAt,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPDATE_STATUS_START',
    details: {
      'reactionId': reactionId.length > 8
          ? reactionId.substring(0, 8)
          : reactionId,
      'deliveryStatus': deliveryStatus,
    },
  );

  try {
    final existing = await db.query(
      'group_reaction_replay_outbox',
      columns: const ['group_id'],
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
      limit: 1,
    );
    if (existing.isEmpty) return;
    await dbUpdateOrdinaryGroupOwnedRows(
      db,
      table: 'group_reaction_replay_outbox',
      groupId: existing.single['group_id'] as String? ?? '',
      values: {
        'delivery_status': deliveryStatus,
        'last_error': lastError,
        'updated_at': updatedAt,
      },
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPDATE_STATUS_SUCCESS',
      details: {
        'reactionId': reactionId.length > 8
            ? reactionId.substring(0, 8)
            : reactionId,
        'deliveryStatus': deliveryStatus,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPDATE_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Completes one loaded reaction replay action only while the complete outbox
/// row and its unmarked group parent are unchanged. A newer reaction
/// transition may reuse the same deterministic row id; the old network result
/// must never mark that replacement stored/failed.
Future<bool> dbUpdateGroupReactionReplayOutboxEntryStatusIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required String deliveryStatus,
  String? lastError,
  required String updatedAt,
}) {
  return dbWriteTransaction(db, (txn) async {
    final reactionId = expected['reaction_id'] as String? ?? '';
    final groupId = expected['group_id'] as String? ?? '';
    if (reactionId.isEmpty ||
        groupId.isEmpty ||
        !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
      return false;
    }
    final rows = await txn.query(
      'group_reaction_replay_outbox',
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
      limit: 1,
    );
    if (rows.isEmpty || !_sameReactionReplayAuthority(rows.single, expected)) {
      return false;
    }
    final updated = await dbUpdateOrdinaryGroupOwnedRows(
      txn,
      table: 'group_reaction_replay_outbox',
      groupId: groupId,
      values: {
        'delivery_status': deliveryStatus,
        'last_error': lastError,
        'updated_at': updatedAt,
      },
      where: 'reaction_id = ? AND delivery_status = ? AND updated_at = ?',
      whereArgs: [
        reactionId,
        expected['delivery_status'],
        expected['updated_at'],
      ],
    );
    return updated == 1;
  });
}

/// Atomically shrinks only the pending-recipient wrapper of one exact strict
/// reaction replay row. A stale receipt cannot mutate a replacement
/// transition that reused the deterministic row identity.
Future<bool> dbReplaceGroupReactionReplayOutboxPayloadIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required String replacement,
  required String updatedAt,
}) {
  return dbWriteTransaction(db, (txn) async {
    final reactionId = expected['reaction_id'] as String? ?? '';
    final groupId = expected['group_id'] as String? ?? '';
    final previous = expected['inbox_retry_payload'] as String? ?? '';
    if (reactionId.isEmpty ||
        groupId.isEmpty ||
        previous.isEmpty ||
        replacement.isEmpty ||
        !_isExactStrictReactionRetryRecipientShrink(previous, replacement) ||
        !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
      return false;
    }
    final rows = await txn.query(
      'group_reaction_replay_outbox',
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
      limit: 1,
    );
    if (rows.isEmpty || !_sameReactionReplayAuthority(rows.single, expected)) {
      return false;
    }
    final updated = await dbUpdateOrdinaryGroupOwnedRows(
      txn,
      table: 'group_reaction_replay_outbox',
      groupId: groupId,
      values: <String, Object?>{
        'inbox_retry_payload': replacement,
        'updated_at': updatedAt,
      },
      where:
          'reaction_id = ? AND inbox_retry_payload = ? '
          'AND delivery_status = ? AND updated_at = ?',
      whereArgs: <Object?>[
        reactionId,
        previous,
        expected['delivery_status'],
        expected['updated_at'],
      ],
    );
    return updated == 1;
  });
}

class _ReactionContentOwnerCasMiss implements Exception {
  const _ReactionContentOwnerCasMiss();
}

Future<bool> dbCompleteGroupReactionContentIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> reactionRow,
  required String action,
  required String transitionId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
  required String updatedAt,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final reactionId = expected['reaction_id'] as String? ?? '';
      final groupId = expected['group_id'] as String? ?? '';
      final messageId = expected['message_id'] as String? ?? '';
      final actor = expected['sender_peer_id'] as String? ?? '';
      if (reactionId.isEmpty ||
          reactionId != transitionId ||
          groupId.isEmpty ||
          messageId.isEmpty ||
          actor.isEmpty ||
          (action != 'add' && action != 'remove') ||
          !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
        return false;
      }
      final rows = await txn.query(
        'group_reaction_replay_outbox',
        where: 'reaction_id = ?',
        whereArgs: <Object?>[reactionId],
        limit: 1,
      );
      if (rows.isEmpty ||
          !_sameReactionReplayAuthority(rows.single, expected) ||
          reactionRow['message_id'] != messageId ||
          reactionRow['sender_peer_id'] != actor) {
        return false;
      }
      final retryWrapper = rows.single['inbox_retry_payload'] as String? ?? '';
      try {
        // The decoder revalidates the immutable signed envelope/full ACL. This
        // transaction may retire only the one mutable recipient represented by
        // the final accepted receipt.
        final manifest = ProtectedGroupContentRetryManifest.decode(
          retryWrapper,
        );
        if (manifest.groupId != groupId ||
            manifest.payloadType != protectedGroupContentReactionPayloadType ||
            manifest.contentEventId != transitionId ||
            manifest.pendingRecipientPeerIds.length != 1) {
          return false;
        }
      } catch (_) {
        return false;
      }
      if (!await dbHasExactProtectedGroupContentPreparedOwner(
        txn,
        groupId: groupId,
        payloadType: protectedGroupContentReactionPayloadType,
        contentEventId: transitionId,
        ownerKind: 'group_reaction',
        ownerId: transitionId,
        ownerStatus: expected['delivery_status'] as String? ?? '',
        retryWrapper: retryWrapper,
        eventPayload: eventPayload,
      )) {
        return false;
      }
      if (await dbHasProtectedGroupContentTerminalInTransaction(
        txn,
        groupId: groupId,
        payloadType: 'group_reaction',
        contentEventId: reactionId,
      )) {
        return false;
      }

      final committed = await dbCommitProtectedGroupReactionInTransaction(
        txn,
        groupId: groupId,
        sourcePeerId: sourcePeerId,
        sourceEventId: sourceEventId,
        sourceTimestamp: sourceTimestamp,
        eventPayload: eventPayload,
        reactionRow: reactionRow,
        transitionId: transitionId,
        action: action,
      );
      if (committed ==
          DbProtectedGroupContentCommitResult.prerequisiteMissing) {
        return false;
      }

      final updated = await dbUpdateOrdinaryGroupOwnedRows(
        txn,
        table: 'group_reaction_replay_outbox',
        groupId: groupId,
        values: <String, Object?>{
          'delivery_status': 'stored',
          'last_error': null,
          'updated_at': updatedAt,
        },
        where:
            'reaction_id = ? AND inbox_retry_payload = ? '
            'AND delivery_status = ? AND updated_at = ?',
        whereArgs: <Object?>[
          reactionId,
          retryWrapper,
          expected['delivery_status'],
          expected['updated_at'],
        ],
      );
      if (updated != 1) throw const _ReactionContentOwnerCasMiss();

      final completed = await txn.query(
        'group_reaction_replay_outbox',
        columns: const <String>[
          'reaction_id',
          'delivery_status',
          'last_error',
          'updated_at',
        ],
        where: 'reaction_id = ?',
        whereArgs: <Object?>[reactionId],
        limit: 1,
      );
      if (completed.isEmpty ||
          completed.single['delivery_status'] != 'stored' ||
          completed.single['last_error'] != null ||
          completed.single['updated_at'] != updatedAt) {
        throw StateError('protected reaction completion readback failed');
      }
      return true;
    }, exclusive: true);
  } on _ReactionContentOwnerCasMiss {
    return false;
  }
}

/// Atomically stages and terminally projects a zero-target strict reaction.
/// The stored outbox owner cannot survive without its protected event and LWW
/// projection, and none of those writes survive an owner conflict.
Future<bool> dbStageAndCompleteLocalGroupReactionContent(
  Database db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> reactionRow,
  required String action,
  required String transitionId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
}) {
  return dbWriteTransaction(db, (txn) async {
    final reactionId = expected['reaction_id'] as String? ?? '';
    final groupId = expected['group_id'] as String? ?? '';
    if (reactionId.isEmpty ||
        reactionId != transitionId ||
        groupId.isEmpty ||
        expected['inbox_retry_payload'] != '' ||
        expected['delivery_status'] != 'stored' ||
        !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
      return false;
    }
    var rows = await txn.query(
      'group_reaction_replay_outbox',
      where: 'reaction_id = ?',
      whereArgs: <Object?>[reactionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (!await dbInsertOrdinaryGroupOwnedRow(
        txn,
        table: 'group_reaction_replay_outbox',
        row: expected,
        conflictAlgorithm: ConflictAlgorithm.abort,
      )) {
        return false;
      }
      rows = await txn.query(
        'group_reaction_replay_outbox',
        where: 'reaction_id = ?',
        whereArgs: <Object?>[reactionId],
        limit: 1,
      );
    }
    if (rows.isEmpty || !_sameReactionReplayAuthority(rows.single, expected)) {
      return false;
    }
    final committed = await dbCommitProtectedGroupReactionInTransaction(
      txn,
      groupId: groupId,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      eventPayload: eventPayload,
      reactionRow: reactionRow,
      transitionId: transitionId,
      action: action,
    );
    if (committed == DbProtectedGroupContentCommitResult.prerequisiteMissing) {
      return false;
    }
    final readback = await txn.query(
      'group_reaction_replay_outbox',
      where: 'reaction_id = ?',
      whereArgs: <Object?>[reactionId],
      limit: 1,
    );
    if (readback.isEmpty ||
        !_sameReactionReplayAuthority(readback.single, expected)) {
      throw StateError('protected local reaction terminal readback failed');
    }
    return true;
  }, exclusive: true);
}

Future<bool> dbStagePreparedLocalGroupReactionContent(
  Database db, {
  required Map<String, Object?> expected,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> preparedEventPayload,
}) {
  return dbWriteTransaction(db, (txn) async {
    final reactionId = expected['reaction_id'] as String? ?? '';
    final groupId = expected['group_id'] as String? ?? '';
    final retryPayload = expected['inbox_retry_payload'] as String? ?? '';
    if (reactionId.isEmpty ||
        groupId.isEmpty ||
        retryPayload.isEmpty ||
        expected['delivery_status'] != 'pending' ||
        !sourceEventId.startsWith('ppr1:') ||
        !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
      return false;
    }
    if (!isExactProtectedGroupContentPreparedStage(
      groupId: groupId,
      payloadType: 'group_reaction',
      contentEventId: reactionId,
      ownerKind: 'group_reaction',
      ownerId: reactionId,
      ownerStatus: expected['delivery_status'] as String? ?? '',
      retryWrapper: retryPayload,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      preparedEventPayload: preparedEventPayload,
    )) {
      return false;
    }
    final preparedPlaintext = preparedEventPayload['payload'];
    if (preparedPlaintext is! Map ||
        !_isExactProtectedPreparedReactionOwner(expected, preparedPlaintext)) {
      return false;
    }
    final targetDisposition = await dbClassifyProtectedGroupReactionTarget(
      txn,
      groupId: groupId,
      messageId: expected['message_id'] as String? ?? '',
    );
    if (targetDisposition !=
        ProtectedGroupReactionTargetDisposition.available) {
      return false;
    }
    var rows = await txn.query(
      'group_reaction_replay_outbox',
      where: 'reaction_id = ?',
      whereArgs: <Object?>[reactionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (!await dbInsertOrdinaryGroupOwnedRow(
        txn,
        table: 'group_reaction_replay_outbox',
        row: expected,
        conflictAlgorithm: ConflictAlgorithm.abort,
      )) {
        return false;
      }
      rows = await txn.query(
        'group_reaction_replay_outbox',
        where: 'reaction_id = ?',
        whereArgs: <Object?>[reactionId],
        limit: 1,
      );
    }
    if (rows.isEmpty || !_sameReactionReplayAuthority(rows.single, expected)) {
      return false;
    }
    await dbAppendGroupEventLogEntryInTransaction(
      txn,
      groupId: groupId,
      eventType: protectedGroupContentPreparedEventType,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      payload: preparedEventPayload,
    );
    return true;
  }, exclusive: true);
}

bool _isExactProtectedPreparedReactionOwner(
  Map<String, Object?> expected,
  Map<Object?, Object?> payload,
) {
  final createdAt = expected['created_at'];
  final payloadTimestamp = payload['timestamp'];
  final rowAt = createdAt is String ? DateTime.tryParse(createdAt) : null;
  final payloadAt = payloadTimestamp is String
      ? DateTime.tryParse(payloadTimestamp)
      : null;
  return expected['reaction_id'] == payload['eventId'] &&
      expected['group_id'] == payload['groupId'] &&
      expected['message_id'] == payload['messageId'] &&
      expected['sender_peer_id'] == payload['senderPeerId'] &&
      expected['emoji'] == payload['emoji'] &&
      expected['action'] == payload['action'] &&
      rowAt != null &&
      payloadAt != null &&
      rowAt.toUtc() == payloadAt.toUtc();
}

/// Atomically terminalizes one exact nonempty-ACL protected reaction owner.
Future<bool> dbTerminalizePreparedLocalGroupReactionIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> preparedEventPayload,
  required String terminalSourcePeerId,
  required String terminalSourceEventId,
  required String terminalSourceTimestamp,
  required Map<String, Object?> terminalEventPayload,
}) async {
  try {
    return await dbWriteTransaction(
      db,
      (txn) => dbTerminalizePreparedLocalGroupReactionIfExactInTransaction(
        txn,
        expected: expected,
        preparedEventPayload: preparedEventPayload,
        terminalSourcePeerId: terminalSourcePeerId,
        terminalSourceEventId: terminalSourceEventId,
        terminalSourceTimestamp: terminalSourceTimestamp,
        terminalEventPayload: terminalEventPayload,
      ),
      exclusive: true,
    );
  } on _ReactionContentOwnerCasMiss {
    return false;
  }
}

/// Transaction-scoped form for reconciliation's owner/evidence/frontier
/// commit. A CAS miss after terminal evidence is appended throws so the outer
/// transaction cannot advance past an unterminated owner.
Future<bool> dbTerminalizePreparedLocalGroupReactionIfExactInTransaction(
  DatabaseExecutor txn, {
  required Map<String, Object?> expected,
  required Map<String, Object?> preparedEventPayload,
  required String terminalSourcePeerId,
  required String terminalSourceEventId,
  required String terminalSourceTimestamp,
  required Map<String, Object?> terminalEventPayload,
}) async {
  final reactionId = expected['reaction_id'] as String? ?? '';
  final groupId = expected['group_id'] as String? ?? '';
  final retryWrapper = expected['inbox_retry_payload'] as String? ?? '';
  if (reactionId.isEmpty || groupId.isEmpty || retryWrapper.isEmpty) {
    return false;
  }
  final reason =
      terminalEventPayload['reasonCode'] as String? ??
      'protected_content_terminal';
  final terminal = Map<String, Object?>.from(expected)
    ..['inbox_retry_payload'] = ''
    ..['delivery_status'] = 'stored'
    ..['last_error'] = reason
    ..['updated_at'] = terminalSourceTimestamp;
  final rows = await txn.query(
    'group_reaction_replay_outbox',
    where: 'reaction_id = ? AND group_id = ?',
    whereArgs: <Object?>[reactionId, groupId],
    limit: 1,
  );
  if (rows.isEmpty) return false;
  final current = rows.single;
  final alreadyTerminal = _sameReactionReplayAuthority(current, terminal);
  if (!alreadyTerminal && !_sameReactionReplayAuthority(current, expected)) {
    return false;
  }
  if (!await dbHasExactProtectedGroupContentPreparedOwner(
    txn,
    groupId: groupId,
    payloadType: 'group_reaction',
    contentEventId: reactionId,
    ownerKind: 'group_reaction',
    ownerId: reactionId,
    ownerStatus: expected['delivery_status'] as String? ?? '',
    retryWrapper: retryWrapper,
    eventPayload: preparedEventPayload,
  )) {
    return false;
  }
  final hasTerminal = await dbHasProtectedGroupContentTerminalInTransaction(
    txn,
    groupId: groupId,
    payloadType: 'group_reaction',
    contentEventId: reactionId,
  );
  if (hasTerminal) return alreadyTerminal;
  await dbCommitProtectedGroupContentTerminalInTransaction(
    txn,
    groupId: groupId,
    sourcePeerId: terminalSourcePeerId,
    sourceEventId: terminalSourceEventId,
    sourceTimestamp: terminalSourceTimestamp,
    eventPayload: terminalEventPayload,
  );
  if (!alreadyTerminal) {
    final updated = await txn.rawUpdate(
      "UPDATE group_reaction_replay_outbox SET inbox_retry_payload = '', "
      "delivery_status = 'stored', last_error = ?, updated_at = ? "
      'WHERE reaction_id = ? AND group_id = ? '
      'AND inbox_retry_payload = ? AND delivery_status = ? '
      'AND updated_at = ?',
      <Object?>[
        reason,
        terminalSourceTimestamp,
        reactionId,
        groupId,
        retryWrapper,
        expected['delivery_status'],
        expected['updated_at'],
      ],
    );
    if (updated != 1) throw const _ReactionContentOwnerCasMiss();
  }
  final readback = await txn.query(
    'group_reaction_replay_outbox',
    where: 'reaction_id = ? AND group_id = ?',
    whereArgs: <Object?>[reactionId, groupId],
    limit: 1,
  );
  if (readback.isEmpty ||
      !_sameReactionReplayAuthority(readback.single, terminal)) {
    throw StateError('protected reaction terminal owner readback failed');
  }
  return true;
}

Future<bool> dbHasExactPreparedLocalGroupReaction(
  DatabaseExecutor db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> eventPayload,
}) async {
  final reactionId = expected['reaction_id'] as String? ?? '';
  final groupId = expected['group_id'] as String? ?? '';
  final retryWrapper = expected['inbox_retry_payload'] as String? ?? '';
  if (reactionId.isEmpty || groupId.isEmpty || retryWrapper.isEmpty) {
    return false;
  }
  final rows = await db.query(
    'group_reaction_replay_outbox',
    where: 'reaction_id = ? AND group_id = ?',
    whereArgs: <Object?>[reactionId, groupId],
    limit: 1,
  );
  return rows.isNotEmpty &&
      _sameReactionReplayAuthority(rows.single, expected) &&
      await dbHasExactProtectedGroupContentPreparedOwner(
        db,
        groupId: groupId,
        payloadType: 'group_reaction',
        contentEventId: reactionId,
        ownerKind: 'group_reaction',
        ownerId: reactionId,
        ownerStatus: expected['delivery_status'] as String? ?? '',
        retryWrapper: retryWrapper,
        eventPayload: eventPayload,
      );
}

Future<void> dbDeleteGroupReactionReplayOutboxEntry(
  Database db,
  String reactionId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_DELETE_START',
    details: {
      'reactionId': reactionId.length > 8
          ? reactionId.substring(0, 8)
          : reactionId,
    },
  );

  try {
    await db.delete(
      'group_reaction_replay_outbox',
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_DELETE_SUCCESS',
      details: {
        'reactionId': reactionId.length > 8
            ? reactionId.substring(0, 8)
            : reactionId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
