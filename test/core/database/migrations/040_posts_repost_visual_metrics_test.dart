import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/040_posts_repost_visual_metrics.dart';
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
    await runPostsPassAlongMigration(db);
    await runPostsRepostEngagementStateMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('adds recipient_count and shared_to_count_baseline columns', () async {
    await runPostsRepostVisualMetricsMigration(db);

    final passColumns = await db.rawQuery('PRAGMA table_info(post_passes)');
    final projectionColumns = await db.rawQuery(
      'PRAGMA table_info(post_repost_projection_state)',
    );

    expect(
      passColumns.map((column) => column['name'] as String),
      contains('recipient_count'),
    );
    expect(
      projectionColumns.map((column) => column['name'] as String),
      contains('shared_to_count_baseline'),
    );
  });

  test(
    'preserves existing rows while adding repost visual metric columns',
    () async {
      await db.insert('post_passes', <String, Object?>{
        'pass_id': 'pass-1',
        'event_id': 'evt-pass-1',
        'post_id': 'post-1',
        'sender_peer_id': 'peer-alice',
        'passer_peer_id': 'peer-alice',
        'passer_username': 'Alice',
        'passed_at': '2026-03-15T11:15:00.000Z',
        'created_at': '2026-03-15T11:15:00.000Z',
        'is_incoming': 0,
      });
      await db.insert('post_repost_projection_state', <String, Object?>{
        'post_id': 'post-1',
        'repost_total_baseline': 2,
        'created_at': '2026-03-15T11:15:00.000Z',
      });

      await runPostsRepostVisualMetricsMigration(db);

      final passRows = await db.query(
        'post_passes',
        where: 'pass_id = ?',
        whereArgs: const <Object?>['pass-1'],
      );
      final projectionRows = await db.query(
        'post_repost_projection_state',
        where: 'post_id = ?',
        whereArgs: const <Object?>['post-1'],
      );

      expect(passRows.single['recipient_count'], isNull);
      expect(projectionRows.single['repost_total_baseline'], 2);
      expect(projectionRows.single['shared_to_count_baseline'], 0);
    },
  );

  test('is idempotent', () async {
    await runPostsRepostVisualMetricsMigration(db);
    await runPostsRepostVisualMetricsMigration(db);

    final passColumns = await db.rawQuery('PRAGMA table_info(post_passes)');
    final projectionColumns = await db.rawQuery(
      'PRAGMA table_info(post_repost_projection_state)',
    );

    expect(
      passColumns.where((column) => column['name'] == 'recipient_count'),
      hasLength(1),
    );
    expect(
      projectionColumns.where(
        (column) => column['name'] == 'shared_to_count_baseline',
      ),
      hasLength(1),
    );
  });
}
