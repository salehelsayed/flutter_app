import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_passes_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/035_posts_repost_delivery_state.dart';
import 'package:flutter_app/core/database/migrations/036_posts_pass_encrypted_snapshots.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/040_posts_repost_visual_metrics.dart';
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

  Map<String, Object?> makePassRow({
    required String passId,
    required String eventId,
    String deliveryStatus = 'sending',
    int isIncoming = 0,
  }) {
    return <String, Object?>{
      'pass_id': passId,
      'event_id': eventId,
      'post_id': 'post-1',
      'sender_peer_id': 'peer-alice',
      'passer_peer_id': 'peer-alice',
      'passer_username': 'Alice',
      'passed_at': '2026-03-15T11:15:00.000Z',
      'created_at': '2026-03-15T11:15:00.000Z',
      'is_incoming': isIncoming,
      'delivery_status': deliveryStatus,
      'inner_payload_json': '{"ciphertext":"abc"}',
      'recipient_count': 3,
    };
  }

  group('dbUpsertPostPass', () {
    test('strips newer columns on legacy schema', () async {
      db = await openWithMigrations(<Future<void> Function(Database)>[
        runPostsCoreMigration,
        runPostsPassAlongMigration,
      ]);

      await dbUpsertPostPass(
        db,
        makePassRow(passId: 'pass-1', eventId: 'evt-1'),
      );

      final row = (await db.query('post_passes')).single;
      expect(row['pass_id'], 'pass-1');
      expect(row.containsKey('delivery_status'), isFalse);
      expect(row.containsKey('inner_payload_json'), isFalse);
      expect(row.containsKey('recipient_count'), isFalse);
    });

    test(
      'preserves delivery_status, inner_payload_json, and recipient_count on newer schema',
      () async {
        db = await openWithMigrations(<Future<void> Function(Database)>[
          runPostsCoreMigration,
          runPostsPassAlongMigration,
          runPostsRepostDeliveryStateMigration,
          runPostsPassEncryptedSnapshotsMigration,
          runPostsRepostEngagementStateMigration,
          runPostsRepostVisualMetricsMigration,
        ]);

        await dbUpsertPostPass(
          db,
          makePassRow(
            passId: 'pass-1',
            eventId: 'evt-1',
            deliveryStatus: 'failed',
          ),
        );

        final row = (await db.query('post_passes')).single;
        expect(row['delivery_status'], 'failed');
        expect(row['inner_payload_json'], '{"ciphertext":"abc"}');
        expect(row['recipient_count'], 3);
      },
    );
  });

  group('dbLoadRetryableOutgoingPostPasses', () {
    test(
      'falls back to outgoing passes when delivery_status is absent',
      () async {
        db = await openWithMigrations(<Future<void> Function(Database)>[
          runPostsCoreMigration,
          runPostsPassAlongMigration,
        ]);

        await dbUpsertPostPass(
          db,
          makePassRow(passId: 'outgoing', eventId: 'evt-outgoing'),
        );
        await dbUpsertPostPass(
          db,
          makePassRow(
            passId: 'incoming',
            eventId: 'evt-incoming',
            isIncoming: 1,
          ),
        );

        final rows = await dbLoadRetryableOutgoingPostPasses(db);
        expect(rows.map((row) => row['pass_id']), <Object?>['outgoing']);
      },
    );

    test(
      'filters retryable statuses when delivery_status is present',
      () async {
        db = await openWithMigrations(<Future<void> Function(Database)>[
          runPostsCoreMigration,
          runPostsPassAlongMigration,
          runPostsRepostDeliveryStateMigration,
          runPostsPassEncryptedSnapshotsMigration,
          runPostsRepostEngagementStateMigration,
          runPostsRepostVisualMetricsMigration,
        ]);

        await dbUpsertPostPass(
          db,
          makePassRow(
            passId: 'sending',
            eventId: 'evt-sending',
            deliveryStatus: 'sending',
          ),
        );
        await dbUpsertPostPass(
          db,
          makePassRow(
            passId: 'partial',
            eventId: 'evt-partial',
            deliveryStatus: 'partial',
          ),
        );
        await dbUpsertPostPass(
          db,
          makePassRow(
            passId: 'failed',
            eventId: 'evt-failed',
            deliveryStatus: 'failed',
          ),
        );
        await dbUpsertPostPass(
          db,
          makePassRow(
            passId: 'sent',
            eventId: 'evt-sent',
            deliveryStatus: 'sent',
          ),
        );
        await dbUpsertPostPass(
          db,
          makePassRow(
            passId: 'incoming',
            eventId: 'evt-incoming',
            deliveryStatus: 'failed',
            isIncoming: 1,
          ),
        );

        final rows = await dbLoadRetryableOutgoingPostPasses(db);
        expect(rows.map((row) => row['pass_id']).toList(), <Object?>[
          'sending',
          'partial',
          'failed',
        ]);
      },
    );
  });
}
