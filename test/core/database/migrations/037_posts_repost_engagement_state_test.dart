import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/035_posts_repost_delivery_state.dart';
import 'package:flutter_app/core/database/migrations/036_posts_pass_encrypted_snapshots.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsEngagementMigration(db);
    await runPostsNearbyMigration(db);
    await runPostsPassAlongMigration(db);
    await runPostsRepostDeliveryStateMigration(db);
    await runPostsPassEncryptedSnapshotsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'creates repost participant, heart baseline, and projection tables without disturbing rows',
    () async {
      await runPostsRepostEngagementStateMigration(db);
      await db.insert('post_repost_engagement_participants', <String, Object?>{
        'post_id': 'post-1',
        'participant_peer_id': 'peer-hisam',
        'created_at': '2026-03-15T11:15:00.000Z',
      });
      await db.insert('post_repost_heart_baseline_peers', <String, Object?>{
        'post_id': 'post-1',
        'sender_peer_id': 'peer-zoya',
        'created_at': '2026-03-15T11:15:00.000Z',
      });
      await db.insert('post_repost_projection_state', <String, Object?>{
        'post_id': 'post-1',
        'repost_total_baseline': 2,
        'created_at': '2026-03-15T11:15:00.000Z',
      });

      await runPostsRepostEngagementStateMigration(db);

      final tableNames = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((row) => row['name']).toSet();
      expect(tableNames, contains('post_repost_engagement_participants'));
      expect(tableNames, contains('post_repost_heart_baseline_peers'));
      expect(tableNames, contains('post_repost_projection_state'));

      final participants = await db.query(
        'post_repost_engagement_participants',
      );
      final heartPeers = await db.query('post_repost_heart_baseline_peers');
      final projectionRows = await db.query('post_repost_projection_state');

      expect(participants, hasLength(1));
      expect(participants.single['participant_peer_id'], 'peer-hisam');
      expect(heartPeers, hasLength(1));
      expect(heartPeers.single['sender_peer_id'], 'peer-zoya');
      expect(projectionRows, hasLength(1));
      expect(projectionRows.single['repost_total_baseline'], 2);
    },
  );
}
