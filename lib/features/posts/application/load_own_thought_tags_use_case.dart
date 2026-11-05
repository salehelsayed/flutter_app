import 'package:flutter_app/core/utils/thought_tags.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

/// One tag the author has used on their own Thoughts.
class OwnThoughtTag {
  const OwnThoughtTag({
    required this.key,
    required this.label,
    required this.lastUsed,
  });

  /// The lowercased word after '#': the same tag however it was written.
  final String key;

  /// The tag as last written, with its '#'.
  final String label;

  /// When the newest Thought carrying it was written.
  final DateTime lastUsed;
}

/// Rows read per query while the tags are gathered.
const _scanPage = 200;

/// Every tag on the author's own Thoughts, [live] and past, newest first.
/// Each keeps the spelling and time of the newest Thought that carries it.
Future<List<OwnThoughtTag>> loadOwnThoughtTags({
  required PostRepository postRepo,
  required PostModel? live,
  DateTime Function()? nowProvider,
}) async {
  final now = (nowProvider ?? DateTime.now)().toUtc().toIso8601String();
  final tags = <String, OwnThoughtTag>{};
  void take(PostModel post) {
    final at = DateTime.tryParse(post.createdAt)?.toUtc();
    if (post.isIncoming || at == null) return;
    for (final tag in parseThoughtTags(post.text)) {
      if (tags.containsKey(tag.key)) continue;
      tags[tag.key] = OwnThoughtTag(
        key: tag.key,
        label: post.text.substring(tag.start, tag.end),
        lastUsed: at,
      );
    }
  }

  if (live != null) take(live);
  for (var offset = 0; ; offset += _scanPage) {
    final posts = await postRepo.loadExpiredOwnPosts(
      now,
      limit: _scanPage,
      offset: offset,
    );
    posts.forEach(take);
    if (posts.length < _scanPage) break;
  }
  // Read newest first, so the map already holds the tags newest first, and
  // tags of one Thought keep their written order.
  return tags.values.toList(growable: false);
}
