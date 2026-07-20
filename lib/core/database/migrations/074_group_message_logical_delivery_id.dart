// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 074: Adds a durable sender-generated logical delivery identity
/// to group messages. The column is intentionally nullable and non-unique:
/// session 03 may use it as evidence, but PGC-007 distinct stable-id sends
/// must remain representable as separate rows.
Future<void> runGroupMessageLogicalDeliveryIdMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_START',
    details: {'migration': '074_group_message_logical_delivery_id'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (!columnNames.contains('logical_delivery_id')) {
      await db.execute(
        'ALTER TABLE group_messages ADD COLUMN logical_delivery_id TEXT',
      );
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_messages_logical_delivery
      ON group_messages(group_id, sender_peer_id, logical_delivery_id)
      WHERE logical_delivery_id IS NOT NULL
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_SUCCESS',
      details: {'migration': '074_group_message_logical_delivery_id'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_ERROR',
      details: {
        'migration': '074_group_message_logical_delivery_id',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
