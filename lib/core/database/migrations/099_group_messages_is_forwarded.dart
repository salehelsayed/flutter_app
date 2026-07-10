// ignore_for_file: file_names

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration 099 (236): durable group-message forwarding marker.
Future<void> runGroupMessagesIsForwardedMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_IS_FORWARDED_MIGRATION_START',
    details: {'migration': '099_group_messages_is_forwarded'},
  );
  try {
    final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
    final names = columns.map((row) => row['name'] as String).toSet();
    if (!names.contains('is_forwarded')) {
      await db.execute(
        'ALTER TABLE group_messages ADD COLUMN is_forwarded INTEGER NOT NULL '
        'DEFAULT 0 CHECK (is_forwarded IN (0,1))',
      );
    }
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_IS_FORWARDED_MIGRATION_SUCCESS',
      details: {'migration': '099_group_messages_is_forwarded'},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_IS_FORWARDED_MIGRATION_ERROR',
      details: {
        'migration': '099_group_messages_is_forwarded',
        'error': error.toString(),
      },
    );
    rethrow;
  }
}
