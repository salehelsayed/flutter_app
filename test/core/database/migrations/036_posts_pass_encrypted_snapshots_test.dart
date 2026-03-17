import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/035_posts_repost_delivery_state.dart';
import 'package:flutter_app/core/database/migrations/036_posts_pass_encrypted_snapshots.dart';
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
  });

  tearDown(() async {
    await db.close();
  });

  test('adds inner_payload_json to post_passes without disturbing existing rows', () async {
    await db.insert('post_passes', <String, Object?>{
      'pass_id': 'pass-1',
      'event_id': 'evt-pass-1',
      'post_id': 'post-1',
      'sender_peer_id': 'peer-self',
      'passer_peer_id': 'peer-self',
      'passer_username': 'Alice',
      'passed_at': '2026-03-15T11:25:00.000Z',
      'created_at': '2026-03-15T11:25:00.000Z',
      'is_incoming': 0,
      'delivery_status': 'sending',
    });

    await runPostsPassEncryptedSnapshotsMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(post_passes)');
    final columnNames = columns.map((column) => column['name'] as String).toSet();
    expect(columnNames, contains('inner_payload_json'));

    final rows = await db.query(
      'post_passes',
      where: 'pass_id = ?',
      whereArgs: const <Object?>['pass-1'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['delivery_status'], 'sending');
    expect(rows.single['inner_payload_json'], isNull);
  });
}
