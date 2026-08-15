import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../media/private_media_policy.dart';
import '../db_write_transaction.dart';
import '../direct_event_fanout_contract.dart';
import '../direct_media_blob_custody.dart';
import '../direct_inbox_event_envelope.dart';
import '../direct_reaction_inbox_custody_outbox_contract.dart';
import '../outgoing_transport_mutation.dart';
import 'direct_contact_device_bindings_db_helpers.dart';
import 'direct_inbox_custody_outbox_db_helpers.dart';
import 'direct_media_blob_custody_db_helpers.dart';
import 'messages_db_helpers.dart';

/// The one physical v109 outbox shared by direct reaction and mutation events.
const String kDirectReactionInboxCustodyOutboxTable =
    'direct_reaction_inbox_custody_outbox';

const String _table = kDirectReactionInboxCustodyOutboxTable;

const int kDirectReactionInboxCustodyOutboxCapacity = 512;
const int kDirectReactionInboxCustodyOutboxMaxLoadBatch = 50;

/// Atomically mutates one ordinary outgoing text parent and retains the exact
/// edit/deletion event in the existing physical v109 outbox.
Future<DbDirectTextMutationCustodyStageResult>
dbStageOutgoingDirectTextMutationInboxCustody(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required OutgoingOrdinaryAttemptKind kind,
  required String recipientPeerId,
  required String eventId,
  required String wireEnvelope,
  int capacity = kDirectReactionInboxCustodyOutboxCapacity,
  Future<void> Function()? beforeCustodyInsertForTest,
}) {
  final classified = classifyDirectInboxEventEnvelope(wireEnvelope);
  final messageId = stagedRow['id'];
  final senderPeerId = stagedRow['sender_peer_id'];
  final createdAt = stagedRow['created_at'];
  final isEdit = kind == OutgoingOrdinaryAttemptKind.edit;
  final isDeletion =
      kind == OutgoingOrdinaryAttemptKind.tombstoneInitial ||
      kind == OutgoingOrdinaryAttemptKind.tombstoneRetry;
  final exactEnvelopeKind =
      (isEdit && classified?.kind == DirectInboxEventEnvelopeKind.edit) ||
      (isDeletion && classified?.kind == DirectInboxEventEnvelopeKind.deletion);
  final valid =
      capacity >= 0 &&
      expectedRow != null &&
      _isNonBlank(recipientPeerId) &&
      _isNonBlank(eventId) &&
      _isNonBlank(messageId) &&
      _isNonBlank(senderPeerId) &&
      _isNonBlank(createdAt) &&
      DateTime.tryParse(createdAt as String) != null &&
      classified != null &&
      classified.eventId == eventId &&
      classified.senderPeerId == senderPeerId &&
      exactEnvelopeKind &&
      (!isEdit || classified.targetMessageId == messageId) &&
      stagedRow['contact_peer_id'] == recipientPeerId &&
      stagedRow['wire_envelope'] == wireEnvelope &&
      _isStrictOrdinaryTextPolicy(expectedRow) &&
      _isStrictOrdinaryTextPolicy(stagedRow) &&
      (isEdit || _isExactOutgoingDeletionProjection(stagedRow));
  if (!valid) {
    return Future<DbDirectTextMutationCustodyStageResult>.value(
      const DbDirectTextMutationCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        custodyRow: null,
      ),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final existingCustody = await txn.query(
      _table,
      where: 'recipient_peer_id = ? AND event_id = ?',
      whereArgs: <Object?>[recipientPeerId, eventId],
      limit: 1,
    );
    if (existingCustody.isNotEmpty) {
      final row = existingCustody.single;
      if (row['wire_envelope'] != wireEnvelope) {
        return const DbDirectTextMutationCustodyStageResult(
          outcome: OutgoingOrdinaryMutationOutcome.refused,
          custodyRow: null,
        );
      }
      return DbDirectTextMutationCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.idempotent,
        custodyRow: Map<String, Object?>.from(row),
      );
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table',
    );
    final count = (countRows.single['count'] as num?)?.toInt() ?? 0;
    if (count >= capacity) {
      return const DbDirectTextMutationCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        custodyRow: null,
      );
    }

    final hasMediaTable = (await txn.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'media_attachments' LIMIT 1",
    )).isNotEmpty;
    if (hasMediaTable) {
      final directMedia = await txn.rawQuery(
        'SELECT 1 FROM media_attachments '
        'WHERE message_id = ? AND owner_lane = ? LIMIT 1',
        <Object?>[messageId, 'direct'],
      );
      if (directMedia.isNotEmpty) {
        return const DbDirectTextMutationCustodyStageResult(
          outcome: OutgoingOrdinaryMutationOutcome.refused,
          custodyRow: null,
        );
      }
    }

    final messageOutcome =
        await dbStageOutgoingOrdinaryAttemptWithinTransaction(
          txn,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          kind: kind,
        );
    if (messageOutcome != OutgoingOrdinaryMutationOutcome.applied) {
      return DbDirectTextMutationCustodyStageResult(
        outcome: messageOutcome == OutgoingOrdinaryMutationOutcome.idempotent
            ? OutgoingOrdinaryMutationOutcome.refused
            : messageOutcome,
        custodyRow: null,
      );
    }

    final custodyRow = <String, Object?>{
      'recipient_peer_id': recipientPeerId,
      'event_id': eventId,
      'wire_envelope': wireEnvelope,
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    };
    await beforeCustodyInsertForTest?.call();
    await txn.insert(
      _table,
      custodyRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return DbDirectTextMutationCustodyStageResult(
      outcome: OutgoingOrdinaryMutationOutcome.applied,
      custodyRow: custodyRow,
    );
  });
}

/// Atomically commits one v1 Protected/View-Once delete-for-everyone tombstone
/// and retains its exact deletion event in the same physical v109 outbox.
///
/// Either both writes land or neither does. The helper deliberately performs no
/// artifact, secure-key, v108 or v111 work: those remain independent lifecycle
/// owners, and cleanup is a caller operation this transaction only authorizes.
///
/// [capacity] and [beforeCustodyInsertForTest] are test seams. Production uses
/// the shared 512-row default and supplies no barrier.
Future<DbDirectPrivateDeletionCustodyStageResult>
dbStageOutgoingDirectPrivateDeletionInboxCustody(
  Database db, {
  required Map<String, Object?> expectedRow,
  required Map<String, Object?> tombstoneRow,
  required String recipientPeerId,
  required String eventId,
  required String wireEnvelope,
  int capacity = kDirectReactionInboxCustodyOutboxCapacity,
  Future<void> Function()? beforeCustodyInsertForTest,
}) {
  final classified = classifyDirectInboxEventEnvelope(wireEnvelope);
  final messageId = tombstoneRow['id'];
  final senderPeerId = tombstoneRow['sender_peer_id'];
  final createdAt = tombstoneRow['created_at'];
  final valid =
      capacity >= 0 &&
      _isNonBlank(recipientPeerId) &&
      _isNonBlank(eventId) &&
      _isNonBlank(messageId) &&
      _isNonBlank(senderPeerId) &&
      _isNonBlank(createdAt) &&
      DateTime.tryParse(createdAt! as String) != null &&
      classified != null &&
      classified.kind == DirectInboxEventEnvelopeKind.deletion &&
      classified.eventId == eventId &&
      classified.senderPeerId == senderPeerId &&
      tombstoneRow['contact_peer_id'] == recipientPeerId &&
      tombstoneRow['wire_envelope'] == wireEnvelope &&
      isExactOutgoingDirectPrivateDeleteTombstoneShape(
        expectedRow: expectedRow,
        tombstoneRow: tombstoneRow,
      );
  if (!valid) {
    return Future<DbDirectPrivateDeletionCustodyStageResult>.value(
      const DbDirectPrivateDeletionCustodyStageResult.refused(),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    // Exact replay is checked before shared capacity, so an already-owned event
    // stays idempotent even when the outbox is full.
    final existingCustody = await txn.query(
      _table,
      where: 'recipient_peer_id = ? AND event_id = ?',
      whereArgs: <Object?>[recipientPeerId, eventId],
      limit: 1,
    );
    if (existingCustody.isNotEmpty) {
      final row = existingCustody.single;
      if (row['wire_envelope'] != wireEnvelope) {
        return const DbDirectPrivateDeletionCustodyStageResult.refused();
      }
      // 357: a retained event proves only that SOME attempt owned this
      // envelope. The deletion outer envelope hides its target message id, so a
      // pre-existing row can never prove which live parent its encrypted inner
      // payload names. Replay therefore authorizes only an ALREADY-persisted
      // exact tombstone: project the completion-style outgoing envelope owner,
      // require it to be unique and to be this message, then require the exact
      // persisted row. Missing, live, crossed, ambiguous, wrong-policy and
      // drifted parents refuse with the retained event left untouched, and the
      // mutating live-parent tombstone body is deliberately never invoked here.
      final projected = await txn.query(
        'messages',
        where: 'contact_peer_id = ? AND is_incoming = 0 AND wire_envelope = ?',
        whereArgs: <Object?>[recipientPeerId, wireEnvelope],
        limit: 2,
      );
      if (projected.length != 1 ||
          projected.single['id'] != messageId ||
          !isPersistedExactOutgoingDirectPrivateDeleteTombstoneRow(
            persistedRow: projected.single,
            tombstoneRow: tombstoneRow,
          )) {
        return const DbDirectPrivateDeletionCustodyStageResult.refused();
      }
      return DbDirectPrivateDeletionCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.idempotent,
        messageRow: Map<String, Object?>.from(projected.single),
        custodyRow: Map<String, Object?>.from(row),
      );
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table',
    );
    if (((countRows.single['count'] as num?)?.toInt() ?? 0) >= capacity) {
      return const DbDirectPrivateDeletionCustodyStageResult.refused();
    }

    final committedTombstone =
        await dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstoneWithinTransaction(
          txn,
          expectedRow: expectedRow,
          tombstoneRow: tombstoneRow,
        );
    if (!committedTombstone) {
      return const DbDirectPrivateDeletionCustodyStageResult.refused();
    }

    final custodyRow = <String, Object?>{
      'recipient_peer_id': recipientPeerId,
      'event_id': eventId,
      'wire_envelope': wireEnvelope,
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    };
    // Test-only barrier between the private parent update and the v109 insert.
    await beforeCustodyInsertForTest?.call();
    await txn.insert(
      _table,
      custodyRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final committed = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (committed.length != 1) {
      throw StateError('private deletion lost its exact tombstone');
    }
    return DbDirectPrivateDeletionCustodyStageResult(
      outcome: OutgoingOrdinaryMutationOutcome.applied,
      messageRow: Map<String, Object?>.from(committed.single),
      custodyRow: custodyRow,
    );
  });
}

/// Atomically applies the canonical direct-reaction transition and retains its
/// exact encrypted inbox obligation.
///
/// [capacity] is a test seam only. Production callers use the exact 512-row
/// default. Exact replay is checked before capacity and remains idempotent even
/// after the target or canonical projection has been deleted.
Future<DbDirectReactionCustodyStageResult>
dbStageOutgoingDirectReactionInboxCustody(
  Database db, {
  required Map<String, Object?> reactionRow,
  required String recipientPeerId,
  required String action,
  required String wireEnvelope,
  int capacity = kDirectReactionInboxCustodyOutboxCapacity,
  Future<void> Function()? beforeCustodyInsertForTest,
}) {
  final eventId = reactionRow['id'];
  final messageId = reactionRow['message_id'];
  final senderPeerId = reactionRow['sender_peer_id'];
  final timestamp = reactionRow['timestamp'];
  final createdAt = reactionRow['created_at'];
  final valid =
      capacity >= 0 &&
      eventId is String &&
      _isNonBlank(eventId) &&
      messageId is String &&
      _isNonBlank(messageId) &&
      senderPeerId is String &&
      _isNonBlank(senderPeerId) &&
      timestamp is String &&
      _isNonBlank(timestamp) &&
      DateTime.tryParse(timestamp) != null &&
      createdAt is String &&
      _isNonBlank(createdAt) &&
      DateTime.tryParse(createdAt) != null &&
      _isNonBlank(recipientPeerId) &&
      _isNonBlank(reactionRow['emoji']) &&
      (action == 'add' || action == 'remove') &&
      (action != 'add' || reactionRow['removed_at'] == null) &&
      _isExactV2DirectReactionEnvelope(
        wireEnvelope,
        eventId: eventId,
        action: action,
        targetMessageId: messageId,
        senderPeerId: senderPeerId,
      );
  if (!valid) {
    return Future<DbDirectReactionCustodyStageResult>.value(
      const DbDirectReactionCustodyStageResult(
        outcome: DirectReactionCustodyStageOutcome.refused,
        custodyRow: null,
      ),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final existingCustody = await txn.query(
      _table,
      where: 'recipient_peer_id = ? AND event_id = ?',
      whereArgs: <Object?>[recipientPeerId, eventId],
      limit: 1,
    );
    if (existingCustody.isNotEmpty) {
      final row = existingCustody.single;
      if (row['wire_envelope'] != wireEnvelope) {
        return const DbDirectReactionCustodyStageResult(
          outcome: DirectReactionCustodyStageOutcome.refused,
          custodyRow: null,
        );
      }
      return DbDirectReactionCustodyStageResult(
        outcome: DirectReactionCustodyStageOutcome.idempotent,
        custodyRow: Map<String, Object?>.from(row),
      );
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table',
    );
    final count = (countRows.single['count'] as num?)?.toInt() ?? 0;
    if (count >= capacity) {
      return const DbDirectReactionCustodyStageResult(
        outcome: DirectReactionCustodyStageOutcome.refused,
        custodyRow: null,
      );
    }

    final directTargets = await txn.query(
      'messages',
      columns: const <String>['id'],
      where: 'id = ? AND contact_peer_id = ?',
      whereArgs: <Object?>[messageId, recipientPeerId],
      limit: 1,
    );
    if (directTargets.isEmpty) {
      return const DbDirectReactionCustodyStageResult(
        outcome: DirectReactionCustodyStageOutcome.refused,
        custodyRow: null,
      );
    }
    final groupTargets = await txn.query(
      'group_messages',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (groupTargets.isNotEmpty) {
      return const DbDirectReactionCustodyStageResult(
        outcome: DirectReactionCustodyStageOutcome.refused,
        custodyRow: null,
      );
    }

    final currentRows = await txn.query(
      'message_reactions',
      where: 'message_id = ? AND sender_peer_id = ?',
      whereArgs: <Object?>[messageId, senderPeerId],
      limit: 1,
    );
    final current = currentRows.isEmpty ? null : currentRows.single;
    final eventRows = await txn.query(
      'message_reactions',
      columns: const <String>['id', 'message_id', 'sender_peer_id'],
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
      limit: 1,
    );
    if (eventRows.isNotEmpty &&
        (eventRows.single['message_id'] != messageId ||
            eventRows.single['sender_peer_id'] != senderPeerId)) {
      return const DbDirectReactionCustodyStageResult(
        outcome: DirectReactionCustodyStageOutcome.refused,
        custodyRow: null,
      );
    }

    final normalizedReaction = Map<String, Object?>.from(reactionRow);
    normalizedReaction['removed_at'] = action == 'remove' ? timestamp : null;
    final currentTimestamp = current == null
        ? null
        : current['removed_at'] as String? ?? current['timestamp'] as String?;
    final incomingAt = DateTime.parse(timestamp);
    final currentAt = currentTimestamp == null
        ? null
        : DateTime.tryParse(currentTimestamp);
    final isOlder = currentAt != null && incomingAt.isBefore(currentAt);
    if (!isOlder) {
      if (current != null &&
          current['id'] == eventId &&
          !_canonicalTransitionMatches(
            current,
            normalizedReaction,
            action: action,
          )) {
        return const DbDirectReactionCustodyStageResult(
          outcome: DirectReactionCustodyStageOutcome.refused,
          custodyRow: null,
        );
      }
      await txn.insert(
        'message_reactions',
        normalizedReaction,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final custodyRow = <String, Object?>{
      'recipient_peer_id': recipientPeerId,
      'event_id': eventId,
      'wire_envelope': wireEnvelope,
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    };
    // Test-only barrier for observing the transaction between canonical and
    // custody writes. Production never supplies it.
    await beforeCustodyInsertForTest?.call();
    await txn.insert(
      _table,
      custodyRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return DbDirectReactionCustodyStageResult(
      outcome: DirectReactionCustodyStageOutcome.applied,
      custodyRow: custodyRow,
    );
  });
}

/// Loads a fair bounded batch. NULL attempt timestamps sort first in SQLite.
Future<List<Map<String, Object?>>> dbLoadDirectReactionInboxCustodyOutbox(
  DatabaseExecutor db, {
  int limit = kDirectReactionInboxCustodyOutboxMaxLoadBatch,
}) {
  if (limit <= 0) return Future<List<Map<String, Object?>>>.value(const []);
  final boundedLimit = math.min(
    limit,
    kDirectReactionInboxCustodyOutboxMaxLoadBatch,
  );
  return db.rawQuery(
    'SELECT * FROM $_table '
    'ORDER BY last_attempt_at ASC, created_at ASC, '
    'recipient_peer_id ASC, event_id ASC LIMIT ?',
    <Object?>[boundedLimit],
  );
}

Future<Map<String, Object?>?> dbLoadDirectReactionInboxCustodyOutboxForEvent(
  DatabaseExecutor db, {
  required String recipientPeerId,
  required String eventId,
}) async {
  final rows = await db.query(
    _table,
    where: 'recipient_peer_id = ? AND event_id = ?',
    whereArgs: <Object?>[recipientPeerId, eventId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

/// Records one bounded failure only while the exact encrypted event survives.
Future<bool> dbRecordDirectReactionInboxCustodyFailureIfExact(
  DatabaseExecutor db, {
  required String recipientPeerId,
  required String eventId,
  required String expectedWireEnvelope,
  required String errorCode,
  required String attemptedAt,
}) async {
  if (!DirectReactionInboxCustodyErrorCode.values.contains(errorCode) ||
      !_isNonBlank(attemptedAt)) {
    return false;
  }
  final changed = await db.rawUpdate(
    'UPDATE $_table SET retry_count = retry_count + 1, '
    'last_attempt_at = ?, last_error_code = ?, updated_at = ? '
    'WHERE recipient_peer_id = ? AND event_id = ? AND wire_envelope = ?',
    <Object?>[
      attemptedAt,
      errorCode,
      attemptedAt,
      recipientPeerId,
      eventId,
      expectedWireEnvelope,
    ],
  );
  return changed == 1;
}

/// Retires only the exact immutable event after accepted remote custody.
/// Absence is explicit convergence for overlapping accepted attempts.
Future<DirectReactionInboxCustodyCompletionOutcome>
dbCompleteAcceptedDirectReactionInboxCustodyIfExact(
  Database db, {
  required String recipientPeerId,
  required String eventId,
  required String expectedWireEnvelope,
}) {
  if (!_isNonBlank(recipientPeerId) ||
      !_isNonBlank(eventId) ||
      !_isNonBlank(expectedWireEnvelope)) {
    return Future<DirectReactionInboxCustodyCompletionOutcome>.value(
      DirectReactionInboxCustodyCompletionOutcome.stale,
    );
  }
  return dbWriteTransaction(db, (txn) async {
    final rows = await txn.query(
      _table,
      columns: const <String>['wire_envelope'],
      where: 'recipient_peer_id = ? AND event_id = ?',
      whereArgs: <Object?>[recipientPeerId, eventId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return DirectReactionInboxCustodyCompletionOutcome.absent;
    }
    if (rows.single['wire_envelope'] != expectedWireEnvelope) {
      return DirectReactionInboxCustodyCompletionOutcome.stale;
    }
    final deleted = await txn.delete(
      _table,
      where: 'recipient_peer_id = ? AND event_id = ? AND wire_envelope = ?',
      whereArgs: <Object?>[recipientPeerId, eventId, expectedWireEnvelope],
    );
    if (deleted != 1) {
      throw StateError(
        'direct reaction custody completion lost its exact event',
      );
    }
    return DirectReactionInboxCustodyCompletionOutcome.completed;
  });
}

/// Transfers one exact edit/deletion event to protected relay custody and, if
/// its bytes still belong to exactly one current parent, projects that parent
/// to visible `inboxed` state in the same transaction that retires the event.
Future<DirectMutationInboxCustodyCompletionOutcome>
dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
  Database db, {
  required String recipientPeerId,
  required String eventId,
  required String expectedWireEnvelope,
  required int? relayExpiresAt,
}) {
  final classified = classifyDirectInboxEventEnvelope(expectedWireEnvelope);
  if (!_isNonBlank(recipientPeerId) ||
      !_isNonBlank(eventId) ||
      classified == null ||
      !classified.isMutation ||
      classified.eventId != eventId ||
      relayExpiresAt == null ||
      relayExpiresAt <= 0) {
    return Future<DirectMutationInboxCustodyCompletionOutcome>.value(
      DirectMutationInboxCustodyCompletionOutcome.stale,
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final custodyRows = await txn.query(
      _table,
      where: 'recipient_peer_id = ? AND event_id = ?',
      whereArgs: <Object?>[recipientPeerId, eventId],
      limit: 1,
    );
    if (custodyRows.isEmpty) {
      return DirectMutationInboxCustodyCompletionOutcome.absent;
    }
    if (custodyRows.single['wire_envelope'] != expectedWireEnvelope) {
      return DirectMutationInboxCustodyCompletionOutcome.stale;
    }

    // 361: a fanout sibling resolves its parent through the persisted logical
    // facts, never through witness-ciphertext equality, and only its FINAL
    // surviving sibling may project — and only while the parent's generation
    // still equals this exact event. A superseded sibling retires alone.
    final fanoutContact =
        custodyRows.single['contact_account_peer_id'] as String?;
    final fanoutParentId = custodyRows.single['parent_message_id'] as String?;
    if (fanoutContact != null) {
      final siblingCountRows = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM $_table WHERE event_id = ?',
        <Object?>[eventId],
      );
      final isFinalSurvivingSibling =
          ((siblingCountRows.single['count'] as num?)?.toInt() ?? 0) == 1;
      if (fanoutParentId != null && isFinalSurvivingSibling) {
        final parents = await txn.query(
          'messages',
          where: 'id = ? AND contact_peer_id = ? AND is_incoming = 0',
          whereArgs: <Object?>[fanoutParentId, fanoutContact],
          limit: 1,
        );
        if (parents.length == 1 &&
            parents.single['direct_event_fanout_generation_id'] == eventId &&
            parents.single['hidden_at'] == null) {
          final parent = parents.single;
          final status = parent['status'];
          final projectable = const <String>{
            'sending',
            'sent',
            'failed',
            'inboxed',
          }.contains(status);
          final alreadyProjected =
              status == 'inboxed' &&
              parent['transport'] == 'inbox' &&
              parent['relay_expires_at'] == relayExpiresAt;
          if (projectable && !alreadyProjected) {
            final changed = await txn.update(
              'messages',
              <String, Object?>{
                'status': 'inboxed',
                'transport': 'inbox',
                'relay_expires_at': relayExpiresAt,
                'custody_checked_at': null,
              },
              where:
                  'id = ? AND contact_peer_id = ? AND is_incoming = 0 '
                  'AND status = ?',
              whereArgs: <Object?>[fanoutParentId, fanoutContact, status],
            );
            if (changed != 1) {
              throw StateError(
                'direct mutation fanout completion lost its exact parent',
              );
            }
          }
        }
      }
      final deleted = await txn.delete(
        _table,
        where: 'recipient_peer_id = ? AND event_id = ? AND wire_envelope = ?',
        whereArgs: <Object?>[recipientPeerId, eventId, expectedWireEnvelope],
      );
      if (deleted != 1) {
        throw StateError(
          'direct mutation custody completion lost its exact event',
        );
      }
      return DirectMutationInboxCustodyCompletionOutcome.completed;
    }

    final editTarget = classified.kind == DirectInboxEventEnvelopeKind.edit
        ? classified.targetMessageId
        : null;
    final parents = await txn.query(
      'messages',
      where:
          'contact_peer_id = ? AND is_incoming = 0 AND wire_envelope = ?'
          '${editTarget == null ? '' : ' AND id = ?'}',
      whereArgs: <Object?>[recipientPeerId, expectedWireEnvelope, ?editTarget],
      limit: 2,
    );
    if (parents.length > 1) {
      return DirectMutationInboxCustodyCompletionOutcome.ambiguous;
    }

    if (parents case [final parent]) {
      final status = parent['status'];
      final isDeletion =
          classified.kind == DirectInboxEventEnvelopeKind.deletion;
      // 356: a v1 Protected/View-Once tombstone is admitted for the DELETION
      // branch only. Private EDIT, disappearing and every non-deletion private
      // transition keep their existing refusal, and a hidden private parent
      // stays valid because local hide is not a settlement conflict.
      final isPrivateDeletionParent =
          isDeletion && _isExactOutgoingPrivateDeletionParent(parent);
      final validParent =
          (_isStrictOrdinaryTextPolicy(parent) || isPrivateDeletionParent) &&
          const <String>{
            'sending',
            'sent',
            'failed',
            'inboxed',
          }.contains(status) &&
          (isDeletion
              ? (isPrivateDeletionParent ||
                    _isExactOutgoingDeletionProjection(parent))
              : parent['deleted_at'] == null &&
                    parent['deleted_by_peer_id'] == null &&
                    parent['hidden_at'] == null &&
                    _isNonBlank(parent['edited_at']));
      if (!validParent) {
        return DirectMutationInboxCustodyCompletionOutcome.stale;
      }
      // Settlement is deliberately attachment-independent for BOTH mutation
      // kinds. Exact v109 staging already proved the owner at authorization
      // time, so acceptance must never inspect or require blob state: a
      // caption EDIT keeps its immutable generation, a deletion may have had
      // its rows cleaned up, and either way this transaction only retires the
      // one exact event and settles the parent that still projects it.
      final alreadyProjected =
          status == 'inboxed' &&
          parent['transport'] == 'inbox' &&
          parent['relay_expires_at'] == relayExpiresAt;
      if (!alreadyProjected) {
        final changed = await txn.update(
          'messages',
          <String, Object?>{
            'status': 'inboxed',
            'transport': 'inbox',
            'relay_expires_at': relayExpiresAt,
            'custody_checked_at': null,
          },
          where:
              'id = ? AND contact_peer_id = ? AND is_incoming = 0 '
              'AND status = ? AND wire_envelope = ?',
          whereArgs: <Object?>[
            parent['id'],
            recipientPeerId,
            status,
            expectedWireEnvelope,
          ],
        );
        if (changed != 1) {
          throw StateError(
            'direct mutation custody completion lost its exact parent',
          );
        }
      }
    }

    final deleted = await txn.delete(
      _table,
      where: 'recipient_peer_id = ? AND event_id = ? AND wire_envelope = ?',
      whereArgs: <Object?>[recipientPeerId, eventId, expectedWireEnvelope],
    );
    if (deleted != 1) {
      throw StateError(
        'direct mutation custody completion lost its exact event',
      );
    }
    return DirectMutationInboxCustodyCompletionOutcome.completed;
  });
}

bool _canonicalTransitionMatches(
  Map<String, Object?> current,
  Map<String, Object?> incoming, {
  required String action,
}) =>
    current['id'] == incoming['id'] &&
    current['message_id'] == incoming['message_id'] &&
    current['emoji'] == incoming['emoji'] &&
    current['sender_peer_id'] == incoming['sender_peer_id'] &&
    current['timestamp'] == incoming['timestamp'] &&
    current['created_at'] == incoming['created_at'] &&
    (action == 'remove'
        ? current['removed_at'] == incoming['timestamp']
        : current['removed_at'] == null);

bool _isExactV2DirectReactionEnvelope(
  String wireEnvelope, {
  required String eventId,
  required String action,
  required String targetMessageId,
  required String senderPeerId,
}) {
  final classified = classifyDirectInboxEventEnvelope(wireEnvelope);
  return classified?.kind == DirectInboxEventEnvelopeKind.reaction &&
      classified?.eventId == eventId &&
      classified?.reactionAction == action &&
      classified?.targetMessageId == targetMessageId &&
      classified?.senderPeerId == senderPeerId;
}

/// The ordinary outgoing direct policy shared by the text and media v109
/// deletion owners. Media parents satisfy it once v108 staging has consumed
/// their v110 intent; only policy/lifecycle columns are inspected here.
bool isStrictOrdinaryOutgoingDirectPolicy(Map<String, Object?> row) =>
    _isStrictOrdinaryTextPolicy(row);

/// 359: the exact outgoing v1 `disappearing` policy a Plan 358 lineage owner
/// may carry into delete-for-everyone.
///
/// Deliberately as narrow as the Plan 358 stamping predicate it mirrors: a v1
/// disappearing row with one allowed duration, lifecycle `available`, NO
/// receiver-local clock (this is the SENDER) and its v110 token already
/// consumed. Protected/View-Once keep the Plan 356 private owner, and a
/// crossed duration, terminal state or sender-side clock is never this owner.
bool isStrictDisappearingOutgoingDirectPolicy(Map<String, Object?> row) {
  final durationSeconds = row['private_media_duration_seconds'];
  return ((row['is_incoming'] as num?)?.toInt() ?? 0) == 0 &&
      // A disappearing INITIAL carries no caption, and Plan 359 gives private
      // EDIT no custody at all, so a caption or edit predecessor is lineage
      // this modality could never have authored. Its own deletion tombstone
      // keeps text empty and never stamps `edited_at`, so both sides of the
      // stage and the persisted completion row satisfy this identically.
      (row['text'] as String? ?? '').isEmpty &&
      row['edited_at'] == null &&
      (row['private_media_policy_version'] as num?)?.toInt() == 1 &&
      row['private_media_mode'] == PrivateMediaMode.disappearing.wireValue &&
      durationSeconds is num &&
      PrivateMediaPolicy.allowedDurationsSeconds.contains(
        durationSeconds.toInt(),
      ) &&
      row['private_media_state'] ==
          PrivateMediaLifecycleState.available.wireValue &&
      row['private_media_received_at_ms'] == null &&
      row['private_media_expires_at_ms'] == null &&
      row['private_media_revealed_at_ms'] == null &&
      row['private_media_terminal_at_ms'] == null &&
      row['private_media_clock_high_water_ms'] == null &&
      row['direct_media_custody_intent_id'] == null;
}

/// The modality columns an expected/staged pair must agree on before the
/// shared media deletion stage may act. A tombstone derived from another
/// parent's policy is a crossed projection, never a downgrade opportunity.
bool sameOutgoingDirectMediaDeletionModality(
  Map<String, Object?> expectedRow,
  Map<String, Object?> stagedRow,
) =>
    expectedRow['private_media_policy_version'] ==
        stagedRow['private_media_policy_version'] &&
    expectedRow['private_media_mode'] == stagedRow['private_media_mode'] &&
    expectedRow['private_media_duration_seconds'] ==
        stagedRow['private_media_duration_seconds'];

/// The exact visible projection every outgoing delete-for-everyone tombstone
/// must carry before it can own a v109 event.
bool isExactOutgoingDirectDeletionProjection(Map<String, Object?> row) =>
    _isExactOutgoingDeletionProjection(row);

bool _isStrictOrdinaryTextPolicy(Map<String, Object?> row) =>
    ((row['is_incoming'] as num?)?.toInt() ?? 0) == 0 &&
    (row['private_media_policy_version'] as num?)?.toInt() == 0 &&
    (row['private_media_mode'] as String? ?? 'ordinary') == 'ordinary' &&
    row['private_media_duration_seconds'] == null &&
    (row['private_media_state'] as String? ?? 'none') == 'none' &&
    row['private_media_received_at_ms'] == null &&
    row['private_media_expires_at_ms'] == null &&
    row['private_media_revealed_at_ms'] == null &&
    row['private_media_terminal_at_ms'] == null &&
    row['private_media_clock_high_water_ms'] == null &&
    row['direct_media_custody_intent_id'] == null;

/// The exact outgoing v1 private deletion tombstone admitted by v109
/// completion: Protected/View-Once (Plan 356) or, since Plan 359, the exact
/// disappearing policy. Hidden state is deliberately allowed for both: a local
/// hide is an independent terminal claim, not a conflicting deletion
/// projection.
bool _isExactOutgoingPrivateDeletionParent(Map<String, Object?> row) =>
    _isExactOutgoingPrivateDeletionProjection(row) &&
    (_isExactOutgoingOneMoreLookDeletionPolicy(row) ||
        isStrictDisappearingOutgoingDirectPolicy(row));

bool _isExactOutgoingPrivateDeletionProjection(Map<String, Object?> row) =>
    ((row['is_incoming'] as num?)?.toInt() ?? 0) == 0 &&
    row['text'] == '' &&
    _isNonBlank(row['deleted_at']) &&
    _isNonBlank(row['deleted_by_peer_id']) &&
    row['deleted_by_peer_id'] == row['sender_peer_id'];

bool _isExactOutgoingOneMoreLookDeletionPolicy(Map<String, Object?> row) =>
    (row['private_media_policy_version'] as num?)?.toInt() == 1 &&
    const <String>{
      'protected',
      'view_once',
    }.contains(row['private_media_mode'] as String?) &&
    row['private_media_duration_seconds'] == null;

bool _isExactOutgoingDeletionProjection(Map<String, Object?> row) =>
    row['text'] == '' &&
    _isNonBlank(row['deleted_at']) &&
    _isNonBlank(row['deleted_by_peer_id']) &&
    row['deleted_by_peer_id'] == row['sender_peer_id'] &&
    row['hidden_at'] == null;

bool _isNonBlank(Object? value) => value is String && value.trim().isNotEmpty;

/// Loads EVERY surviving v109 sibling of one logical event, in stable order.
Future<List<Map<String, Object?>>>
dbLoadDirectReactionInboxCustodyOutboxRowsForEventId(
  DatabaseExecutor db, {
  required String eventId,
}) {
  return db.query(
    _table,
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
    orderBy: 'recipient_peer_id ASC',
  );
}

/// Loads a fair bounded batch of EXACT v113 blob-free fanout event rows only.
Future<List<Map<String, Object?>>>
dbLoadDirectReactionInboxCustodyOutboxExactFanoutRows(
  DatabaseExecutor db, {
  int limit = kDirectReactionInboxCustodyOutboxMaxLoadBatch,
}) {
  if (limit <= 0) return Future<List<Map<String, Object?>>>.value(const []);
  final boundedLimit = math.min(
    limit,
    kDirectReactionInboxCustodyOutboxMaxLoadBatch,
  );
  return db.rawQuery(
    'SELECT * FROM $_table '
    'WHERE contact_account_peer_id IS NOT NULL '
    'ORDER BY last_attempt_at ASC, created_at ASC, '
    'recipient_peer_id ASC, event_id ASC LIMIT ?',
    <Object?>[boundedLimit],
  );
}

/// Loads surviving v109 siblings of [eventId] inside [txn] and verifies the
/// caller's attempt agrees with them byte-for-byte. Returns null on conflict.
Future<List<Map<String, Object?>>?> _consistentEventSurvivors(
  DatabaseExecutor txn, {
  required String eventId,
  required String contactAccountPeerId,
  required String parentMessageId,
  required List<DirectEventFanoutTargetCandidate> candidates,
}) async {
  final survivors = await txn.query(
    _table,
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
    orderBy: 'recipient_peer_id ASC',
  );
  for (final row in survivors) {
    final candidate = candidates
        .where((c) => c.recipientPeerId == row['recipient_peer_id'])
        .firstOrNull;
    if (row['contact_account_peer_id'] != contactAccountPeerId ||
        row['parent_message_id'] != parentMessageId ||
        (candidate != null && candidate.wireEnvelope != row['wire_envelope'])) {
      return null;
    }
  }
  return survivors
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);
}

/// Atomically stages one ordinary text EDIT / Delete-for-Everyone mutation and
/// its COMPLETE all-target v109 sibling batch (Plan 361 / DB v113), replacing
/// the parent's current fanout generation with [eventId].
///
/// Survivor-first: surviving siblings for [eventId] are the complete pending
/// set and win before roster/capacity. With zero survivors, a parent whose
/// generation already equals [eventId] is terminal. A genuinely later
/// generation stages over an older one's survivors; the superseded event can
/// still drain its own exact rows but can never project or be reminted.
Future<DbDirectEventFanoutStageResult>
dbStageOutgoingDirectTextMutationFanoutInboxCustody(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required OutgoingOrdinaryAttemptKind kind,
  required String eventId,
  required String parentMessageId,
  required String contactAccountPeerId,
  required String senderTransportPeerId,
  required DirectContactFanoutSnapshot expectedSnapshot,
  required List<DirectEventFanoutTargetCandidate> candidates,
  int capacity = kDirectReactionInboxCustodyOutboxCapacity,
  Future<void> Function()? beforeSiblingInsertForTest,
}) {
  final createdAt = stagedRow['created_at'];
  final isEdit = kind == OutgoingOrdinaryAttemptKind.edit;
  final isDeletion =
      kind == OutgoingOrdinaryAttemptKind.tombstoneInitial ||
      kind == OutgoingOrdinaryAttemptKind.tombstoneRetry;
  final exactOrdinaryPolicy =
      _isStrictOrdinaryTextPolicy(expectedRow ?? const <String, Object?>{}) &&
      _isStrictOrdinaryTextPolicy(stagedRow);
  final exactPrivateDeletionPolicy =
      isDeletion &&
      expectedRow != null &&
      isExactOutgoingDirectPrivateDeleteTombstoneShape(
        expectedRow: expectedRow,
        tombstoneRow: stagedRow,
      );
  final exactDisappearingDeletionPolicy =
      isDeletion &&
      expectedRow != null &&
      isStrictDisappearingOutgoingDirectPolicy(expectedRow) &&
      isStrictDisappearingOutgoingDirectPolicy(stagedRow) &&
      sameOutgoingDirectMediaDeletionModality(expectedRow, stagedRow);
  bool exactCandidate(DirectEventFanoutTargetCandidate candidate) {
    final classified = classifyDirectInboxEventEnvelope(candidate.wireEnvelope);
    if (classified == null ||
        classified.eventId != eventId ||
        classified.senderPeerId != senderTransportPeerId) {
      return false;
    }
    return isEdit
        ? classified.kind == DirectInboxEventEnvelopeKind.edit &&
              classified.targetMessageId == parentMessageId
        : isDeletion &&
              classified.kind == DirectInboxEventEnvelopeKind.deletion;
  }

  final valid =
      capacity >= 0 &&
      (isEdit || isDeletion) &&
      expectedRow != null &&
      _isNonBlank(eventId) &&
      _isNonBlank(parentMessageId) &&
      _isNonBlank(contactAccountPeerId) &&
      _isNonBlank(senderTransportPeerId) &&
      expectedSnapshot.contactAccountPeerId == contactAccountPeerId &&
      directEventFanoutCandidatesMatchSnapshot(candidates, expectedSnapshot) &&
      stagedRow['id'] == parentMessageId &&
      expectedRow['id'] == parentMessageId &&
      stagedRow['contact_peer_id'] == contactAccountPeerId &&
      expectedRow['contact_peer_id'] == contactAccountPeerId &&
      stagedRow['wire_envelope'] == candidates.first.wireEnvelope &&
      createdAt is String &&
      _isNonBlank(createdAt) &&
      DateTime.tryParse(createdAt) != null &&
      candidates.every(exactCandidate) &&
      (isEdit
          ? exactOrdinaryPolicy
          : exactOrdinaryPolicy ||
                exactPrivateDeletionPolicy ||
                exactDisappearingDeletionPolicy) &&
      (isEdit || _isExactOutgoingDeletionProjection(stagedRow));
  if (!valid) {
    return Future<DbDirectEventFanoutStageResult>.value(
      const DbDirectEventFanoutStageResult.refused(),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final survivors = await _consistentEventSurvivors(
      txn,
      eventId: eventId,
      contactAccountPeerId: contactAccountPeerId,
      parentMessageId: parentMessageId,
      candidates: candidates,
    );
    if (survivors == null) {
      return const DbDirectEventFanoutStageResult.refused();
    }
    if (survivors.isNotEmpty) {
      return DbDirectEventFanoutStageResult(
        outcome: DirectEventFanoutStageOutcome.survivorReplay,
        rows: survivors,
      );
    }

    final parentRows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[parentMessageId],
      limit: 1,
    );
    if (parentRows.isNotEmpty &&
        parentRows.single['direct_event_fanout_generation_id'] == eventId) {
      return const DbDirectEventFanoutStageResult(
        outcome: DirectEventFanoutStageOutcome.terminal,
        rows: <Map<String, Object?>>[],
      );
    }

    final currentSnapshot = await dbReadDirectContactFanoutSnapshot(
      txn,
      contactAccountPeerId: contactAccountPeerId,
    );
    if (currentSnapshot == null ||
        currentSnapshot.targets.isEmpty ||
        !currentSnapshot.sameSnapshotAs(expectedSnapshot)) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table',
    );
    final count = (countRows.single['count'] as num?)?.toInt() ?? 0;
    if (count + candidates.length > capacity) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    // 362: an ORDINARY direct-media parent now fans its caption EDIT and
    // delete-for-everyone through this same blob-free v109 authority — the
    // event batch carries zero blob bytes and performs zero re-encryption.
    // The v109 event itself never uploads; only a DELETION additionally
    // terminalizes the parent's still-unbound v114 target rows below.
    final hasMediaTable = (await txn.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'media_attachments' LIMIT 1",
    )).isNotEmpty;
    var hasDirectMediaParent = false;
    if (hasMediaTable) {
      final directMedia = await txn.rawQuery(
        'SELECT 1 FROM media_attachments '
        'WHERE message_id = ? AND owner_lane = ? LIMIT 1',
        <Object?>[parentMessageId, 'direct'],
      );
      hasDirectMediaParent = directMedia.isNotEmpty;
    }

    // Freeze and validate every v114 row before mutating the parent. Returning
    // `refused` after a tombstone update would otherwise commit a partial
    // transaction when a malformed blob row is encountered.
    var unboundActiveBlobRows = const <DirectMediaBlobCustodyRow>[];
    if (isDeletion && hasDirectMediaParent) {
      final rawBlobRows = await txn.query(
        kDirectMediaBlobCustodyTable,
        where: 'owner_lane = ? AND message_id = ? AND direction = ?',
        whereArgs: <Object?>[
          MediaBlobCustodyOwnerLane.direct.dbValue,
          parentMessageId,
          'outgoing',
        ],
        orderBy: 'attachment_id ASC, recipient_peer_id ASC',
      );
      try {
        unboundActiveBlobRows = rawBlobRows
            .map(DirectMediaBlobCustodyRow.fromMap)
            .where(
              (row) =>
                  row.inboxCustodyIncarnationId == null &&
                  (row.state == DirectMediaBlobCustodyState.outgoingPrepared ||
                      row.state == DirectMediaBlobCustodyState.outgoingStored),
            )
            .toList(growable: false);
      } on FormatException {
        return const DbDirectEventFanoutStageResult.refused();
      }
    }

    // Protected/View-Once uses its incumbent update-only private tombstone
    // commit; ordinary and disappearing continue through the incumbent
    // ordinary mutation CAS. Every private fanout is necessarily media-shaped.
    if ((exactPrivateDeletionPolicy || exactDisappearingDeletionPolicy) &&
        !hasDirectMediaParent) {
      return const DbDirectEventFanoutStageResult.refused();
    }
    final OutgoingOrdinaryMutationOutcome messageOutcome;
    if (exactPrivateDeletionPolicy) {
      final committed =
          await dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstoneWithinTransaction(
            txn,
            expectedRow: expectedRow,
            tombstoneRow: stagedRow,
          );
      messageOutcome = committed
          ? OutgoingOrdinaryMutationOutcome.applied
          : OutgoingOrdinaryMutationOutcome.refused;
    } else {
      messageOutcome = await dbStageOutgoingOrdinaryAttemptWithinTransaction(
        txn,
        expectedRow: expectedRow,
        stagedRow: stagedRow,
        kind: kind,
        allowDirectAttachments: hasDirectMediaParent,
      );
    }
    if (messageOutcome != OutgoingOrdinaryMutationOutcome.applied) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    // A media DELETION terminalizes every still-unbound ACTIVE outgoing v114
    // target row of this parent atomically with the tombstone: it may not
    // retire target A and stage only surviving B. Rows already bound to an
    // exact v108 sibling keep converging through their own drains, and the
    // durable generation marker survives as the no-remint fact.
    if (isDeletion && unboundActiveBlobRows.isNotEmpty) {
      final terminalizedAt = createdAt;
      for (final row in unboundActiveBlobRows) {
        final cleanup = row.copyWith(
          state: DirectMediaBlobCustodyState.outgoingCleanupPending,
          updatedAt: terminalizedAt,
        );
        final changed =
            await dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
              txn,
              expected: row,
              next: cleanup,
            );
        if (!changed) {
          throw StateError(
            'media deletion fanout lost its unbound v114 terminalization',
          );
        }
      }
    }
    // Atomically replace the parent's current generation: the older event is
    // superseded and can never project or remint from now on.
    final markerChanged = await txn.update(
      'messages',
      <String, Object?>{'direct_event_fanout_generation_id': eventId},
      where: 'id = ?',
      whereArgs: <Object?>[parentMessageId],
    );
    if (markerChanged != 1) {
      throw StateError('mutation fanout lost its exact parent generation');
    }

    final stagedRows = <Map<String, Object?>>[];
    for (final candidate in candidates) {
      final siblingRow = <String, Object?>{
        'recipient_peer_id': candidate.recipientPeerId,
        'event_id': eventId,
        'wire_envelope': candidate.wireEnvelope,
        'retry_count': 0,
        'last_attempt_at': null,
        'last_error_code': null,
        'contact_account_peer_id': contactAccountPeerId,
        'parent_message_id': parentMessageId,
        'created_at': createdAt,
        'updated_at': createdAt,
      };
      await beforeSiblingInsertForTest?.call();
      await txn.insert(
        _table,
        siblingRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      stagedRows.add(siblingRow);
    }
    return DbDirectEventFanoutStageResult(
      outcome: DirectEventFanoutStageOutcome.applied,
      rows: stagedRows,
    );
  });
}

/// Atomically applies one canonical direct-reaction ADD/REMOVE transition and
/// stages its COMPLETE all-target v109 sibling batch (Plan 361 / DB v113).
///
/// The canonical reaction row ID is the exact event generation: an exact
/// canonical transition with zero surviving siblings is terminal, an OLDER
/// event stages zero rows against a newer canonical row, and a hidden or
/// deleted parent refuses new staging entirely.
Future<DbDirectEventFanoutStageResult>
dbStageOutgoingDirectReactionFanoutInboxCustody(
  Database db, {
  required Map<String, Object?> reactionRow,
  required String action,
  required String parentMessageId,
  required String contactAccountPeerId,
  required String senderTransportPeerId,
  required DirectContactFanoutSnapshot expectedSnapshot,
  required List<DirectEventFanoutTargetCandidate> candidates,
  int capacity = kDirectReactionInboxCustodyOutboxCapacity,
  Future<void> Function()? beforeSiblingInsertForTest,
}) {
  final eventId = reactionRow['id'];
  final messageId = reactionRow['message_id'];
  final senderPeerId = reactionRow['sender_peer_id'];
  final timestamp = reactionRow['timestamp'];
  final createdAt = reactionRow['created_at'];
  bool exactCandidate(DirectEventFanoutTargetCandidate candidate) {
    final classified = classifyDirectInboxEventEnvelope(candidate.wireEnvelope);
    return classified?.kind == DirectInboxEventEnvelopeKind.reaction &&
        classified?.eventId == eventId &&
        classified?.reactionAction == action &&
        classified?.targetMessageId == parentMessageId &&
        classified?.senderPeerId == senderTransportPeerId;
  }

  final valid =
      capacity >= 0 &&
      eventId is String &&
      _isNonBlank(eventId) &&
      messageId == parentMessageId &&
      _isNonBlank(parentMessageId) &&
      _isNonBlank(contactAccountPeerId) &&
      _isNonBlank(senderTransportPeerId) &&
      senderPeerId is String &&
      _isNonBlank(senderPeerId) &&
      timestamp is String &&
      _isNonBlank(timestamp) &&
      DateTime.tryParse(timestamp) != null &&
      createdAt is String &&
      _isNonBlank(createdAt) &&
      DateTime.tryParse(createdAt) != null &&
      _isNonBlank(reactionRow['emoji']) &&
      (action == 'add' || action == 'remove') &&
      (action != 'add' || reactionRow['removed_at'] == null) &&
      expectedSnapshot.contactAccountPeerId == contactAccountPeerId &&
      directEventFanoutCandidatesMatchSnapshot(candidates, expectedSnapshot) &&
      candidates.every(exactCandidate);
  if (!valid) {
    return Future<DbDirectEventFanoutStageResult>.value(
      const DbDirectEventFanoutStageResult.refused(),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final survivors = await _consistentEventSurvivors(
      txn,
      eventId: eventId,
      contactAccountPeerId: contactAccountPeerId,
      parentMessageId: parentMessageId,
      candidates: candidates,
    );
    if (survivors == null) {
      return const DbDirectEventFanoutStageResult.refused();
    }
    if (survivors.isNotEmpty) {
      return DbDirectEventFanoutStageResult(
        outcome: DirectEventFanoutStageOutcome.survivorReplay,
        rows: survivors,
      );
    }

    final normalizedReaction = Map<String, Object?>.from(reactionRow);
    normalizedReaction['removed_at'] = action == 'remove' ? timestamp : null;

    final eventRows = await txn.query(
      'message_reactions',
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
      limit: 1,
    );
    if (eventRows.isNotEmpty) {
      final row = eventRows.single;
      // Exact canonical event plus zero surviving rows is terminal — never
      // authority to resolve a new roster and remint the event.
      final exactTransition =
          row['message_id'] == parentMessageId &&
          row['sender_peer_id'] == senderPeerId &&
          _canonicalTransitionMatches(row, normalizedReaction, action: action);
      return exactTransition
          ? const DbDirectEventFanoutStageResult(
              outcome: DirectEventFanoutStageOutcome.terminal,
              rows: <Map<String, Object?>>[],
            )
          : const DbDirectEventFanoutStageResult.refused();
    }

    // New staging requires a live parent in this logical conversation. The
    // fanout owner sweeps or scrubs parents deliberately, so a hidden or
    // deleted parent terminally refuses new reaction generations.
    final parents = await txn.query(
      'messages',
      where: 'id = ? AND contact_peer_id = ?',
      whereArgs: <Object?>[parentMessageId, contactAccountPeerId],
      limit: 1,
    );
    if (parents.isEmpty ||
        parents.single['deleted_at'] != null ||
        parents.single['hidden_at'] != null) {
      return const DbDirectEventFanoutStageResult.refused();
    }
    final groupTargets = await txn.query(
      'group_messages',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[parentMessageId],
      limit: 1,
    );
    if (groupTargets.isNotEmpty) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    // An OLDER event never mutates a newer canonical transition and never
    // stages rows: the newer generation owns the (message, sender) lane.
    final currentRows = await txn.query(
      'message_reactions',
      where: 'message_id = ? AND sender_peer_id = ?',
      whereArgs: <Object?>[parentMessageId, senderPeerId],
      limit: 1,
    );
    final current = currentRows.isEmpty ? null : currentRows.single;
    if (current != null) {
      final currentTimestamp =
          current['removed_at'] as String? ?? current['timestamp'] as String?;
      final currentAt = currentTimestamp == null
          ? null
          : DateTime.tryParse(currentTimestamp);
      if (currentAt != null && DateTime.parse(timestamp).isBefore(currentAt)) {
        return const DbDirectEventFanoutStageResult.refused();
      }
    }

    final currentSnapshot = await dbReadDirectContactFanoutSnapshot(
      txn,
      contactAccountPeerId: contactAccountPeerId,
    );
    if (currentSnapshot == null ||
        currentSnapshot.targets.isEmpty ||
        !currentSnapshot.sameSnapshotAs(expectedSnapshot)) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table',
    );
    final count = (countRows.single['count'] as num?)?.toInt() ?? 0;
    if (count + candidates.length > capacity) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    await txn.insert(
      'message_reactions',
      normalizedReaction,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final stagedRows = <Map<String, Object?>>[];
    for (final candidate in candidates) {
      final siblingRow = <String, Object?>{
        'recipient_peer_id': candidate.recipientPeerId,
        'event_id': eventId,
        'wire_envelope': candidate.wireEnvelope,
        'retry_count': 0,
        'last_attempt_at': null,
        'last_error_code': null,
        'contact_account_peer_id': contactAccountPeerId,
        'parent_message_id': parentMessageId,
        'created_at': createdAt,
        'updated_at': createdAt,
      };
      await beforeSiblingInsertForTest?.call();
      await txn.insert(
        _table,
        siblingRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      stagedRows.add(siblingRow);
    }
    return DbDirectEventFanoutStageResult(
      outcome: DirectEventFanoutStageOutcome.applied,
      rows: stagedRows,
    );
  });
}
