import 'package:sqflite_sqlcipher/sqflite.dart';

Future<Set<String>> dbLoadIntroReviewSeenKeys(Database db) async {
  final rows = await db.query('intro_review_seen', columns: ['item_key']);
  return rows.map((row) => row['item_key'] as String).toSet();
}

Future<void> dbMarkIntroReviewItemsSeen(
  Database db,
  Set<String> itemKeys,
  DateTime seenAt,
) async {
  if (itemKeys.isEmpty) return;

  final seenAtIso = seenAt.toUtc().toIso8601String();
  final batch = db.batch();
  for (final itemKey in itemKeys) {
    batch.insert('intro_review_seen', {
      'item_key': itemKey,
      'seen_at': seenAtIso,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}
