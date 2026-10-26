import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';

Future<void> dbUpsertPostFollowOnOutboxEventWithRecipients(
  Database db,
  Map<String, Object?> event,
  List<Map<String, Object?>> recipients,
) async {
  await dbWriteTransaction(db, (txn) async {
    final batch = txn.batch();
    batch.insert(
      'post_follow_on_outbox_events',
      event,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (final recipient in recipients) {
      batch.insert(
        'post_follow_on_outbox_recipient_deliveries',
        recipient,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  });
}

Future<void> dbDeletePostFollowOnOutboxEvent(
  Database db,
  String eventId,
) async {
  await dbWriteTransaction(db, (txn) async {
    await txn.delete(
      'post_follow_on_outbox_recipient_deliveries',
      where: 'event_id = ?',
      whereArgs: <Object?>[eventId],
    );
    await txn.delete(
      'post_follow_on_outbox_events',
      where: 'event_id = ?',
      whereArgs: <Object?>[eventId],
    );
  });
}

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
  await dbWriteTransaction(db, (txn) async {
    // A late delivery completion must not recreate rows after retirement.
    final events = await txn.query(
      'post_follow_on_outbox_events',
      columns: ['event_id'],
      where: 'event_id = ?',
      whereArgs: <Object?>[row['event_id']],
      limit: 1,
    );
    if (events.isEmpty) return;
    await txn.insert(
      'post_follow_on_outbox_recipient_deliveries',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  });
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
          AND d.delivery_status NOT IN ('delivered', 'inbox', 'expired')
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
        'event_id IN ($placeholders) AND delivery_status NOT IN (?, ?, ?)',
    whereArgs: <Object?>[
      ...eventIds,
      'delivered',
      'inbox',
      'expired',
    ],
    orderBy: 'created_at ASC, event_id ASC, recipient_peer_id ASC',
  );
}
