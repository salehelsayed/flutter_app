import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertIntroductionOutboxDelivery(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'introduction_outbox_deliveries',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> dbDeleteIntroductionOutboxDelivery(
  Database db,
  String deliveryId,
) {
  return db.delete(
    'introduction_outbox_deliveries',
    where: 'delivery_id = ?',
    whereArgs: [deliveryId],
  );
}

Future<void> dbDeleteIntroductionOutboxDeliveriesForIntroduction(
  Database db,
  String introductionId,
) {
  return db.delete(
    'introduction_outbox_deliveries',
    where: 'introduction_id = ?',
    whereArgs: [introductionId],
  );
}

Future<List<Map<String, Object?>>>
dbLoadIntroductionOutboxDeliveriesForIntroduction(
  Database db,
  String introductionId,
) {
  return db.query(
    'introduction_outbox_deliveries',
    where: 'introduction_id = ?',
    whereArgs: [introductionId],
    orderBy: 'created_at ASC, delivery_id ASC',
  );
}

Future<List<Map<String, Object?>>> dbLoadRetryableIntroductionOutboxDeliveries(
  Database db, {
  required String olderThan,
  int limit = 100,
}) {
  return db.query(
    'introduction_outbox_deliveries',
    where: '''
delivery_status = ?
OR (delivery_status IN (?, ?) AND updated_at <= ?)
OR (delivery_status = ? AND delivery_path = ?)
''',
    whereArgs: ['failed', 'sending', 'sent', olderThan, 'delivered', 'inbox'],
    orderBy: 'created_at ASC, delivery_id ASC',
    limit: limit,
  );
}
