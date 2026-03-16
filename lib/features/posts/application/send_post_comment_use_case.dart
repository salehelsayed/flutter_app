import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_engagement_follow_on_support.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
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

Future<(SendPostCommentResult, PostCommentModel?)> sendPostComment({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String senderPeerId,
  required String senderUsername,
  required String body,
  DateTime Function()? nowProvider,
  int maxConcurrentRecipients = defaultPostFollowOnDeliveryConcurrency,
}) async {
  final trimmedBody = body.trim();
  if (trimmedBody.isEmpty) {
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
    body: trimmedBody,
    commentedAt: commentedAt,
    isIncoming: false,
  );

  final envelope = PostCommentEnvelope(
    eventId: comment.eventId,
    createdAt: commentedAt,
    senderPeerId: senderPeerId,
    commentId: comment.id,
    postId: postId,
    body: trimmedBody,
    commentedAt: commentedAt,
  ).toJson();
  await postRepo.saveComment(comment);
  await refreshPostExpiryForComment(
    postRepo: postRepo,
    postId: postId,
    commentedAt: commentedAt,
  );
  final deliveryResult = await queueAndSendPostEngagementFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: comment.eventId,
    eventType: postCommentFollowOnEventType,
    postId: postId,
    commentId: comment.id,
    senderPeerId: senderPeerId,
    envelope: envelope,
    createdAt: commentedAt,
    recipientPeerIds: recipients.map((recipient) => recipient.peerId),
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
  return (
    _sendPostCommentResultForSettlement(deliveryResult.settlement),
    comment,
  );
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
