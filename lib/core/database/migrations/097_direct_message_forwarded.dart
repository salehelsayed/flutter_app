// ignore_for_file: file_names

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration 097 (232): durable direct-message forwarding marker.
Future<void> runDirectMessageForwardedMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_MESSAGE_FORWARDED_MIGRATION_START',
    details: {'migration': '097_direct_message_forwarded'},
  );
  try {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final names = columns.map((row) => row['name'] as String).toSet();
    if (!names.contains('is_forwarded')) {
      await db.execute(
        'ALTER TABLE messages ADD COLUMN is_forwarded INTEGER NOT NULL '
        'DEFAULT 0 CHECK (is_forwarded IN (0,1))',
      );
    }
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_MESSAGE_FORWARDED_MIGRATION_SUCCESS',
      details: {'migration': '097_direct_message_forwarded'},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_MESSAGE_FORWARDED_MIGRATION_ERROR',
      details: {
        'migration': '097_direct_message_forwarded',
        'error': error.toString(),
      },
    );
    rethrow;
  }
}
