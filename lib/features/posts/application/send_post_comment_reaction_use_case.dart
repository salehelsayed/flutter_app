import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_engagement_follow_on_support.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/post_repost_engagement_support.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_envelope.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum SendPostCommentReactionResult {
  success,
  partiallySettled,
  queuedForRetry,
  nodeNotRunning,
  postNotFound,
  commentNotFound,
  noEligibleRecipients,
  sendFailed,
}

Future<(SendPostCommentReactionResult, PostCommentReactionModel?)>
sendPostCommentReaction({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String commentId,
  required String senderPeerId,
  required bool isActive,
  int maxConcurrentRecipients = defaultPostFollowOnDeliveryConcurrency,
}) async {
  if (!p2pService.currentState.isStarted) {
    return (SendPostCommentReactionResult.nodeNotRunning, null);
  }

  final post = await postRepo.getPost(postId);
  if (post == null) {
    return (SendPostCommentReactionResult.postNotFound, null);
  }
  final commentExists = (await postRepo.loadComments(
    postId,
  )).any((comment) => comment.id == commentId);
  if (!commentExists) {
    return (SendPostCommentReactionResult.commentNotFound, null);
  }

  final recipients = await resolvePostEngagementRecipients(
    postRepo: postRepo,
    contactRepo: contactRepo,
    postId: postId,
    authorPeerId: post.authorPeerId,
    senderPeerId: senderPeerId,
  );
  if (recipients.isEmpty) {
    return (SendPostCommentReactionResult.noEligibleRecipients, null);
  }

  final createdAt = DateTime.now().toUtc().toIso8601String();
  final reaction = PostCommentReactionModel(
    reactionId: 'comment_heart:$commentId:$senderPeerId',
    eventId: 'evt_${_uuid.v4()}',
    postId: postId,
    commentId: commentId,
    senderPeerId: senderPeerId,
    isActive: isActive,
    reactedAt: createdAt,
  );
  final envelope = PostReactionEnvelope.buildCommentReactionJson(
    eventId: reaction.eventId,
    createdAt: createdAt,
    senderPeerId: senderPeerId,
    postId: postId,
    commentId: commentId,
    isActive: isActive,
  );
  await postRepo.saveCommentReaction(reaction);
  await persistRepostEngagementParticipantIfNeeded(
    postRepo: postRepo,
    postId: postId,
    participantPeerId: senderPeerId,
    createdAt: createdAt,
  );
  final deliveryResult = await queueAndSendPostEngagementFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: reaction.eventId,
    eventType: postCommentReactionFollowOnEventType,
    postId: postId,
    commentId: commentId,
    senderPeerId: senderPeerId,
    envelope: envelope,
    createdAt: createdAt,
    recipientPeerIds: recipients,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
  return (
    _sendPostCommentReactionResultForSettlement(deliveryResult.settlement),
    reaction,
  );
}

SendPostCommentReactionResult _sendPostCommentReactionResultForSettlement(
  PostFollowOnSettlement settlement,
) {
  return switch (settlement) {
    PostFollowOnSettlement.fullySettled =>
      SendPostCommentReactionResult.success,
    PostFollowOnSettlement.partiallySettled =>
      SendPostCommentReactionResult.partiallySettled,
    PostFollowOnSettlement.notSettled =>
      SendPostCommentReactionResult.queuedForRetry,
  };
}
