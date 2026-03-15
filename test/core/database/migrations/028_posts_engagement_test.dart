import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
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
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'migration creates comment, reaction, media, and pending-child-event tables',
    () async {
      await runPostsEngagementMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final names = tables.map((row) => row['name']).toList();

      expect(names, contains('post_comments'));
      expect(names, contains('post_reactions'));
      expect(names, contains('post_comment_reactions'));
      expect(names, contains('post_media_attachments'));
      expect(names, contains('post_pending_child_events'));

      final postColumns = await db.rawQuery("PRAGMA table_info(posts)");
      final postColumnNames = postColumns
          .map((row) => row['name'])
          .toList(growable: false);
      expect(postColumnNames, contains('last_engagement_at'));
    },
  );
}
