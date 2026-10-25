import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';

const authoredDirectTextIntentsTable = 'authored_direct_text_intents';

Future<bool> dbSaveAuthoredDirectTextIntent(
  Database db,
  Map<String, Object?> intent,
) => dbWriteTransaction(db, (txn) async {
  if (!await _contactAllowsIntent(txn, intent['contact_peer_id'])) return false;
  final existing = await txn.query(
    authoredDirectTextIntentsTable,
    where: 'id = ?',
    whereArgs: [intent['id']],
  );
  if (existing.isNotEmpty) {
    return intent.entries.every(
      (entry) => existing.single[entry.key] == entry.value,
    );
  }
  final parents = await txn.query(
    'messages',
    columns: ['id'],
    where: 'id = ?',
    whereArgs: [intent['id']],
    limit: 1,
  );
  final count =
      Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM $authoredDirectTextIntentsTable',
        ),
      ) ??
      0;
  if (parents.isNotEmpty || count >= 512) return false;
  await txn.insert(
    authoredDirectTextIntentsTable,
    intent,
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
  return true;
});

Future<List<Map<String, Object?>>> dbLoadAuthoredDirectTextIntents(
  DatabaseExecutor db,
) => db.query(authoredDirectTextIntentsTable, orderBy: 'timestamp ASC, id ASC');

/// Called inside custody's transaction. No intent is consumed on a refusal.
Future<bool> dbMatchesAuthoredDirectTextIntent(
  DatabaseExecutor txn,
  Map<String, Object?> stagedRow,
  String token,
) async {
  final rows = await txn.query(
    authoredDirectTextIntentsTable,
    where: 'id = ? AND token = ?',
    whereArgs: [stagedRow['id'], token],
    limit: 1,
  );
  if (rows.isEmpty ||
      !await _contactAllowsIntent(txn, stagedRow['contact_peer_id'])) {
    return false;
  }
  final row = rows.single;
  return row['contact_peer_id'] == stagedRow['contact_peer_id'] &&
      row['text'] == stagedRow['text'] &&
      row['timestamp'] == stagedRow['timestamp'] &&
      row['timestamp'] == stagedRow['created_at'] &&
      row['quoted_message_id'] == stagedRow['quoted_message_id'];
}

Future<bool> _contactAllowsIntent(DatabaseExecutor txn, Object? peerId) async {
  final contacts = await txn.query(
    'contacts',
    columns: ['peer_id', 'is_blocked'],
    where: 'peer_id = ?',
    whereArgs: [peerId],
    limit: 1,
  );
  return contacts.isNotEmpty && contacts.single['is_blocked'] != 1;
}

/// Legacy test databases may intentionally stop before v123.
Future<int> dbDeleteAuthoredDirectTextIntents(
  DatabaseExecutor txn, {
  String? messageId,
  String? contactPeerId,
}) async {
  final exists = await txn.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    [authoredDirectTextIntentsTable],
  );
  if (exists.isEmpty) return 0;
  assert(messageId != null || contactPeerId != null);
  return txn.delete(
    authoredDirectTextIntentsTable,
    where: messageId != null ? 'id = ?' : 'contact_peer_id = ?',
    whereArgs: [messageId ?? contactPeerId],
  );
}

Future<bool> dbCancelAuthoredDirectTextIntent(
  Database db,
  Map<String, Object?> intent,
) => dbWriteTransaction(
  db,
  (txn) async =>
      await txn.delete(
        authoredDirectTextIntentsTable,
        where: 'id = ? AND token = ? AND contact_peer_id = ?',
        whereArgs: [intent['id'], intent['token'], intent['contact_peer_id']],
      ) ==
      1,
);
