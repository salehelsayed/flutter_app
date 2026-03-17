import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsPassEncryptedSnapshotsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_PASS_ENCRYPTED_SNAPSHOTS_MIGRATION_START',
    details: {'migration': '036_posts_pass_encrypted_snapshots'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(post_passes)');
    final hasInnerPayloadJson = columns.any(
      (column) => column['name'] == 'inner_payload_json',
    );
    if (!hasInnerPayloadJson) {
      await db.execute(
        'ALTER TABLE post_passes ADD COLUMN inner_payload_json TEXT',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_PASS_ENCRYPTED_SNAPSHOTS_MIGRATION_SUCCESS',
      details: {'migration': '036_posts_pass_encrypted_snapshots'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_PASS_ENCRYPTED_SNAPSHOTS_MIGRATION_ERROR',
      details: {
        'migration': '036_posts_pass_encrypted_snapshots',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
