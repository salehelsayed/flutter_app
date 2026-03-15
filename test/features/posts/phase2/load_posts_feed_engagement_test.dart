import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryPostRepository postRepo;

  setUp(() {
    postRepo = InMemoryPostRepository();
  });

  tearDown(() {
    postRepo.dispose();
  });

  test('enriches feed items with comment counts and active post hearts', () async {
    await postRepo.savePost(
      const PostModel(
        id: 'post-1',
        eventId: 'evt-post-1',
        senderPeerId: 'peer-alice',
        authorPeerId: 'peer-alice',
        authorUsername: 'Alice',
        text: 'Need a ladder',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: '2026-03-15T10:15:30.000Z',
        visibleAt: '2026-03-15T10:15:30.000Z',
        expiresAt: '2026-03-18T10:15:30.000Z',
      ),
    );
    await postRepo.saveComment(
      const PostCommentModel(
        id: 'comment-1',
        eventId: 'evt-comment-1',
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        body: 'I can lend one.',
        commentedAt: '2026-03-15T11:00:00.000Z',
      ),
    );
    await postRepo.saveComment(
      const PostCommentModel(
        id: 'comment-2',
        eventId: 'evt-comment-2',
        postId: 'post-1',
        senderPeerId: 'peer-cara',
        body: 'I have one too.',
        commentedAt: '2026-03-15T11:05:00.000Z',
      ),
    );
    await postRepo.savePostReaction(
      const PostReactionModel(
        reactionId: 'post_heart:post-1:peer-bob',
        eventId: 'evt-reaction-1',
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        isActive: true,
        reactedAt: '2026-03-15T11:10:00.000Z',
      ),
    );
    await postRepo.savePostReaction(
      const PostReactionModel(
        reactionId: 'post_heart:post-1:peer-cara',
        eventId: 'evt-reaction-2',
        postId: 'post-1',
        senderPeerId: 'peer-cara',
        isActive: false,
        reactedAt: '2026-03-15T11:11:00.000Z',
      ),
    );

    final feed = await loadPostsFeed(
      postRepo: postRepo,
      viewerPeerId: 'peer-bob',
    );

    expect(feed.single.commentCount, 2);
    expect(feed.single.heartCount, 1);
    expect(feed.single.viewerHasHearted, isTrue);
  });
}
