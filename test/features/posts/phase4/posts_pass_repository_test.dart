import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_origin_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_passes_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_repost_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/036_posts_pass_encrypted_snapshots.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/039_posts_pass_avatar_snapshots.dart';
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
    await runPostsPassEncryptedSnapshotsMigration(db);
    await runPostsRepostEngagementStateMigration(db);
    await runPostsPassAvatarSnapshotsMigration(db);
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
      dbUpsertRepostEngagementParticipant: (row) =>
          dbUpsertPostRepostEngagementParticipant(db, row),
      dbLoadRepostEngagementParticipants: (postId) =>
          dbLoadPostRepostEngagementParticipants(db, postId),
      dbUpsertRepostHeartBaselinePeer: (row) =>
          dbUpsertPostRepostHeartBaselinePeer(db, row),
      dbLoadRepostHeartBaselinePeers: (postId) =>
          dbLoadPostRepostHeartBaselinePeers(db, postId),
      dbLoadRepostHeartBaselinePeersForPosts: (postIds) =>
          dbLoadPostRepostHeartBaselinePeersForPosts(db, postIds),
      dbInsertRepostProjectionState: (row) =>
          dbInsertPostRepostProjectionState(db, row),
      dbLoadRepostProjectionState: (postId) =>
          dbLoadPostRepostProjectionState(db, postId),
      dbLoadRepostProjectionStates: (postIds) =>
          dbLoadPostRepostProjectionStates(db, postIds),
      dbUpsertPostOrigin: (row) => dbUpsertPostOrigin(db, row),
      dbLoadPostOrigin: (postId) => dbLoadPostOrigin(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
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

  test(
    'persists encrypted repost inner payload snapshots for retry rebuilds',
    () async {
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
          isIncoming: false,
          innerPayloadJson:
              '{"pass_id":"pass-1","participant_peer_ids":["peer-alice","peer-bob"],"heart_baseline":{"active_peer_ids":["peer-zoya"]},"repost_total_baseline":2}',
        ),
      );

      final loaded = (await repository.loadPostPasses('post-1')).single;

      expect(loaded.innerPayloadJson, isNotNull);
      expect(loaded.innerPayloadJson, contains('"participant_peer_ids"'));
      expect(loaded.innerPayloadJson, contains('"heart_baseline"'));
      expect(loaded.innerPayloadJson, contains('"repost_total_baseline":2'));
    },
  );

  test(
    'persists repost participant state, heart baselines, and projected share baselines',
    () async {
      await repository.savePost(
        const PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-hisam',
          authorPeerId: 'peer-solz',
          authorUsername: 'Solz',
          text: 'Need a ladder',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T11:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
      );
      await repository.savePostPass(
        const PostPassModel(
          passId: 'pass-1',
          eventId: 'evt-pass-1',
          postId: 'post-1',
          senderPeerId: 'peer-hisam',
          passerPeerId: 'peer-hisam',
          passerUsername: 'Hisam',
          passedAt: '2026-03-15T11:15:30.000Z',
          createdAt: '2026-03-15T11:15:30.000Z',
        ),
      );

      await repository.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-solz',
        createdAt: '2026-03-15T11:15:30.000Z',
      );
      await repository.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-hisam',
        createdAt: '2026-03-15T11:15:30.000Z',
      );
      await repository.saveRepostHeartBaselinePeerIds(
        postId: 'post-1',
        peerIds: const <String>['peer-zoya'],
        createdAt: '2026-03-15T11:15:30.000Z',
      );
      await repository.seedRepostTotalBaseline(
        postId: 'post-1',
        repostTotalBaseline: 2,
        existingLocalPassCount: 1,
        createdAt: '2026-03-15T11:15:30.000Z',
      );

      expect(
        await repository.loadRepostEngagementParticipantPeerIds('post-1'),
        <String>{'peer-hisam', 'peer-solz'},
      );
      expect(
        await repository.loadRepostHeartBaselinePeerIds('post-1'),
        <String>{'peer-zoya'},
      );
      expect(await repository.loadRepostTotalBaseline('post-1'), 2);
      expect((await repository.getPost('post-1'))?.shareCount, 3);
    },
  );

  test('persists and loads avatar snapshot for a passed-along post', () async {
    final avatarBytes = Uint8List.fromList(<int>[1, 7, 9, 11]);

    await repository.savePassAvatarSnapshot(
      postId: 'post-1',
      authorPeerId: 'peer-solz',
      avatarBlob: avatarBytes,
      createdAt: '2026-03-15T11:15:30.000Z',
    );

    expect(await repository.loadPassAvatarSnapshot('post-1'), avatarBytes);
  });

  test('loadPassAvatarSnapshot returns null when no snapshot exists', () async {
    expect(await repository.loadPassAvatarSnapshot('post-1'), isNull);
  });

  test(
    'duplicate savePassAvatarSnapshot for the same postId does not corrupt stored bytes',
    () async {
      final initialAvatarBytes = Uint8List.fromList(<int>[5, 4, 3, 2]);

      await repository.savePassAvatarSnapshot(
        postId: 'post-1',
        authorPeerId: 'peer-solz',
        avatarBlob: initialAvatarBytes,
        createdAt: '2026-03-15T11:15:30.000Z',
      );
      await repository.savePassAvatarSnapshot(
        postId: 'post-1',
        authorPeerId: 'peer-solz',
        avatarBlob: Uint8List.fromList(<int>[9, 9, 9, 9]),
        createdAt: '2026-03-15T11:16:30.000Z',
      );

      expect(
        await repository.loadPassAvatarSnapshot('post-1'),
        initialAvatarBytes,
      );
    },
  );
}
