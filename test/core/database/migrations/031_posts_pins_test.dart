import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/031_posts_pins.dart';
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
  });

  tearDown(() async {
    await db.close();
  });

  test('creates pin state and local dismissal tables', () async {
    await runPostsPinsMigration(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((row) => row['name']).toList(growable: false);

    expect(names, contains('post_pins'));
    expect(names, contains('post_pin_dismissals'));

    final pinColumns = await db.rawQuery('PRAGMA table_info(post_pins)');
    final pinColumnNames = pinColumns
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      pinColumnNames,
      containsAll(<String>{
        'post_id',
        'event_id',
        'pin_event_id',
        'sender_peer_id',
        'state',
        'effective_at',
        'pinned_at',
        'removed_at',
        'reason',
        'created_at',
      }),
    );

    final dismissalColumns = await db.rawQuery(
      'PRAGMA table_info(post_pin_dismissals)',
    );
    final dismissalColumnNames = dismissalColumns
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      dismissalColumnNames,
      containsAll(<String>{'post_id', 'dismissed_at'}),
    );
  });
}
