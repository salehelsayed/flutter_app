import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/database/helpers/post_comments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_pending_child_events_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_passes_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/031_posts_pins.dart';
import 'package:flutter_app/core/database/migrations/034_posts_media_upload_recovery.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/038_posts_repost_media_crypto.dart';
import 'package:flutter_app/core/database/migrations/039_posts_pass_avatar_snapshots.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pending_child_event.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late PostRepositoryImpl repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsEngagementMigration(db);
    await runPostsPassAlongMigration(db);
    await runPostsPinsMigration(db);
    await runPostsMediaUploadRecoveryMigration(db);
    await runPostsRepostEngagementStateMigration(db);
    await runPostsRepostMediaCryptoMigration(db);
    await runPostsPassAvatarSnapshotsMigration(db);
    repository = PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (postId) => dbLoadPost(db, postId),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db),
      dbLoadExpiredPosts: (nowIso) => dbLoadExpiredPosts(db, nowIso),
      dbDeletePostCascade: (postId) => dbDeletePostCascade(db, postId),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) =>
          dbLoadPostRecipientDeliveries(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      dbInsertPostComment: (row) => dbInsertPostComment(db, row),
      dbLoadPostComment: (commentId) => dbLoadPostComment(db, commentId),
      dbLoadPostComments: (postId) => dbLoadPostComments(db, postId),
      dbInsertPendingChildEvent: (row) =>
          dbInsertPendingPostChildEvent(db, row),
      dbLoadPendingChildEvents: (postId) =>
          dbLoadPendingPostChildEvents(db, postId),
      dbDeletePendingChildEvent: (eventId) =>
          dbDeletePendingPostChildEvent(db, eventId),
      dbUpsertPostMedia: (row) => dbUpsertPostMediaAttachment(db, row),
      dbLoadPostMedia: (postId) => dbLoadPostMediaAttachments(db, postId),
      dbSavePassAvatarSnapshot: (postId, authorPeerId, avatarBlob, createdAt) =>
          dbSavePassAvatarSnapshot(
            db,
            postId,
            authorPeerId,
            avatarBlob,
            createdAt,
          ),
      dbLoadPassAvatarSnapshot: (postId) =>
          dbLoadPassAvatarSnapshot(db, postId),
      dbLoadPassAvatarSnapshotsForPosts: (postIds) =>
          dbLoadPassAvatarSnapshotsForPosts(db, postIds),
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  test(
    'repository round-trip persists comments and pending child events',
    () async {
      await repository.savePost(
        const PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-bob',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
          text: 'Need a ladder in Kreuzberg',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
      );
      await repository.saveComment(
        const PostCommentModel(
          id: 'comment-1',
          eventId: 'evt-comment-1',
          postId: 'post-1',
          senderPeerId: 'peer-bob',
          body: 'I can lend one.',
          commentedAt: '2026-03-15T11:00:00.000Z',
        ),
      );
      await repository.stagePendingChildEvent(
        const PostPendingChildEvent(
          postId: 'post-2',
          eventId: 'evt-comment-2',
          eventType: 'post_comment',
          senderPeerId: 'peer-bob',
          createdAt: '2026-03-15T11:05:00.000Z',
          rawEnvelope: '{"type":"post_comment"}',
        ),
      );

      final comments = await repository.loadComments('post-1');
      final pending = await repository.loadPendingChildEvents('post-2');

      expect(comments, hasLength(1));
      expect(comments.single.body, 'I can lend one.');
      expect(pending, hasLength(1));
      expect(pending.single.eventType, 'post_comment');
    },
  );

  test(
    'repository can load and delete expired posts with media rows',
    () async {
      await repository.savePost(
        const PostModel(
          id: 'post-expired',
          eventId: 'evt-post-expired',
          senderPeerId: 'peer-bob',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
          text: 'Expired post',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-16T08:00:00.000Z',
        ),
      );
      await repository.savePostMediaAttachment(
        const PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-expired',
          blobId: 'blob-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 128,
          localPath: 'post_media/post-expired/blob-1',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );
      await repository.savePassAvatarSnapshot(
        postId: 'post-expired',
        authorPeerId: 'peer-bob',
        avatarBlob: Uint8List.fromList(<int>[1, 2, 3, 4]),
        createdAt: '2026-03-15T10:25:00.000Z',
      );

      final expired = await repository.loadExpiredPosts(
        '2026-03-16T09:00:00.000Z',
      );
      expect(expired.map((post) => post.id), ['post-expired']);

      await repository.deletePostCascade('post-expired');

      expect(await repository.getPost('post-expired'), isNull);
      expect(
        await repository.loadPostMediaAttachments('post-expired'),
        isEmpty,
      );
      expect(await repository.loadPassAvatarSnapshot('post-expired'), isNull);
    },
  );

  test(
    'deletePostCascade fails when a required posts table is missing',
    () async {
      await repository.savePost(
        const PostModel(
          id: 'post-missing-table',
          eventId: 'evt-post-missing-table',
          senderPeerId: 'peer-bob',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
          text: 'Needs strict schema',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
      );
      await db.execute('DROP TABLE post_reactions');

      await expectLater(
        repository.deletePostCascade('post-missing-table'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('post_reactions'),
          ),
        ),
      );
    },
  );
}
