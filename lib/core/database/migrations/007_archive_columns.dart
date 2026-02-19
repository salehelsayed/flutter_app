import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 007: Adds archive columns to the contacts table.
///
/// - `is_archived INTEGER NOT NULL DEFAULT 0` — 0 = active, 1 = archived
/// - `archived_at TEXT` — nullable; ISO-8601 timestamp when archived
///
/// Idempotent: checks PRAGMA table_info before running.
Future<void> runArchiveColumnsMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(contacts)');
  final hasIsArchived = columns.any((col) => col['name'] == 'is_archived');
  if (hasIsArchived) {
    emitFlowEvent(
      layer: 'DB',
      event: 'ARCHIVE_COLUMNS_MIGRATION_ALREADY_DONE',
      details: {'migration': '007_archive_columns'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'ARCHIVE_COLUMNS_MIGRATION_START',
    details: {'migration': '007_archive_columns'},
  );

  try {
    await db.transaction((txn) async {
      await txn.execute(
        'ALTER TABLE contacts ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0',
      );
      await txn.execute(
        'ALTER TABLE contacts ADD COLUMN archived_at TEXT',
      );
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'ARCHIVE_COLUMNS_MIGRATION_SUCCESS',
      details: {'migration': '007_archive_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'ARCHIVE_COLUMNS_MIGRATION_ERROR',
      details: {'migration': '007_archive_columns', 'error': e.toString()},
    );
    rethrow;
  }
}
