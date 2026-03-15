import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<PostModel>> loadPostsFeed({
  required PostRepository postRepo,
  MediaFileManager? mediaFileManager,
  String? viewerPeerId,
}) async {
  final posts = await postRepo.loadFeed();
  if (posts.isEmpty) {
    return const <PostModel>[];
  }

  final mediaMap = await postRepo.loadPostMediaAttachmentsForPosts(
    posts.map((post) => post.id).toList(growable: false),
  );

  return Future.wait(
    posts.map((post) async {
      final comments = await postRepo.loadComments(post.id);
      final reactions = await postRepo.loadPostReactions(post.id);
      final activeHeartCount = reactions.where((reaction) => reaction.isActive).length;
      final viewerHasHearted =
          viewerPeerId != null &&
          reactions.any(
            (reaction) =>
                reaction.senderPeerId == viewerPeerId && reaction.isActive,
          );
      final attachments =
          mediaMap[post.id] ?? const <PostMediaAttachmentModel>[];
      if (attachments.isEmpty) {
        return post.copyWith(
          commentCount: comments.length,
          heartCount: activeHeartCount,
          viewerHasHearted: viewerHasHearted,
        );
      }
      final resolvedAttachments = <PostMediaAttachmentModel>[];
      for (final attachment in attachments) {
        if (attachment.localPath != null && mediaFileManager != null) {
          resolvedAttachments.add(
            attachment.copyWith(
              localPath: await mediaFileManager.resolveStoredPath(
                attachment.localPath!,
              ),
            ),
          );
        } else {
          resolvedAttachments.add(attachment);
        }
      }
      return post.copyWith(
        mediaKind: post.mediaKind == 'none'
            ? PostMediaAttachmentModel.deriveMediaKind(resolvedAttachments)
            : post.mediaKind,
        media: resolvedAttachments,
        commentCount: comments.length,
        heartCount: activeHeartCount,
        viewerHasHearted: viewerHasHearted,
      );
    }),
  );
}
