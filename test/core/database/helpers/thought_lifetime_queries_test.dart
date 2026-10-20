import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_upload_recovery_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  final now = DateTime.utc(2026, 10, 21, 9);
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 122,
        onCreate: runProductionOnCreate,
      ),
    );
  });
  tearDown(() => db.close());
  Future<void> seed(
    String id,
    DateTime created, {
    bool keep = false,
    String status = 'partial',
  }) => dbInsertPost(db, <String, Object?>{
    'post_id': id,
    'event_id': 'evt-$id',
    'sender_peer_id': 'author',
    'author_peer_id': 'author',
    'author_username': 'Author',
    'text': 'private',
    'audience_kind': 'all_friends',
    'post_created_at': created.toIso8601String(),
    'visible_at': created.toIso8601String(),
    'expires_at': created.add(const Duration(hours: 24)).toIso8601String(),
    'is_incoming': 0,
    'delivery_status': status,
    'keep_available': keep ? 1 : 0,
  });
  test(
    'read helpers exclude expiry before any sweep, including keep-available',
    () async {
      await seed(
        'expired',
        now.subtract(const Duration(hours: 24)),
        keep: true,
      );
      await seed('live', now.subtract(const Duration(hours: 23)));
      expect(await dbLoadPost(db, 'expired', nowProvider: () => now), isNull);
      expect(
        (await dbLoadPostsByIds(db, [
          'expired',
          'live',
        ], nowProvider: () => now)).map((row) => row['post_id']),
        ['live'],
      );
      expect(
        (await dbLoadPostsFeed(
          db,
          nowProvider: () => now,
        )).map((row) => row['post_id']),
        ['live'],
      );
      expect(
        (await dbLoadExpiredPosts(db, now.toIso8601String())).single['post_id'],
        'expired',
      );
    },
  );
  test(
    'retry eligibility leaves expired partial and failed status unchanged',
    () async {
      await seed('expired-partial', now.subtract(const Duration(hours: 24)));
      await seed(
        'expired-failed',
        now.subtract(const Duration(hours: 25)),
        status: 'failed',
      );
      await seed('live', now.subtract(const Duration(hours: 23)));
      expect(
        (await dbLoadRetryableOutgoingPosts(
          db,
          nowProvider: () => now,
        )).map((row) => row['post_id']),
        ['live'],
      );
      final expired = await db.query(
        'posts',
        where: 'post_id LIKE ?',
        whereArgs: ['expired-%'],
      );
      expect(expired.map((row) => row['delivery_status']).toSet(), {
        'partial',
        'failed',
      });
    },
  );
  test(
    'expired recovery rows are terminal and cannot be selected again',
    () async {
      await seed('expired', now.subtract(const Duration(hours: 24)));
      await seed('live', now.subtract(const Duration(hours: 23)));
      for (final id in ['expired', 'live']) {
        await db.insert('post_media_upload_recovery', {
          'post_id': id,
          'position': 0,
          'kind': 'image',
          'local_file_path': 'source.jpg',
          'mime': 'image/jpeg',
          'created_at': now.toIso8601String(),
        });
      }
      expect(
        (await dbLoadPendingPostMediaUploadPosts(
          db,
          nowProvider: () => now,
        )).single['post_id'],
        'live',
      );
      expect(await dbLoadPostMediaUploadRecoveryItems(db, 'expired'), isEmpty);
      expect(
        (await dbLoadPendingPostMediaUploadPosts(
          db,
          nowProvider: () => now,
        )).single['post_id'],
        'live',
      );
    },
  );
}
