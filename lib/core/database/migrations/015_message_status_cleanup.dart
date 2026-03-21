import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration 015: normalize legacy outgoing 'queued' rows.
///
/// Product rule is now:
/// - direct ACK success => delivered
/// - inbox store success => delivered
///
/// Older builds stored inbox-accepted outgoing messages as 'queued'.
/// This migration upgrades those rows to 'delivered' and clears any
/// lingering wire_envelope retry payload.
Future<void> runMessageStatusCleanupMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGE_STATUS_CLEANUP_MIGRATION_START',
    details: {'migration': '015_message_status_cleanup'},
  );

  try {
    await db.execute('''
      UPDATE messages
      SET status = 'delivered',
          wire_envelope = NULL
      WHERE is_incoming = 0
        AND status = 'queued'
      ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGE_STATUS_CLEANUP_MIGRATION_SUCCESS',
      details: {'migration': '015_message_status_cleanup'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGE_STATUS_CLEANUP_MIGRATION_ERROR',
      details: {
        'migration': '015_message_status_cleanup',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
