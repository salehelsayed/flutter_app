import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/application/post_surface_hydrator.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<PostModel>> loadPinnedPosts({
  required PostRepository postRepo,
  MediaFileManager? mediaFileManager,
  String? viewerPeerId,
}) async {
  final activePins = await postRepo.loadActivePinStates();
  if (activePins.isEmpty) {
    return const <PostModel>[];
  }
  final dismissedPostIds = await postRepo.loadDismissedPinPostIds();
  final posts = <PostModel>[];
  for (final pinState in activePins) {
    if (dismissedPostIds.contains(pinState.postId)) {
      continue;
    }
    final post = await postRepo.getPost(pinState.postId);
    if (post == null) {
      continue;
    }
    posts.add(post);
  }
  return hydratePostSurfaceItems(
    postRepo: postRepo,
    posts: posts,
    mediaFileManager: mediaFileManager,
    viewerPeerId: viewerPeerId,
  );
}
