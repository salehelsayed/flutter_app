import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../notifications/durable_local_notification_effect_coordinator.dart';
import '../../notifications/notification_completed_outcome.dart';
import '../../notifications/notification_completed_outcome_correlation.dart';
import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'direct_notification_reconciliation_outbox_db_helpers.dart';
import 'notification_completed_outcome_outbox_db_helpers.dart';

const String _table = 'direct_notification_display_outbox';
const int kDirectNotificationDisplayOutboxCapacity = 512;
const int kDirectNotificationDisplayOutboxMaxLoadBatch = 50;
const int kDirectNotificationCommittedSqlTerminalMaxLoadBatch = 512;

/// Total durable custody, including NOT_READY and deferred/backoff rows.
Future<int> dbCountAllDirectNotificationDisplayOutboxEntries(
  DatabaseExecutor db,
) async {
  if (!await _tableExists(db)) return 0;
  return Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_table'),
      ) ??
      0;
}

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

/// Bounded armed custody for one direct peer, including deferred retries.
///
/// Durable effect-terminal recovery must inspect the exact SQL row at its
/// current revision. It therefore cannot reuse the due-only batch loader or
/// assume the initial revision after a retry. The global v107 capacity bounds
/// this peer scan independently of caller input.
Future<List<Map<String, Object?>>>
dbLoadAllReadyDirectNotificationDisplayOutboxEntriesForPeer(
  DatabaseExecutor db, {
  required String peerId,
  int limit = kDirectNotificationDisplayOutboxCapacity,
}) async {
  if (peerId.isEmpty || limit <= 0 || !await _tableExists(db)) {
    return const <Map<String, Object?>>[];
  }
  final boundedLimit = math.min(
    limit,
    kDirectNotificationDisplayOutboxCapacity,
  );
  return db.rawQuery(
    'SELECT * FROM $_table WHERE peer_id = ? AND readiness = ? '
    'ORDER BY created_at ASC, event_kind ASC, event_id ASC LIMIT ?',
    <Object?>[peerId, 'ready', boundedLimit],
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
    "last_error_code = CASE WHEN last_attempt_at = 'canonical_retired' "
    'THEN last_error_code ELSE ? END, '
    "last_attempt_at = CASE WHEN last_attempt_at = 'canonical_retired' "
    'THEN last_attempt_at ELSE ? END, next_attempt_at = ?, '
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

/// Legacy one-transaction completion for callers without a file-ledger owner.
///
/// Message terminal state lives on the typed direct message row. Reaction
/// terminal state is written to the peer-scoped direct authority table. The
/// durable Plan-372 path uses [dbHandoffDirectNotificationDisplayOutboxEntryIfExact]
/// followed by
/// [dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact]
/// instead, so raw READY custody spans file-ledger settlement.
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
  NotificationCompletedOutcomeCandidate? outcome,
}) async =>
    await dbHandoffDirectNotificationDisplayOutboxEntryIfExact(
      db,
      eventId: eventId,
      expectedRevision: expectedRevision,
      expectedEventKind: expectedEventKind,
      expectedPeerId: expectedPeerId,
      expectedMessageId: expectedMessageId,
      expectedActorPeerId: expectedActorPeerId,
      expectedEventTimestamp: expectedEventTimestamp,
      expectedReactionId: expectedReactionId,
      expectedReactionAction: expectedReactionAction,
      expectedReactionTombstone: expectedReactionTombstone,
      completedAt: completedAt,
      outcome: outcome,
      allowExistingDifferentOutcome: true,
      enqueueDurableRecovery: false,
      retireReadyWithinTransaction: true,
    ) ==
    DurableLocalNotificationSqlHandoffResult.committed;

/// Commits/verifies the exact direct SQL/v116 terminal while retaining READY.
///
/// The direct reaction terminal table is intentionally one-row-per-actor and
/// can be advanced by a later reaction. Deleting the raw READY tuple before
/// file-ledger settlement would therefore lose the authenticated event key and
/// exact revision needed after a crash. Durable callers settle the ledger and
/// then invoke
/// [dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact].
///
/// Missing custody is accepted only for an older one-transaction database when
/// the exact typed terminal and optional immutable v116 fact both survive.
/// Bare absence and a same-event row at a different revision never authorize
/// settlement.
Future<DurableLocalNotificationSqlHandoffResult>
dbHandoffDirectNotificationDisplayOutboxEntryIfExact(
  Database db, {
  required String eventId,
  required int? expectedRevision,
  required String expectedEventKind,
  required String expectedPeerId,
  required String expectedMessageId,
  required String expectedActorPeerId,
  required String expectedEventTimestamp,
  required String? expectedReactionId,
  required String? expectedReactionAction,
  required bool? expectedReactionTombstone,
  required String completedAt,
  NotificationCompletedOutcomeCandidate? outcome,
  bool allowExistingDifferentOutcome = false,
  bool enqueueDurableRecovery = true,
  bool retireReadyWithinTransaction = false,
}) => dbWriteTransaction(db, (txn) async {
  if (!await _tableExists(txn)) {
    return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
  }
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
    columns: const <String>[
      'event_id',
      'last_error_code',
      'last_attempt_at',
      'next_attempt_at',
    ],
    where: where.toString(),
    whereArgs: whereArgs,
    limit: 1,
  );
  if (exactCustody.isEmpty) {
    final sameScopedEvent = await txn.query(
      _table,
      columns: const <String>['event_id'],
      where: 'peer_id = ? AND event_kind = ? AND event_id = ?',
      whereArgs: <Object?>[expectedPeerId, expectedEventKind, eventId],
      limit: 1,
    );
    return sameScopedEvent.isEmpty &&
            await _directNotificationSqlTerminalMatches(
              txn,
              eventId: eventId,
              expectedEventKind: expectedEventKind,
              expectedPeerId: expectedPeerId,
              expectedMessageId: expectedMessageId,
              expectedActorPeerId: expectedActorPeerId,
              expectedEventTimestamp: expectedEventTimestamp,
              expectedReactionId: expectedReactionId,
              expectedReactionAction: expectedReactionAction,
              expectedReactionTombstone: expectedReactionTombstone,
            ) &&
            await _directNotificationOutcomeMatches(txn, outcome)
        ? DurableLocalNotificationSqlHandoffResult.alreadyCommitted
        : DurableLocalNotificationSqlHandoffResult.retryableMismatch;
  }

  final typedTerminalMatches = await _directNotificationSqlTerminalMatches(
    txn,
    eventId: eventId,
    expectedEventKind: expectedEventKind,
    expectedPeerId: expectedPeerId,
    expectedMessageId: expectedMessageId,
    expectedActorPeerId: expectedActorPeerId,
    expectedEventTimestamp: expectedEventTimestamp,
    expectedReactionId: expectedReactionId,
    expectedReactionAction: expectedReactionAction,
    expectedReactionTombstone: expectedReactionTombstone,
  );
  final canonicalRetirementMatches =
      !typedTerminalMatches &&
      (_directNotificationCustodyCarriesCanonicalRetirement(
            exactCustody.single,
          ) ||
          await _directNotificationCanonicalRetirementMatches(
            txn,
            expectedEventKind: expectedEventKind,
            expectedPeerId: expectedPeerId,
            expectedMessageId: expectedMessageId,
            expectedActorPeerId: expectedActorPeerId,
            expectedEventTimestamp: expectedEventTimestamp,
            expectedReactionId: expectedReactionId,
            expectedReactionAction: expectedReactionAction,
            expectedReactionTombstone: expectedReactionTombstone,
          ));
  if (!retireReadyWithinTransaction &&
      (typedTerminalMatches || canonicalRetirementMatches) &&
      await _directNotificationOutcomeMatches(txn, outcome)) {
    return DurableLocalNotificationSqlHandoffResult.alreadyCommitted;
  }

  if (canonicalRetirementMatches) {
    // READY retains every immutable raw comparand. The current direct message
    // tombstone/private terminal or reaction remove/newer generation is the
    // SQL-side terminal proof, so replay must not resurrect an obsolete typed
    // reaction terminal merely to settle the file ledger.
  } else if (expectedEventKind == 'message') {
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
    if (updated != 1) {
      return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
    }
  } else if (expectedEventKind == 'reaction' &&
      expectedReactionId != null &&
      expectedReactionAction == 'add' &&
      expectedReactionTombstone == false) {
    if (!await _directReactionIsExactCurrent(
      txn,
      expectedPeerId: expectedPeerId,
      expectedMessageId: expectedMessageId,
      expectedActorPeerId: expectedActorPeerId,
      expectedEventTimestamp: expectedEventTimestamp,
      expectedReactionId: expectedReactionId,
    )) {
      return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
    }
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

  if (outcome != null) {
    final insertResult =
        await dbInsertNotificationCompletedOutcomeWithinTransaction(
          txn,
          candidate: outcome,
          now: DateTime.parse(completedAt).toUtc(),
        );
    if (insertResult ==
        NotificationCompletedOutcomeInsertResult.existingDifferent) {
      emitFlowEvent(
        layer: 'DB',
        event: 'NOTIFICATION_OUTCOME_CATEGORY_REPLAY',
        details: const <String, Object?>{'reason': 'outcome_category_replay'},
      );
      if (!allowExistingDifferentOutcome) {
        return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
      }
    }
  }

  if (retireReadyWithinTransaction && enqueueDurableRecovery) {
    await dbEnqueueDirectNotificationReconciliationOutbox(
      txn,
      peerId: expectedPeerId,
    );
  }

  if (retireReadyWithinTransaction) {
    final deleted = await txn.delete(
      _table,
      where: where.toString(),
      whereArgs: whereArgs,
    );
    if (deleted != 1) {
      throw StateError('direct notification display completion CAS failed');
    }
  }
  return DurableLocalNotificationSqlHandoffResult.committed;
}, exclusive: true);

/// Exact SQL transaction B after the file-ledger record is SETTLED.
///
/// The caller supplies the same final READY revision used by transaction A.
/// Successful durable settlement already published the current peer card, so
/// this transaction retires only the exact SQL custody. A different revision or
/// sibling event is never consumed.
Future<bool>
dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact(
  Database db, {
  required String eventId,
  required int? expectedRevision,
  required String expectedEventKind,
  required String expectedPeerId,
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
  final sameScopedEvent = await txn.query(
    _table,
    columns: const <String>['event_id'],
    where: 'peer_id = ? AND event_kind = ? AND event_id = ?',
    whereArgs: <Object?>[expectedPeerId, expectedEventKind, eventId],
    limit: 1,
  );
  final exactCustody = sameScopedEvent.isEmpty
      ? const <Map<String, Object?>>[]
      : await txn.query(
          _table,
          columns: const <String>[
            'event_id',
            'last_error_code',
            'last_attempt_at',
            'next_attempt_at',
          ],
          where: where.toString(),
          whereArgs: whereArgs,
          limit: 1,
        );
  final typedTerminalMatches = await _directNotificationSqlTerminalMatches(
    txn,
    eventId: eventId,
    expectedEventKind: expectedEventKind,
    expectedPeerId: expectedPeerId,
    expectedMessageId: expectedMessageId,
    expectedActorPeerId: expectedActorPeerId,
    expectedEventTimestamp: expectedEventTimestamp,
    expectedReactionId: expectedReactionId,
    expectedReactionAction: expectedReactionAction,
    expectedReactionTombstone: expectedReactionTombstone,
  );
  final canonicalRetirementMatches =
      exactCustody.isNotEmpty &&
      (_directNotificationCustodyCarriesCanonicalRetirement(
            exactCustody.single,
          ) ||
          await _directNotificationCanonicalRetirementMatches(
            txn,
            expectedEventKind: expectedEventKind,
            expectedPeerId: expectedPeerId,
            expectedMessageId: expectedMessageId,
            expectedActorPeerId: expectedActorPeerId,
            expectedEventTimestamp: expectedEventTimestamp,
            expectedReactionId: expectedReactionId,
            expectedReactionAction: expectedReactionAction,
            expectedReactionTombstone: expectedReactionTombstone,
          ));
  if (!typedTerminalMatches && !canonicalRetirementMatches) return false;
  if (sameScopedEvent.isNotEmpty) {
    if (exactCustody.isEmpty) return false;
    final deleted = await txn.delete(
      _table,
      where: where.toString(),
      whereArgs: whereArgs,
    );
    if (deleted != 1) return false;
  }
  return true;
}, exclusive: true);

Future<bool> _directNotificationSqlTerminalMatches(
  DatabaseExecutor db, {
  required String eventId,
  required String expectedEventKind,
  required String expectedPeerId,
  required String expectedMessageId,
  required String expectedActorPeerId,
  required String expectedEventTimestamp,
  required String? expectedReactionId,
  required String? expectedReactionAction,
  required bool? expectedReactionTombstone,
}) async {
  var terminalMatches = false;
  if (expectedEventKind == 'message') {
    final rows = await db.query(
      'messages',
      columns: const <String>['notification_display_terminal_event_id'],
      where:
          'id = ? AND contact_peer_id = ? AND sender_peer_id = ? '
          'AND timestamp = ?',
      whereArgs: <Object?>[
        expectedMessageId,
        expectedPeerId,
        expectedActorPeerId,
        expectedEventTimestamp,
      ],
      limit: 1,
    );
    terminalMatches =
        rows.length == 1 &&
        rows.single['notification_display_terminal_event_id'] == eventId;
  } else if (expectedEventKind == 'reaction' &&
      expectedReactionId != null &&
      expectedReactionAction == 'add' &&
      expectedReactionTombstone == false) {
    final rows = await db.query(
      'direct_notification_reaction_terminal_events',
      columns: const <String>['terminal_event_id'],
      where:
          'peer_id = ? AND message_id = ? AND actor_peer_id = ? '
          'AND reaction_id = ?',
      whereArgs: <Object?>[
        expectedPeerId,
        expectedMessageId,
        expectedActorPeerId,
        expectedReactionId,
      ],
      limit: 1,
    );
    terminalMatches =
        rows.length == 1 && rows.single['terminal_event_id'] == eventId;
  }
  return terminalMatches;
}

bool _directNotificationCustodyCarriesCanonicalRetirement(
  Map<String, Object?> row,
) =>
    row['last_error_code'] == 'state_unavailable' &&
    row['last_attempt_at'] == 'canonical_retired';

Future<bool> _directNotificationOutcomeMatches(
  DatabaseExecutor db,
  NotificationCompletedOutcomeCandidate? outcome,
) async {
  if (outcome == null) return true;
  final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
    physicalPeerId: outcome.physicalPeerId,
    producerKind: outcome.producerKind,
    eventKey: outcome.eventKey,
  );
  if (correlation == null) return false;
  final rows = await db.query(
    'notification_completed_outcome_outbox',
    columns: const <String>['wake_correlation', 'outcome'],
    where: 'wake_correlation = ?',
    whereArgs: <Object?>[correlation],
    limit: 1,
  );
  return rows.length == 1 &&
      rows.single['outcome'] == outcome.outcome.wireValue;
}

Future<bool> _directNotificationCanonicalRetirementMatches(
  DatabaseExecutor db, {
  required String expectedEventKind,
  required String expectedPeerId,
  required String expectedMessageId,
  required String expectedActorPeerId,
  required String expectedEventTimestamp,
  required String? expectedReactionId,
  required String? expectedReactionAction,
  required bool? expectedReactionTombstone,
}) async {
  if (expectedEventKind == 'message') {
    final messages = await db.query(
      'messages',
      where:
          'id = ? AND contact_peer_id = ? AND sender_peer_id = ? '
          'AND timestamp = ?',
      whereArgs: <Object?>[
        expectedMessageId,
        expectedPeerId,
        expectedActorPeerId,
        expectedEventTimestamp,
      ],
      limit: 1,
    );
    if (messages.isEmpty) return false;
    final message = messages.single;
    return message['read_at'] != null ||
        message['deleted_at'] != null ||
        message['hidden_at'] != null ||
        const <String>{
          'consumed',
          'expired',
          'unsupported',
        }.contains(message['private_media_state']);
  }
  if (expectedEventKind != 'reaction' ||
      expectedReactionId == null ||
      expectedReactionAction != 'add' ||
      expectedReactionTombstone != false) {
    return false;
  }
  final target = await db.query(
    'messages',
    where: 'id = ? AND contact_peer_id = ? AND is_incoming = 0',
    whereArgs: <Object?>[expectedMessageId, expectedPeerId],
    limit: 1,
  );
  if (target.isEmpty) return false;
  final targetRow = target.single;
  if (targetRow['deleted_at'] != null ||
      targetRow['hidden_at'] != null ||
      const <String>{
        'consumed',
        'expired',
        'unsupported',
      }.contains(targetRow['private_media_state'])) {
    return true;
  }
  final reactions = await db.query(
    'message_reactions',
    columns: const <String>['id', 'timestamp', 'removed_at'],
    where: 'message_id = ? AND sender_peer_id = ?',
    whereArgs: <Object?>[expectedMessageId, expectedActorPeerId],
    limit: 1,
  );
  if (reactions.isEmpty) return false;
  final reaction = reactions.single;
  return reaction['removed_at'] != null ||
      reaction['id'] != expectedReactionId ||
      reaction['timestamp'] != expectedEventTimestamp;
}

Future<bool> _directReactionIsExactCurrent(
  DatabaseExecutor db, {
  required String expectedPeerId,
  required String expectedMessageId,
  required String expectedActorPeerId,
  required String expectedEventTimestamp,
  required String expectedReactionId,
}) async {
  final rows = await db.rawQuery(
    'SELECT r.id FROM message_reactions r '
    'INNER JOIN messages m ON m.id = r.message_id '
    'WHERE r.id = ? AND r.message_id = ? AND r.sender_peer_id = ? '
    'AND r.timestamp = ? AND r.removed_at IS NULL '
    'AND m.contact_peer_id = ? AND m.is_incoming = 0 '
    'AND m.deleted_at IS NULL AND m.hidden_at IS NULL LIMIT 1',
    <Object?>[
      expectedReactionId,
      expectedMessageId,
      expectedActorPeerId,
      expectedEventTimestamp,
      expectedPeerId,
    ],
  );
  return rows.length == 1;
}

final class DirectNotificationCommittedSqlTerminal {
  const DirectNotificationCommittedSqlTerminal({
    required this.eventKind,
    required this.eventId,
    required this.peerId,
    required this.messageId,
    required this.actorPeerId,
    required this.eventTimestamp,
    this.reactionId,
    this.reactionAction,
    this.reactionTombstone,
  });

  final String eventKind;
  final String eventId;
  final String peerId;
  final String messageId;
  final String actorPeerId;
  final String eventTimestamp;
  final String? reactionId;
  final String? reactionAction;
  final bool? reactionTombstone;
}

/// Bounded typed SQL terminals for one reconciliation peer.
///
/// The transaction above makes the peer reconciliation trigger atomic with
/// completion, so an unresolved crash-gap terminal is among the newest rows.
Future<List<DirectNotificationCommittedSqlTerminal>>
dbLoadDirectNotificationCommittedSqlTerminalsForPeer(
  DatabaseExecutor db, {
  required String peerId,
  int limitPerKind = kDirectNotificationCommittedSqlTerminalMaxLoadBatch,
}) async {
  if (limitPerKind <= 0) {
    return const <DirectNotificationCommittedSqlTerminal>[];
  }
  final boundedLimit = math.min(
    limitPerKind,
    kDirectNotificationCommittedSqlTerminalMaxLoadBatch,
  );
  final messages = await db.rawQuery(
    '''
    SELECT id, contact_peer_id, sender_peer_id, timestamp,
           notification_display_terminal_event_id
    FROM messages
    WHERE contact_peer_id = ?
      AND notification_display_terminal_event_id IS NOT NULL
    ORDER BY timestamp DESC, id DESC
    LIMIT ?
    ''',
    <Object?>[peerId, boundedLimit],
  );
  final reactions = await db.rawQuery(
    '''
    SELECT peer_id, message_id, actor_peer_id, reaction_id,
           terminal_event_id, updated_at
    FROM direct_notification_reaction_terminal_events
    WHERE peer_id = ?
    ORDER BY updated_at DESC, terminal_event_id DESC
    LIMIT ?
    ''',
    <Object?>[peerId, boundedLimit],
  );
  return <DirectNotificationCommittedSqlTerminal>[
    for (final row in messages)
      DirectNotificationCommittedSqlTerminal(
        eventKind: 'message',
        eventId: row['notification_display_terminal_event_id']! as String,
        peerId: row['contact_peer_id']! as String,
        messageId: row['id']! as String,
        actorPeerId: row['sender_peer_id']! as String,
        eventTimestamp: row['timestamp']! as String,
      ),
    for (final row in reactions)
      DirectNotificationCommittedSqlTerminal(
        eventKind: 'reaction',
        eventId: row['terminal_event_id']! as String,
        peerId: row['peer_id']! as String,
        messageId: row['message_id']! as String,
        actorPeerId: row['actor_peer_id']! as String,
        eventTimestamp: row['updated_at']! as String,
        reactionId: row['reaction_id']! as String,
        reactionAction: 'add',
        reactionTombstone: false,
      ),
  ];
}

/// Resolves one durable direct-reaction correlation against the complete typed
/// terminal set for [peerId]. Pages stay bounded in Dart, while one database
/// transaction freezes the global set so a duplicate beyond an earlier page
/// cannot be missed by concurrent inserts or updates.
///
/// `null` deliberately covers missing, malformed and ambiguous matches. The
/// caller must retain reconciliation custody for every one of those cases.
Future<DirectNotificationCommittedSqlTerminal?>
dbLoadUniqueDirectNotificationCommittedReactionTerminalByCorrelation(
  Database db, {
  required String peerId,
  required String physicalPeerId,
  required String eventCorrelation,
  int pageSize = kDirectNotificationCommittedSqlTerminalMaxLoadBatch,
}) {
  if (pageSize <= 0) return Future.value(null);
  final boundedPageSize = math.min(
    pageSize,
    kDirectNotificationCommittedSqlTerminalMaxLoadBatch,
  );
  return dbWriteTransaction(db, (txn) async {
    DirectNotificationCommittedSqlTerminal? matched;
    var offset = 0;
    while (true) {
      final rows = await txn.rawQuery(
        '''
        SELECT peer_id, message_id, actor_peer_id, reaction_id,
               terminal_event_id, updated_at
        FROM direct_notification_reaction_terminal_events
        WHERE peer_id = ?
        ORDER BY updated_at DESC, terminal_event_id DESC,
                 message_id DESC, actor_peer_id DESC
        LIMIT ? OFFSET ?
        ''',
        <Object?>[peerId, boundedPageSize, offset],
      );
      for (final row in rows) {
        final reactionId = row['reaction_id'] as String?;
        if (reactionId == null) continue;
        final eventKey = trySelectNotificationCompletedOutcomeEventKey(
          producerKind: NotificationCompletedOutcomeProducerKind.directReaction,
          authenticatedEnvelope: <String, Object?>{'reactionId': reactionId},
        );
        if (eventKey == null ||
            tryComputeNotificationCompletedOutcomeCorrelation(
                  physicalPeerId: physicalPeerId,
                  producerKind:
                      NotificationCompletedOutcomeProducerKind.directReaction,
                  eventKey: eventKey,
                ) !=
                eventCorrelation) {
          continue;
        }
        if (matched != null) return null;
        matched = DirectNotificationCommittedSqlTerminal(
          eventKind: 'reaction',
          eventId: row['terminal_event_id']! as String,
          peerId: row['peer_id']! as String,
          messageId: row['message_id']! as String,
          actorPeerId: row['actor_peer_id']! as String,
          eventTimestamp: row['updated_at']! as String,
          reactionId: reactionId,
          reactionAction: 'add',
          reactionTombstone: false,
        );
      }
      if (rows.length < boundedPageSize) return matched;
      offset += rows.length;
    }
  }, exclusive: false);
}

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

/// Explicit peer/account teardown only. Canonical policy/contact mutations
/// must preserve armed custody and use the trigger-backed retirement proof.
Future<int> dbDeleteDirectNotificationDisplayOutboxForPeer(
  DatabaseExecutor db,
  String peerId,
) async {
  if (!await _tableExists(db)) return 0;
  return db.delete(_table, where: 'peer_id = ?', whereArgs: <Object?>[peerId]);
}

/// Explicit teardown/testing primitive; never a canonical mutation owner.
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

/// Explicit bulk teardown only. Ordinary canonical deletion uses
/// [dbRetireUnarmedDirectNotificationDisplayOutboxForMessage].
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

/// Retires only display custody that cannot have entered the final-effect
/// protocol for this canonical direct target.
///
/// `READY` is armed custody: another owner may already have loaded it and
/// durably entered CLAIMED/PUBLISHING. Canonical deletion must leave that exact
/// row available for the no-native terminal SQL handoff; bare row absence is
/// not settlement evidence. Every READY sibling is therefore preserved and
/// later resolves through its own exact revision/authority CAS.
Future<int> dbRetireUnarmedDirectNotificationDisplayOutboxForMessage(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
}) async {
  if (peerId.isEmpty || messageId.isEmpty || !await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where: 'peer_id = ? AND message_id = ? AND readiness = ?',
    whereArgs: <Object?>[peerId, messageId, 'not_ready'],
  );
}

/// Explicit message-kind teardown primitive. Canonical private terminal owners
/// use the unarmed-only variant below so READY can finish the durable barrier.
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

/// Message-kind variant of
/// [dbRetireUnarmedDirectNotificationDisplayOutboxForMessage].
///
/// Private-media terminal owners affect their exact message projection while
/// same-message reaction custody remains independently reconciled. Armed
/// message custody survives so a loaded/PUBLISHING attempt can durably record
/// cancellation and complete its exact SQL handoff.
Future<int>
dbRetireUnarmedDirectNotificationDisplayOutboxMessageEntriesForMessage(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
}) async {
  if (peerId.isEmpty || messageId.isEmpty || !await _tableExists(db)) return 0;
  return db.delete(
    _table,
    where:
        'peer_id = ? AND message_id = ? AND event_kind = ? AND readiness = ?',
    whereArgs: <Object?>[peerId, messageId, 'message', 'not_ready'],
  );
}

/// Explicit compatibility/teardown primitive, not an adopted canonical owner.
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

/// Explicit compatibility/teardown primitive, not an adopted canonical owner.
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
