import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 006: Adds `read_at` column to the messages table for
/// unread tracking.
///
/// - `read_at TEXT` — nullable; NULL means unread, ISO-8601 timestamp
///   means the message was read at that time.
/// - Marks all existing incoming messages as read during migration to
///   prevent a false badge flood on upgrade.
/// - Adds composite index for efficient unread count queries.
///
/// Idempotent: checks PRAGMA table_info before running.
Future<void> runReadAtColumnMigration(Database db) async {
  // Idempotency: skip if read_at column already exists
  final columns = await db.rawQuery('PRAGMA table_info(messages)');
  final hasReadAt = columns.any((col) => col['name'] == 'read_at');
  if (hasReadAt) {
    emitFlowEvent(
      layer: 'DB',
      event: 'READ_AT_MIGRATION_ALREADY_DONE',
      details: {'migration': '006_read_at_column'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'READ_AT_MIGRATION_START',
    details: {'migration': '006_read_at_column'},
  );

  try {
    await db.transaction((txn) async {
      // 1. Add nullable read_at column
      await txn.execute('ALTER TABLE messages ADD COLUMN read_at TEXT');

      // 2. Mark all existing incoming messages as read
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.execute(
        'UPDATE messages SET read_at = ? WHERE is_incoming = 1',
        [now],
      );

      // 3. Add composite index for unread count queries
      await txn.execute('''
CREATE INDEX IF NOT EXISTS idx_messages_unread
  ON messages(contact_peer_id, is_incoming, read_at)
''');
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'READ_AT_MIGRATION_SUCCESS',
      details: {'migration': '006_read_at_column'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'READ_AT_MIGRATION_ERROR',
      details: {'migration': '006_read_at_column', 'error': e.toString()},
    );
    rethrow;
  }
}
