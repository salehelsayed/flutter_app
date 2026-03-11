import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 026: Adds `quoted_message_id` to `group_messages`.
///
/// This mirrors the direct-message quote column added in migration 009.
/// NULL means the group message is not a reply.
Future<void> runGroupQuotedMessageIdMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
  final hasColumn = columns.any((col) => col['name'] == 'quoted_message_id');
  if (hasColumn) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_QUOTED_MESSAGE_ID_MIGRATION_ALREADY_DONE',
      details: {'migration': '026_group_quoted_message_id'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_QUOTED_MESSAGE_ID_MIGRATION_START',
    details: {'migration': '026_group_quoted_message_id'},
  );

  try {
    await db.execute(
      'ALTER TABLE group_messages ADD COLUMN quoted_message_id TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_QUOTED_MESSAGE_ID_MIGRATION_SUCCESS',
      details: {'migration': '026_group_quoted_message_id'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_QUOTED_MESSAGE_ID_MIGRATION_ERROR',
      details: {
        'migration': '026_group_quoted_message_id',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
