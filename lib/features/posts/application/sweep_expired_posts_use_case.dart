import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<String>> sweepExpiredPosts({
  required PostRepository postRepo,
  required MediaFileManager mediaFileManager,
  DateTime Function()? nowProvider,
}) async {
  final nowIso = (nowProvider ?? DateTime.now).call().toUtc().toIso8601String();
  final expiredPosts = await postRepo.loadExpiredPosts(nowIso);
  final deletedPostIds = <String>[];

  for (final post in expiredPosts) {
    // One post that cannot be deleted must not keep every later one alive.
    try {
      await mediaFileManager.deleteMediaForPost(post.id);
      await postRepo.deletePostCascade(post.id);
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
