import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 043: Add `edited_at` column to `messages` table.
///
/// Stores the UTC timestamp when a message was last edited. Null means the
/// message still reflects its original send payload.
Future<void> runMessagesEditedAtMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(messages)');
  final hasColumn = columns.any((col) => col['name'] == 'edited_at');
  if (hasColumn) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_EDITED_AT_MIGRATION_ALREADY_DONE',
      details: {'migration': '043_messages_edited_at'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_EDITED_AT_MIGRATION_START',
    details: {'migration': '043_messages_edited_at'},
  );

  try {
    await db.execute('ALTER TABLE messages ADD COLUMN edited_at TEXT');
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_EDITED_AT_MIGRATION_SUCCESS',
      details: {'migration': '043_messages_edited_at'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_EDITED_AT_MIGRATION_ERROR',
      details: {
        'migration': '043_messages_edited_at',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
