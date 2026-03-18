import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsRepostVisualMetricsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_REPOST_VISUAL_METRICS_MIGRATION_START',
    details: {'migration': '040_posts_repost_visual_metrics'},
  );

  try {
    final passColumns = await db.rawQuery('PRAGMA table_info(post_passes)');
    final hasRecipientCount = passColumns.any(
      (column) => column['name'] == 'recipient_count',
    );
    if (!hasRecipientCount) {
      await db.execute(
        'ALTER TABLE post_passes ADD COLUMN recipient_count INTEGER',
      );
    }

    final projectionColumns = await db.rawQuery(
      'PRAGMA table_info(post_repost_projection_state)',
    );
    final hasSharedToCountBaseline = projectionColumns.any(
      (column) => column['name'] == 'shared_to_count_baseline',
    );
    if (!hasSharedToCountBaseline) {
      await db.execute('''
        ALTER TABLE post_repost_projection_state
        ADD COLUMN shared_to_count_baseline INTEGER NOT NULL DEFAULT 0
        ''');
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_REPOST_VISUAL_METRICS_MIGRATION_SUCCESS',
      details: {'migration': '040_posts_repost_visual_metrics'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_REPOST_VISUAL_METRICS_MIGRATION_ERROR',
      details: {
        'migration': '040_posts_repost_visual_metrics',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
