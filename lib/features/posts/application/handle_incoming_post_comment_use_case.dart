import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/post_repost_engagement_support.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pending_child_event.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/application/refresh_post_expiry_for_comment_use_case.dart';

enum HandleIncomingPostCommentResult {
  commentCreated,
  stagedPendingParent,
  notPostComment,
  unknownSender,
  blockedSender,
  duplicate,
}

Future<(HandleIncomingPostCommentResult, PostCommentModel?)>
handleIncomingPostComment({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  bool allowStaging = true,
}) async {
  final envelope = PostCommentEnvelope.fromJson(message.content);
  if (envelope == null) {
    return (HandleIncomingPostCommentResult.notPostComment, null);
  }
  if (envelope.senderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_COMMENT_SENDER_MISMATCH',
      details: {
        'transportSender': message.from,
        'payloadSender': envelope.senderPeerId,
      },
    );
    return (HandleIncomingPostCommentResult.notPostComment, null);
  }

  final sender = await contactRepo.getContact(envelope.senderPeerId);
  final trustedParticipant = sender == null
      ? await isTrustedRepostThreadParticipant(
          postRepo: postRepo,
          postId: envelope.postId,
          participantPeerId: envelope.senderPeerId,
        )
      : false;
  if (sender == null && !trustedParticipant) {
    return (HandleIncomingPostCommentResult.unknownSender, null);
  }
  if (sender?.isBlocked ?? false) {
    return (HandleIncomingPostCommentResult.blockedSender, null);
  }
  if (await postRepo.commentExists(envelope.commentId)) {
    return (HandleIncomingPostCommentResult.duplicate, null);
  }

  final parent = await postRepo.getPost(envelope.postId);
  if (parent == null) {
    if (!allowStaging) {
      return (HandleIncomingPostCommentResult.notPostComment, null);
    }
    await postRepo.stagePendingChildEvent(
      PostPendingChildEvent(
        postId: envelope.postId,
        eventId: envelope.eventId,
        eventType: 'post_comment',
        senderPeerId: envelope.senderPeerId,
        createdAt: envelope.createdAt,
        rawEnvelope: message.content,
      ),
    );
    return (HandleIncomingPostCommentResult.stagedPendingParent, null);
  }

  await persistRepostEngagementParticipantIfNeeded(
    postRepo: postRepo,
    postId: envelope.postId,
    participantPeerId: envelope.senderPeerId,
    createdAt: envelope.commentedAt,
  );
  final authorUsername = sender?.username ?? envelope.senderPeerId;
  final comment = PostCommentModel(
    id: envelope.commentId,
    eventId: envelope.eventId,
    postId: envelope.postId,
    senderPeerId: envelope.senderPeerId,
    authorUsername: authorUsername,
    body: envelope.body,
    commentedAt: envelope.commentedAt,
  );
  await postRepo.saveComment(comment);
  await refreshPostExpiryForComment(
    postRepo: postRepo,
    postId: envelope.postId,
    commentedAt: envelope.commentedAt,
  );
  return (HandleIncomingPostCommentResult.commentCreated, comment);
}
