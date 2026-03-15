import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<PostCommentModel>> loadPostComments({
  required PostRepository postRepo,
  required String postId,
  String? viewerPeerId,
}) async {
  final comments = await postRepo.loadComments(postId);
  return Future.wait(
    comments.map((comment) async {
      final reactions = await postRepo.loadCommentReactions(comment.id);
      final activeHeartCount = reactions.where((reaction) => reaction.isActive).length;
      final viewerHasHearted =
          viewerPeerId != null &&
          reactions.any(
            (reaction) =>
                reaction.senderPeerId == viewerPeerId && reaction.isActive,
          );
      return comment.copyWith(
        heartCount: activeHeartCount,
        viewerHasHearted: viewerHasHearted,
      );
    }),
  );
}
