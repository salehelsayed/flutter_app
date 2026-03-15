import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/refresh_post_expiry_for_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum SendPostCommentResult {
  success,
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

  final didSend = await fanoutPostEngagementEnvelope(
    p2pService: p2pService,
    recipients: recipients,
    envelope: envelope,
  );
  if (!didSend) {
    return (SendPostCommentResult.sendFailed, null);
  }

  await postRepo.saveComment(comment);
  await refreshPostExpiryForComment(
    postRepo: postRepo,
    postId: postId,
    commentedAt: commentedAt,
  );
  return (SendPostCommentResult.success, comment);
}
