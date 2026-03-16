import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsRetryRecipientContextMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_RETRY_RECIPIENT_CONTEXT_MIGRATION_START',
    details: {'migration': '032_posts_retry_recipient_context'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(post_recipients)');
    final hasNearbyDistanceM = columns.any(
      (column) => column['name'] == 'nearby_distance_m',
    );
    if (hasNearbyDistanceM) {
      emitFlowEvent(
        layer: 'DB',
        event: 'POSTS_RETRY_RECIPIENT_CONTEXT_MIGRATION_ALREADY_DONE',
        details: {'migration': '032_posts_retry_recipient_context'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE post_recipients ADD COLUMN nearby_distance_m INTEGER',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_RETRY_RECIPIENT_CONTEXT_MIGRATION_SUCCESS',
      details: {'migration': '032_posts_retry_recipient_context'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_RETRY_RECIPIENT_CONTEXT_MIGRATION_ERROR',
      details: {'migration': '032_posts_retry_recipient_context', 'error': e.toString()},
    );
    rethrow;
  }
}
