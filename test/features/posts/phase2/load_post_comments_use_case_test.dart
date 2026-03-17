import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/load_post_comments_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_reaction_model.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryPostRepository postRepo;

  setUp(() {
    postRepo = InMemoryPostRepository();
  });

  tearDown(() {
    postRepo.dispose();
  });

  test(
    'enriches comments with heart counts and the viewer heart state',
    () async {
      await postRepo.saveComment(
        const PostCommentModel(
          id: 'comment-1',
          eventId: 'evt-comment-1',
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          body: 'I can lend one.',
          commentedAt: '2026-03-15T11:00:00.000Z',
        ),
      );
      await postRepo.saveCommentReaction(
        const PostCommentReactionModel(
          reactionId: 'comment_heart:comment-1:peer-bob',
          eventId: 'evt-heart-1',
          postId: 'post-1',
          commentId: 'comment-1',
          senderPeerId: 'peer-bob',
          isActive: true,
          reactedAt: '2026-03-15T11:01:00.000Z',
        ),
      );
      await postRepo.saveCommentReaction(
        const PostCommentReactionModel(
          reactionId: 'comment_heart:comment-1:peer-cara',
          eventId: 'evt-heart-2',
          postId: 'post-1',
          commentId: 'comment-1',
          senderPeerId: 'peer-cara',
          isActive: false,
          reactedAt: '2026-03-15T11:02:00.000Z',
        ),
      );

      final comments = await loadPostComments(
        postRepo: postRepo,
        postId: 'post-1',
        viewerPeerId: 'peer-bob',
      );

      expect(comments.single.heartCount, 1);
      expect(comments.single.viewerHasHearted, isTrue);
    },
  );

  test(
    'keeps comments in chronological order while enriching heart state',
    () async {
      await postRepo.saveComment(
        const PostCommentModel(
          id: 'comment-2',
          eventId: 'evt-comment-2',
          postId: 'post-1',
          senderPeerId: 'peer-cara',
          body: 'I can drop it off after lunch.',
          commentedAt: '2026-03-15T11:05:00.000Z',
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
      await postRepo.saveCommentReaction(
        const PostCommentReactionModel(
          reactionId: 'comment_heart:comment-2:peer-bob',
          eventId: 'evt-heart-2',
          postId: 'post-1',
          commentId: 'comment-2',
          senderPeerId: 'peer-bob',
          isActive: true,
          reactedAt: '2026-03-15T11:06:00.000Z',
        ),
      );

      final comments = await loadPostComments(
        postRepo: postRepo,
        postId: 'post-1',
        viewerPeerId: 'peer-bob',
      );

      expect(comments.map((comment) => comment.id), <String>[
        'comment-1',
        'comment-2',
      ]);
      expect(comments.first.heartCount, 0);
      expect(comments.first.viewerHasHearted, isFalse);
      expect(comments.last.heartCount, 1);
      expect(comments.last.viewerHasHearted, isTrue);
    },
  );
}
