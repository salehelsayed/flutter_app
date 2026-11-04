import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_upload_recovery_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/application/retract_thought_use_case.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../services/fake_p2p_service.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  final now = DateTime.utc(2026, 10, 21, 9);
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
      ),
    );
  });
  tearDown(() => db.close());
  final ownPageRequests = <(int?, int)>[];
  final ownPageRowCounts = <int>[];
  setUp(() {
    ownPageRequests.clear();
    ownPageRowCounts.clear();
  });
  PostRepositoryImpl repository() {
    final posts = PostRepositoryImpl(
      dbLoadExpiredOwnPosts: (iso, {limit, offset = 0}) async {
        ownPageRequests.add((limit, offset));
        final rows = await dbLoadExpiredOwnPosts(
          db,
          iso,
          limit: limit,
          offset: offset,
        );
        ownPageRowCounts.add(rows.length);
        return rows;
      },
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (id) => dbLoadPost(db, id, nowProvider: () => now),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db, nowProvider: () => now),
      dbLoadExpiredPosts: (iso) => dbLoadExpiredPosts(db, iso),
      dbDeletePostCascade: (id) => dbDeletePostCascade(db, id),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (id) => dbLoadPostRecipientDeliveries(db, id),
      dbMarkPostFocused: (id) => dbMarkPostFocused(db, id),
    );
    addTearDown(posts.dispose);
    return posts;
  }

  Future<void> seed(
    String id,
    DateTime created, {
    bool keep = false,
    bool incoming = false,
    String author = 'author',
    String status = 'partial',
  }) => dbInsertPost(db, <String, Object?>{
    'post_id': id,
    'event_id': 'evt-$id',
    'sender_peer_id': author,
    'author_peer_id': author,
    'author_username': 'Author',
    'text': 'private',
    'audience_kind': 'all_friends',
    'post_created_at': created.toIso8601String(),
    'visible_at': created.toIso8601String(),
    'expires_at': created.add(const Duration(hours: 24)).toIso8601String(),
    'is_incoming': incoming ? 1 : 0,
    'delivery_status': status,
    'keep_available': keep ? 1 : 0,
  });
  test(
    'own history repository read keeps expired authors out of public reads',
    () async {
      await seed('own-older', now.subtract(const Duration(hours: 48)));
      await seed('own-newer', now.subtract(const Duration(hours: 25)));
      await seed('own-live', now.subtract(const Duration(hours: 1)));
      await seed(
        'friend-expired',
        now.subtract(const Duration(hours: 26)),
        incoming: true,
      );
      final posts = repository();

      expect(
        (await posts.loadExpiredOwnPosts(
          now.toIso8601String(),
        )).map((post) => post.id),
        ['own-newer', 'own-older'],
      );
      expect(await posts.getPost('own-newer'), isNull);
      expect((await posts.loadFeed()).map((post) => post.id), ['own-live']);
      expect(
        (await posts.loadPostsByIds([
          'own-newer',
          'own-live',
        ])).map((post) => post.id),
        ['own-live'],
      );
    },
  );

  test('a history page asks the database for that page only', () async {
    for (var i = 0; i < 50; i++) {
      await seed(
        'own-${i.toString().padLeft(2, '0')}',
        now.subtract(Duration(hours: 100 - i)),
      );
    }
    await seed(
      'friend-expired',
      now.subtract(const Duration(hours: 30)),
      incoming: true,
    );
    await seed('own-live', now.subtract(const Duration(hours: 1)));
    final posts = repository();

    final first = await posts.loadExpiredOwnPosts(
      now.toIso8601String(),
      limit: 20,
    );
    final older = await posts.loadExpiredOwnPosts(
      now.toIso8601String(),
      limit: 20,
      offset: 20,
    );

    expect(ownPageRequests, [(20, 0), (20, 20)]);
    expect(ownPageRowCounts, [20, 20]);
    expect(first.map((post) => post.id), [
      for (var i = 49; i >= 30; i--) 'own-$i',
    ]);
    expect(older.map((post) => post.id), [
      for (var i = 29; i >= 10; i--) 'own-${i.toString().padLeft(2, '0')}',
    ]);
  });

  test(
    'expired own history retracts locally with its file but cannot retract friends',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'own-history-delete-',
      );
      final originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _ThoughtHistoryPathProvider(
        directory.path,
      );
      addTearDown(() async {
        PathProviderPlatform.instance = originalPathProvider;
        await directory.delete(recursive: true);
      });
      for (final id in ['own-history', 'friend-expired']) {
        await seed(
          id,
          now.subtract(const Duration(hours: 25)),
          incoming: id == 'friend-expired',
          author: id == 'friend-expired' ? 'friend' : 'author',
        );
        final relative = 'post_media/$id/image.jpg';
        final file = File('${directory.path}/$relative');
        await file.parent.create(recursive: true);
        await file.writeAsBytes([7, 8, 9]);
        await db.insert(
          'post_media_attachments',
          PostMediaAttachmentModel(
            mediaId: 'media-$id',
            postId: id,
            blobId: 'blob-$id',
            kind: 'image',
            mime: 'image/jpeg',
            sizeBytes: 3,
            localPath: relative,
            downloadStatus: 'done',
            createdAt: now
                .subtract(const Duration(hours: 25))
                .toIso8601String(),
          ).toMap(),
        );
      }
      final posts = repository();
      final service = FakeP2PService();
      Future<ThoughtRetraction> retract(String id, String sender) =>
          retractThought(
            postRepo: posts,
            p2pService: service,
            mediaFileManager: MediaFileManager(),
            postId: id,
            senderPeerId: sender,
            nowProvider: () => now,
          );
      expect(await posts.getPost('own-history'), isNull);
      expect(
        (await retract('own-history', 'not-author')).result,
        RetractThoughtResult.notAuthor,
      );
      expect(
        (await retract('friend-expired', 'author')).result,
        RetractThoughtResult.postNotFound,
      );
      expect(
        (await retract('own-history', 'author')).result,
        RetractThoughtResult.deleted,
      );
      expect(
        await db.query(
          'posts',
          where: 'post_id = ?',
          whereArgs: ['own-history'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'post_media_attachments',
          where: 'post_id = ?',
          whereArgs: ['own-history'],
        ),
        isEmpty,
      );
      expect(
        await File(
          '${directory.path}/post_media/own-history/image.jpg',
        ).exists(),
        isFalse,
      );
      expect(
        await db.query(
          'posts',
          where: 'post_id = ?',
          whereArgs: ['friend-expired'],
        ),
        hasLength(1),
      );
      expect(
        await File(
          '${directory.path}/post_media/friend-expired/image.jpg',
        ).readAsBytes(),
        [7, 8, 9],
      );
    },
  );

  test(
    'next expiry ignores retained own history and keeps incoming deadline',
    () async {
      await seed('own-history', now.subtract(const Duration(hours: 48)));
      await seed('own-live', now.subtract(const Duration(minutes: 1410)));
      await seed(
        'incoming-deadline',
        now.subtract(const Duration(hours: 23)),
        incoming: true,
      );

      expect(await dbLoadNextPostExpiry(db), now.add(const Duration(hours: 1)));
    },
  );

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
    'expired own recovery sources survive without becoming pending work',
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
      final expiredSource = await dbLoadPostMediaUploadRecoveryItems(
        db,
        'expired',
      );
      expect(expiredSource, hasLength(1));
      expect(
        (await dbLoadPendingPostMediaUploadPosts(
          db,
          nowProvider: () => now,
        )).single['post_id'],
        'live',
      );
      expect(
        await dbLoadPostMediaUploadRecoveryItems(db, 'expired'),
        equals(expiredSource),
      );
      expect(
        (await dbLoadPendingPostMediaUploadPosts(
          db,
          nowProvider: () => now,
        )).single['post_id'],
        'live',
      );
      expect(
        await dbLoadPostMediaUploadRecoveryItems(db, 'expired'),
        equals(expiredSource),
      );
    },
  );
}

class _ThoughtHistoryPathProvider extends PathProviderPlatform {
  _ThoughtHistoryPathProvider(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
