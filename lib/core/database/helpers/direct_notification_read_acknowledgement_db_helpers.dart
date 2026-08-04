import 'package:sqflite_sqlcipher/sqflite.dart';

const String directNotificationReadAcknowledgementsTable =
    'direct_notification_read_acknowledgements';
const int maxPendingDirectNotificationReadAcknowledgements = 512;

Future<bool> dbHasDirectNotificationReadAcknowledgementsTable(
  DatabaseExecutor db,
) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const <Object?>[directNotificationReadAcknowledgementsTable],
  );
  return rows.isNotEmpty;
}

/// Records exact peer-scoped read custody, including enough typed identity to
/// clean or absorb a reaction fact without consulting `message_reactions`.
Future<bool> dbRecordDirectNotificationReadAcknowledgement(
  DatabaseExecutor db, {
  required String peerId,
  required String contentKind,
  required String eventIdentity,
  required String messageId,
  required String? actorPeerId,
  required String generation,
  required String acknowledgedAt,
}) async {
  final values = _validatedTuple(
    peerId: peerId,
    contentKind: contentKind,
    eventIdentity: eventIdentity,
    messageId: messageId,
    actorPeerId: actorPeerId,
    generation: generation,
    acknowledgedAt: acknowledgedAt,
  );
  if (!await dbHasDirectNotificationReadAcknowledgementsTable(db)) {
    return false;
  }

  final existing = await db.query(
    directNotificationReadAcknowledgementsTable,
    columns: const <String>['generation'],
    where:
        'peer_id = ? AND content_kind = ? AND event_identity = ? '
        'AND generation = ?',
    whereArgs: <Object?>[
      values['peer_id'],
      values['content_kind'],
      values['event_identity'],
      values['generation'],
    ],
    limit: 1,
  );
  if (existing.isEmpty) {
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $directNotificationReadAcknowledgementsTable',
          ),
        ) ??
        0;
    if (count >= maxPendingDirectNotificationReadAcknowledgements) {
      throw StateError(
        'direct notification read acknowledgement capacity exhausted',
      );
    }
  }

  await db.insert(
    directNotificationReadAcknowledgementsTable,
    values,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  return true;
}

Future<Map<String, Object?>?> dbLoadExactDirectNotificationReadAcknowledgement(
  DatabaseExecutor db, {
  required String peerId,
  required String contentKind,
  required String eventIdentity,
  String? generation,
}) async {
  final normalizedPeerId = _requiredIdentifier(peerId, 'peerId');
  final normalizedKind = _contentKind(contentKind);
  final normalizedIdentity = _requiredIdentifier(
    eventIdentity,
    'eventIdentity',
    bounded: false,
  );
  final normalizedGeneration = generation == null
      ? null
      : _requiredIdentifier(generation, 'generation');
  if (!await dbHasDirectNotificationReadAcknowledgementsTable(db)) return null;
  final rows = await db.query(
    directNotificationReadAcknowledgementsTable,
    where:
        'peer_id = ? AND content_kind = ? AND event_identity = ?'
        '${normalizedGeneration == null ? '' : ' AND generation = ?'}',
    whereArgs: <Object?>[
      normalizedPeerId,
      normalizedKind,
      normalizedIdentity,
      ?normalizedGeneration,
    ],
    orderBy: 'acknowledged_at DESC, generation DESC',
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<int> dbConsumeExactDirectNotificationReadAcknowledgement(
  DatabaseExecutor db, {
  required String peerId,
  required String contentKind,
  required String eventIdentity,
}) async {
  final normalizedPeerId = _requiredIdentifier(peerId, 'peerId');
  final normalizedKind = _contentKind(contentKind);
  final normalizedIdentity = _requiredIdentifier(
    eventIdentity,
    'eventIdentity',
    bounded: false,
  );
  if (!await dbHasDirectNotificationReadAcknowledgementsTable(db)) return 0;
  return db.delete(
    directNotificationReadAcknowledgementsTable,
    where: 'peer_id = ? AND content_kind = ? AND event_identity = ?',
    whereArgs: <Object?>[normalizedPeerId, normalizedKind, normalizedIdentity],
  );
}

Future<int> dbDeleteDirectNotificationReadAcknowledgementsForPeer(
  DatabaseExecutor db,
  String peerId,
) async {
  final normalized = _requiredIdentifier(peerId, 'peerId');
  if (!await dbHasDirectNotificationReadAcknowledgementsTable(db)) return 0;
  return db.delete(
    directNotificationReadAcknowledgementsTable,
    where: 'peer_id = ?',
    whereArgs: <Object?>[normalized],
  );
}

Map<String, Object?> _validatedTuple({
  required String peerId,
  required String contentKind,
  required String eventIdentity,
  required String messageId,
  required String? actorPeerId,
  required String generation,
  required String acknowledgedAt,
}) {
  final kind = _contentKind(contentKind);
  final identity = _requiredIdentifier(
    eventIdentity,
    'eventIdentity',
    bounded: false,
  );
  final normalizedMessageId = _requiredIdentifier(
    messageId,
    'messageId',
    bounded: false,
  );
  final normalizedActor = actorPeerId?.trim();
  if (kind == 'message') {
    if (identity != normalizedMessageId || normalizedActor != null) {
      throw ArgumentError(
        'message acknowledgement requires eventIdentity == messageId and no actor',
      );
    }
  } else if (normalizedActor == null || normalizedActor.isEmpty) {
    throw ArgumentError.value(
      actorPeerId,
      'actorPeerId',
      'reaction acknowledgement requires an actor',
    );
  }
  final acknowledged = _requiredIdentifier(acknowledgedAt, 'acknowledgedAt');
  if (DateTime.tryParse(acknowledged) == null) {
    throw ArgumentError.value(
      acknowledgedAt,
      'acknowledgedAt',
      'must be an ISO-8601 timestamp',
    );
  }
  return <String, Object?>{
    'peer_id': _requiredIdentifier(peerId, 'peerId'),
    'content_kind': kind,
    'event_identity': identity,
    'message_id': normalizedMessageId,
    'actor_peer_id': normalizedActor,
    'generation': _requiredIdentifier(generation, 'generation'),
    'acknowledged_at': acknowledged,
  };
}

String _contentKind(String value) {
  final normalized = value.trim();
  if (normalized != 'message' && normalized != 'reaction') {
    throw ArgumentError.value(
      value,
      'contentKind',
      'must be message or reaction',
    );
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
