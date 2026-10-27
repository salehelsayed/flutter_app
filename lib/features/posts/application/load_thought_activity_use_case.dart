import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/posts/application/group_thought_reactions.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/thought_reaction_message_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/thought_view_repository.dart';

typedef ThoughtActivity = ({
  List<ThoughtReactionParticipant> viewers,
  List<ThoughtReactionGroup> reactions,
});

/// Own-Thought activity, limited to its original recipients still eligible
/// here. Delivery never contributes to viewers; only explicit card receipts do.
Future<ThoughtActivity> loadThoughtActivity({
  required String postId,
  required String localPeerId,
  required PostRepository postRepo,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  DateTime Function()? nowProvider,
}) async {
  final post = await postRepo.getPost(postId);
  final expiry = DateTime.tryParse(post?.expiresAt ?? '');
  final now = (nowProvider ?? DateTime.now)().toUtc();
  if (post == null ||
      post.isIncoming ||
      post.authorPeerId != localPeerId ||
      expiry == null ||
      !expiry.isAfter(now)) {
    return (
      viewers: const <ThoughtReactionParticipant>[],
      reactions: const <ThoughtReactionGroup>[],
    );
  }
  if (postRepo is! ThoughtViewRepository ||
      messageRepo is! ThoughtReactionMessageRepository) {
    throw StateError('Thought activity is not configured.');
  }
  final recipients = {
    for (final delivery in await postRepo.getRecipientDeliveries(postId))
      delivery.recipientPeerId,
  };
  final names = {
    for (final contact in await contactRepo.getAllContacts())
      if (!contact.isBlocked &&
          !contact.isArchived &&
          recipients.contains(contact.peerId))
        contact.peerId: contact.username,
  };
  final receipts = await (postRepo as ThoughtViewRepository).loadThoughtViews(
    postId,
  );
  final viewers = <String, ThoughtReactionParticipant>{
    for (final receipt in receipts)
      if (receipt.postId == postId && names.containsKey(receipt.viewerPeerId))
        receipt.viewerPeerId: (
          peerId: receipt.viewerPeerId,
          name: names[receipt.viewerPeerId]!,
        ),
  };
  final replies = await (messageRepo as ThoughtReactionMessageRepository)
      .loadThoughtReactionMessages(postId);
  // The card's refresh/generation fence discards a late result if its Thought
  // has been retired, replaced, or made ineligible during these reads.
  return (
    viewers: List<ThoughtReactionParticipant>.unmodifiable(viewers.values),
    reactions: groupThoughtReactions(
      postId: postId,
      replies: replies,
      participantNames: names,
    ),
  );
}
