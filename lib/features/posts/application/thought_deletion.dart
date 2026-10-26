import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

/// Removes a thought's media files and every row that belongs to it.
///
/// Expiry, the author's retraction and replacement by the author's newer
/// thought all leave through here, so a thought is never gone from one store
/// and left in the other. Deleting the rows emits `postChanges`, which the
/// orbit and the expiry scheduler listen to.
Future<void> deleteStoredThought({
  required PostRepository postRepo,
  required MediaFileManager? mediaFileManager,
  required String postId,
}) async {
  await mediaFileManager?.deleteMediaForPost(postId);
  await postRepo.deletePostCascade(postId);
}

/// The thoughts stored here by [authorPeerId] other than [exceptPostId]: the
/// friend's copies when [incoming], else the user's own.
Future<List<PostModel>> otherThoughtsBy(
  PostRepository postRepo, {
  required String authorPeerId,
  required bool incoming,
  required String exceptPostId,
}) async => [
  for (final post in await postRepo.loadFeed())
    if (post.isIncoming == incoming &&
        post.authorPeerId == authorPeerId &&
        post.id != exceptPostId)
      post,
];

/// Match the orbit's newest-thought ordering, including equal creation times.
/// A stored row with an unreadable time never wins and never blocks.
bool isNewerThought(PostModel candidate, PostModel previous) {
  final candidateAt = DateTime.tryParse(candidate.createdAt);
  if (candidateAt == null) return false;
  final previousAt = DateTime.tryParse(previous.createdAt);
  if (previousAt == null) return true;
  final byCreatedAt = candidateAt.compareTo(previousAt);
  return byCreatedAt > 0 ||
      (byCreatedAt == 0 && candidate.id.compareTo(previous.id) < 0);
}

/// One live thought per author: the [replacement] takes the author's
/// older [thoughts] with it, so deleting it later cannot bring one of them
/// back. A thought that cannot be removed is logged and does not keep the new
/// one out; the expiry sweep gets another run at it within 24 h.
Future<void> deleteReplacedThoughts({
  required PostRepository postRepo,
  required MediaFileManager? mediaFileManager,
  required Iterable<PostModel> thoughts,
  required PostModel replacement,
}) async {
  for (final thought in thoughts) {
    if (!isNewerThought(replacement, thought)) continue;
    try {
      await deleteStoredThought(
        postRepo: postRepo,
        mediaFileManager: mediaFileManager,
        postId: thought.id,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_REPLACED_OLDER',
        details: {'postId': thought.id, 'replacedBy': replacement.id},
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_REPLACE_OLDER_ERROR',
        details: {
          'postId': thought.id,
          'errorType': error.runtimeType.toString(),
        },
      );
    }
  }
}
