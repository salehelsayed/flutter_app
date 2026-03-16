import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/032_posts_retry_recipient_context.dart';
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

  test('adds nearby_distance_m to post_recipients', () async {
    await runPostsRetryRecipientContextMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(post_recipients)');
    final names = columns
        .map((column) => column['name'] as String)
        .toSet();

    expect(names, contains('nearby_distance_m'));
  });
}
