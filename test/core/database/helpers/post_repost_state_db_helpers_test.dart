import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_repost_state_db_helpers.dart';
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

  tearDown(() async {
    await db.close();
  });

  Future<Database> openWithMigrations(
    List<Future<void> Function(Database)> migrations,
  ) async {
    final database = await openDatabase(inMemoryDatabasePath, version: 1);
    for (final migration in migrations) {
      await migration(database);
    }
    return database;
  }

  test('strips shared_to_count_baseline on legacy schema', () async {
    db = await openWithMigrations(<Future<void> Function(Database)>[
      runPostsRepostEngagementStateMigration,
    ]);

    await dbInsertPostRepostProjectionState(db, <String, Object?>{
      'post_id': 'post-1',
      'repost_total_baseline': 2,
      'shared_to_count_baseline': 6,
      'created_at': '2026-03-15T11:15:00.000Z',
    });

    final row = await dbLoadPostRepostProjectionState(db, 'post-1');
    expect(row, isNotNull);
    expect(row!['repost_total_baseline'], 2);
    expect(row.containsKey('shared_to_count_baseline'), isFalse);
  });

  test('preserves shared_to_count_baseline on newer schema', () async {
    db = await openWithMigrations(<Future<void> Function(Database)>[
      runPostsPassAlongMigration,
      runPostsRepostEngagementStateMigration,
      runPostsRepostVisualMetricsMigration,
    ]);

    await dbInsertPostRepostProjectionState(db, <String, Object?>{
      'post_id': 'post-1',
      'repost_total_baseline': 2,
      'shared_to_count_baseline': 6,
      'created_at': '2026-03-15T11:15:00.000Z',
    });

    final row = await dbLoadPostRepostProjectionState(db, 'post-1');
    expect(row, isNotNull);
    expect(row!['repost_total_baseline'], 2);
    expect(row['shared_to_count_baseline'], 6);
  });
}
