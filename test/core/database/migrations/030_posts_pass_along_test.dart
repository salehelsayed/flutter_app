import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
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
  });

  tearDown(() async {
    await db.close();
  });

  test('creates pass event and post origin tables', () async {
    await runPostsPassAlongMigration(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((row) => row['name']).toList(growable: false);

    expect(names, contains('post_passes'));
    expect(names, contains('post_origin'));

    final passColumns = await db.rawQuery('PRAGMA table_info(post_passes)');
    final passColumnNames = passColumns
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      passColumnNames,
      containsAll(<String>{
        'pass_id',
        'event_id',
        'post_id',
        'sender_peer_id',
        'passer_peer_id',
        'passer_username',
        'passed_at',
        'created_at',
        'is_incoming',
      }),
    );

    final originColumns = await db.rawQuery('PRAGMA table_info(post_origin)');
    final originColumnNames = originColumns
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      originColumnNames,
      containsAll(<String>{
        'post_id',
        'origin_kind',
        'pass_id',
        'passer_peer_id',
        'passer_username',
        'pass_created_at',
      }),
    );
  });
}
