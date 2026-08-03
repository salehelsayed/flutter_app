import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../notifications/deterministic_notification_id.dart';
import '../db_write_transaction.dart';

const String _table = 'group_notification_display_outbox';
const int kGroupNotificationDisplayOutboxCapacity = 512;
const int kGroupNotificationDisplayOutboxMaxLoadBatch = 50;

const List<String> _authorityFields = <String>[
  'event_id',
  'event_kind',
  'group_id',
  'message_id',
  'actor_peer_id',
  'event_timestamp',
  'reaction_id',
  'reaction_action',
  'reaction_tombstone',
];

bool _sameAuthority(
  Map<String, Object?> current,
  Map<String, Object?> incoming,
) {
  for (final field in _authorityFields) {
    if (current[field] != incoming[field]) return false;
  }
  return true;
}

/// Acquires durable display custody before canonical mutation.
///
/// Replaying the exact event is idempotent even if the existing marker has
/// already advanced. Reusing an event id for different authority or reaching
/// capacity throws before any row changes; live custody is never evicted.
Future<void> dbStageGroupNotificationDisplayOutboxEntry(
  Database db,
  Map<String, Object?> row, {
  int capacity = kGroupNotificationDisplayOutboxCapacity,
}) {
  if (capacity <= 0) {
    throw StateError('group notification display outbox capacity exhausted');
  }
  if (row['readiness'] != 'not_ready' ||
      row['revision'] != 1 ||
      row['retry_count'] != 0 ||
      row['last_error_code'] != null ||
      row['last_attempt_at'] != null ||
      row['next_attempt_at'] != null) {
    throw StateError('a new display marker must be pristine and not_ready');
  }

  return dbWriteTransaction(db, (txn) async {
    final eventId = row['event_id'] as String? ?? '';
    final existing = await txn.query(
      _table,
      where: 'event_id = ?',
      whereArgs: <Object?>[eventId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      if (_sameAuthority(existing.single, row)) return;
      throw StateError('display outbox event id authority conflict');
    }

    final count = Sqflite.firstIntValue(
      await txn.rawQuery('SELECT COUNT(*) FROM $_table'),
    );
    if ((count ?? 0) >= capacity) {
      throw StateError('group notification display outbox capacity exhausted');
    }
    await txn.insert(_table, row, conflictAlgorithm: ConflictAlgorithm.abort);
  }, exclusive: true);
}

Future<Map<String, Object?>?> dbLoadGroupNotificationDisplayOutboxEntry(
  DatabaseExecutor db,
  String eventId,
) async {
  if (!await _tableExists(db)) return null;
  final rows = await db.query(
    _table,
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<bool> dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
  DatabaseExecutor db, {
  required String eventId,
  required int expectedRevision,
  required String updatedAt,
}) async {
  if (!await _tableExists(db)) return false;
  final updated = await db.rawUpdate(
    'UPDATE $_table SET readiness = ?, revision = revision + 1, '
    'last_error_code = NULL, last_attempt_at = NULL, next_attempt_at = NULL, '
    'updated_at = ? WHERE event_id = ? AND revision = ? AND readiness = ?',
    <Object?>['ready', updatedAt, eventId, expectedRevision, 'not_ready'],
  );
  return updated == 1;
}

Future<List<Map<String, Object?>>>
dbLoadReadyGroupNotificationDisplayOutboxEntries(
  DatabaseExecutor db, {
  int limit = 20,
  required String eligibleAt,
}) async {
  if (limit <= 0 || !await _tableExists(db)) return const [];
  final boundedLimit = math.min(
    limit,
    kGroupNotificationDisplayOutboxMaxLoadBatch,
  );
  return db.rawQuery(
    'SELECT * FROM $_table WHERE readiness = ? '
    'AND (next_attempt_at IS NULL OR next_attempt_at <= ?) '
    'ORDER BY created_at ASC, event_id ASC LIMIT ?',
    <Object?>['ready', eligibleAt, boundedLimit],
  );
}

/// Returns the earliest persisted retry deadline for ready custody.
///
/// Rows without [next_attempt_at] are already returned by the ready loader;
/// this query is used only after that loader produced an empty batch.
Future<String?> dbLoadEarliestGroupNotificationDisplayOutboxNextAttemptAt(
  DatabaseExecutor db,
) async {
  if (!await _tableExists(db)) return null;
  final rows = await db.rawQuery(
    'SELECT next_attempt_at FROM $_table WHERE readiness = ? '
    'AND next_attempt_at IS NOT NULL ORDER BY next_attempt_at ASC LIMIT 1',
    const <Object?>['ready'],
  );
  return rows.isEmpty ? null : rows.single['next_attempt_at'] as String?;
}

Future<bool> dbRecordGroupNotificationDisplayOutboxRetryIfExact(
  DatabaseExecutor db, {
  required String eventId,
  required int expectedRevision,
  required String lastErrorCode,
  required String lastAttemptAt,
  required String nextAttemptAt,
  required String updatedAt,
}) async {
  if (!await _tableExists(db)) return false;
  final updated = await db.rawUpdate(
    'UPDATE $_table SET retry_count = retry_count + 1, '
    'last_error_code = ?, last_attempt_at = ?, next_attempt_at = ?, '
    'updated_at = ?, revision = revision + 1 '
    'WHERE event_id = ? AND revision = ? AND readiness = ?',
    <Object?>[
      lastErrorCode,
      lastAttemptAt,
      nextAttemptAt,
      updatedAt,
      eventId,
      expectedRevision,
      'ready',
    ],
  );
  return updated == 1;
}

Future<bool> dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
  Database db, {
  required String eventId,
  required int expectedRevision,
  required String expectedEventKind,
  required String expectedGroupId,
  required String expectedMessageId,
  required String expectedActorPeerId,
  required String expectedEventTimestamp,
  required String? expectedReactionId,
  required String? expectedReactionAction,
  required bool? expectedReactionTombstone,
}) => dbWriteTransaction(db, (txn) async {
  if (!await _tableExists(txn)) return false;
  final where = StringBuffer(
    'event_id = ? AND revision = ? AND readiness = ? '
    'AND event_kind = ? AND group_id = ? AND message_id = ? '
    'AND actor_peer_id = ? AND event_timestamp = ?',
  );
  final whereArgs = <Object?>[
    eventId,
    expectedRevision,
    'ready',
    expectedEventKind,
    expectedGroupId,
    expectedMessageId,
    expectedActorPeerId,
    expectedEventTimestamp,
  ];
  if (expectedReactionId == null) {
    where.write(' AND reaction_id IS NULL');
  } else {
    where.write(' AND reaction_id = ?');
    whereArgs.add(expectedReactionId);
  }
  if (expectedReactionAction == null) {
    where.write(' AND reaction_action IS NULL');
  } else {
    where.write(' AND reaction_action = ?');
    whereArgs.add(expectedReactionAction);
  }
  if (expectedReactionTombstone == null) {
    where.write(' AND reaction_tombstone IS NULL');
  } else {
    where.write(' AND reaction_tombstone = ?');
    whereArgs.add(expectedReactionTombstone ? 1 : 0);
  }
  final exactCustody = await txn.query(
    _table,
    columns: const <String>['event_id'],
    where: where.toString(),
    whereArgs: whereArgs,
    limit: 1,
  );
  if (exactCustody.isEmpty) return false;

  // Record the terminal canonical generation before retiring ready custody.
  // Both writes share this transaction, so a failed CAS/delete cannot leave a
  // false terminal fact and a successful delete cannot lose dedupe authority.
  if (expectedEventKind == 'message') {
    await txn.rawUpdate(
      'UPDATE group_messages '
      'SET notification_display_terminal_event_id = ? '
      'WHERE id = ? AND group_id = ? AND sender_peer_id = ? '
      'AND timestamp = ? '
      'AND (notification_display_terminal_event_id IS NULL '
      'OR notification_display_terminal_event_id = ?)',
      <Object?>[
        eventId,
        expectedMessageId,
        expectedGroupId,
        expectedActorPeerId,
        expectedEventTimestamp,
        eventId,
      ],
    );
  } else if (expectedEventKind == 'reaction' &&
      expectedReactionId != null &&
      expectedReactionAction == 'add' &&
      expectedReactionTombstone == false) {
    final terminalIdentity = boundedReactionEventIdentity(eventId);
    await txn.rawUpdate(
      'UPDATE message_reactions '
      'SET notification_display_terminal_event_id = ? '
      'WHERE id = ? AND message_id = ? AND sender_peer_id = ? '
      'AND timestamp = ? AND removed_at IS NULL '
      'AND (notification_display_terminal_event_id IS NULL '
      'OR notification_display_terminal_event_id = ?) '
      'AND EXISTS (SELECT 1 FROM group_messages '
      'WHERE group_messages.id = message_reactions.message_id '
      'AND group_messages.group_id = ?)',
      <Object?>[
        terminalIdentity,
        expectedReactionId,
        expectedMessageId,
        expectedActorPeerId,
        expectedEventTimestamp,
        terminalIdentity,
        expectedGroupId,
      ],
    );
  }

  final deleted = await txn.delete(
    _table,
    where: where.toString(),
    whereArgs: whereArgs,
  );
  if (deleted != 1) {
    throw StateError('group notification display completion CAS failed');
  }
  return true;
}, exclusive: true);

/// Atomically moves duplicate-message display custody onto its canonical row.
///
/// A reminted wire message ID can stage an alias marker before logical-ID
/// dedupe discovers the existing canonical message. If canonical custody
/// exists it is promoted and the exact alias is retired in one transaction.
/// If only the alias exists, it is re-keyed to the canonical identity instead,
/// so there is never a markerless interval or a stranded `not_ready` alias.
Future<bool> dbReconcileGroupNotificationDisplayOutboxMessageAliasReady(
  Database db, {
  required String aliasEventId,
  required String canonicalEventId,
  required String groupId,
  required String actorPeerId,
  required String eventTimestamp,
  required String updatedAt,
}) {
  return dbWriteTransaction(db, (txn) async {
    if (!await _tableExists(txn)) return false;
    final canonicalRows = await txn.query(
      _table,
      where: 'event_id = ?',
      whereArgs: <Object?>[canonicalEventId],
      limit: 1,
    );
    final aliasRows = aliasEventId == canonicalEventId
        ? canonicalRows
        : await txn.query(
            _table,
            where: 'event_id = ?',
            whereArgs: <Object?>[aliasEventId],
            limit: 1,
          );
    final canonical = canonicalRows.isEmpty ? null : canonicalRows.single;
    final alias = aliasRows.isEmpty ? null : aliasRows.single;
    final canonicalMessageRows = await txn.query(
      'group_messages',
      columns: const <String>['notification_display_terminal_event_id'],
      where: 'id = ? AND group_id = ? AND sender_peer_id = ? AND timestamp = ?',
      whereArgs: <Object?>[
        canonicalEventId,
        groupId,
        actorPeerId,
        eventTimestamp,
      ],
      limit: 1,
    );
    final terminalEventId = canonicalMessageRows.isEmpty
        ? null
        : canonicalMessageRows.single['notification_display_terminal_event_id']
              as String?;
    final canonicalAlreadyTerminal = terminalEventId?.trim().isNotEmpty == true;
    if (canonical == null && alias == null) return canonicalAlreadyTerminal;

    if (canonical != null &&
        !_sameMessageAuthority(
          canonical,
          eventId: canonicalEventId,
          groupId: groupId,
          actorPeerId: actorPeerId,
          eventTimestamp: eventTimestamp,
        )) {
      throw StateError('canonical message display custody authority conflict');
    }
    if (alias != null &&
        !_sameMessageAuthority(
          alias,
          eventId: aliasEventId,
          groupId: groupId,
          actorPeerId: actorPeerId,
          eventTimestamp: eventTimestamp,
        )) {
      throw StateError('alias message display custody authority conflict');
    }

    if (canonicalAlreadyTerminal) {
      if (canonical != null) {
        final deleted = await txn.delete(
          _table,
          where: 'event_id = ? AND revision = ?',
          whereArgs: <Object?>[canonicalEventId, canonical['revision']],
        );
        if (deleted != 1) {
          throw StateError('terminal canonical custody retire failed');
        }
      }
      if (aliasEventId != canonicalEventId && alias != null) {
        final deleted = await txn.delete(
          _table,
          where: 'event_id = ? AND revision = ?',
          whereArgs: <Object?>[aliasEventId, alias['revision']],
        );
        if (deleted != 1) {
          throw StateError('terminal alias custody retire failed');
        }
      }
      return true;
    }

    if (canonical != null) {
      if (canonical['readiness'] == 'not_ready') {
        final promoted = await txn.rawUpdate(
          'UPDATE $_table SET readiness = ?, revision = revision + 1, '
          'last_error_code = NULL, last_attempt_at = NULL, '
          'next_attempt_at = NULL, updated_at = ? '
          'WHERE event_id = ? AND revision = ? AND readiness = ?',
          <Object?>[
            'ready',
            updatedAt,
            canonicalEventId,
            canonical['revision'],
            'not_ready',
          ],
        );
        if (promoted != 1) {
          throw StateError('canonical message display custody CAS failed');
        }
      }
      if (aliasEventId != canonicalEventId && alias != null) {
        final deleted = await txn.delete(
          _table,
          where: 'event_id = ? AND revision = ?',
          whereArgs: <Object?>[aliasEventId, alias['revision']],
        );
        if (deleted != 1) {
          throw StateError('alias message display custody retire failed');
        }
      }
      return true;
    }

    final rekeyed = await txn.rawUpdate(
      'UPDATE $_table SET event_id = ?, message_id = ?, readiness = ?, '
      'revision = revision + 1, last_error_code = NULL, '
      'last_attempt_at = NULL, next_attempt_at = NULL, updated_at = ? '
      'WHERE event_id = ? AND revision = ?',
      <Object?>[
        canonicalEventId,
        canonicalEventId,
        'ready',
        updatedAt,
        aliasEventId,
        alias!['revision'],
      ],
    );
    if (rekeyed != 1) {
      throw StateError('alias message display custody rekey failed');
    }
    return true;
  }, exclusive: true);
}

bool _sameMessageAuthority(
  Map<String, Object?> row, {
  required String eventId,
  required String groupId,
  required String actorPeerId,
  required String eventTimestamp,
}) {
  return row['event_id'] == eventId &&
      row['event_kind'] == 'message' &&
      row['group_id'] == groupId &&
      row['message_id'] == eventId &&
      row['actor_peer_id'] == actorPeerId &&
      row['event_timestamp'] == eventTimestamp &&
      row['reaction_id'] == null &&
      row['reaction_action'] == null &&
      row['reaction_tombstone'] == null;
}

Future<int> dbDeleteGroupNotificationDisplayOutboxForGroup(
  DatabaseExecutor db,
  String groupId,
) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
  );
}

/// Retires display-ready work that was already canonical when the user opened
/// the conversation, while preserving `not_ready` marker-first custody racing
/// ahead of its canonical message/reaction mutation.
Future<int> dbDeleteReadyGroupNotificationDisplayOutboxForGroup(
  DatabaseExecutor db,
  String groupId,
) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where: 'group_id = ? AND readiness = ?',
    whereArgs: <Object?>[groupId, 'ready'],
  );
}

Future<int> dbDeleteGroupNotificationDisplayOutboxForMessage(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
}) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where: 'group_id = ? AND message_id = ?',
    whereArgs: <Object?>[groupId, messageId],
  );
}

Future<int> dbDeleteGroupNotificationDisplayOutboxForReaction(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
  required String reactionId,
}) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where:
        'group_id = ? AND message_id = ? AND event_kind = ? AND reaction_id = ?',
    whereArgs: <Object?>[groupId, messageId, 'reaction', reactionId],
  );
}

/// Retires every reaction-display transition owned by one canonical
/// `(group, message, actor)` reaction state.
///
/// A REMOVE transition has its own event/reaction identity, so deleting by
/// the REMOVE payload id would leave the earlier ADD marker behind. The
/// explicit group id is also mandatory: direct and group message ids may
/// legally collide and must never be used to infer the ownership lane.
Future<int> dbDeleteGroupNotificationDisplayOutboxForReactionActor(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
  required String actorPeerId,
}) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where:
        'group_id = ? AND message_id = ? AND event_kind = ? '
        'AND actor_peer_id = ?',
    whereArgs: <Object?>[groupId, messageId, 'reaction', actorPeerId],
  );
}

Future<bool> _tableExists(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const <Object?>[_table],
  );
  return rows.isNotEmpty;
}
