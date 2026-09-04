import 'package:sqflite_sqlcipher/sqflite.dart';

import '../migrations/117_call_history.dart';

Future<void> insertCallHistoryTerminal(
  Database database,
  Map<String, Object?> row,
) async {
  await database.insert(
    kCallHistoryTable,
    row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

Future<Map<String, Object?>?> loadCallHistoryById(
  Database database,
  String callId,
) async {
  final rows = await database.query(
    kCallHistoryTable,
    where: 'call_id = ?',
    whereArgs: <Object?>[callId],
    limit: 1,
  );
  return rows.isEmpty ? null : Map<String, Object?>.of(rows.single);
}

Future<List<Map<String, Object?>>> loadCallHistoryForContact(
  Database database,
  String contactAccountPeerId,
) async => (await database.query(
  kCallHistoryTable,
  where: 'contact_account_peer_id = ?',
  whereArgs: <Object?>[contactAccountPeerId],
  orderBy: 'started_at DESC, call_id ASC',
)).map(Map<String, Object?>.of).toList(growable: false);
