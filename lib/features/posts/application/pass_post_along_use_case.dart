import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/post_pass_follow_on_support.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
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

Future<(PassPostAlongResult, PostPassModel?)> passPostAlong({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String senderPeerId,
  required String senderUsername,
  required List<String> recipientPeerIds,
  DateTime Function()? nowProvider,
  int maxConcurrentRecipients = defaultPostFollowOnDeliveryConcurrency,
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
  final deliveryResult = await queueAndSendPostPassFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: pass.eventId,
    postId: post.id,
    senderPeerId: senderPeerId,
    envelope: envelope,
    createdAt: now,
    recipientPeerIds: recipients.keys,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
  return (_passPostAlongResultForSettlement(deliveryResult.settlement), pass);
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

PassPostAlongResult _passPostAlongResultForSettlement(
  PostFollowOnSettlement settlement,
) {
  return switch (settlement) {
    PostFollowOnSettlement.fullySettled => PassPostAlongResult.success,
    PostFollowOnSettlement.partiallySettled =>
      PassPostAlongResult.partiallySettled,
    PostFollowOnSettlement.notSettled => PassPostAlongResult.queuedForRetry,
  };
}
