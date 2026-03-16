import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_upload_recovery_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/034_posts_media_upload_recovery.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
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
    await runPostsPassAlongMigration(db);
    await runPostsMediaUploadRecoveryMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  PostRepositoryImpl buildRepository() {
    return PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (postId) => dbLoadPost(db, postId),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) =>
          dbLoadPostRecipientDeliveries(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      dbReplacePostMediaUploadRecoveryItems: (postId, rows) =>
          dbReplacePostMediaUploadRecoveryItems(db, postId, rows),
      dbLoadPostMediaUploadRecoveryItems: (postId) =>
          dbLoadPostMediaUploadRecoveryItems(db, postId),
      dbLoadPendingMediaUploadPosts: () =>
          dbLoadPendingPostMediaUploadPosts(db),
    );
  }

  test(
    'repository round-trip preserves recovery metadata order and pending-post discovery across recreation',
    () async {
      final firstRepository = buildRepository();
      const imagePost = PostModel(
        id: 'post-image',
        eventId: 'evt-image',
        senderPeerId: 'peer-alice',
        authorPeerId: 'peer-alice',
        authorUsername: 'Alice',
        text: '',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: '2026-03-16T11:00:00.000Z',
        visibleAt: '2026-03-16T11:00:00.000Z',
        expiresAt: '2026-03-19T11:00:00.000Z',
        mediaKind: 'image_carousel',
        isIncoming: false,
        deliveryStatus: 'sending',
      );
      const voicePost = PostModel(
        id: 'post-voice',
        eventId: 'evt-voice',
        senderPeerId: 'peer-alice',
        authorPeerId: 'peer-alice',
        authorUsername: 'Alice',
        text: '',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: '2026-03-16T11:05:00.000Z',
        visibleAt: '2026-03-16T11:05:00.000Z',
        expiresAt: '2026-03-19T11:05:00.000Z',
        mediaKind: 'voice',
        isIncoming: false,
        deliveryStatus: 'failed',
      );

      await firstRepository.savePost(imagePost);
      await firstRepository.savePost(voicePost);
      await firstRepository.replacePostMediaUploadRecoveryItems(
        imagePost.id,
        const <PostMediaUploadRecoveryItem>[
          PostMediaUploadRecoveryItem(
            postId: 'post-image',
            position: 0,
            localFilePath: '/tmp/photo-1.jpg',
            mime: 'image/jpeg',
            kind: 'image',
            width: 1080,
            height: 1440,
            createdAt: '2026-03-16T11:00:00.000Z',
          ),
          PostMediaUploadRecoveryItem(
            postId: 'post-image',
            position: 1,
            localFilePath: '/tmp/photo-2.jpg',
            mime: 'image/jpeg',
            kind: 'image',
            width: 1440,
            height: 1080,
            createdAt: '2026-03-16T11:00:01.000Z',
          ),
        ],
      );
      await firstRepository.replacePostMediaUploadRecoveryItems(
        voicePost.id,
        const <PostMediaUploadRecoveryItem>[
          PostMediaUploadRecoveryItem(
            postId: 'post-voice',
            position: 0,
            localFilePath: '/tmp/voice.m4a',
            mime: 'audio/mp4',
            kind: 'voice',
            durationMs: 4200,
            waveform: <double>[0.1, 0.2, 0.4],
            createdAt: '2026-03-16T11:05:00.000Z',
          ),
        ],
      );
      firstRepository.dispose();

      final secondRepository = buildRepository();
      final imageRecovery = await secondRepository
          .loadPostMediaUploadRecoveryItems(imagePost.id);
      final voiceRecovery = await secondRepository
          .loadPostMediaUploadRecoveryItems(voicePost.id);
      final pendingPosts = await secondRepository.loadPendingMediaUploadPosts();

      expect(
        imageRecovery.map((item) => item.position).toList(growable: false),
        <int>[0, 1],
      );
      expect(
        imageRecovery.map((item) => item.localFilePath).toList(growable: false),
        <String>['/tmp/photo-1.jpg', '/tmp/photo-2.jpg'],
      );
      expect(imageRecovery.first.mime, 'image/jpeg');
      expect(imageRecovery.first.kind, 'image');
      expect(imageRecovery.first.width, 1080);
      expect(imageRecovery.first.height, 1440);

      expect(voiceRecovery, hasLength(1));
      expect(voiceRecovery.single.localFilePath, '/tmp/voice.m4a');
      expect(voiceRecovery.single.mime, 'audio/mp4');
      expect(voiceRecovery.single.kind, 'voice');
      expect(voiceRecovery.single.durationMs, 4200);
      expect(voiceRecovery.single.waveform, <double>[0.1, 0.2, 0.4]);

      expect(
        pendingPosts.map((post) => post.id).toList(growable: false),
        <String>['post-image', 'post-voice'],
      );

      secondRepository.dispose();
    },
  );
}
