import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();
const Duration _postExpiry = Duration(days: 3);
const Duration _interactivePostBudget = Duration(seconds: 4);

enum SendPostResult {
  success,
  partialSuccess,
  nodeNotRunning,
  invalidPost,
  noEligibleRecipients,
  sendFailed,
}

Future<(SendPostResult, PostModel?)> sendPost({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String senderPeerId,
  required String senderUsername,
  required String text,
  required PostAudience audience,
  Bridge? bridge,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_SEND_START',
    details: {'audienceKind': audience.kind.toWireValue()},
  );

  if (text.trim().isEmpty) {
    return (SendPostResult.invalidPost, null);
  }
  if (!p2pService.currentState.isStarted) {
    return (SendPostResult.nodeNotRunning, null);
  }

  final eligibleRecipients = await _resolveEligibleRecipients(
    contactRepo: contactRepo,
    audience: audience,
  );
  if (eligibleRecipients.isEmpty) {
    return (SendPostResult.noEligibleRecipients, null);
  }

  final createdAt = DateTime.now().toUtc().toIso8601String();
  final expiresAt = DateTime.now().toUtc().add(_postExpiry).toIso8601String();
  final post = PostModel(
    id: 'post_${_uuid.v4()}',
    eventId: 'evt_${_uuid.v4()}',
    senderPeerId: senderPeerId,
    authorPeerId: senderPeerId,
    authorUsername: senderUsername,
    text: text.trim(),
    audience: audience,
    createdAt: createdAt,
    visibleAt: createdAt,
    expiresAt: expiresAt,
    keepAvailable: false,
    isIncoming: false,
    deliveryStatus: 'sending',
  );
  await postRepo.savePost(post);

  var successCount = 0;
  var failureCount = 0;

  for (final recipient in eligibleRecipients) {
    final now = DateTime.now().toUtc().toIso8601String();
    final wireEnvelope = await _buildWireEnvelope(
      post: post,
      bridge: bridge,
      recipient: recipient,
    );
    final delivery = await _deliverToRecipient(
      p2pService: p2pService,
      recipientPeerId: recipient.peerId,
      wireEnvelope: wireEnvelope,
    );

    if (delivery.deliveryStatus == 'delivered' ||
        delivery.deliveryStatus == 'inbox') {
      successCount++;
    } else {
      failureCount++;
    }

    await postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: post.id,
        recipientPeerId: recipient.peerId,
        deliveryStatus: delivery.deliveryStatus,
        lastAttemptAt: now,
        deliveryPath: delivery.deliveryPath,
        lastError: delivery.lastError,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  final updatedPost = post.copyWith(
    deliveryStatus: switch ((successCount, failureCount)) {
      (> 0, 0) => 'sent',
      (> 0, > 0) => 'partial',
      _ => 'failed',
    },
  );
  await postRepo.savePost(updatedPost);

  final result = switch ((successCount, failureCount)) {
    (> 0, 0) => SendPostResult.success,
    (> 0, > 0) => SendPostResult.partialSuccess,
    _ => SendPostResult.sendFailed,
  };
  return (result, updatedPost);
}

Future<List<ContactModel>> _resolveEligibleRecipients({
  required ContactRepository contactRepo,
  required PostAudience audience,
}) async {
  final recipients = <ContactModel>[];
  switch (audience.kind) {
    case PostAudienceKind.allFriends:
      final contacts = await contactRepo.getActiveContacts();
      recipients.addAll(contacts.where((contact) => !contact.isBlocked));
    case PostAudienceKind.pickPeople:
      for (final peerId in audience.selectedPeerIds) {
        final contact = await contactRepo.getContact(peerId);
        if (contact == null || contact.isArchived || contact.isBlocked) {
          continue;
        }
        recipients.add(contact);
      }
  }

  final deduped = <String, ContactModel>{};
  for (final recipient in recipients) {
    deduped[recipient.peerId] = recipient;
  }
  return deduped.values.toList(growable: false);
}

Future<String> _buildWireEnvelope({
  required PostModel post,
  required ContactModel recipient,
  Bridge? bridge,
}) async {
  final envelope = PostCreateEnvelope.fromPost(post);
  if (bridge == null || recipient.mlKemPublicKey == null) {
    return envelope.toJson(selectedPeerIds: post.audience.selectedPeerIds);
  }

  final encryptResult = await callEncryptMessage(
    bridge: bridge,
    recipientMlKemPublicKey: recipient.mlKemPublicKey!,
    plaintext: envelope.toInnerJson(
      selectedPeerIds: post.audience.selectedPeerIds,
    ),
  );

  if (encryptResult['ok'] != true) {
    return envelope.toJson(selectedPeerIds: post.audience.selectedPeerIds);
  }

  return PostCreateEnvelope.buildEncryptedEnvelope(
    eventId: post.eventId,
    createdAt: post.createdAt,
    senderPeerId: post.senderPeerId,
    kem: encryptResult['kem'] as String,
    ciphertext: encryptResult['ciphertext'] as String,
    nonce: encryptResult['nonce'] as String,
  );
}

Future<_DeliveryAttempt> _deliverToRecipient({
  required P2PService p2pService,
  required String recipientPeerId,
  required String wireEnvelope,
}) async {
  try {
    final sendResult = await p2pService.sendMessageWithReply(
      recipientPeerId,
      wireEnvelope,
      timeoutMs: _interactivePostBudget.inMilliseconds,
    );
    if (sendResult.sent) {
      return const _DeliveryAttempt(
        deliveryStatus: 'delivered',
        deliveryPath: 'direct',
      );
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_SEND_DIRECT_ERROR',
      details: {'recipientPeerId': recipientPeerId, 'error': e.toString()},
    );
  }

  final stored = await p2pService.storeInInbox(recipientPeerId, wireEnvelope);
  if (stored) {
    return const _DeliveryAttempt(
      deliveryStatus: 'inbox',
      deliveryPath: 'inbox',
    );
  }
  return const _DeliveryAttempt(
    deliveryStatus: 'failed',
    deliveryPath: 'failed',
    lastError: 'direct_and_inbox_failed',
  );
}

class _DeliveryAttempt {
  final String deliveryStatus;
  final String deliveryPath;
  final String? lastError;

  const _DeliveryAttempt({
    required this.deliveryStatus,
    required this.deliveryPath,
    this.lastError,
  });
}
