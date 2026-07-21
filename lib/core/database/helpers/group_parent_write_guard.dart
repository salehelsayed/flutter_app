import 'package:sqflite_sqlcipher/sqflite.dart';

/// Whether this database has the Plan-263 durable self-removal authority.
///
/// Several focused helper tests intentionally build only the child table they
/// exercise. Treat those pre-v102/partial schemas as legacy so this guard can
/// be adopted without forcing unrelated fixtures to create the full group
/// schema. Once `groups.self_removed_at` exists, every ordinary child write is
/// parent-authorized.
Future<bool> dbHasSelfRemovedGroupWriteGuard(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(groups)');
  return columns.any((row) => row['name'] == 'self_removed_at');
}

/// Short, non-authoritative preflight used only to avoid unnecessary work.
/// Mutations must still use one of the atomic guarded helpers below.
Future<bool> dbAllowsOrdinaryGroupWrite(
  DatabaseExecutor db,
  String groupId,
) async {
  if (!await dbHasSelfRemovedGroupWriteGuard(db)) return true;
  final rows = await db.query(
    'groups',
    columns: const ['id'],
    where: 'id = ? AND self_removed_at IS NULL',
    whereArgs: [groupId],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Inserts [row] only while its group parent exists and is unmarked.
///
/// The v102 branch is one `INSERT ... SELECT ... WHERE EXISTS` statement, so a
/// B3 marker commit cannot interleave between the authority check and insert.
/// Returns false for a refused parent or an ignored conflict.
Future<bool> dbInsertOrdinaryGroupOwnedRow(
  DatabaseExecutor db, {
  required String table,
  required Map<String, Object?> row,
  ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
}) async {
  final groupId = row['group_id'] as String? ?? '';
  if (!await dbHasSelfRemovedGroupWriteGuard(db)) {
    final inserted = await db.insert(
      table,
      row,
      conflictAlgorithm: conflictAlgorithm,
    );
    return inserted != 0;
  }
  if (groupId.isEmpty || row.isEmpty) return false;

  final quotedTable = _quoteIdentifier(table);
  final columns = row.keys.map(_quoteIdentifier).join(', ');
  final placeholders = List.filled(row.length, '?').join(', ');
  final conflict = _conflictSql(conflictAlgorithm);
  final inserted = await db.rawInsert(
    'INSERT$conflict INTO $quotedTable ($columns) '
    'SELECT $placeholders '
    'WHERE EXISTS ('
    'SELECT 1 FROM groups parent '
    'WHERE parent.id = ? AND parent.self_removed_at IS NULL'
    ')',
    [...row.values, groupId],
  );
  return inserted != 0;
}

/// Privileged insert for evidence tied to one exact durable removal marker.
/// It deliberately has no legacy fallback: without the marker column there is
/// no authority to cross the ordinary marked-parent write guard.
Future<bool> dbInsertExactMarkedGroupOwnedRow(
  DatabaseExecutor db, {
  required String table,
  required Map<String, Object?> row,
  required String expectedSelfRemovedAt,
  ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
}) async {
  final groupId = row['group_id'] as String? ?? '';
  if (!await dbHasSelfRemovedGroupWriteGuard(db) ||
      groupId.isEmpty ||
      expectedSelfRemovedAt.isEmpty ||
      row.isEmpty) {
    return false;
  }

  final quotedTable = _quoteIdentifier(table);
  final columns = row.keys.map(_quoteIdentifier).join(', ');
  final placeholders = List.filled(row.length, '?').join(', ');
  final conflict = _conflictSql(conflictAlgorithm);
  final inserted = await db.rawInsert(
    'INSERT$conflict INTO $quotedTable ($columns) '
    'SELECT $placeholders '
    'WHERE EXISTS ('
    'SELECT 1 FROM groups parent '
    'WHERE parent.id = ? AND parent.self_removed_at = ?'
    ')',
    [...row.values, groupId, expectedSelfRemovedAt],
  );
  return inserted != 0;
}

/// Updates matching child rows only while [groupId] exists and is unmarked.
/// The parent predicate and update execute as one SQLite statement.
Future<int> dbUpdateOrdinaryGroupOwnedRows(
  DatabaseExecutor db, {
  required String table,
  required String groupId,
  required Map<String, Object?> values,
  required String where,
  required List<Object?> whereArgs,
}) async {
  if (!await dbHasSelfRemovedGroupWriteGuard(db)) {
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }
  if (groupId.isEmpty) return 0;
  final quotedTable = _quoteIdentifier(table);
  return db.update(
    table,
    values,
    where:
        '($where) AND $quotedTable."group_id" = ? AND EXISTS ('
        'SELECT 1 FROM groups parent '
        'WHERE parent.id = $quotedTable."group_id" '
        'AND parent.self_removed_at IS NULL'
        ')',
    whereArgs: [...whereArgs, groupId],
  );
}

/// SQL predicate for ordinary loaders/completions that must hide work owned by
/// absent or marked groups. Returns a tautology on pre-v102 partial schemas.
Future<String> dbOrdinaryGroupParentPredicate(
  DatabaseExecutor db, {
  required String groupIdExpression,
}) async {
  _validateSqlColumnExpression(groupIdExpression);
  if (!await dbHasSelfRemovedGroupWriteGuard(db)) return '1 = 1';
  return 'EXISTS ('
      'SELECT 1 FROM groups parent '
      'WHERE parent.id = $groupIdExpression '
      'AND parent.self_removed_at IS NULL'
      ')';
}

String _quoteIdentifier(String value) {
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'identifier',
      'unsupported SQL identifier',
    );
  }
  return '"$value"';
}

void _validateSqlColumnExpression(String value) {
  if (!RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$',
  ).hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'groupIdExpression',
      'unsupported SQL column expression',
    );
  }
}

String _conflictSql(ConflictAlgorithm algorithm) => switch (algorithm) {
  ConflictAlgorithm.rollback => ' OR ROLLBACK',
  ConflictAlgorithm.abort => ' OR ABORT',
  ConflictAlgorithm.fail => ' OR FAIL',
  ConflictAlgorithm.ignore => ' OR IGNORE',
  ConflictAlgorithm.replace => ' OR REPLACE',
};
