import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/034_posts_media_upload_recovery.dart';
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
    'creates media upload recovery table with ordered recovery fields',
    () async {
      await runPostsMediaUploadRecoveryMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final names = tables.map((row) => row['name']).toList(growable: false);

      expect(names, contains('post_media_upload_recovery'));

      final columns = await db.rawQuery(
        'PRAGMA table_info(post_media_upload_recovery)',
      );
      final columnNames = columns
          .map((column) => column['name'] as String)
          .toSet();

      expect(
        columnNames,
        containsAll(<String>{
          'post_id',
          'position',
          'local_file_path',
          'mime',
          'kind',
          'width',
          'height',
          'duration_ms',
          'waveform',
          'created_at',
        }),
      );

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='post_media_upload_recovery'",
      );
      final indexNames = indexes.map((row) => row['name'] as String).toSet();
      expect(indexNames, contains('idx_post_media_upload_recovery_created_at'));
    },
  );
}
