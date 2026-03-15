import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();
const Duration _interactivePostPassBudget = Duration(seconds: 4);

enum PassPostAlongResult {
  success,
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
  final envelope = PostPassEnvelope.buildJson(pass: pass, post: post);

  var delivered = false;
  for (final recipient in recipients.values) {
    final sendResult = await p2pService.sendMessageWithReply(
      recipient.peerId,
      envelope,
      timeoutMs: _interactivePostPassBudget.inMilliseconds,
    );
    if (sendResult.sent) {
      delivered = true;
      continue;
    }
    final stored = await p2pService.storeInInbox(recipient.peerId, envelope);
    delivered = delivered || stored;
  }

  if (!delivered) {
    return (PassPostAlongResult.sendFailed, null);
  }
  return (PassPostAlongResult.success, pass);
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
