import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 041: Add reliability columns to `group_messages` table.
///
/// Three new columns:
/// - `wire_envelope TEXT` — cached plaintext publish parameters for retry.
/// - `inbox_stored INTEGER NOT NULL DEFAULT 0` — whether relay inbox store succeeded.
/// - `inbox_retry_payload TEXT` — cached inbox-store parameters for retry.
///
/// Each ALTER TABLE is guarded by PRAGMA table_info check (idempotent).
Future<void> runGroupMessageReliabilityColumnsMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
  final columnNames = columns.map((col) => col['name'] as String).toSet();

  final hasWireEnvelope = columnNames.contains('wire_envelope');
  final hasInboxStored = columnNames.contains('inbox_stored');
  final hasInboxRetryPayload = columnNames.contains('inbox_retry_payload');

  if (hasWireEnvelope && hasInboxStored && hasInboxRetryPayload) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MSG_RELIABILITY_MIGRATION_ALREADY_DONE',
      details: {'migration': '041_group_message_reliability_columns'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MSG_RELIABILITY_MIGRATION_START',
    details: {'migration': '041_group_message_reliability_columns'},
  );

  try {
    if (!hasWireEnvelope) {
      await db.execute(
        'ALTER TABLE group_messages ADD COLUMN wire_envelope TEXT',
      );
    }

    if (!hasInboxStored) {
      await db.execute(
        'ALTER TABLE group_messages ADD COLUMN inbox_stored INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (!hasInboxRetryPayload) {
      await db.execute(
        'ALTER TABLE group_messages ADD COLUMN inbox_retry_payload TEXT',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MSG_RELIABILITY_MIGRATION_SUCCESS',
      details: {'migration': '041_group_message_reliability_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MSG_RELIABILITY_MIGRATION_ERROR',
      details: {
        'migration': '041_group_message_reliability_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
