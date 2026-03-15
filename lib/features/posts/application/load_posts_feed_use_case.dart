import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/application/post_surface_hydrator.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<PostModel>> loadPostsFeed({
  required PostRepository postRepo,
  MediaFileManager? mediaFileManager,
  String? viewerPeerId,
  DateTime Function()? nowProvider,
}) async {
  final posts = await postRepo.loadFeed();
  if (posts.isEmpty) {
    return const <PostModel>[];
  }
  final now = (nowProvider ?? DateTime.now).call().toUtc();
  final visiblePosts = posts.where(
    (post) => !_shouldHideFromNormalFeed(post, now),
  );
  return hydratePostSurfaceItems(
    postRepo: postRepo,
    posts: visiblePosts,
    mediaFileManager: mediaFileManager,
    viewerPeerId: viewerPeerId,
  );
}

bool _shouldHideFromNormalFeed(PostModel post, DateTime now) {
  if (!post.keepAvailable) {
    return false;
  }
  final createdAt = DateTime.tryParse(post.createdAt)?.toUtc();
  if (createdAt == null) {
    return false;
  }
  return !now.isBefore(createdAt.add(const Duration(hours: 24)));
}
