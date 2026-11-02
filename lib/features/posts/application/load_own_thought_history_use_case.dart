import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/application/post_surface_hydrator.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

/// The author's expired history with the same media hydration as the live feed.
Future<List<PostModel>> loadOwnThoughtHistory({
  required PostRepository postRepo,
  MediaFileManager? mediaFileManager,
  String? viewerPeerId,
  DateTime Function()? nowProvider,
}) async {
  final now = (nowProvider ?? DateTime.now)().toUtc();
  final posts = await postRepo.loadExpiredOwnPosts(now.toIso8601String());
  return hydratePostSurfaceItems(
    postRepo: postRepo,
    posts: posts,
    mediaFileManager: mediaFileManager,
    viewerPeerId: viewerPeerId,
  );
}
