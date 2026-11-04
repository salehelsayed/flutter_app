import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/thought_tags.dart';
import 'package:flutter_app/features/posts/application/post_surface_hydrator.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

/// The author's newest [historyLimit] expired Thoughts with the same media
/// hydration as the live feed.
Future<List<PostModel>> loadOwnThoughtHistory({
  required PostRepository postRepo,
  required int historyLimit,
  MediaFileManager? mediaFileManager,
  String? viewerPeerId,
  DateTime Function()? nowProvider,
}) async {
  final now = (nowProvider ?? DateTime.now)().toUtc();
  final posts = await postRepo.loadExpiredOwnPosts(
    now.toIso8601String(),
    limit: historyLimit,
  );
  return hydratePostSurfaceItems(
    postRepo: postRepo,
    posts: posts,
    mediaFileManager: mediaFileManager,
    viewerPeerId: viewerPeerId,
  );
}

/// Rows read per query while a tag is counted.
const _tagScanPage = 200;

/// The author's newest [historyLimit] expired Thoughts with the tag key
/// [tag], hydrated as above, and how many carry it in all. The history is
/// read a page at a time; only the shown Thoughts are hydrated.
Future<({List<PostModel> posts, int count})> loadOwnTaggedThoughtHistory({
  required PostRepository postRepo,
  required int historyLimit,
  required String tag,
  MediaFileManager? mediaFileManager,
  String? viewerPeerId,
  DateTime Function()? nowProvider,
}) async {
  final now = (nowProvider ?? DateTime.now)().toUtc().toIso8601String();
  final tagged = <PostModel>[];
  var count = 0;
  for (var offset = 0; ; offset += _tagScanPage) {
    final posts = await postRepo.loadExpiredOwnPosts(
      now,
      limit: _tagScanPage,
      offset: offset,
    );
    for (final post in posts) {
      if (!hasThoughtTag(post.text, tag)) continue;
      count++;
      if (tagged.length < historyLimit) tagged.add(post);
    }
    if (posts.length < _tagScanPage) break;
  }
  return (
    posts: await hydratePostSurfaceItems(
      postRepo: postRepo,
      posts: tagged,
      mediaFileManager: mediaFileManager,
      viewerPeerId: viewerPeerId,
    ),
    count: count,
  );
}
