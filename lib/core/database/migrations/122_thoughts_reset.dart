// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Plan 407: old Posts data is not part of the first Thoughts release.
///
/// Database open wraps onCreate/onUpgrade in one transaction. Keep the reset
/// inside that transaction, before any post listener or retrier can start.
Future<void> runThoughtsResetMigration(Database db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND (name = 'posts' OR name GLOB 'post_*') "
    "ORDER BY CASE name WHEN 'posts' THEN 2 "
    "WHEN 'post_comments' THEN 1 ELSE 0 END, name",
  );
  for (final row in tables) {
    final name = row['name'] as String;
    await db.delete(name);
  }
}
