import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 027: posts core', () {
    test('creates posts, post_recipients, and post_feed_state tables', () async {
      await runPostsCoreMigration(db);

      final postsColumns = await db.rawQuery('PRAGMA table_info(posts)');
      final postsColumnNames = postsColumns
          .map((column) => column['name'] as String)
          .toSet();
      expect(postsColumnNames, containsAll(<String>{
        'post_id',
        'event_id',
        'author_peer_id',
        'author_username',
        'sender_peer_id',
        'text',
        'audience_kind',
        'scope_label',
        'post_created_at',
        'expires_at',
        'is_incoming',
        'delivery_status',
      }));

      final recipientColumns = await db.rawQuery(
        'PRAGMA table_info(post_recipients)',
      );
      final recipientColumnNames = recipientColumns
          .map((column) => column['name'] as String)
          .toSet();
      expect(recipientColumnNames, containsAll(<String>{
        'post_id',
        'recipient_peer_id',
        'delivery_status',
        'delivery_path',
        'last_attempt_at',
        'last_error',
      }));

      final feedStateColumns = await db.rawQuery(
        'PRAGMA table_info(post_feed_state)',
      );
      final feedStateColumnNames = feedStateColumns
          .map((column) => column['name'] as String)
          .toSet();
      expect(feedStateColumnNames, containsAll(<String>{
        'post_id',
        'is_hidden',
        'is_read',
        'last_focused_at',
      }));
    });

    test('is idempotent', () async {
      await runPostsCoreMigration(db);
      await runPostsCoreMigration(db);

      final tables = await db.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name IN ('posts', 'post_recipients', 'post_feed_state')
        ORDER BY name
        ''',
      );

      expect(
        tables.map((row) => row['name']),
        orderedEquals(['post_feed_state', 'post_recipients', 'posts']),
      );
    });
  });
}
