import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pending_child_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';

abstract class PostRepository {
  Stream<String> get postChanges;

  Future<void> savePost(PostModel post);

  Future<PostModel?> getPost(String postId);

  Future<bool> postExists(String postId);

  Future<List<PostModel>> loadFeed();

  Future<List<PostModel>> loadExpiredPosts(String nowIso);

  Future<void> deletePostCascade(String postId);

  Future<void> saveComment(PostCommentModel comment);

  Future<List<PostCommentModel>> loadComments(String postId);

  Future<bool> commentExists(String commentId);

  Future<void> savePostReaction(PostReactionModel reaction);

  Future<PostReactionModel?> getPostReaction(String reactionId);

  Future<List<PostReactionModel>> loadPostReactions(String postId);

  Future<void> saveCommentReaction(PostCommentReactionModel reaction);

  Future<PostCommentReactionModel?> getCommentReaction(String reactionId);

  Future<List<PostCommentReactionModel>> loadCommentReactions(String commentId);

  Future<void> savePostMediaAttachment(PostMediaAttachmentModel attachment);

  Future<void> replacePostMediaAttachments(
    String postId,
    List<PostMediaAttachmentModel> attachments,
  );

  Future<List<PostMediaAttachmentModel>> loadPostMediaAttachments(
    String postId,
  );

  Future<Map<String, List<PostMediaAttachmentModel>>>
  loadPostMediaAttachmentsForPosts(List<String> postIds);

  Future<void> updatePostMediaLocalPath(String mediaId, String localPath);

  Future<void> updatePostMediaDownloadStatus(
    String mediaId,
    String downloadStatus,
  );

  Future<void> stagePendingChildEvent(PostPendingChildEvent event);

  Future<List<PostPendingChildEvent>> loadPendingChildEvents(String postId);

  Future<void> deletePendingChildEvent(String eventId);

  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery);

  Future<List<PostRecipientDelivery>> getRecipientDeliveries(String postId);

  Future<void> savePostPass(PostPassModel pass);

  Future<bool> postPassExists(String passId);

  Future<List<PostPassModel>> loadPostPasses(String postId);

  Future<int> loadPostPassCount(String postId);

  Future<Map<String, int>> loadPostPassCounts(List<String> postIds);

  Future<void> savePostOrigin(PostOriginModel origin);

  Future<PostOriginModel?> getPostOrigin(String postId);

  Future<void> savePostPinState(PostPinStateModel pinState);

  Future<PostPinStateModel?> getPostPinState(String postId);

  Future<List<PostPinStateModel>> loadActivePinStates();

  Future<void> savePinDismissal(String postId, String dismissedAt);

  Future<Set<String>> loadDismissedPinPostIds();

  Future<void> clearPinDismissal(String postId);

  Future<void> markFocused(String postId);

  void dispose();
}
