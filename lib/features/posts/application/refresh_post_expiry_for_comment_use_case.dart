import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const Duration postCommentExpiryExtension = Duration(days: 3);

Future<PostModel?> refreshPostExpiryForComment({
  required PostRepository postRepo,
  required String postId,
  required String commentedAt,
}) async {
  final post = await postRepo.getPost(postId);
  if (post == null) {
    return null;
  }
  final timestamp = DateTime.tryParse(commentedAt)?.toUtc();
  if (timestamp == null) {
    return post;
  }

  final updatedPost = post.copyWith(
    expiresAt: timestamp.add(postCommentExpiryExtension).toIso8601String(),
    lastEngagementAt: commentedAt,
  );
  await postRepo.savePost(updatedPost);
  return updatedPost;
}
