import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/posts/application/thought_deletion.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<String>> sweepExpiredPosts({
  required PostRepository postRepo,
  required MediaFileManager mediaFileManager,
  DateTime Function()? nowProvider,
  void Function(String postId)? onExpiredKept,
}) async {
  final now = (nowProvider ?? DateTime.now).call().toUtc();
  final deleteBefore = now.subtract(ThoughtLifetime.deleteGrace);
  final expiredPosts = await postRepo.loadExpiredPosts(now.toIso8601String());
  final deletedPostIds = <String>[];

  for (final post in expiredPosts) {
    if (!post.isIncoming) continue;
    final expiresAt = DateTime.tryParse(post.expiresAt)?.toUtc();
    if (expiresAt != null && expiresAt.isAfter(deleteBefore)) {
      onExpiredKept?.call(post.id);
      continue;
    }
    // One post that cannot be deleted must not keep every later one alive.
    try {
      await deleteStoredThought(
        postRepo: postRepo,
        mediaFileManager: mediaFileManager,
        postId: post.id,
      );
      deletedPostIds.add(post.id);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_EXPIRY_SWEEP_POST_ERROR',
        details: {'postId': post.id, 'errorType': error.runtimeType.toString()},
      );
    }
  }

  return deletedPostIds;
}
