import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_engagement_follow_on_support.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum SendPostReactionResult {
  success,
  partiallySettled,
  queuedForRetry,
  nodeNotRunning,
  postNotFound,
  noEligibleRecipients,
  sendFailed,
}

Future<(SendPostReactionResult, PostReactionModel?)> sendPostReaction({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String senderPeerId,
  required bool isActive,
  int maxConcurrentRecipients = defaultPostFollowOnDeliveryConcurrency,
}) async {
  if (!p2pService.currentState.isStarted) {
    return (SendPostReactionResult.nodeNotRunning, null);
  }

  final post = await postRepo.getPost(postId);
  if (post == null) {
    return (SendPostReactionResult.postNotFound, null);
  }
  final recipients = await resolvePostEngagementRecipients(
    postRepo: postRepo,
    contactRepo: contactRepo,
    postId: postId,
    authorPeerId: post.authorPeerId,
    senderPeerId: senderPeerId,
  );
  if (recipients.isEmpty) {
    return (SendPostReactionResult.noEligibleRecipients, null);
  }

  final createdAt = DateTime.now().toUtc().toIso8601String();
  final reaction = PostReactionModel(
    reactionId: 'post_heart:$postId:$senderPeerId',
    eventId: 'evt_${_uuid.v4()}',
    postId: postId,
    senderPeerId: senderPeerId,
    isActive: isActive,
    reactedAt: createdAt,
  );
  final envelope = PostReactionEnvelope.buildPostReactionJson(
    eventId: reaction.eventId,
    createdAt: createdAt,
    senderPeerId: senderPeerId,
    postId: postId,
    isActive: isActive,
  );
  await postRepo.savePostReaction(reaction);
  final deliveryResult = await queueAndSendPostEngagementFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: reaction.eventId,
    eventType: postReactionFollowOnEventType,
    postId: postId,
    commentId: null,
    senderPeerId: senderPeerId,
    envelope: envelope,
    createdAt: createdAt,
    recipientPeerIds: recipients.map((recipient) => recipient.peerId),
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
  return (
    _sendPostReactionResultForSettlement(deliveryResult.settlement),
    reaction,
  );
}

Future<List<ContactModel>> resolvePostEngagementRecipients({
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String authorPeerId,
  required String senderPeerId,
}) async {
  final deliveries = await postRepo.getRecipientDeliveries(postId);
  final peerIds = <String>{
    ...deliveries.map((delivery) => delivery.recipientPeerId),
    authorPeerId,
  }..remove(senderPeerId);

  final recipients = <ContactModel>[];
  for (final peerId in peerIds) {
    final contact = await contactRepo.getContact(peerId);
    if (contact == null || contact.isBlocked || contact.isArchived) {
      continue;
    }
    recipients.add(contact);
  }
  return recipients;
}

Future<PostFollowOnDeliveryResult> fanoutPostEngagementEnvelope({
  required P2PService p2pService,
  required Iterable<String> recipientPeerIds,
  required String envelope,
  int maxConcurrentRecipients = defaultPostFollowOnDeliveryConcurrency,
}) async {
  return fanoutPostFollowOnEnvelope(
    p2pService: p2pService,
    recipientPeerIds: recipientPeerIds,
    envelope: envelope,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
}

SendPostReactionResult _sendPostReactionResultForSettlement(
  PostFollowOnSettlement settlement,
) {
  return switch (settlement) {
    PostFollowOnSettlement.fullySettled => SendPostReactionResult.success,
    PostFollowOnSettlement.partiallySettled =>
      SendPostReactionResult.partiallySettled,
    PostFollowOnSettlement.notSettled => SendPostReactionResult.queuedForRetry,
  };
}
