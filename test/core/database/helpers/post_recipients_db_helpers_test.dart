import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/032_posts_retry_recipient_context.dart';
import 'package:flutter_app/core/database/migrations/035_posts_repost_delivery_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await db.close();
  });

  Future<Database> openWithMigrations(
    List<Future<void> Function(Database)> migrations,
  ) async {
    final database = await openDatabase(inMemoryDatabasePath, version: 1);
    for (final migration in migrations) {
      await migration(database);
    }
    return database;
  }

  Map<String, Object?> makeRecipientRow({
    required String postId,
    required String recipientPeerId,
    String deliveryOwnerKind = 'post',
    String? deliveryOwnerId,
    int? nearbyDistanceM,
  }) {
    return <String, Object?>{
      'post_id': postId,
      'recipient_peer_id': recipientPeerId,
      'delivery_status': 'sending',
      'last_attempt_at': '2026-03-15T11:15:00.000Z',
      'delivery_path': 'relay',
      'last_error': null,
      'nearby_distance_m': nearbyDistanceM,
      'created_at': '2026-03-15T11:15:00.000Z',
      'updated_at': '2026-03-15T11:15:00.000Z',
      'delivery_owner_kind': deliveryOwnerKind,
      'delivery_owner_id': deliveryOwnerId ?? postId,
    };
  }

  group('legacy schema', () {
    test('strips newer columns and loads deliveries by post_id', () async {
      db = await openWithMigrations(<Future<void> Function(Database)>[
        runPostsCoreMigration,
      ]);

      await dbUpsertPostRecipientDelivery(
        db,
        makeRecipientRow(
          postId: 'post-1',
          recipientPeerId: 'peer-bob',
          deliveryOwnerKind: 'post_pass',
          deliveryOwnerId: 'pass-1',
          nearbyDistanceM: 42,
        ),
      );

      final rows = await dbLoadPostRecipientDeliveries(db, 'post-1');
      expect(rows, hasLength(1));
      expect(rows.single['recipient_peer_id'], 'peer-bob');
      expect(rows.single.containsKey('nearby_distance_m'), isFalse);

      final passRows = await dbLoadPostPassRecipientDeliveries(db, 'pass-1');
      expect(passRows, isEmpty);
    });
  });

  group('expanded schema', () {
    test(
      'preserves owner columns and splits post/pass delivery views',
      () async {
        db = await openWithMigrations(<Future<void> Function(Database)>[
          runPostsCoreMigration,
          runPostsPassAlongMigration,
          runPostsRetryRecipientContextMigration,
          runPostsRepostDeliveryStateMigration,
        ]);

        await dbUpsertPostRecipientDelivery(
          db,
          makeRecipientRow(
            postId: 'post-1',
            recipientPeerId: 'peer-bob',
            nearbyDistanceM: 42,
          ),
        );
        await dbUpsertPostRecipientDelivery(
          db,
          makeRecipientRow(
            postId: 'post-1',
            recipientPeerId: 'peer-charlie',
            deliveryOwnerKind: 'post_pass',
            deliveryOwnerId: 'pass-1',
            nearbyDistanceM: 64,
          ),
        );

        final postRows = await dbLoadPostRecipientDeliveries(db, 'post-1');
        expect(postRows, hasLength(1));
        expect(postRows.single['recipient_peer_id'], 'peer-bob');
        expect(postRows.single['nearby_distance_m'], 42);

        final passRows = await dbLoadPostPassRecipientDeliveries(db, 'pass-1');
        expect(passRows, hasLength(1));
        expect(passRows.single['recipient_peer_id'], 'peer-charlie');
        expect(passRows.single['delivery_owner_kind'], 'post_pass');
        expect(passRows.single['delivery_owner_id'], 'pass-1');
        expect(passRows.single['nearby_distance_m'], 64);
      },
    );
  });
}
