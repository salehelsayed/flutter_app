import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();
const Duration _interactivePostReactionBudget = Duration(seconds: 4);

enum SendPostReactionResult {
  success,
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
  final didSend = await fanoutPostEngagementEnvelope(
    p2pService: p2pService,
    recipients: recipients,
    envelope: envelope,
  );
  if (!didSend) {
    return (SendPostReactionResult.sendFailed, null);
  }

  await postRepo.savePostReaction(reaction);
  return (SendPostReactionResult.success, reaction);
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

Future<bool> fanoutPostEngagementEnvelope({
  required P2PService p2pService,
  required List<ContactModel> recipients,
  required String envelope,
}) async {
  var delivered = false;
  for (final recipient in recipients) {
    final sendResult = await p2pService.sendMessageWithReply(
      recipient.peerId,
      envelope,
      timeoutMs: _interactivePostReactionBudget.inMilliseconds,
    );
    if (sendResult.sent) {
      delivered = true;
      continue;
    }
    final stored = await p2pService.storeInInbox(recipient.peerId, envelope);
    delivered = delivered || stored;
  }
  return delivered;
}
