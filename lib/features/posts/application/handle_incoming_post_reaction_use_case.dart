import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pending_child_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

enum HandleIncomingPostReactionResult {
  reactionApplied,
  stagedPendingParent,
  notPostReaction,
  unknownSender,
  blockedSender,
  staleIgnored,
}

enum HandleIncomingPostCommentReactionResult {
  reactionApplied,
  stagedPendingParent,
  notPostCommentReaction,
  unknownSender,
  blockedSender,
  staleIgnored,
}

Future<(HandleIncomingPostReactionResult, PostReactionModel?)>
handleIncomingPostReaction({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  bool allowStaging = true,
}) async {
  final envelope = PostReactionEnvelope.fromJson(message.content);
  if (envelope == null || envelope.isCommentReaction) {
    return (HandleIncomingPostReactionResult.notPostReaction, null);
  }
  if (envelope.senderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_REACTION_SENDER_MISMATCH',
      details: {
        'transportSender': message.from,
        'payloadSender': envelope.senderPeerId,
      },
    );
    return (HandleIncomingPostReactionResult.notPostReaction, null);
  }

  final sender = await contactRepo.getContact(envelope.senderPeerId);
  if (sender == null) {
    return (HandleIncomingPostReactionResult.unknownSender, null);
  }
  if (sender.isBlocked) {
    return (HandleIncomingPostReactionResult.blockedSender, null);
  }

  final post = await postRepo.getPost(envelope.postId);
  if (post == null) {
    if (allowStaging) {
      await _stagePendingReaction(
        postRepo: postRepo,
        envelope: envelope,
        rawEnvelope: message.content,
      );
    }
    return (HandleIncomingPostReactionResult.stagedPendingParent, null);
  }

  final existing = await postRepo.getPostReaction(envelope.reactionId);
  if (_isIncomingEventStale(
    existingReactedAt: existing?.reactedAt,
    existingEventId: existing?.eventId,
    incomingReactedAt: envelope.reactedAt,
    incomingEventId: envelope.eventId,
  )) {
    return (HandleIncomingPostReactionResult.staleIgnored, existing);
  }

  final reaction = PostReactionModel(
    reactionId: envelope.reactionId,
    eventId: envelope.eventId,
    postId: envelope.postId,
    senderPeerId: envelope.senderPeerId,
    isActive: envelope.isActive,
    reactedAt: envelope.reactedAt,
  );
  await postRepo.savePostReaction(reaction);
  return (HandleIncomingPostReactionResult.reactionApplied, reaction);
}

Future<(HandleIncomingPostCommentReactionResult, PostCommentReactionModel?)>
handleIncomingPostCommentReaction({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  bool allowStaging = true,
}) async {
  final envelope = PostReactionEnvelope.fromJson(message.content);
  if (envelope == null ||
      !envelope.isCommentReaction ||
      envelope.commentId == null) {
    return (
      HandleIncomingPostCommentReactionResult.notPostCommentReaction,
      null,
    );
  }
  if (envelope.senderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_COMMENT_REACTION_SENDER_MISMATCH',
      details: {
        'transportSender': message.from,
        'payloadSender': envelope.senderPeerId,
      },
    );
    return (
      HandleIncomingPostCommentReactionResult.notPostCommentReaction,
      null,
    );
  }

  final sender = await contactRepo.getContact(envelope.senderPeerId);
  if (sender == null) {
    return (HandleIncomingPostCommentReactionResult.unknownSender, null);
  }
  if (sender.isBlocked) {
    return (HandleIncomingPostCommentReactionResult.blockedSender, null);
  }

  final post = await postRepo.getPost(envelope.postId);
  final comments = await postRepo.loadComments(envelope.postId);
  final commentExists = comments.any(
    (comment) => comment.id == envelope.commentId,
  );
  if (post == null || !commentExists) {
    if (allowStaging) {
      await _stagePendingReaction(
        postRepo: postRepo,
        envelope: envelope,
        rawEnvelope: message.content,
      );
    }
    return (HandleIncomingPostCommentReactionResult.stagedPendingParent, null);
  }

  final existing = await postRepo.getCommentReaction(envelope.reactionId);
  if (_isIncomingEventStale(
    existingReactedAt: existing?.reactedAt,
    existingEventId: existing?.eventId,
    incomingReactedAt: envelope.reactedAt,
    incomingEventId: envelope.eventId,
  )) {
    return (HandleIncomingPostCommentReactionResult.staleIgnored, existing);
  }

  final reaction = PostCommentReactionModel(
    reactionId: envelope.reactionId,
    eventId: envelope.eventId,
    postId: envelope.postId,
    commentId: envelope.commentId!,
    senderPeerId: envelope.senderPeerId,
    isActive: envelope.isActive,
    reactedAt: envelope.reactedAt,
  );
  await postRepo.saveCommentReaction(reaction);
  return (HandleIncomingPostCommentReactionResult.reactionApplied, reaction);
}

Future<void> _stagePendingReaction({
  required PostRepository postRepo,
  required PostReactionEnvelope envelope,
  required String rawEnvelope,
}) {
  return postRepo.stagePendingChildEvent(
    PostPendingChildEvent(
      postId: envelope.postId,
      eventId: envelope.eventId,
      eventType: envelope.type,
      senderPeerId: envelope.senderPeerId,
      createdAt: envelope.createdAt,
      rawEnvelope: rawEnvelope,
    ),
  );
}

bool _isIncomingEventStale({
  required String? existingReactedAt,
  required String? existingEventId,
  required String incomingReactedAt,
  required String incomingEventId,
}) {
  if (existingReactedAt == null || existingEventId == null) {
    return false;
  }
  final timeCompare = incomingReactedAt.compareTo(existingReactedAt);
  if (timeCompare > 0) {
    return false;
  }
  if (timeCompare < 0) {
    return true;
  }
  return incomingEventId.compareTo(existingEventId) <= 0;
}
