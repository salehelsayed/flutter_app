import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_envelope.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum SendPostCommentReactionResult {
  success,
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
  final didSend = await fanoutPostEngagementEnvelope(
    p2pService: p2pService,
    recipients: recipients,
    envelope: envelope,
  );
  if (!didSend) {
    return (SendPostCommentReactionResult.sendFailed, null);
  }

  await postRepo.saveCommentReaction(reaction);
  return (SendPostCommentReactionResult.success, reaction);
}
