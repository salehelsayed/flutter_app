import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';
import 'direct_notification_read_acknowledgement_db_helpers.dart';

const String directNotificationReactionTerminalEventsTable =
    'direct_notification_reaction_terminal_events';

Future<bool> dbHasDirectNotificationReactionTerminalEventsTable(
  DatabaseExecutor db,
) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const <Object?>[directNotificationReactionTerminalEventsTable],
  );
  return rows.isNotEmpty;
}

/// Upserts one current direct reaction generation using explicit direct lane
/// identity. This helper intentionally has no `message_reactions` dependency.
Future<bool> dbUpsertDirectNotificationReactionTerminalEvent(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
  required String actorPeerId,
  required String reactionId,
  required String terminalEventId,
  required String updatedAt,
}) async {
  final values = _validatedTerminalTuple(
    peerId: peerId,
    messageId: messageId,
    actorPeerId: actorPeerId,
    reactionId: reactionId,
    terminalEventId: terminalEventId,
    updatedAt: updatedAt,
  );
  if (!await dbHasDirectNotificationReactionTerminalEventsTable(db)) {
    return false;
  }
  await db.rawInsert(
    '''
    INSERT INTO $directNotificationReactionTerminalEventsTable (
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
      values['peer_id'],
      values['message_id'],
      values['actor_peer_id'],
      values['reaction_id'],
      values['terminal_event_id'],
      values['updated_at'],
    ],
  );
  return true;
}

Future<Map<String, Object?>?> dbLoadDirectNotificationReactionTerminalEvent(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
  required String actorPeerId,
}) async {
  if (!await dbHasDirectNotificationReactionTerminalEventsTable(db)) {
    return null;
  }
  final rows = await db.query(
    directNotificationReactionTerminalEventsTable,
    where: 'peer_id = ? AND message_id = ? AND actor_peer_id = ?',
    whereArgs: <Object?>[
      _requiredIdentifier(peerId, 'peerId'),
      _requiredIdentifier(messageId, 'messageId', bounded: false),
      _requiredIdentifier(actorPeerId, 'actorPeerId'),
    ],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<Map<String, Object?>?>
dbLoadDirectNotificationReactionTerminalEventByIdentity(
  DatabaseExecutor db, {
  required String peerId,
  required String terminalEventId,
}) async {
  if (!await dbHasDirectNotificationReactionTerminalEventsTable(db)) {
    return null;
  }
  final rows = await db.query(
    directNotificationReactionTerminalEventsTable,
    where: 'peer_id = ? AND terminal_event_id = ?',
    whereArgs: <Object?>[
      _requiredIdentifier(peerId, 'peerId'),
      _requiredIdentifier(terminalEventId, 'terminalEventId', bounded: false),
    ],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<bool> dbMarkDirectNotificationReactionTerminalAcknowledgedIfExact(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
  required String actorPeerId,
  required String terminalEventId,
  required String acknowledgedAt,
}) async {
  if (!await dbHasDirectNotificationReactionTerminalEventsTable(db)) {
    return false;
  }
  final normalizedAcknowledgedAt = _timestamp(acknowledgedAt, 'acknowledgedAt');
  final updated = await db.rawUpdate(
    'UPDATE $directNotificationReactionTerminalEventsTable '
    'SET notification_acknowledged_at = ?, updated_at = ? '
    'WHERE peer_id = ? AND message_id = ? AND actor_peer_id = ? '
    'AND terminal_event_id = ?',
    <Object?>[
      normalizedAcknowledgedAt,
      normalizedAcknowledgedAt,
      _requiredIdentifier(peerId, 'peerId'),
      _requiredIdentifier(messageId, 'messageId', bounded: false),
      _requiredIdentifier(actorPeerId, 'actorPeerId'),
      _requiredIdentifier(terminalEventId, 'terminalEventId', bounded: false),
    ],
  );
  return updated == 1;
}

/// Atomically absorbs a typed push-before-inbox reaction acknowledgement into
/// the matching direct terminal fact. A colliding group reaction row is never
/// read or written.
Future<bool>
dbConsumeDirectNotificationReactionAcknowledgementIntoTerminalIfExact(
  Database db, {
  required String peerId,
  required String messageId,
  required String actorPeerId,
  required String terminalEventId,
  required String generation,
}) => dbWriteTransaction(db, (txn) async {
  if (!await dbHasDirectNotificationReactionTerminalEventsTable(txn) ||
      !await dbHasDirectNotificationReadAcknowledgementsTable(txn)) {
    return false;
  }
  final acknowledgements = await txn.query(
    directNotificationReadAcknowledgementsTable,
    where:
        'peer_id = ? AND content_kind = ? AND event_identity = ? '
        'AND message_id = ? AND actor_peer_id = ? AND generation = ?',
    whereArgs: <Object?>[
      _requiredIdentifier(peerId, 'peerId'),
      'reaction',
      _requiredIdentifier(terminalEventId, 'terminalEventId', bounded: false),
      _requiredIdentifier(messageId, 'messageId', bounded: false),
      _requiredIdentifier(actorPeerId, 'actorPeerId'),
      _requiredIdentifier(generation, 'generation'),
    ],
    orderBy: 'acknowledged_at DESC',
    limit: 1,
  );
  if (acknowledgements.isEmpty) return false;
  final acknowledgedAt = acknowledgements.single['acknowledged_at'] as String;
  final updated = await txn.rawUpdate(
    'UPDATE $directNotificationReactionTerminalEventsTable '
    'SET notification_acknowledged_at = ?, updated_at = ? '
    'WHERE peer_id = ? AND message_id = ? AND actor_peer_id = ? '
    'AND terminal_event_id = ?',
    <Object?>[
      acknowledgedAt,
      acknowledgedAt,
      peerId.trim(),
      messageId.trim(),
      actorPeerId.trim(),
      terminalEventId.trim(),
    ],
  );
  if (updated != 1) return false;
  final deleted = await txn.delete(
    directNotificationReadAcknowledgementsTable,
    where:
        'peer_id = ? AND content_kind = ? AND event_identity = ? '
        'AND generation = ?',
    whereArgs: <Object?>[
      peerId.trim(),
      'reaction',
      terminalEventId.trim(),
      generation.trim(),
    ],
  );
  if (deleted != 1) {
    throw StateError('direct reaction acknowledgement consumption CAS failed');
  }
  return true;
}, exclusive: true);

Future<int> dbDeleteDirectNotificationReactionTerminalForActor(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
  required String actorPeerId,
}) async {
  if (!await dbHasDirectNotificationReactionTerminalEventsTable(db)) return 0;
  return db.delete(
    directNotificationReactionTerminalEventsTable,
    where: 'peer_id = ? AND message_id = ? AND actor_peer_id = ?',
    whereArgs: <Object?>[
      _requiredIdentifier(peerId, 'peerId'),
      _requiredIdentifier(messageId, 'messageId', bounded: false),
      _requiredIdentifier(actorPeerId, 'actorPeerId'),
    ],
  );
}

Future<int> dbDeleteDirectNotificationReactionTerminalsForMessage(
  DatabaseExecutor db, {
  required String peerId,
  required String messageId,
}) async {
  if (!await dbHasDirectNotificationReactionTerminalEventsTable(db)) return 0;
  return db.delete(
    directNotificationReactionTerminalEventsTable,
    where: 'peer_id = ? AND message_id = ?',
    whereArgs: <Object?>[
      _requiredIdentifier(peerId, 'peerId'),
      _requiredIdentifier(messageId, 'messageId', bounded: false),
    ],
  );
}

Future<int> dbDeleteDirectNotificationReactionTerminalsForPeer(
  DatabaseExecutor db,
  String peerId,
) async {
  if (!await dbHasDirectNotificationReactionTerminalEventsTable(db)) return 0;
  return db.delete(
    directNotificationReactionTerminalEventsTable,
    where: 'peer_id = ?',
    whereArgs: <Object?>[_requiredIdentifier(peerId, 'peerId')],
  );
}

Map<String, Object?> _validatedTerminalTuple({
  required String peerId,
  required String messageId,
  required String actorPeerId,
  required String reactionId,
  required String terminalEventId,
  required String updatedAt,
}) => <String, Object?>{
  'peer_id': _requiredIdentifier(peerId, 'peerId'),
  'message_id': _requiredIdentifier(messageId, 'messageId', bounded: false),
  'actor_peer_id': _requiredIdentifier(actorPeerId, 'actorPeerId'),
  'reaction_id': _requiredIdentifier(reactionId, 'reactionId', bounded: false),
  'terminal_event_id': _requiredIdentifier(
    terminalEventId,
    'terminalEventId',
    bounded: false,
  ),
  'updated_at': _timestamp(updatedAt, 'updatedAt'),
};

String _timestamp(String value, String name) {
  final normalized = _requiredIdentifier(value, name);
  if (DateTime.tryParse(normalized) == null) {
    throw ArgumentError.value(value, name, 'must be an ISO-8601 timestamp');
  }
  return normalized;
}

String _requiredIdentifier(String value, String name, {bool bounded = true}) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must be non-empty');
  }
  if (bounded && normalized.length > 1024) {
    throw ArgumentError.value(value, name, 'must be at most 1024 characters');
  }
  return normalized;
}
