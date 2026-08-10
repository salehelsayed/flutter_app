import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';

const String _table = 'direct_notification_display_outbox';
const int kDirectNotificationDisplayOutboxCapacity = 512;
const int kDirectNotificationDisplayOutboxMaxLoadBatch = 50;

const List<String> _authorityFields = <String>[
  'event_id',
  'event_kind',
  'peer_id',
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

/// Acquires marker-first, identifier-only direct display custody.
///
/// Exact replay is idempotent. Authority is scoped by direct peer and event
/// kind, so colliding producer IDs in another direct conversation remain
/// independent. Reuse within the same scoped key and capacity exhaustion fail
/// before canonical mutation; live custody is never evicted.
Future<void> dbStageDirectNotificationDisplayOutboxEntry(
  Database db,
  Map<String, Object?> row, {
  int capacity = kDirectNotificationDisplayOutboxCapacity,
}) {
  if (capacity <= 0) {
    throw StateError('direct notification display outbox capacity exhausted');
  }
  if (row['readiness'] != 'not_ready' ||
      row['revision'] != 1 ||
      row['retry_count'] != 0 ||
      row['last_error_code'] != null ||
      row['last_attempt_at'] != null ||
      row['next_attempt_at'] != null) {
    throw StateError(
      'a new direct display marker must be pristine and not_ready',
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final eventId = row['event_id'] as String? ?? '';
    final eventKind = row['event_kind'] as String? ?? '';
    final peerId = row['peer_id'] as String? ?? '';
    // A durable author tombstone is terminal for this target's message
    // presentation. Refusing custody here (rather than after promotion) is
    // what makes deletion-before-display and display-before-deletion converge
    // on the same durable outcome from either commit order.
    if (eventKind == 'message' &&
        await _messageParentIsTombstoned(
          txn,
          messageId: row['message_id'] as String? ?? '',
        )) {
      return;
    }
    final existing = await txn.query(
      _table,
      where: 'peer_id = ? AND event_kind = ? AND event_id = ?',
      whereArgs: <Object?>[peerId, eventKind, eventId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      if (_sameAuthority(existing.single, row)) return;
      throw StateError('direct display outbox scoped event authority conflict');
    }

    final count = Sqflite.firstIntValue(
      await txn.rawQuery('SELECT COUNT(*) FROM $_table'),
    );
    if ((count ?? 0) >= capacity) {
      throw StateError('direct notification display outbox capacity exhausted');
    }
    await txn.insert(_table, row, conflictAlgorithm: ConflictAlgorithm.abort);
  }, exclusive: true);
}

Future<Map<String, Object?>?> dbLoadDirectNotificationDisplayOutboxEntry(
  DatabaseExecutor db, {
  required String peerId,
  required String eventKind,
  required String eventId,
}) async {
  if (!await _tableExists(db)) return null;
  final rows = await db.query(
    _table,
    where: 'peer_id = ? AND event_kind = ? AND event_id = ?',
    whereArgs: <Object?>[peerId, eventKind, eventId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<bool> dbPromoteDirectNotificationDisplayOutboxReadyIfExact(
  DatabaseExecutor db, {
  required String peerId,
  required String eventKind,
  required String eventId,
  required int expectedRevision,
  required String updatedAt,
}) async {
  if (!await _tableExists(db)) return false;
  final updated = await db.rawUpdate(
    'UPDATE $_table SET readiness = ?, revision = revision + 1, '
    'last_error_code = NULL, last_attempt_at = NULL, next_attempt_at = NULL, '
    'updated_at = ? WHERE peer_id = ? AND event_kind = ? AND event_id = ? '
    'AND revision = ? AND readiness = ?',
    <Object?>[
      'ready',
      updatedAt,
      peerId,
      eventKind,
      eventId,
      expectedRevision,
      'not_ready',
    ],
  );
  return updated == 1;
}

Future<List<Map<String, Object?>>>
dbLoadReadyDirectNotificationDisplayOutboxEntries(
  DatabaseExecutor db, {
  int limit = 20,
  required String eligibleAt,
}) async {
  if (limit <= 0 || !await _tableExists(db)) return const [];
  final boundedLimit = math.min(
    limit,
    kDirectNotificationDisplayOutboxMaxLoadBatch,
  );
  return db.rawQuery(
    'SELECT * FROM $_table WHERE readiness = ? '
    'AND (next_attempt_at IS NULL OR next_attempt_at <= ?) '
    'ORDER BY created_at ASC, peer_id ASC, event_kind ASC, event_id ASC LIMIT ?',
    <Object?>['ready', eligibleAt, boundedLimit],
  );
}

Future<String?> dbLoadEarliestDirectNotificationDisplayOutboxNextAttemptAt(
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

Future<bool> dbRecordDirectNotificationDisplayOutboxRetryIfExact(
  DatabaseExecutor db, {
  required String peerId,
  required String eventKind,
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
    'WHERE peer_id = ? AND event_kind = ? AND event_id = ? '
    'AND revision = ? AND readiness = ?',
    <Object?>[
      lastErrorCode,
      lastAttemptAt,
      nextAttemptAt,
      updatedAt,
      peerId,
      eventKind,
      eventId,
      expectedRevision,
      'ready',
    ],
  );
  return updated == 1;
}

/// Records terminal authority and retires only the exact ready custody row.
///
/// Message terminal state lives on the typed direct message row. Reaction
/// terminal state is written only to the peer-scoped direct authority table;
/// this function never queries or mutates the untyped shared reaction row.
Future<bool> dbCompleteDirectNotificationDisplayOutboxEntryIfExact(
  Database db, {
  required String eventId,
  required int expectedRevision,
  required String expectedEventKind,
  required String expectedPeerId,
  required String expectedMessageId,
  required String expectedActorPeerId,
  required String expectedEventTimestamp,
  required String? expectedReactionId,
  required String? expectedReactionAction,
  required bool? expectedReactionTombstone,
  required String completedAt,
}) => dbWriteTransaction(db, (txn) async {
  if (!await _tableExists(txn)) return false;
  final where = StringBuffer(
    'event_id = ? AND revision = ? AND readiness = ? '
    'AND event_kind = ? AND peer_id = ? AND message_id = ? '
    'AND actor_peer_id = ? AND event_timestamp = ?',
  );
  final whereArgs = <Object?>[
    eventId,
    expectedRevision,
    'ready',
    expectedEventKind,
    expectedPeerId,
    expectedMessageId,
    expectedActorPeerId,
    expectedEventTimestamp,
  ];
  _appendNullableComparand(
    where,
    whereArgs,
    column: 'reaction_id',
    value: expectedReactionId,
  );
  _appendNullableComparand(
    where,
    whereArgs,
    column: 'reaction_action',
    value: expectedReactionAction,
  );
  _appendNullableComparand(
    where,
    whereArgs,
    column: 'reaction_tombstone',
    value: expectedReactionTombstone == null
        ? null
        : (expectedReactionTombstone ? 1 : 0),
  );

  final exactCustody = await txn.query(
    _table,
    columns: const <String>['event_id'],
    where: where.toString(),
    whereArgs: whereArgs,
    limit: 1,
  );
  if (exactCustody.isEmpty) return false;

  if (expectedEventKind == 'message') {
    final updated = await txn.rawUpdate(
      'UPDATE messages SET notification_display_terminal_event_id = ? '
      'WHERE id = ? AND contact_peer_id = ? AND sender_peer_id = ? '
      'AND timestamp = ? '
      'AND (notification_display_terminal_event_id IS NULL '
      'OR notification_display_terminal_event_id = ?)',
      <Object?>[
        eventId,
        expectedMessageId,
        expectedPeerId,
        expectedActorPeerId,
        expectedEventTimestamp,
        eventId,
      ],
    );
    if (updated != 1) return false;
  } else if (expectedEventKind == 'reaction' &&
      expectedReactionId != null &&
      expectedReactionAction == 'add' &&
      expectedReactionTombstone == false) {
    await txn.rawInsert(
      '''
      INSERT INTO direct_notification_reaction_terminal_events (
        peer_id, message_id, actor_peer_id, reaction_id, terminal_event_id,
        notification_acknowledged_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, NULL, ?)
      ON CONFLICT(peer_id, message_id, actor_peer_id) DO UPDATE SET
        reaction_id = excluded.reaction_id,
        terminal_event_id = excluded.terminal_event_id,
        notification_acknowledged_at = NULL,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        expectedPeerId,
        expectedMessageId,
        expectedActorPeerId,
        expectedReactionId,
        eventId,
        completedAt,
      ],
    );
  } else if (expectedEventKind == 'reaction' &&
      expectedReactionAction == 'remove' &&
      expectedReactionTombstone == true) {
    await txn.delete(
      'direct_notification_reaction_terminal_events',
      where:
          'peer_id = ? AND message_id = ? AND actor_peer_id = ? '
          'AND reaction_id = ?',
      whereArgs: <Object?>[
        expectedPeerId,
        expectedMessageId,
        expectedActorPeerId,
        expectedReactionId,
      ],
    );
  }

  final deleted = await txn.delete(
    _table,
    where: where.toString(),
    whereArgs: whereArgs,
  );
  if (deleted != 1) {
    throw StateError('direct notification display completion CAS failed');
  }
  return true;
}, exclusive: true);

/// Retires stale/ineligible custody without recording a display terminal.
///
/// This is separate from completion because completion is canonical evidence
/// that the event was shown or terminally suppressed. Reusing it for a stale
/// row would let that row overwrite typed message/reaction terminal authority.
Future<bool> dbRetireDirectNotificationDisplayOutboxEntryIfExact(
  DatabaseExecutor db, {
  required String eventId,
  required int expectedRevision,
  required String expectedEventKind,
  required String expectedPeerId,
  required String expectedMessageId,
  required String expectedActorPeerId,
  required String expectedEventTimestamp,
  required String? expectedReactionId,
  required String? expectedReactionAction,
  required bool? expectedReactionTombstone,
}) async {
  if (!await _tableExists(db)) return false;
  final where = StringBuffer(
    'event_id = ? AND revision = ? AND readiness = ? '
    'AND event_kind = ? AND peer_id = ? AND message_id = ? '
    'AND actor_peer_id = ? AND event_timestamp = ?',
  );
  final whereArgs = <Object?>[
    eventId,
    expectedRevision,
    'ready',
    expectedEventKind,
    expectedPeerId,
    expectedMessageId,
    expectedActorPeerId,
    expectedEventTimestamp,
  ];
  _appendNullableComparand(
    where,
    whereArgs,
    column: 'reaction_id',
    value: expectedReactionId,
  );
  _appendNullableComparand(
    where,
    whereArgs,
    column: 'reaction_action',
    value: expectedReactionAction,
  );
  _appendNullableComparand(
    where,
    whereArgs,
    column: 'reaction_tombstone',
    value: expectedReactionTombstone == null
        ? null
        : (expectedReactionTombstone ? 1 : 0),
  );
  return await db.delete(
        _table,
        where: where.toString(),
        whereArgs: whereArgs,
      ) ==
      1;
}

void _appendNullableComparand(
  StringBuffer where,
  List<Object?> whereArgs, {
  required String column,
  required Object? value,
}) {
  if (value == null) {
    where.write(' AND $column IS NULL');
  } else {
    where.write(' AND $column = ?');
    whereArgs.add(value);
  }
}

Future<int> dbDeleteDirectNotificationDisplayOutboxForPeer(
  DatabaseExecutor db,
  String peerId,
) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(_table, where: 'peer_id = ?', whereArgs: <Object?>[peerId]);
}

Future<int> dbDeleteReadyDirectNotificationDisplayOutboxForPeer(
  DatabaseExecutor db,
  String peerId,
) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where: 'peer_id = ? AND readiness = ?',
    whereArgs: <Object?>[peerId, 'ready'],
  );
}

Future<int> dbDeleteDirectNotificationDisplayOutboxForMessage(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
}) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where: 'peer_id = ? AND message_id = ?',
    whereArgs: <Object?>[peerId, messageId],
  );
}

/// Retires ONLY the message-kind display markers for one peer + message event.
///
/// 355: a private terminal winner must leave no card behind, in either
/// readiness. Reaction rows for the same message and every other message's
/// rows are deliberately untouched, so this is safe to call from inside a
/// terminal/stage transaction that owns just this one message event.
Future<int> dbDeleteDirectNotificationDisplayOutboxMessageEntriesForMessage(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
}) async {
  if (peerId.isEmpty || messageId.isEmpty) return 0;
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where: 'peer_id = ? AND message_id = ? AND event_kind = ?',
    whereArgs: <Object?>[peerId, messageId, 'message'],
  );
}

Future<int> dbDeleteDirectNotificationDisplayOutboxForReaction(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
  required String reactionId,
}) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where:
        'peer_id = ? AND message_id = ? AND event_kind = ? AND reaction_id = ?',
    whereArgs: <Object?>[peerId, messageId, 'reaction', reactionId],
  );
}

Future<int> dbDeleteDirectNotificationDisplayOutboxForReactionActor(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
  required String actorPeerId,
}) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where:
        'peer_id = ? AND message_id = ? AND event_kind = ? '
        'AND actor_peer_id = ?',
    whereArgs: <Object?>[peerId, messageId, 'reaction', actorPeerId],
  );
}

Future<bool> _messageParentIsTombstoned(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  if (messageId.isEmpty) return false;
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'messages' LIMIT 1",
  );
  if (rows.isEmpty) return false;
  final parents = await db.query(
    'messages',
    columns: const <String>['deleted_at'],
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
    limit: 1,
  );
  return parents.isNotEmpty && parents.single['deleted_at'] != null;
}

Future<bool> _tableExists(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const <Object?>[_table],
  );
  return rows.isNotEmpty;
}
