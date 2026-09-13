// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Preserve transport alert intent through staging, commit and process death.
/// Existing messages keep their current notification/read/delivery semantics.
Future<void> runQuietMessageRecoveryMigration(Database database) async {
  for (final table in ['inbox_staging_entries', 'messages']) {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((column) => column['name'] == 'quiet_recovery')) {
      await database.execute(
        'ALTER TABLE $table ADD COLUMN quiet_recovery INTEGER NOT NULL '
        'DEFAULT 0 CHECK (quiet_recovery IN (0, 1))',
      );
    }
  }
}
