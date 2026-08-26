import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../notifications/deterministic_notification_id.dart';
import '../../notifications/durable_local_notification_effect_coordinator.dart';
import '../../notifications/notification_completed_outcome.dart';
import '../../notifications/notification_completed_outcome_correlation.dart';
import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'notification_completed_outcome_outbox_db_helpers.dart';
import 'protected_group_reaction_display_terminal_db_helpers.dart';

const String _table = 'group_notification_display_outbox';
const int kGroupNotificationDisplayOutboxCapacity = 512;
const int kGroupNotificationDisplayOutboxMaxLoadBatch = 50;
const String kGroupNotificationDisplayCanonicalRetiredMarker =
    'terminal:canonical_retired';
const String _groupNotificationDisplayDurableCorrelationMarkerPrefix =
    'effect:';
const String _groupNotificationDisplayCanonicalRetiredCorrelationMarkerPrefix =
    '$kGroupNotificationDisplayCanonicalRetiredMarker:';
final RegExp _durableEventCorrelationPattern = RegExp(r'^[0-9a-f]{64}$');

/// Total durable custody, including NOT_READY and deferred/backoff rows.
Future<int> dbCountAllGroupNotificationDisplayOutboxEntries(
  DatabaseExecutor db,
) async {
  if (!await _tableExists(db)) return 0;
  return Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_table'),
      ) ??
      0;
}

/// Privacy-safe SQL custody marker written before entering the file-ledger
/// final-effect boundary. It preserves the raw event correlation even if a
/// concurrent canonical mutation removes the message row that derived it.
String groupNotificationDisplayDurableCorrelationMarker(
  String durableEventCorrelation,
) {
  if (!_durableEventCorrelationPattern.hasMatch(durableEventCorrelation)) {
    throw ArgumentError.value(
      durableEventCorrelation,
      'durableEventCorrelation',
      'must be a lowercase 64-hex digest',
    );
  }
  return '$_groupNotificationDisplayDurableCorrelationMarkerPrefix'
      '$durableEventCorrelation';
}

String? groupNotificationDisplayDurableCorrelationFromMarker(String? marker) {
  if (marker == null) return null;
  final prefix =
      marker.startsWith(
        _groupNotificationDisplayCanonicalRetiredCorrelationMarkerPrefix,
      )
      ? _groupNotificationDisplayCanonicalRetiredCorrelationMarkerPrefix
      : marker.startsWith(
          _groupNotificationDisplayDurableCorrelationMarkerPrefix,
        )
      ? _groupNotificationDisplayDurableCorrelationMarkerPrefix
      : null;
  if (prefix == null) return null;
  final correlation = marker.substring(prefix.length);
  return _durableEventCorrelationPattern.hasMatch(correlation)
      ? correlation
      : null;
}

bool isGroupNotificationDisplayCanonicalRetiredMarker(String? marker) =>
    marker == kGroupNotificationDisplayCanonicalRetiredMarker ||
    (marker?.startsWith(
              _groupNotificationDisplayCanonicalRetiredCorrelationMarkerPrefix,
            ) ==
            true &&
        groupNotificationDisplayDurableCorrelationFromMarker(marker) != null);

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

/// Binds one exact READY row to its opaque file-ledger correlation before any
/// final effect can start. Replays return the already-bound row without
/// advancing its revision; a different correlation or canonical-retired row
/// is never rebound.
Future<Map<String, Object?>?>
dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
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
  required String durableEventCorrelation,
  required String updatedAt,
}) => dbWriteTransaction(db, (txn) async {
  if (!_durableEventCorrelationPattern.hasMatch(durableEventCorrelation) ||
      !await _tableExists(txn)) {
    return null;
  }
  final rows = await txn.query(
    _table,
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final current = rows.single;
  final expectedAuthority = <String, Object?>{
    'event_id': eventId,
    'event_kind': expectedEventKind,
    'group_id': expectedGroupId,
    'message_id': expectedMessageId,
    'actor_peer_id': expectedActorPeerId,
    'event_timestamp': expectedEventTimestamp,
    'reaction_id': expectedReactionId,
    'reaction_action': expectedReactionAction,
    'reaction_tombstone': expectedReactionTombstone == null
        ? null
        : (expectedReactionTombstone ? 1 : 0),
  };
  if (current['revision'] != expectedRevision ||
      current['readiness'] != 'ready' ||
      !_sameAuthority(current, expectedAuthority)) {
    return null;
  }
  final marker = current['last_attempt_at'] as String?;
  final existingCorrelation =
      groupNotificationDisplayDurableCorrelationFromMarker(marker);
  if (existingCorrelation != null) {
    return existingCorrelation == durableEventCorrelation ? current : null;
  }
  if (isGroupNotificationDisplayCanonicalRetiredMarker(marker)) return null;

  final updated = await txn.rawUpdate(
    'UPDATE $_table SET last_attempt_at = ?, next_attempt_at = NULL, '
    'updated_at = ? '
    'WHERE event_id = ? AND revision = ? AND readiness = ?',
    <Object?>[
      groupNotificationDisplayDurableCorrelationMarker(durableEventCorrelation),
      updatedAt,
      eventId,
      expectedRevision,
      'ready',
    ],
  );
  if (updated != 1) return null;
  final rebound = await txn.query(
    _table,
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
    limit: 1,
  );
  return rebound.isEmpty ? null : rebound.single;
}, exclusive: true);

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
    'last_error_code = ?, '
    'last_attempt_at = CASE WHEN last_attempt_at = ? '
    'OR last_attempt_at LIKE ? OR last_attempt_at LIKE ? '
    'THEN last_attempt_at ELSE ? END, next_attempt_at = ?, '
    'updated_at = ?, revision = revision + 1 '
    'WHERE event_id = ? AND revision = ? AND readiness = ?',
    <Object?>[
      lastErrorCode,
      kGroupNotificationDisplayCanonicalRetiredMarker,
      '$_groupNotificationDisplayDurableCorrelationMarkerPrefix%',
      '$_groupNotificationDisplayCanonicalRetiredCorrelationMarkerPrefix%',
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
  required String completedAt,
  NotificationCompletedOutcomeCandidate? outcome,
}) async {
  final handoff =
      await dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
        db,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedGroupId: expectedGroupId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
        completedAt: completedAt,
        outcome: outcome,
        allowExistingDifferentOutcome: true,
        durableEventCorrelation: null,
        retireReadyWithinTransaction: true,
      );
  return handoff == DurableLocalNotificationSqlHandoffResult.committed;
}

/// Commits/verifies the exact group terminal while retaining READY custody.
///
/// Group reaction SQL retains only a bounded event alias, so deleting READY
/// before file-ledger settlement would lose the raw authenticated transition
/// needed by a fresh process. The caller must settle the ledger and only then
/// call [dbRetireGroupNotificationDisplayOutboxAfterDurableSettlementIfExact].
/// A missing READY row remains supported for exact replay of databases written
/// by an earlier completion path, but requires the typed terminal and v116 fact.
Future<DurableLocalNotificationSqlHandoffResult>
dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
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
  required String completedAt,
  NotificationCompletedOutcomeCandidate? outcome,
  bool allowExistingDifferentOutcome = false,
  String? durableEventCorrelation,
  bool retireReadyWithinTransaction = false,
}) => dbWriteTransaction(db, (txn) async {
  if (!await _tableExists(txn)) {
    return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
  }
  if (durableEventCorrelation != null &&
      !_durableEventCorrelationPattern.hasMatch(durableEventCorrelation)) {
    return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
  }
  if (outcome != null &&
      durableEventCorrelation != null &&
      tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: outcome.physicalPeerId,
            producerKind: outcome.producerKind,
            eventKey: outcome.eventKey,
          ) !=
          durableEventCorrelation) {
    return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
  }
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
  _appendNullableAuthorityComparand(
    where,
    whereArgs,
    column: 'reaction_id',
    value: expectedReactionId,
  );
  _appendNullableAuthorityComparand(
    where,
    whereArgs,
    column: 'reaction_action',
    value: expectedReactionAction,
  );
  _appendNullableAuthorityComparand(
    where,
    whereArgs,
    column: 'reaction_tombstone',
    value: expectedReactionTombstone == null
        ? null
        : (expectedReactionTombstone ? 1 : 0),
  );

  final exactCustody = await txn.query(
    _table,
    columns: const <String>['event_id', 'last_attempt_at'],
    where: where.toString(),
    whereArgs: whereArgs,
    limit: 1,
  );
  if (exactCustody.isEmpty) {
    final sameEvent = await txn.query(
      _table,
      columns: const <String>['event_id'],
      where: 'event_id = ?',
      whereArgs: <Object?>[eventId],
      limit: 1,
    );
    if (sameEvent.isNotEmpty ||
        !await _hasExactCompletedGroupTerminal(
          txn,
          eventId: eventId,
          eventKind: expectedEventKind,
          groupId: expectedGroupId,
          messageId: expectedMessageId,
          actorPeerId: expectedActorPeerId,
          eventTimestamp: expectedEventTimestamp,
          reactionId: expectedReactionId,
          reactionAction: expectedReactionAction,
          reactionTombstone: expectedReactionTombstone,
          durableEventCorrelation: durableEventCorrelation,
        ) ||
        !await _hasExactGroupOutcome(txn, outcome)) {
      return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
    }
    return DurableLocalNotificationSqlHandoffResult.alreadyCommitted;
  }

  final canonicalRetirementTerminal =
      durableEventCorrelation != null &&
      isGroupNotificationDisplayCanonicalRetiredMarker(
        exactCustody.single['last_attempt_at'] as String?,
      ) &&
      groupNotificationDisplayDurableCorrelationFromMarker(
            exactCustody.single['last_attempt_at'] as String?,
          ) ==
          durableEventCorrelation &&
      await _hasExactCanonicalGroupRetirementTerminal(
        txn,
        eventKind: expectedEventKind,
        groupId: expectedGroupId,
        messageId: expectedMessageId,
        actorPeerId: expectedActorPeerId,
        eventTimestamp: expectedEventTimestamp,
        reactionId: expectedReactionId,
        reactionAction: expectedReactionAction,
        reactionTombstone: expectedReactionTombstone,
      );
  final terminalAlreadyCommitted =
      canonicalRetirementTerminal ||
      await _hasExactCompletedGroupTerminal(
        txn,
        eventId: eventId,
        eventKind: expectedEventKind,
        groupId: expectedGroupId,
        messageId: expectedMessageId,
        actorPeerId: expectedActorPeerId,
        eventTimestamp: expectedEventTimestamp,
        reactionId: expectedReactionId,
        reactionAction: expectedReactionAction,
        reactionTombstone: expectedReactionTombstone,
        durableEventCorrelation: durableEventCorrelation,
      );
  if (!retireReadyWithinTransaction &&
      terminalAlreadyCommitted &&
      await _hasExactGroupOutcome(txn, outcome)) {
    return DurableLocalNotificationSqlHandoffResult.alreadyCommitted;
  }

  if (canonicalRetirementTerminal) {
    // A canonical delete/remove transaction deliberately retains this exact
    // raw READY row. Together they are the typed SQL terminal: the tombstone
    // or newer reaction state proves retirement while READY preserves every
    // immutable producer comparand until the file-ledger record settles.
  } else if (expectedEventKind == 'message') {
    final updated = await txn.rawUpdate(
      'UPDATE group_messages '
      'SET notification_display_terminal_event_id = ? '
      'WHERE id = ? AND group_id = ? AND sender_peer_id = ? '
      'AND timestamp = ? '
      'AND (notification_display_terminal_event_id IS NULL '
      'OR notification_display_terminal_event_id = ?)',
      <Object?>[
        durableEventCorrelation ?? eventId,
        expectedMessageId,
        expectedGroupId,
        expectedActorPeerId,
        expectedEventTimestamp,
        durableEventCorrelation ?? eventId,
      ],
    );
    if (updated != 1) {
      return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
    }
  } else if (expectedEventKind == 'reaction' &&
      expectedReactionId != null &&
      expectedReactionAction == 'add' &&
      expectedReactionTombstone == false) {
    final terminalIdentity =
        durableEventCorrelation ?? boundedReactionEventIdentity(eventId);
    final updated = await txn.rawUpdate(
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
    if (updated != 1) {
      return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
    }
    await dbAppendProtectedGroupReactionDisplayTerminalIfExact(
      txn,
      groupId: expectedGroupId,
      transitionId: eventId,
      messageId: expectedMessageId,
      actorPeerId: expectedActorPeerId,
      reactionId: expectedReactionId,
      eventTimestamp: expectedEventTimestamp,
    );
  } else {
    return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
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

  if (retireReadyWithinTransaction) {
    final deleted = await txn.delete(
      _table,
      where: where.toString(),
      whereArgs: whereArgs,
    );
    if (deleted != 1) {
      throw StateError('group notification display completion CAS failed');
    }
  }

  return DurableLocalNotificationSqlHandoffResult.committed;
}, exclusive: true);

/// Deletes the exact raw READY row only after its ledger record settled.
///
/// Successful settlement already proves that canonical content reached its
/// final native effect, so this retirement must not enqueue an immediate
/// replacement of that same content. Canonical mutations own reconciliation
/// separately. Missing-row replay is accepted only with the same typed SQL
/// terminal evidence.
Future<bool>
dbRetireGroupNotificationDisplayOutboxAfterDurableSettlementIfExact(
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
  String? durableEventCorrelation,
}) => dbWriteTransaction(db, (txn) async {
  if ((durableEventCorrelation != null &&
          !_durableEventCorrelationPattern.hasMatch(durableEventCorrelation)) ||
      !await _tableExists(txn)) {
    return false;
  }
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
  _appendNullableAuthorityComparand(
    where,
    whereArgs,
    column: 'reaction_id',
    value: expectedReactionId,
  );
  _appendNullableAuthorityComparand(
    where,
    whereArgs,
    column: 'reaction_action',
    value: expectedReactionAction,
  );
  _appendNullableAuthorityComparand(
    where,
    whereArgs,
    column: 'reaction_tombstone',
    value: expectedReactionTombstone == null
        ? null
        : (expectedReactionTombstone ? 1 : 0),
  );
  final sameEvent = await txn.query(
    _table,
    columns: const <String>['event_id'],
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
    limit: 1,
  );
  final exactCustody = sameEvent.isEmpty
      ? const <Map<String, Object?>>[]
      : await txn.query(
          _table,
          columns: const <String>['event_id', 'last_attempt_at'],
          where: where.toString(),
          whereArgs: whereArgs,
          limit: 1,
        );
  final hasTypedTerminal = await _hasExactCompletedGroupTerminal(
    txn,
    eventId: eventId,
    eventKind: expectedEventKind,
    groupId: expectedGroupId,
    messageId: expectedMessageId,
    actorPeerId: expectedActorPeerId,
    eventTimestamp: expectedEventTimestamp,
    reactionId: expectedReactionId,
    reactionAction: expectedReactionAction,
    reactionTombstone: expectedReactionTombstone,
    durableEventCorrelation: durableEventCorrelation,
  );
  final hasCanonicalRetirementTerminal =
      exactCustody.isNotEmpty &&
      durableEventCorrelation != null &&
      isGroupNotificationDisplayCanonicalRetiredMarker(
        exactCustody.single['last_attempt_at'] as String?,
      ) &&
      groupNotificationDisplayDurableCorrelationFromMarker(
            exactCustody.single['last_attempt_at'] as String?,
          ) ==
          durableEventCorrelation &&
      await _hasExactCanonicalGroupRetirementTerminal(
        txn,
        eventKind: expectedEventKind,
        groupId: expectedGroupId,
        messageId: expectedMessageId,
        actorPeerId: expectedActorPeerId,
        eventTimestamp: expectedEventTimestamp,
        reactionId: expectedReactionId,
        reactionAction: expectedReactionAction,
        reactionTombstone: expectedReactionTombstone,
      );
  if (!hasTypedTerminal && !hasCanonicalRetirementTerminal) return false;
  if (sameEvent.isNotEmpty) {
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

void _appendNullableAuthorityComparand(
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

Future<bool> _hasExactCompletedGroupTerminal(
  DatabaseExecutor db, {
  required String eventId,
  required String eventKind,
  required String groupId,
  required String messageId,
  required String actorPeerId,
  required String eventTimestamp,
  required String? reactionId,
  required String? reactionAction,
  required bool? reactionTombstone,
  required String? durableEventCorrelation,
}) => switch (eventKind) {
  'message' => _hasExactCompletedGroupMessageTerminal(
    db,
    groupId: groupId,
    messageId: messageId,
    actorPeerId: actorPeerId,
    eventTimestamp: eventTimestamp,
    terminalEventIdentity: durableEventCorrelation ?? eventId,
  ),
  'reaction'
      when reactionId != null &&
          reactionAction == 'add' &&
          reactionTombstone == false =>
    _hasExactCompletedGroupReactionTerminal(
      db,
      eventId: eventId,
      groupId: groupId,
      messageId: messageId,
      actorPeerId: actorPeerId,
      eventTimestamp: eventTimestamp,
      reactionId: reactionId,
      terminalEventIdentity:
          durableEventCorrelation ?? boundedReactionEventIdentity(eventId),
      allowProtectedTerminalFallback: durableEventCorrelation == null,
    ),
  _ => Future<bool>.value(false),
};

Future<bool> _hasExactGroupOutcome(
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
  final row = await dbLoadExactNotificationCompletedOutcomeOutboxEntry(
    db,
    wakeCorrelation: correlation,
  );
  return row != null && row['outcome'] == outcome.outcome.wireValue;
}

Future<bool> _hasExactCompletedGroupMessageTerminal(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
  required String actorPeerId,
  required String eventTimestamp,
  required String terminalEventIdentity,
}) async {
  final rows = await db.query(
    'group_messages',
    columns: const <String>['id'],
    where:
        'id = ? AND group_id = ? AND sender_peer_id = ? AND timestamp = ? '
        'AND notification_display_terminal_event_id = ?',
    whereArgs: <Object?>[
      messageId,
      groupId,
      actorPeerId,
      eventTimestamp,
      terminalEventIdentity,
    ],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<bool> _hasExactCompletedGroupReactionTerminal(
  DatabaseExecutor db, {
  required String eventId,
  required String groupId,
  required String messageId,
  required String actorPeerId,
  required String eventTimestamp,
  required String reactionId,
  required String terminalEventIdentity,
  required bool allowProtectedTerminalFallback,
}) async {
  final rows = await db.rawQuery(
    'SELECT r.id FROM message_reactions r '
    'INNER JOIN group_messages m ON m.id = r.message_id '
    'WHERE r.id = ? AND r.message_id = ? AND r.sender_peer_id = ? '
    'AND r.timestamp = ? AND r.removed_at IS NULL '
    'AND r.notification_display_terminal_event_id = ? AND m.group_id = ? '
    'LIMIT 1',
    <Object?>[
      reactionId,
      messageId,
      actorPeerId,
      eventTimestamp,
      terminalEventIdentity,
      groupId,
    ],
  );
  if (rows.isNotEmpty) return true;
  if (!allowProtectedTerminalFallback) return false;
  return dbHasProtectedGroupReactionDisplayTerminalExact(
    db,
    groupId: groupId,
    transitionId: eventId,
    messageId: messageId,
    actorPeerId: actorPeerId,
    reactionId: reactionId,
    eventTimestamp: eventTimestamp,
  );
}

/// Proves a canonical delete/remove terminal while exact raw READY custody is
/// still present in the caller's transaction.
///
/// Absence alone is never sufficient: callers have already verified the exact
/// correlation-bound canonical-retired READY marker written in the same
/// mutation transaction. A message tombstone is preferred; membership repair
/// uses the marker itself as a monotonic terminal even if buffered canonical
/// content is later restored. Reactions require a deleted target, an absent
/// group, or a materialized remove/newer transition for the same target and
/// actor.
Future<bool> _hasExactCanonicalGroupRetirementTerminal(
  DatabaseExecutor db, {
  required String eventKind,
  required String groupId,
  required String messageId,
  required String actorPeerId,
  required String eventTimestamp,
  required String? reactionId,
  required String? reactionAction,
  required bool? reactionTombstone,
}) async {
  final groupRows = await db.query(
    'groups',
    columns: const <String>['id'],
    where: 'id = ?',
    whereArgs: <Object?>[groupId],
    limit: 1,
  );
  if (groupRows.isEmpty) return true;

  final deletionRows = await db.query(
    'group_message_local_deletions',
    columns: const <String>['message_id'],
    where: 'message_id = ? AND group_id = ?',
    whereArgs: <Object?>[messageId, groupId],
    limit: 1,
  );
  if (deletionRows.isNotEmpty) return true;
  // The caller already matched immutable READY comparands and the exact
  // correlation-bearing retirement marker. Restoring the same message must
  // not reopen this old notification attempt.
  if (eventKind == 'message') return true;
  if (eventKind != 'reaction' ||
      reactionId == null ||
      reactionAction != 'add' ||
      reactionTombstone != false) {
    return false;
  }

  final targetRows = await db.query(
    'group_messages',
    columns: const <String>['id'],
    where: 'id = ? AND group_id = ?',
    whereArgs: <Object?>[messageId, groupId],
    limit: 1,
  );
  if (targetRows.isEmpty) return false;
  final reactionRows = await db.query(
    'message_reactions',
    columns: const <String>['id', 'timestamp', 'removed_at'],
    where: 'message_id = ? AND sender_peer_id = ?',
    whereArgs: <Object?>[messageId, actorPeerId],
    limit: 1,
  );
  if (reactionRows.isEmpty) return false;
  final current = reactionRows.single;
  final expectedAt = DateTime.tryParse(eventTimestamp)?.toUtc();
  final currentAt = DateTime.tryParse(
    current['timestamp'] as String? ?? '',
  )?.toUtc();
  final removedAt = DateTime.tryParse(
    current['removed_at'] as String? ?? '',
  )?.toUtc();
  if (expectedAt == null || currentAt == null) return false;
  return currentAt.isAfter(expectedAt) ||
      (removedAt != null && !removedAt.isBefore(expectedAt));
}

/// Retires stale or ineligible custody without recording display authority.
///
/// Every immutable comparand and the ready revision must still match so a
/// reused event id or newer retry generation cannot be deleted by an older
/// projection.
Future<bool> dbRetireGroupNotificationDisplayOutboxEntryIfExact(
  DatabaseExecutor db, {
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
}) async {
  if (!await _tableExists(db)) return false;
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
      if (canonical != null && canonical['readiness'] == 'not_ready') {
        final deleted = await txn.delete(
          _table,
          where: 'event_id = ? AND revision = ? AND readiness = ?',
          whereArgs: <Object?>[
            canonicalEventId,
            canonical['revision'],
            'not_ready',
          ],
        );
        if (deleted != 1) {
          throw StateError('terminal canonical custody retire failed');
        }
      }
      // A canonical READY row may already own CLAIMED/PUBLISHING or an
      // EFFECT_TERMINAL awaiting settlement. The typed message terminal
      // authorizes replay, but only exact transaction B may delete READY.
      if (aliasEventId != canonicalEventId && alias != null) {
        // Alias reconciliation runs synchronously before a duplicate delivery
        // can enter notification projection; this non-canonical marker cannot
        // own a durable effect and would otherwise be permanently stranded.
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
  String groupId, {
  bool preserveReadyCustody = false,
}) async {
  if (!await _tableExists(db)) return 0;
  return _deleteOrMarkCanonicalRetired(
    db,
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
    preserveReadyCustody: preserveReadyCustody,
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
  bool preserveReadyCustody = false,
}) async {
  if (!await _tableExists(db)) return 0;
  return _deleteOrMarkCanonicalRetired(
    db,
    where: 'group_id = ? AND message_id = ?',
    whereArgs: <Object?>[groupId, messageId],
    preserveReadyCustody: preserveReadyCustody,
  );
}

Future<int> dbDeleteGroupNotificationDisplayOutboxForReaction(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
  required String reactionId,
  bool preserveReadyCustody = false,
}) async {
  if (!await _tableExists(db)) return 0;
  return _deleteOrMarkCanonicalRetired(
    db,
    where:
        'group_id = ? AND message_id = ? AND event_kind = ? '
        'AND reaction_id = ?',
    whereArgs: <Object?>[groupId, messageId, 'reaction', reactionId],
    preserveReadyCustody: preserveReadyCustody,
  );
}

/// Retires one authority-exact reaction transition without consuming READY
/// custody that may already be represented by a PUBLISHING/EFFECT_TERMINAL
/// ledger record.
Future<int> dbRetireExactGroupNotificationDisplayOutboxReactionTransition(
  DatabaseExecutor db, {
  required String eventId,
  required String groupId,
  required String messageId,
  required String actorPeerId,
  required String eventTimestamp,
  required String reactionId,
  required String reactionAction,
  required bool reactionTombstone,
}) async {
  if (!await _tableExists(db)) return 0;
  return _deleteOrMarkCanonicalRetired(
    db,
    where:
        'event_id = ? AND event_kind = ? AND group_id = ? '
        'AND message_id = ? AND actor_peer_id = ? AND event_timestamp = ? '
        'AND reaction_id = ? AND reaction_action = ? '
        'AND reaction_tombstone = ?',
    whereArgs: <Object?>[
      eventId,
      'reaction',
      groupId,
      messageId,
      actorPeerId,
      eventTimestamp,
      reactionId,
      reactionAction,
      reactionTombstone ? 1 : 0,
    ],
    preserveReadyCustody: true,
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
  bool preserveReadyCustody = false,
}) async {
  if (!await _tableExists(db)) return 0;
  return _deleteOrMarkCanonicalRetired(
    db,
    where:
        'group_id = ? AND message_id = ? AND event_kind = ? '
        'AND actor_peer_id = ?',
    whereArgs: <Object?>[groupId, messageId, 'reaction', actorPeerId],
    preserveReadyCustody: preserveReadyCustody,
  );
}

/// Canonical mutation owns a two-part terminal when READY may already be in a
/// final-effect attempt: immutable READY comparands plus this marker. A row
/// already bound to a durable correlation carries that digest into the
/// retirement marker so recovery never has to reconstruct deleted raw facts.
/// NOT_READY has never entered the effect boundary and remains safe to delete.
Future<int> _deleteOrMarkCanonicalRetired(
  DatabaseExecutor db, {
  required String where,
  required List<Object?> whereArgs,
  required bool preserveReadyCustody,
}) async {
  if (!preserveReadyCustody) {
    return db.delete(_table, where: where, whereArgs: whereArgs);
  }
  await db.rawUpdate(
    'UPDATE $_table SET revision = revision + 1, '
    'last_error_code = ?, last_attempt_at = CASE '
    'WHEN last_attempt_at LIKE ? THEN ? || '
    'substr(last_attempt_at, ${_groupNotificationDisplayDurableCorrelationMarkerPrefix.length + 1}) '
    'WHEN last_attempt_at LIKE ? THEN last_attempt_at ELSE ? END, '
    'next_attempt_at = NULL, '
    "updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') "
    'WHERE ($where) AND readiness = ?',
    <Object?>[
      'state_unavailable',
      '$_groupNotificationDisplayDurableCorrelationMarkerPrefix%',
      _groupNotificationDisplayCanonicalRetiredCorrelationMarkerPrefix,
      '$_groupNotificationDisplayCanonicalRetiredCorrelationMarkerPrefix%',
      kGroupNotificationDisplayCanonicalRetiredMarker,
      ...whereArgs,
      'ready',
    ],
  );
  return db.delete(
    _table,
    where: '($where) AND readiness != ?',
    whereArgs: <Object?>[...whereArgs, 'ready'],
  );
}

Future<bool> _tableExists(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const <Object?>[_table],
  );
  return rows.isNotEmpty;
}
