import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/post_surface_hydrator.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryPostRepository posts;

  setUp(() {
    posts = InMemoryPostRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'hydrates totalSharedToCount for the original author from recipient totals rather than repost event count',
    () async {
      await posts.savePost(_post());
      await posts.savePostPass(
        const PostPassModel(
          passId: 'pass-1',
          eventId: 'evt-pass-1',
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          passerPeerId: 'peer-alice',
          passerUsername: 'Alice',
          passedAt: '2026-03-15T11:15:00.000Z',
          createdAt: '2026-03-15T11:15:00.000Z',
          recipientCount: 2,
        ),
      );
      await posts.savePostPass(
        const PostPassModel(
          passId: 'pass-2',
          eventId: 'evt-pass-2',
          postId: 'post-1',
          senderPeerId: 'peer-james',
          passerPeerId: 'peer-james',
          passerUsername: 'James',
          passedAt: '2026-03-15T11:20:00.000Z',
          createdAt: '2026-03-15T11:20:00.000Z',
          recipientCount: 3,
        ),
      );

      final surface = (await hydratePostSurfaceItems(
        postRepo: posts,
        posts: <PostModel>[(await posts.getPost('post-1'))!],
        viewerPeerId: 'peer-bob',
      )).single;

      expect(surface.shareCount, 2);
      expect(surface.totalSharedToCount, 5);
      expect(surface.viewerSharedToCount, 0);
      expect(surface.viewerHasPassed, isFalse);
    },
  );

  test(
    'hydrates viewer-local repost metrics from outgoing repost rows',
    () async {
      await posts.savePost(_post());
      await posts.savePostPass(
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
          recipientCount: 2,
        ),
      );
      await posts.savePostPass(
        const PostPassModel(
          passId: 'pass-2',
          eventId: 'evt-pass-2',
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          passerPeerId: 'peer-alice',
          passerUsername: 'Alice',
          passedAt: '2026-03-15T11:20:00.000Z',
          createdAt: '2026-03-15T11:20:00.000Z',
          isIncoming: false,
          recipientCount: 1,
        ),
      );
      await posts.savePostPass(
        const PostPassModel(
          passId: 'pass-3',
          eventId: 'evt-pass-3',
          postId: 'post-1',
          senderPeerId: 'peer-james',
          passerPeerId: 'peer-james',
          passerUsername: 'James',
          passedAt: '2026-03-15T11:25:00.000Z',
          createdAt: '2026-03-15T11:25:00.000Z',
          recipientCount: 4,
        ),
      );

      final surface = (await hydratePostSurfaceItems(
        postRepo: posts,
        posts: <PostModel>[(await posts.getPost('post-1'))!],
        viewerPeerId: 'peer-alice',
      )).single;

      expect(surface.totalSharedToCount, 7);
      expect(surface.viewerSharedToCount, 3);
      expect(surface.viewerHasPassed, isTrue);
    },
  );

  test(
    'keeps totalSharedToCount and viewer-local metrics readable for carried baselines and legacy recipient-count fallback',
    () async {
      await posts.savePost(
        _post(
          senderPeerId: 'peer-james',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
        ),
      );
      await posts.savePostPass(
        const PostPassModel(
          passId: 'pass-1',
          eventId: 'evt-pass-1',
          postId: 'post-1',
          senderPeerId: 'peer-james',
          passerPeerId: 'peer-james',
          passerUsername: 'James',
          passedAt: '2026-03-15T11:15:00.000Z',
          createdAt: '2026-03-15T11:15:00.000Z',
        ),
      );
      await posts.seedRepostSharedToBaseline(
        postId: 'post-1',
        sharedToCountBaseline: 4,
        existingLocalSharedToCount: 1,
        currentPassRecipientCount: 1,
        createdAt: '2026-03-15T11:15:00.000Z',
      );
      await posts.savePostPass(
        const PostPassModel(
          passId: 'pass-2',
          eventId: 'evt-pass-2',
          postId: 'post-1',
          senderPeerId: 'peer-cara',
          passerPeerId: 'peer-cara',
          passerUsername: 'Cara',
          passedAt: '2026-03-15T11:25:00.000Z',
          createdAt: '2026-03-15T11:25:00.000Z',
          isIncoming: false,
        ),
      );

      final surface = (await hydratePostSurfaceItems(
        postRepo: posts,
        posts: <PostModel>[(await posts.getPost('post-1'))!],
        viewerPeerId: 'peer-cara',
      )).single;

      expect(surface.totalSharedToCount, 6);
      expect(surface.viewerSharedToCount, 1);
      expect(surface.viewerHasPassed, isTrue);
    },
  );
}

PostModel _post({
  String senderPeerId = 'peer-bob',
  String authorPeerId = 'peer-bob',
  String authorUsername = 'Bob',
}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: senderPeerId,
    authorPeerId: authorPeerId,
    authorUsername: authorUsername,
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}
