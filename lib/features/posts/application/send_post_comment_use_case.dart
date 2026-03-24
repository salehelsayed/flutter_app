import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_engagement_follow_on_support.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/post_repost_engagement_support.dart';
import 'package:flutter_app/features/posts/application/refresh_post_expiry_for_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum SendPostCommentResult {
  success,
  partiallySettled,
  queuedForRetry,
  nodeNotRunning,
  postNotFound,
  invalidComment,
  noEligibleRecipients,
  sendFailed,
}

class CreatedLocalPostComment {
  final PostCommentModel comment;
  final String envelope;
  final int recipientCount;

  const CreatedLocalPostComment({
    required this.comment,
    required this.envelope,
    required this.recipientCount,
  });
}

Future<(SendPostCommentResult, PostCommentModel?)> sendPostComment({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String senderPeerId,
  required String senderUsername,
  required String body,
  DateTime Function()? nowProvider,
  int maxConcurrentRecipients = defaultPostCommentDeliveryConcurrency,
}) async {
  final (createResult, created) = await createLocalPostComment(
    p2pService: p2pService,
    postRepo: postRepo,
    contactRepo: contactRepo,
    postId: postId,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    body: body,
    nowProvider: nowProvider,
  );
  if (createResult != SendPostCommentResult.success || created == null) {
    return (createResult, created?.comment);
  }

  final deliveryResult = await deliverCreatedLocalPostComment(
    p2pService: p2pService,
    postRepo: postRepo,
    created: created,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
  return (
    _sendPostCommentResultForSettlement(deliveryResult.settlement),
    created.comment,
  );
}

Future<(SendPostCommentResult, CreatedLocalPostComment?)>
createLocalPostComment({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String senderPeerId,
  required String senderUsername,
  required String body,
  DateTime Function()? nowProvider,
}) async {
  final sanitizedBody = sanitizeMessageText(body);
  if (sanitizedBody.trim().isEmpty) {
    return (SendPostCommentResult.invalidComment, null);
  }
  if (!p2pService.currentState.isStarted) {
    return (SendPostCommentResult.nodeNotRunning, null);
  }

  final post = await postRepo.getPost(postId);
  if (post == null) {
    return (SendPostCommentResult.postNotFound, null);
  }
  final recipients = await resolvePostEngagementRecipients(
    postRepo: postRepo,
    contactRepo: contactRepo,
    postId: postId,
    authorPeerId: post.authorPeerId,
    senderPeerId: senderPeerId,
  );
  if (recipients.isEmpty) {
    return (SendPostCommentResult.noEligibleRecipients, null);
  }

  final now = (nowProvider ?? DateTime.now).call().toUtc();
  final commentedAt = now.toIso8601String();
  final comment = PostCommentModel(
    id: 'comment_${_uuid.v4()}',
    eventId: 'evt_${_uuid.v4()}',
    postId: postId,
    senderPeerId: senderPeerId,
    authorUsername: senderUsername,
    body: sanitizedBody,
    commentedAt: commentedAt,
    isIncoming: false,
  );

  final envelope = PostCommentEnvelope(
    eventId: comment.eventId,
    createdAt: commentedAt,
    senderPeerId: senderPeerId,
    commentId: comment.id,
    postId: postId,
    body: sanitizedBody,
    commentedAt: commentedAt,
  ).toJson();
  await postRepo.saveComment(comment);
  await persistRepostEngagementParticipantIfNeeded(
    postRepo: postRepo,
    postId: postId,
    participantPeerId: senderPeerId,
    createdAt: commentedAt,
  );
  await refreshPostExpiryForComment(
    postRepo: postRepo,
    postId: postId,
    commentedAt: commentedAt,
  );
  await queuePostEngagementFollowOn(
    postRepo: postRepo,
    eventId: comment.eventId,
    eventType: postCommentFollowOnEventType,
    postId: postId,
    commentId: comment.id,
    senderPeerId: senderPeerId,
    envelope: envelope,
    createdAt: commentedAt,
    recipientPeerIds: recipients,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_COMMENT_LOCAL_PERSISTED',
    details: {
      'postId': postId,
      'commentId': comment.id,
      'recipientCount': recipients.length,
    },
  );
  return (
    SendPostCommentResult.success,
    CreatedLocalPostComment(
      comment: comment,
      envelope: envelope,
      recipientCount: recipients.length,
    ),
  );
}

Future<PostFollowOnDeliveryResult> deliverCreatedLocalPostComment({
  required P2PService p2pService,
  required PostRepository postRepo,
  required CreatedLocalPostComment created,
  int maxConcurrentRecipients = defaultPostCommentDeliveryConcurrency,
}) async {
  final deliveryResult = await deliverQueuedPostEngagementFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: created.comment.eventId,
    envelope: created.envelope,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
  final directCount = deliveryResult.recipientResults
      .where(
        (result) =>
            result.deliveryPath == 'direct' &&
            result.deliveryStatus == 'delivered',
      )
      .length;
  final inboxCount = deliveryResult.recipientResults
      .where(
        (result) =>
            result.deliveryPath == 'inbox' && result.deliveryStatus == 'inbox',
      )
      .length;
  final failedCount = deliveryResult.recipientResults
      .where((result) => result.deliveryStatus == 'failed')
      .length;
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_COMMENT_DELIVERY_RESULT',
    details: {
      'postId': created.comment.postId,
      'commentId': created.comment.id,
      'recipientCount': created.recipientCount,
      'settlement': deliveryResult.settlement.name,
      'directCount': directCount,
      'inboxCount': inboxCount,
      'failedCount': failedCount,
    },
  );
  return deliveryResult;
}

SendPostCommentResult _sendPostCommentResultForSettlement(
  PostFollowOnSettlement settlement,
) {
  return switch (settlement) {
    PostFollowOnSettlement.fullySettled => SendPostCommentResult.success,
    PostFollowOnSettlement.partiallySettled =>
      SendPostCommentResult.partiallySettled,
    PostFollowOnSettlement.notSettled => SendPostCommentResult.queuedForRetry,
  };
}
