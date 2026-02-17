import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 008: Adds block columns to the contacts table.
///
/// - `is_blocked INTEGER NOT NULL DEFAULT 0` — 0 = active, 1 = blocked
/// - `blocked_at TEXT` — nullable; ISO-8601 timestamp when blocked
///
/// Idempotent: checks PRAGMA table_info before running.
Future<void> runBlockColumnsMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(contacts)');
  final hasIsBlocked = columns.any((col) => col['name'] == 'is_blocked');
  if (hasIsBlocked) {
    emitFlowEvent(
      layer: 'DB',
      event: 'BLOCK_COLUMNS_MIGRATION_ALREADY_DONE',
      details: {'migration': '008_block_columns'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'BLOCK_COLUMNS_MIGRATION_START',
    details: {'migration': '008_block_columns'},
  );

  try {
    await db.transaction((txn) async {
      await txn.execute(
        'ALTER TABLE contacts ADD COLUMN is_blocked INTEGER NOT NULL DEFAULT 0',
      );
      await txn.execute(
        'ALTER TABLE contacts ADD COLUMN blocked_at TEXT',
      );
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'BLOCK_COLUMNS_MIGRATION_SUCCESS',
      details: {'migration': '008_block_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'BLOCK_COLUMNS_MIGRATION_ERROR',
      details: {'migration': '008_block_columns', 'error': e.toString()},
    );
    rethrow;
  }
}
