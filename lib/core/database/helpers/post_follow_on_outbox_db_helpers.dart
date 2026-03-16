import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostFollowOnOutboxEvent(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_follow_on_outbox_events',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadPostFollowOnOutboxEvent(
  Database db,
  String eventId,
) async {
  final rows = await db.query(
    'post_follow_on_outbox_events',
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first;
}

Future<void> dbUpsertPostFollowOnOutboxRecipientDelivery(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_follow_on_outbox_recipient_deliveries',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<List<Map<String, Object?>>> dbLoadPostFollowOnOutboxRecipientDeliveries(
  Database db,
  String eventId,
) async {
  return db.query(
    'post_follow_on_outbox_recipient_deliveries',
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
    orderBy: 'recipient_peer_id ASC',
  );
}

Future<List<Map<String, Object?>>> dbLoadRetryablePostFollowOnOutboxEvents(
  Database db,
) async {
  return db.rawQuery(
    '''
      SELECT e.*
      FROM post_follow_on_outbox_events e
      WHERE EXISTS (
        SELECT 1
        FROM post_follow_on_outbox_recipient_deliveries d
        WHERE d.event_id = e.event_id
          AND d.delivery_status NOT IN ('delivered', 'inbox')
      )
      ORDER BY e.created_at ASC, e.event_id ASC
    ''',
  );
}

Future<List<Map<String, Object?>>>
dbLoadRetryablePostFollowOnOutboxRecipientDeliveries(
  Database db,
  List<String> eventIds,
) async {
  if (eventIds.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  final placeholders = List<String>.filled(eventIds.length, '?').join(', ');
  return db.query(
    'post_follow_on_outbox_recipient_deliveries',
    where:
        'event_id IN ($placeholders) AND delivery_status NOT IN (?, ?)',
    whereArgs: <Object?>[
      ...eventIds,
      'delivered',
      'inbox',
    ],
    orderBy: 'created_at ASC, event_id ASC, recipient_peer_id ASC',
  );
}
