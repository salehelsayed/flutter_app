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
  final orderedPostIds = <String>[];
  for (final pinState in activePins) {
    if (!dismissedPostIds.contains(pinState.postId)) {
      orderedPostIds.add(pinState.postId);
    }
  }
  if (orderedPostIds.isEmpty) {
    return const <PostModel>[];
  }

  final postsById = <String, PostModel>{
    for (final post in await postRepo.loadPostsByIds(orderedPostIds))
      post.id: post,
  };
  final posts = <PostModel>[];
  for (final postId in orderedPostIds) {
    final post = postsById[postId];
    if (post != null) {
      posts.add(post);
    }
  }
  return hydratePostSurfaceItems(
    postRepo: postRepo,
    posts: posts,
    mediaFileManager: mediaFileManager,
    viewerPeerId: viewerPeerId,
  );
}
