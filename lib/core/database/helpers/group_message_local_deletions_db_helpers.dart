import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertGroupMessageLocalDeletion(
  DatabaseExecutor db, {
  required String messageId,
  required String groupId,
  DateTime? deletedAt,
}) async {
  if (messageId.trim().isEmpty || groupId.trim().isEmpty) return;
  if (!await _hasGroupMessageLocalDeletionsTable(db)) return;

  final now = (deletedAt ?? DateTime.now()).toUtc().toIso8601String();
  await db.insert('group_message_local_deletions', {
    'message_id': messageId,
    'group_id': groupId,
    'deleted_at': now,
    'created_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<Map<String, Object?>?> dbLoadGroupMessageLocalDeletion(
  DatabaseExecutor db,
  String messageId,
) async {
  if (messageId.trim().isEmpty) return null;
  if (!await _hasGroupMessageLocalDeletionsTable(db)) return null;

  final rows = await db.query(
    'group_message_local_deletions',
    where: 'message_id = ?',
    whereArgs: [messageId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<bool> dbIsGroupMessageLocallyDeleted(
  DatabaseExecutor db,
  String messageId,
) async {
  return await dbLoadGroupMessageLocalDeletion(db, messageId) != null;
}

Future<bool> _hasGroupMessageLocalDeletionsTable(DatabaseExecutor db) async {
  try {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['group_message_local_deletions'],
    );
    return rows.isNotEmpty;
  } catch (_) {
    return false;
  }
}
