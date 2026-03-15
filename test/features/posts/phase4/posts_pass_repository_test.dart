import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_origin_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_passes_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
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
    await runPostsNearbyMigration(db);
    await runPostsPassAlongMigration(db);
    repository = PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (postId) => dbLoadPost(db, postId),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) =>
          dbLoadPostRecipientDeliveries(db, postId),
      dbUpsertPostPass: (row) => dbUpsertPostPass(db, row),
      dbLoadPostPass: (passId) => dbLoadPostPass(db, passId),
      dbLoadPostPasses: (postId) => dbLoadPostPasses(db, postId),
      dbCountPostPasses: (postId) => dbCountPostPasses(db, postId),
      dbLoadPostPassCounts: (postIds) => dbLoadPostPassCounts(db, postIds),
      dbUpsertPostOrigin: (row) => dbUpsertPostOrigin(db, row),
      dbLoadPostOrigin: (postId) => dbLoadPostOrigin(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  test('persists stable pass attribution and share counts', () async {
    await repository.savePost(
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
      ),
    );
    await repository.savePostOrigin(
      const PostOriginModel(
        postId: 'post-1',
        originKind: PostOriginKind.pass,
        passId: 'pass-1',
        passerPeerId: 'peer-alice',
        passerUsername: 'Alice',
        passCreatedAt: '2026-03-15T11:15:00.000Z',
      ),
    );
    await repository.savePostPass(
      const PostPassModel(
        passId: 'pass-1',
        eventId: 'evt-pass-1',
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        passerPeerId: 'peer-alice',
        passerUsername: 'Alice',
        passedAt: '2026-03-15T11:15:00.000Z',
        createdAt: '2026-03-15T11:15:00.000Z',
      ),
    );
    await repository.savePostPass(
      const PostPassModel(
        passId: 'pass-2',
        eventId: 'evt-pass-2',
        postId: 'post-1',
        senderPeerId: 'peer-james',
        passerPeerId: 'peer-james',
        passerUsername: 'James',
        passedAt: '2026-03-15T11:20:00.000Z',
        createdAt: '2026-03-15T11:20:00.000Z',
      ),
    );

    final loaded = await repository.getPost('post-1');
    final counts = await repository.loadPostPassCounts(const <String>[
      'post-1',
    ]);
    final origin = await repository.getPostOrigin('post-1');

    expect(loaded, isNotNull);
    expect(loaded!.passedByUsername, 'Alice');
    expect(loaded.shareCount, 2);
    expect(counts['post-1'], 2);
    expect(origin?.passerUsername, 'Alice');
    expect(await repository.postPassExists('pass-2'), isTrue);
  });
}
