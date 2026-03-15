import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
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
  });

  tearDown(() async {
    await db.close();
  });

  test('creates nearby privacy and presence tables', () async {
    await runPostsNearbyMigration(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((row) => row['name']).toList(growable: false);

    expect(names, contains('post_privacy_state'));
    expect(names, contains('post_location_presence'));

    final postColumns = await db.rawQuery('PRAGMA table_info(posts)');
    final postColumnNames = postColumns
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      postColumnNames,
      containsAll(<String>{
        'audience_radius_m',
        'nearby_distance_m',
        'nearby_sender_lat_e3',
        'nearby_sender_lng_e3',
        'nearby_sender_captured_at',
        'nearby_sender_accuracy_m',
      }),
    );

    final privacyColumns = await db.rawQuery(
      'PRAGMA table_info(post_privacy_state)',
    );
    final privacyColumnNames = privacyColumns
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      privacyColumnNames,
      containsAll(<String>{
        'sharing_enabled',
        'permission_state',
        'last_local_lat_e3',
        'last_local_lng_e3',
        'last_local_captured_at',
        'last_local_accuracy_m',
        'last_refresh_attempt_at',
      }),
    );
  });
}
