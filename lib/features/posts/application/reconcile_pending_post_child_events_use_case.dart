import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<int> reconcilePendingPostChildEvents({
  required String postId,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
}) async {
  final pendingEvents = await postRepo.loadPendingChildEvents(postId);
  var applied = 0;

  for (final pendingEvent in pendingEvents) {
    switch (pendingEvent.eventType) {
      case 'post_comment':
        final (result, _) = await handleIncomingPostComment(
          message: ChatMessage(
            from: pendingEvent.senderPeerId,
            to: '',
            content: pendingEvent.rawEnvelope,
            timestamp: pendingEvent.createdAt,
            isIncoming: true,
          ),
          postRepo: postRepo,
          contactRepo: contactRepo,
          allowStaging: false,
        );
        if (result == HandleIncomingPostCommentResult.commentCreated) {
          applied += 1;
        }
        if (result != HandleIncomingPostCommentResult.stagedPendingParent) {
          await postRepo.deletePendingChildEvent(pendingEvent.eventId);
        }
      case 'post_reaction':
        final (result, _) = await handleIncomingPostReaction(
          message: ChatMessage(
            from: pendingEvent.senderPeerId,
            to: '',
            content: pendingEvent.rawEnvelope,
            timestamp: pendingEvent.createdAt,
            isIncoming: true,
          ),
          postRepo: postRepo,
          contactRepo: contactRepo,
          allowStaging: false,
        );
        if (result == HandleIncomingPostReactionResult.reactionApplied) {
          applied += 1;
        }
        if (result != HandleIncomingPostReactionResult.stagedPendingParent) {
          await postRepo.deletePendingChildEvent(pendingEvent.eventId);
        }
      case 'post_comment_reaction':
        final (result, _) = await handleIncomingPostCommentReaction(
          message: ChatMessage(
            from: pendingEvent.senderPeerId,
            to: '',
            content: pendingEvent.rawEnvelope,
            timestamp: pendingEvent.createdAt,
            isIncoming: true,
          ),
          postRepo: postRepo,
          contactRepo: contactRepo,
          allowStaging: false,
        );
        if (result == HandleIncomingPostCommentReactionResult.reactionApplied) {
          applied += 1;
        }
        if (result !=
            HandleIncomingPostCommentReactionResult.stagedPendingParent) {
          await postRepo.deletePendingChildEvent(pendingEvent.eventId);
        }
      default:
        continue;
    }
  }

  return applied;
}
