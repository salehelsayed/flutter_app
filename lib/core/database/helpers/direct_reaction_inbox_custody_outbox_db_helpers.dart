import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';
import '../direct_reaction_inbox_custody_outbox_contract.dart';

const String _table = 'direct_reaction_inbox_custody_outbox';

const int kDirectReactionInboxCustodyOutboxCapacity = 512;
const int kDirectReactionInboxCustodyOutboxMaxLoadBatch = 50;

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
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) return false;
    final encrypted = decoded['encrypted'];
    return decoded['type'] == 'message_reaction' &&
        decoded['version'] == '2' &&
        decoded['eventId'] == eventId &&
        decoded['action'] == action &&
        decoded['targetMessageId'] == targetMessageId &&
        decoded['senderPeerId'] == senderPeerId &&
        encrypted is Map<String, dynamic> &&
        _isNonBlank(encrypted['kem']) &&
        _isNonBlank(encrypted['ciphertext']) &&
        _isNonBlank(encrypted['nonce']);
  } catch (_) {
    return false;
  }
}

bool _isNonBlank(Object? value) => value is String && value.trim().isNotEmpty;
