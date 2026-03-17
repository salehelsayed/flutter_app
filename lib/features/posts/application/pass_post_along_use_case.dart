import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum PassPostAlongResult {
  success,
  partiallySettled,
  queuedForRetry,
  nodeNotRunning,
  postNotFound,
  noEligibleRecipients,
  pickPeopleNotAllowed,
  oneHopLimitReached,
  sendFailed,
}

class CreatedLocalPostPass {
  final PostPassModel pass;
  final PostModel snapshotPost;
  final String envelope;
  final List<CreatedLocalPostRecipient> resolvedRecipients;
  final List<String> allRecipientPeerIds;

  const CreatedLocalPostPass({
    required this.pass,
    required this.snapshotPost,
    required this.envelope,
    required this.resolvedRecipients,
    this.allRecipientPeerIds = const <String>[],
  });

  List<String> get recipientPeerIds => allRecipientPeerIds.isNotEmpty
      ? allRecipientPeerIds
      : resolvedRecipients
            .map((recipient) => recipient.contact.peerId)
            .toList(growable: false);
}

Future<(PassPostAlongResult, PostPassModel?)> passPostAlong({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String senderPeerId,
  required String senderUsername,
  required List<String> recipientPeerIds,
  DateTime Function()? nowProvider,
  int maxConcurrentRecipients = defaultPostDeliveryConcurrency,
}) async {
  final (createResult, created) = await createLocalPostPass(
    p2pService: p2pService,
    postRepo: postRepo,
    contactRepo: contactRepo,
    postId: postId,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    recipientPeerIds: recipientPeerIds,
    nowProvider: nowProvider,
  );
  if (createResult != PassPostAlongResult.success || created == null) {
    return (createResult, created?.pass);
  }

  final deliveryResult = await deliverCreatedLocalPostPass(
    p2pService: p2pService,
    postRepo: postRepo,
    created: created,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
  return (
    _passPostAlongResultForDeliveryResult(deliveryResult.$1),
    deliveryResult.$2,
  );
}

Future<(PassPostAlongResult, CreatedLocalPostPass?)> createLocalPostPass({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String senderPeerId,
  required String senderUsername,
  required List<String> recipientPeerIds,
  DateTime Function()? nowProvider,
}) async {
  if (!p2pService.currentState.isStarted) {
    return (PassPostAlongResult.nodeNotRunning, null);
  }

  final post = await postRepo.getPost(postId);
  if (post == null) {
    return (PassPostAlongResult.postNotFound, null);
  }
  if (post.audience.kind == PostAudienceKind.pickPeople) {
    return (PassPostAlongResult.pickPeopleNotAllowed, null);
  }
  if (post.senderPeerId != post.authorPeerId) {
    return (PassPostAlongResult.oneHopLimitReached, null);
  }

  final snapshotMedia = post.media.isNotEmpty
      ? post.media
      : await postRepo.loadPostMediaAttachments(post.id);
  final renderablePost = post.copyWith(
    mediaKind: snapshotMedia.isEmpty
        ? post.mediaKind
        : PostMediaAttachmentModel.deriveMediaKind(snapshotMedia),
    media: snapshotMedia,
  );
  if (!PostMediaAttachmentModel.isValidSnapshotMedia(
    mediaKind: renderablePost.mediaKind,
    media: renderablePost.media,
  )) {
    return (PassPostAlongResult.sendFailed, null);
  }

  final explicitRecipients = await _resolveRecipients(
    contactRepo: contactRepo,
    peerIds: recipientPeerIds,
  );
  if (explicitRecipients.isEmpty) {
    return (PassPostAlongResult.noEligibleRecipients, null);
  }

  final recipients = <String, ContactModel>{
    for (final contact in explicitRecipients) contact.peerId: contact,
  };
  if (post.authorPeerId != senderPeerId) {
    final authorContact = await contactRepo.getContact(post.authorPeerId);
    if (authorContact != null &&
        !authorContact.isBlocked &&
        !authorContact.isArchived) {
      recipients[authorContact.peerId] = authorContact;
    }
  }

  final now = (nowProvider ?? DateTime.now).call().toUtc().toIso8601String();
  final pass = PostPassModel(
    passId: 'pass_${_uuid.v4()}',
    eventId: 'evt_${_uuid.v4()}',
    postId: post.id,
    senderPeerId: senderPeerId,
    passerPeerId: senderPeerId,
    passerUsername: senderUsername,
    passedAt: now,
    createdAt: now,
    isIncoming: false,
  );
  final envelope = PostPassEnvelope.buildJson(pass: pass, post: renderablePost);
  await postRepo.savePostPass(pass);
  final resolvedRecipients = recipients.values
      .map((contact) => CreatedLocalPostRecipient(contact: contact))
      .toList(growable: false);
  for (final recipient in resolvedRecipients) {
    await postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: post.id,
        deliveryOwnerKind: postRecipientDeliveryOwnerKindPass,
        deliveryOwnerId: pass.passId,
        recipientPeerId: recipient.contact.peerId,
        deliveryStatus: 'pending',
        lastAttemptAt: now,
        deliveryPath: 'pending',
        nearbyDistanceM: recipient.nearbyDistanceM,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  return (
    PassPostAlongResult.success,
    CreatedLocalPostPass(
      pass: pass,
      snapshotPost: renderablePost,
      envelope: envelope,
      resolvedRecipients: resolvedRecipients,
      allRecipientPeerIds: recipients.keys.toList(growable: false),
    ),
  );
}

Future<(SendPostResult, PostPassModel)> deliverCreatedLocalPostPass({
  required P2PService p2pService,
  required PostRepository postRepo,
  required CreatedLocalPostPass created,
  int maxConcurrentRecipients = defaultPostDeliveryConcurrency,
}) {
  return PostDeliveryRunner(
    p2pService: p2pService,
    postRepo: postRepo,
    maxConcurrentRecipients: maxConcurrentRecipients,
  ).executePostPass(
    pass: created.pass,
    snapshotPost: created.snapshotPost,
    resolvedRecipients: created.resolvedRecipients,
    allRecipientPeerIds: created.recipientPeerIds,
  );
}

Future<List<ContactModel>> _resolveRecipients({
  required ContactRepository contactRepo,
  required List<String> peerIds,
}) async {
  final recipients = <String, ContactModel>{};
  for (final peerId in peerIds) {
    final contact = await contactRepo.getContact(peerId);
    if (contact == null || contact.isBlocked || contact.isArchived) {
      continue;
    }
    recipients[contact.peerId] = contact;
  }
  return recipients.values.toList(growable: false);
}

PassPostAlongResult _passPostAlongResultForDeliveryResult(
  SendPostResult result,
) {
  return switch (result) {
    SendPostResult.success => PassPostAlongResult.success,
    SendPostResult.partialSuccess => PassPostAlongResult.partiallySettled,
    _ => PassPostAlongResult.queuedForRetry,
  };
}
