import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_passes_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/040_posts_repost_visual_metrics.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late PostRepositoryImpl repository;
  late int postPassLoadCount;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsPassAlongMigration(db);
    await runPostsRepostEngagementStateMigration(db);
    await runPostsRepostVisualMetricsMigration(db);
    postPassLoadCount = 0;
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
      dbLoadPostPasses: (postId) async {
        postPassLoadCount++;
        return dbLoadPostPasses(db, postId);
      },
      dbLoadViewerSharedToCountsForPosts: (postIds, viewerPeerId) =>
          dbLoadViewerSharedToCountsForPosts(db, postIds, viewerPeerId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      dbInsertPostComment: (row) async {},
      dbLoadPostComments: (postId) async => const <Map<String, Object?>>[],
      dbLoadPostReactions: (postId) async => const <Map<String, Object?>>[],
      dbLoadPostMediaForPosts: (postIds) async => const <Map<String, Object?>>[],
      dbLoadRepostHeartBaselinePeersForPosts: (postIds) async =>
          const <Map<String, Object?>>[],
      dbLoadPassAvatarSnapshotsForPosts: (postIds) async =>
          <String, List<int>>{},
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  test(
    'loadPostsFeed uses query-layer viewer repost metrics instead of loading post passes',
    () async {
      await dbInsertPost(
        db,
        const PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-bob',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
          text: 'Need a ladder',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ).toMap(),
      );
      await dbUpsertPostPass(
        db,
        const PostPassModel(
          passId: 'pass-1',
          eventId: 'evt-pass-1',
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          passerPeerId: 'peer-alice',
          passerUsername: 'Alice',
          passedAt: '2026-03-15T11:15:00.000Z',
          createdAt: '2026-03-15T11:15:00.000Z',
          isIncoming: false,
          recipientCount: 3,
        ).toMap(),
      );

      final feed = await loadPostsFeed(
        postRepo: repository,
        viewerPeerId: 'peer-alice',
      );

      expect(postPassLoadCount, 0);
      expect(feed, hasLength(1));
      expect(feed.single.shareCount, 1);
      expect(feed.single.totalSharedToCount, 3);
      expect(feed.single.viewerSharedToCount, 3);
      expect(feed.single.viewerHasPassed, isTrue);
    },
  );
}
