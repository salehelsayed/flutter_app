import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/032_posts_retry_recipient_context.dart';
import 'package:flutter_app/core/database/migrations/033_posts_follow_on_outbox.dart';
import 'package:flutter_app/core/database/migrations/035_posts_repost_delivery_state.dart';
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
    await runPostsRetryRecipientContextMigration(db);
    await runPostsFollowOnOutboxMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'adds repost delivery ownership to post_recipients and migrates legacy pass outbox rows',
    () async {
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
      });
      await db.insert('post_follow_on_outbox_events', <String, Object?>{
        'event_id': 'evt-pass-1',
        'event_type': 'post_pass_along',
        'post_id': 'post-1',
        'sender_peer_id': 'peer-self',
        'raw_envelope': '{"type":"post_pass"}',
        'created_at': '2026-03-15T11:25:00.000Z',
      });
      await db.insert(
        'post_follow_on_outbox_recipient_deliveries',
        <String, Object?>{
          'event_id': 'evt-pass-1',
          'recipient_peer_id': 'peer-bob',
          'delivery_status': 'failed',
          'delivery_path': 'failed',
          'last_error': 'direct_and_inbox_failed',
          'last_attempt_at': '2026-03-15T11:25:10.000Z',
          'created_at': '2026-03-15T11:25:00.000Z',
          'updated_at': '2026-03-15T11:25:10.000Z',
        },
      );

      await runPostsRepostDeliveryStateMigration(db);

      final recipientColumns = await db.rawQuery(
        'PRAGMA table_info(post_recipients)',
      );
      final recipientColumnNames = recipientColumns
          .map((column) => column['name'] as String)
          .toSet();
      expect(
        recipientColumnNames,
        containsAll(<String>{'delivery_owner_kind', 'delivery_owner_id'}),
      );

      final migratedDeliveries = await db.query(
        'post_recipients',
        where: 'delivery_owner_kind = ? AND delivery_owner_id = ?',
        whereArgs: const <Object?>['post_pass', 'pass-1'],
      );
      expect(migratedDeliveries, hasLength(1));
      expect(migratedDeliveries.single['recipient_peer_id'], 'peer-bob');
      expect(migratedDeliveries.single['delivery_status'], 'failed');
      expect(migratedDeliveries.single['post_id'], 'post-1');

      final passColumns = await db.rawQuery('PRAGMA table_info(post_passes)');
      final passColumnNames = passColumns
          .map((column) => column['name'] as String)
          .toSet();
      expect(passColumnNames, contains('delivery_status'));

      final passRows = await db.query(
        'post_passes',
        where: 'pass_id = ?',
        whereArgs: const <Object?>['pass-1'],
      );
      expect(passRows.single['delivery_status'], 'failed');

      final remainingPassEvents = await db.query(
        'post_follow_on_outbox_events',
        where: 'event_type = ?',
        whereArgs: const <Object?>['post_pass_along'],
      );
      expect(remainingPassEvents, isEmpty);
    },
  );
}
