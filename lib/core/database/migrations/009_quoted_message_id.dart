import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 009: Adds `quoted_message_id` column to the messages table
/// for quote-reply support.
///
/// - `quoted_message_id TEXT` — nullable; NULL means no quote, otherwise
///   the UUID of the message being quoted.
///
/// Idempotent: checks PRAGMA table_info before running.
Future<void> runQuotedMessageIdMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(messages)');
  final hasColumn =
      columns.any((col) => col['name'] == 'quoted_message_id');
  if (hasColumn) {
    emitFlowEvent(
      layer: 'DB',
      event: 'QUOTED_MESSAGE_ID_MIGRATION_ALREADY_DONE',
      details: {'migration': '009_quoted_message_id'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'QUOTED_MESSAGE_ID_MIGRATION_START',
    details: {'migration': '009_quoted_message_id'},
  );

  try {
    await db.execute(
      'ALTER TABLE messages ADD COLUMN quoted_message_id TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'QUOTED_MESSAGE_ID_MIGRATION_SUCCESS',
      details: {'migration': '009_quoted_message_id'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'QUOTED_MESSAGE_ID_MIGRATION_ERROR',
      details: {'migration': '009_quoted_message_id', 'error': e.toString()},
    );
    rethrow;
  }
}
