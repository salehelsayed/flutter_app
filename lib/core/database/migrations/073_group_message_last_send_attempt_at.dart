// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 073: Adds the operational send-attempt timestamp to group messages.
Future<void> runGroupMessageLastSendAttemptAtMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGE_LAST_SEND_ATTEMPT_AT_MIGRATION_START',
    details: {'migration': '073_group_message_last_send_attempt_at'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (columnNames.contains('last_send_attempt_at')) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MESSAGE_LAST_SEND_ATTEMPT_AT_MIGRATION_ALREADY_DONE',
        details: {'migration': '073_group_message_last_send_attempt_at'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE group_messages ADD COLUMN last_send_attempt_at TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_LAST_SEND_ATTEMPT_AT_MIGRATION_SUCCESS',
      details: {'migration': '073_group_message_last_send_attempt_at'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_LAST_SEND_ATTEMPT_AT_MIGRATION_ERROR',
      details: {
        'migration': '073_group_message_last_send_attempt_at',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
