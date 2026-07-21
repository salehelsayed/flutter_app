import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';

const _table = 'group_exit_diagnostics';
const _historyLimit = 20;

/// Atomically appends all facts for one processor outcome and prunes history.
///
/// SQL constraints are deliberately the final validation boundary. If any
/// row is invalid, the transaction rolls the complete batch back and pruning
/// does not run.
Future<void> dbAppendGroupExitDiagnosticOutcome(
  Database db,
  List<Map<String, Object?>> rows,
) async {
  if (rows.isEmpty) {
    throw ArgumentError.value(rows, 'rows', 'must contain at least one fact');
  }

  await _runLinearizedWrite(db, (transaction) async {
    for (final row in rows) {
      await transaction.insert(
        _table,
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
    await transaction.rawDelete('''
DELETE FROM $_table
WHERE id NOT IN (
  SELECT id FROM $_table ORDER BY id DESC LIMIT $_historyLimit
)
''');
  });
}

Future<List<Map<String, Object?>>> dbLoadNewestGroupExitDiagnostics(
  DatabaseExecutor db,
) async {
  final rows = await db.query(_table, orderBy: 'id DESC', limit: _historyLimit);
  return rows.map(Map<String, Object?>.from).toList(growable: false);
}

Future<List<Map<String, Object?>>> dbLoadGroupExitDiagnosticsForAction(
  DatabaseExecutor db, {
  required String groupRef,
  required String intentRef,
}) async {
  final rows = await db.query(
    _table,
    where: 'group_ref = ? AND intent_ref = ?',
    whereArgs: [groupRef, intentRef],
    orderBy: 'id DESC',
    limit: _historyLimit,
  );
  return rows.map(Map<String, Object?>.from).toList(growable: false);
}

/// Removes diagnostic history without creating or resetting sqlite_sequence.
Future<void> dbClearGroupExitDiagnostics(Database db) async {
  await _runLinearizedWrite(db, (transaction) => transaction.delete(_table));
}

/// Separate SQLite handles can race at `BEGIN IMMEDIATE/EXCLUSIVE`. sqflite
/// may surface SQLITE_BUSY/SQLITE_LOCKED after its native wait instead of
/// queueing that begin behind the winner, so retry only those two result
/// classes. Constraint and shape failures are never retried.
Future<T> _runLinearizedWrite<T>(
  Database db,
  Future<T> Function(Transaction transaction) body,
) async {
  const maxAttempts = 4;
  for (var attempt = 0; ; attempt++) {
    try {
      return await dbWriteTransaction(db, body, exclusive: true);
    } on DatabaseException catch (error) {
      final primaryResultCode = (error.getResultCode() ?? -1) & 0xff;
      final isConcurrentWriter =
          primaryResultCode == 5 || primaryResultCode == 6;
      if (!isConcurrentWriter || attempt + 1 >= maxAttempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 8 << attempt));
    }
  }
}
