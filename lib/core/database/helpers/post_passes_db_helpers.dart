import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostPass(Database db, Map<String, Object?> row) async {
  final insertRow = Map<String, Object?>.from(row);
  final columns = await db.rawQuery("PRAGMA table_info(post_passes)");
  final hasDeliveryStatus = columns.any(
    (column) => column['name'] == 'delivery_status',
  );
  if (!hasDeliveryStatus) {
    insertRow.remove('delivery_status');
  }
  await db.insert(
    'post_passes',
    insertRow,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadPostPass(Database db, String passId) async {
  final rows = await db.query(
    'post_passes',
    where: 'pass_id = ?',
    whereArgs: <Object?>[passId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<List<Map<String, Object?>>> dbLoadPostPasses(
  Database db,
  String postId,
) async {
  return db.query(
    'post_passes',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'passed_at DESC, pass_id DESC',
  );
}

Future<int> dbCountPostPasses(Database db, String postId) async {
  final rows = await db.rawQuery(
    '''
      SELECT COUNT(*) AS share_count
      FROM post_passes
      WHERE post_id = ?
    ''',
    <Object?>[postId],
  );
  return (rows.first['share_count'] as num?)?.toInt() ?? 0;
}

Future<List<Map<String, Object?>>> dbLoadPostPassCounts(
  Database db,
  List<String> postIds,
) async {
  final placeholders = List<String>.filled(postIds.length, '?').join(', ');
  return db.rawQuery('''
      SELECT post_id, COUNT(*) AS share_count
      FROM post_passes
      WHERE post_id IN ($placeholders)
      GROUP BY post_id
    ''', postIds);
}

Future<List<Map<String, Object?>>> dbLoadRetryableOutgoingPostPasses(
  Database db,
) async {
  final columns = await db.rawQuery("PRAGMA table_info(post_passes)");
  final hasDeliveryStatus = columns.any(
    (column) => column['name'] == 'delivery_status',
  );
  if (!hasDeliveryStatus) {
    return db.query(
      'post_passes',
      where: 'is_incoming = ?',
      whereArgs: const <Object?>[0],
      orderBy: 'passed_at DESC, pass_id DESC',
    );
  }
  return db.query(
    'post_passes',
    where: 'is_incoming = ? AND delivery_status IN (?, ?, ?)',
    whereArgs: const <Object?>[0, 'sending', 'partial', 'failed'],
    orderBy: 'passed_at DESC, pass_id DESC',
  );
}
