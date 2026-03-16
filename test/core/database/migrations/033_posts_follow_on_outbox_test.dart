import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/033_posts_follow_on_outbox.dart';
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

  test('creates follow-on outbox event and recipient-delivery tables', () async {
    await runPostsFollowOnOutboxMigration(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((row) => row['name']).toList(growable: false);

    expect(names, contains('post_follow_on_outbox_events'));
    expect(names, contains('post_follow_on_outbox_recipient_deliveries'));

    final eventColumns = await db.rawQuery(
      'PRAGMA table_info(post_follow_on_outbox_events)',
    );
    final eventColumnNames = eventColumns
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      eventColumnNames,
      containsAll(<String>{
        'event_id',
        'event_type',
        'post_id',
        'comment_id',
        'sender_peer_id',
        'raw_envelope',
        'created_at',
      }),
    );

    final deliveryColumns = await db.rawQuery(
      'PRAGMA table_info(post_follow_on_outbox_recipient_deliveries)',
    );
    final deliveryColumnNames = deliveryColumns
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      deliveryColumnNames,
      containsAll(<String>{
        'event_id',
        'recipient_peer_id',
        'delivery_status',
        'delivery_path',
        'last_error',
        'last_attempt_at',
        'created_at',
        'updated_at',
      }),
    );
  });
}
