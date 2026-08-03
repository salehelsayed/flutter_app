import 'package:sqflite_sqlcipher/sqflite.dart';

const String groupNotificationReadAcknowledgementsTable =
    'group_notification_read_acknowledgements';

/// An acknowledgement is tiny and identifier-only, but push-before-inbox
/// events can outlive a process. Refuse unbounded growth instead of evicting a
/// live fact that could otherwise let an already-viewed event reappear.
const int maxPendingGroupNotificationReadAcknowledgements = 512;

Future<bool> dbHasGroupNotificationReadAcknowledgementsTable(
  DatabaseExecutor db,
) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    <Object?>[groupNotificationReadAcknowledgementsTable],
  );
  return rows.isNotEmpty;
}

/// Records the exact managed card visible at a conversation-read boundary.
///
/// All fields are opaque identifiers. Notification copy, payloads, emoji and
/// media paths are intentionally excluded. Returns false for a pre-v106 test or
/// compatibility schema where the additive table is not installed.
Future<bool> dbRecordExactGroupNotificationReadAcknowledgement(
  DatabaseExecutor db, {
  required String groupId,
  required String contentKind,
  required String eventIdentity,
  required String generation,
  required String acknowledgedAt,
}) async {
  final values = _validatedAcknowledgementTuple(
    groupId: groupId,
    contentKind: contentKind,
    eventIdentity: eventIdentity,
    generation: generation,
    acknowledgedAt: acknowledgedAt,
  );
  if (!await dbHasGroupNotificationReadAcknowledgementsTable(db)) {
    return false;
  }

  final existing = await db.query(
    groupNotificationReadAcknowledgementsTable,
    columns: const <String>['generation'],
    where:
        'group_id = ? AND content_kind = ? AND event_identity = ? '
        'AND generation = ?',
    whereArgs: <Object?>[
      values['group_id'],
      values['content_kind'],
      values['event_identity'],
      values['generation'],
    ],
    limit: 1,
  );
  if (existing.isEmpty) {
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM '
      '$groupNotificationReadAcknowledgementsTable',
    );
    final count = Sqflite.firstIntValue(countRows) ?? 0;
    if (count >= maxPendingGroupNotificationReadAcknowledgements) {
      throw StateError(
        'group notification read acknowledgement capacity exhausted',
      );
    }
  }

  await db.insert(
    groupNotificationReadAcknowledgementsTable,
    values,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  return true;
}

/// Loads an acknowledgement for this exact content event. When [generation]
/// is supplied, all four identity fields must match. The generation-less form
/// supports background readers that compare the returned generation with the
/// card snapshot in their own pure decision boundary.
Future<Map<String, Object?>?> dbLoadExactGroupNotificationReadAcknowledgement(
  DatabaseExecutor db, {
  required String groupId,
  required String contentKind,
  required String eventIdentity,
  String? generation,
}) async {
  final normalizedGroupId = _requiredIdentifier(groupId, 'groupId');
  final normalizedContentKind = _contentKind(contentKind);
  final normalizedEventIdentity = _requiredIdentifier(
    eventIdentity,
    'eventIdentity',
    bounded: false,
  );
  final normalizedGeneration = generation == null
      ? null
      : _requiredIdentifier(generation, 'generation');
  if (!await dbHasGroupNotificationReadAcknowledgementsTable(db)) {
    return null;
  }
  final rows = await db.query(
    groupNotificationReadAcknowledgementsTable,
    where:
        'group_id = ? AND content_kind = ? AND event_identity = ?'
        '${normalizedGeneration == null ? '' : ' AND generation = ?'}',
    whereArgs: <Object?>[
      normalizedGroupId,
      normalizedContentKind,
      normalizedEventIdentity,
      ?normalizedGeneration,
    ],
    orderBy: 'acknowledged_at DESC, generation DESC',
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<bool> dbIsExactGroupNotificationEventAcknowledged(
  DatabaseExecutor db, {
  required String groupId,
  required String contentKind,
  required String eventIdentity,
  required String generation,
}) async {
  return await dbLoadExactGroupNotificationReadAcknowledgement(
        db,
        groupId: groupId,
        contentKind: contentKind,
        eventIdentity: eventIdentity,
        generation: generation,
      ) !=
      null;
}

/// Consumes every generation bound to an event once canonical persistence has
/// absorbed the acknowledgement. A later event has a different identity and
/// remains eligible.
Future<int> dbConsumeExactGroupNotificationReadAcknowledgement(
  DatabaseExecutor db, {
  required String groupId,
  required String contentKind,
  required String eventIdentity,
}) async {
  final normalizedGroupId = _requiredIdentifier(groupId, 'groupId');
  final normalizedContentKind = _contentKind(contentKind);
  final normalizedEventIdentity = _requiredIdentifier(
    eventIdentity,
    'eventIdentity',
    bounded: false,
  );
  if (!await dbHasGroupNotificationReadAcknowledgementsTable(db)) return 0;
  return db.delete(
    groupNotificationReadAcknowledgementsTable,
    where: 'group_id = ? AND content_kind = ? AND event_identity = ?',
    whereArgs: <Object?>[
      normalizedGroupId,
      normalizedContentKind,
      normalizedEventIdentity,
    ],
  );
}

Map<String, Object?> _validatedAcknowledgementTuple({
  required String groupId,
  required String contentKind,
  required String eventIdentity,
  required String generation,
  required String acknowledgedAt,
}) {
  final normalizedAcknowledgedAt = _requiredIdentifier(
    acknowledgedAt,
    'acknowledgedAt',
  );
  if (DateTime.tryParse(normalizedAcknowledgedAt) == null) {
    throw ArgumentError.value(
      acknowledgedAt,
      'acknowledgedAt',
      'must be an ISO-8601 timestamp',
    );
  }
  return <String, Object?>{
    'group_id': _requiredIdentifier(groupId, 'groupId'),
    'content_kind': _contentKind(contentKind),
    'event_identity': _requiredIdentifier(
      eventIdentity,
      'eventIdentity',
      bounded: false,
    ),
    'generation': _requiredIdentifier(generation, 'generation'),
    'acknowledged_at': normalizedAcknowledgedAt,
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
  // Message event identities are canonical group-message IDs, whose existing
  // persisted/wire contract has no length ceiling. Row count is still bounded
  // above; rejecting an otherwise accepted message ID here would roll back the
  // whole conversation-read transaction. Reaction identities are bounded
  // before they reach this helper.
  if (bounded && normalized.length > 1024) {
    throw ArgumentError.value(value, name, 'must be at most 1024 characters');
  }
  return normalized;
}
