// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration 126 (Thoughts metrics switch, build 129).
///
/// `posts.metrics_opt_out` marks an own Thought created, or still undelivered,
/// while the Settings switch was off; its post_create envelope then carries
/// `thoughts_metrics_opt_out: true`. Default 0: existing rows keep today's
/// envelope.
Future<void> runThoughtsMetricsOptOutMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(posts)');
  if (!columns.any((column) => column['name'] == 'metrics_opt_out')) {
    await db.execute(
      'ALTER TABLE posts ADD COLUMN metrics_opt_out INTEGER NOT NULL DEFAULT 0 '
      'CHECK (metrics_opt_out IN (0, 1))',
    );
  }
}
