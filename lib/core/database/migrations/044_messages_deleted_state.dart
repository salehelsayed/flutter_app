import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 044: Add deleted/tombstone metadata to `messages`.
///
/// - `deleted_at TEXT` — when the message was deleted.
/// - `deleted_by_peer_id TEXT` — who initiated the delete.
/// - `hidden_at TEXT` — sender-side local hide timestamp for durable retries.
Future<void> runMessagesDeletedStateMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(messages)');
  final columnNames = columns
      .map((column) => column['name'] as String)
      .toSet();

  final hasDeletedAt = columnNames.contains('deleted_at');
  final hasDeletedByPeerId = columnNames.contains('deleted_by_peer_id');
  final hasHiddenAt = columnNames.contains('hidden_at');

  if (hasDeletedAt && hasDeletedByPeerId && hasHiddenAt) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DELETED_STATE_MIGRATION_ALREADY_DONE',
      details: {'migration': '044_messages_deleted_state'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DELETED_STATE_MIGRATION_START',
    details: {'migration': '044_messages_deleted_state'},
  );

  try {
    if (!hasDeletedAt) {
      await db.execute('ALTER TABLE messages ADD COLUMN deleted_at TEXT');
    }
    if (!hasDeletedByPeerId) {
      await db.execute(
        'ALTER TABLE messages ADD COLUMN deleted_by_peer_id TEXT',
      );
    }
    if (!hasHiddenAt) {
      await db.execute('ALTER TABLE messages ADD COLUMN hidden_at TEXT');
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DELETED_STATE_MIGRATION_SUCCESS',
      details: {'migration': '044_messages_deleted_state'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DELETED_STATE_MIGRATION_ERROR',
      details: {
        'migration': '044_messages_deleted_state',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
