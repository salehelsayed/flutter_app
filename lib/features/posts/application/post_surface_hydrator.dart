import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/application/nearby_eligibility_service.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<PostModel>> hydratePostSurfaceItems({
  required PostRepository postRepo,
  required Iterable<PostModel> posts,
  MediaFileManager? mediaFileManager,
  String? viewerPeerId,
}) async {
  final postList = posts.toList(growable: false);
  if (postList.isEmpty) {
    return const <PostModel>[];
  }

  final mediaMap = await postRepo.loadPostMediaAttachmentsForPosts(
    postList.map((post) => post.id).toList(growable: false),
  );

  return Future.wait(
    postList.map((post) async {
      final comments = await postRepo.loadComments(post.id);
      final reactions = await postRepo.loadPostReactions(post.id);
      final activeHeartCount = reactions
          .where((reaction) => reaction.isActive)
          .length;
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
          nearbyDistanceLabel:
              post.audience.kind == PostAudienceKind.peopleNearby &&
                  post.nearbyDistanceM != null
              ? formatNearbyDistanceLabel(post.nearbyDistanceM!)
              : null,
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
        nearbyDistanceLabel:
            post.audience.kind == PostAudienceKind.peopleNearby &&
                post.nearbyDistanceM != null
            ? formatNearbyDistanceLabel(post.nearbyDistanceM!)
            : null,
      );
    }),
  );
}
