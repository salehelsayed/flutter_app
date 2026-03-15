import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_eligibility_service.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';

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
  List<PostMediaDraft> mediaDrafts = const <PostMediaDraft>[],
  SecureKeyStore? secureKeyStore,
  ImageProcessor? imageProcessor,
  MediaFileManager? mediaFileManager,
  UploadPostMediaFn? uploadPostMediaFn,
  Bridge? bridge,
  ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository,
  PostsPrivacySettingsRepository? postsPrivacySettingsRepository,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_SEND_START',
    details: {'audienceKind': audience.kind.toWireValue()},
  );

  final hasMedia = mediaDrafts.isNotEmpty;
  if (text.trim().isEmpty && !hasMedia) {
    return (SendPostResult.invalidPost, null);
  }
  if (!p2pService.currentState.isStarted) {
    return (SendPostResult.nodeNotRunning, null);
  }

  final nearbySettings =
      audience.kind == PostAudienceKind.peopleNearby &&
          postsPrivacySettingsRepository != null
      ? await postsPrivacySettingsRepository.load()
      : null;
  final eligibleRecipients = await _resolveEligibleRecipients(
    contactRepo: contactRepo,
    audience: audience,
    contactPresenceSnapshotRepository: contactPresenceSnapshotRepository,
    postsPrivacySettingsRepository: postsPrivacySettingsRepository,
    nearbySettings: nearbySettings,
  );
  if (eligibleRecipients.isEmpty) {
    return (SendPostResult.noEligibleRecipients, null);
  }

  final createdAt = DateTime.now().toUtc().toIso8601String();
  final expiresAt = DateTime.now().toUtc().add(_postExpiry).toIso8601String();
  var post = PostModel(
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
    mediaKind: _deriveDraftMediaKind(mediaDrafts),
    nearbySenderLatE3: nearbySettings?.lastLocalLatE3,
    nearbySenderLngE3: nearbySettings?.lastLocalLngE3,
    nearbySenderCapturedAt: nearbySettings?.lastLocalCapturedAt,
    nearbySenderAccuracyM: nearbySettings?.lastLocalAccuracyM,
    isIncoming: false,
    deliveryStatus: 'sending',
  );
  await postRepo.savePost(post);

  for (final recipient in eligibleRecipients) {
    await postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: post.id,
        recipientPeerId: recipient.contact.peerId,
        deliveryStatus: 'pending',
        lastAttemptAt: createdAt,
        deliveryPath: 'pending',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
  }

  if (hasMedia) {
    if (secureKeyStore == null || imageProcessor == null) {
      final failedPost = post.copyWith(deliveryStatus: 'failed');
      await postRepo.savePost(failedPost);
      return (SendPostResult.sendFailed, failedPost);
    }

    final (mediaResult, attachments) = await attachPostMedia(
      postId: post.id,
      postRepo: postRepo,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      mediaFileManager: mediaFileManager,
      drafts: mediaDrafts,
      uploadPostMediaFn: uploadPostMediaFn,
      bridge: bridge,
    );
    if (mediaResult != AttachPostMediaResult.success) {
      final failedPost = post.copyWith(deliveryStatus: 'failed');
      await postRepo.savePost(failedPost);
      return (SendPostResult.sendFailed, failedPost);
    }
    post = post.copyWith(
      mediaKind: PostMediaAttachmentModel.deriveMediaKind(attachments),
      media: attachments,
    );
    await postRepo.savePost(post);
  }

  var successCount = 0;
  var failureCount = 0;

  for (final recipient in eligibleRecipients) {
    final now = DateTime.now().toUtc().toIso8601String();
    final wireEnvelope = await _buildWireEnvelope(
      post: post,
      bridge: bridge,
      recipient: recipient.contact,
      recipientPeerIds: eligibleRecipients
          .map((eligibleRecipient) => eligibleRecipient.contact.peerId)
          .toList(growable: false),
      nearbyDistanceM: recipient.distanceM,
    );
    final delivery = await _deliverToRecipient(
      p2pService: p2pService,
      recipientPeerId: recipient.contact.peerId,
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
        recipientPeerId: recipient.contact.peerId,
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

String _deriveDraftMediaKind(List<PostMediaDraft> mediaDrafts) {
  if (mediaDrafts.isEmpty) {
    return 'none';
  }
  final firstKind = mediaDrafts.first.kind;
  if (firstKind == 'image' && mediaDrafts.length > 1) {
    return 'image_carousel';
  }
  return firstKind;
}

Future<List<_ResolvedRecipient>> _resolveEligibleRecipients({
  required ContactRepository contactRepo,
  required PostAudience audience,
  ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository,
  PostsPrivacySettingsRepository? postsPrivacySettingsRepository,
  PostsPrivacySettings? nearbySettings,
}) async {
  final recipients = <_ResolvedRecipient>[];
  switch (audience.kind) {
    case PostAudienceKind.allFriends:
      final contacts = await contactRepo.getActiveContacts();
      recipients.addAll(
        contacts
            .where((contact) => !contact.isBlocked)
            .map((contact) => _ResolvedRecipient(contact: contact)),
      );
    case PostAudienceKind.peopleNearby:
      final snapshotRepo = contactPresenceSnapshotRepository;
      final privacyRepo = postsPrivacySettingsRepository;
      final radiusM = audience.radiusM;
      if (snapshotRepo == null || privacyRepo == null || radiusM == null) {
        return const <_ResolvedRecipient>[];
      }
      final nearbyRecipients = await resolveNearbyEligibleRecipients(
        contactRepo: contactRepo,
        snapshotRepo: snapshotRepo,
        privacySettingsRepo: privacyRepo,
        radiusM: radiusM,
        localSettings: nearbySettings,
      );
      recipients.addAll(
        nearbyRecipients.map(
          (entry) => _ResolvedRecipient(
            contact: entry.contact,
            distanceM: entry.distanceM,
          ),
        ),
      );
    case PostAudienceKind.pickPeople:
      for (final peerId in audience.selectedPeerIds) {
        final contact = await contactRepo.getContact(peerId);
        if (contact == null || contact.isArchived || contact.isBlocked) {
          continue;
        }
        recipients.add(_ResolvedRecipient(contact: contact));
      }
  }

  final deduped = <String, _ResolvedRecipient>{};
  for (final recipient in recipients) {
    deduped[recipient.contact.peerId] = recipient;
  }
  return deduped.values.toList(growable: false);
}

Future<String> _buildWireEnvelope({
  required PostModel post,
  required ContactModel recipient,
  required List<String> recipientPeerIds,
  Bridge? bridge,
  int? nearbyDistanceM,
}) async {
  final envelope = PostCreateEnvelope.fromPost(post);
  if (bridge == null || recipient.mlKemPublicKey == null) {
    return envelope.toJson(
      selectedPeerIds: post.audience.selectedPeerIds,
      recipientPeerIds: recipientPeerIds,
      nearbyDistanceM: nearbyDistanceM,
    );
  }

  final encryptResult = await callEncryptMessage(
    bridge: bridge,
    recipientMlKemPublicKey: recipient.mlKemPublicKey!,
    plaintext: envelope.toInnerJson(
      selectedPeerIds: post.audience.selectedPeerIds,
      recipientPeerIds: recipientPeerIds,
      nearbyDistanceM: nearbyDistanceM,
    ),
  );

  if (encryptResult['ok'] != true) {
    return envelope.toJson(
      selectedPeerIds: post.audience.selectedPeerIds,
      recipientPeerIds: recipientPeerIds,
      nearbyDistanceM: nearbyDistanceM,
    );
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

class _ResolvedRecipient {
  final ContactModel contact;
  final int? distanceM;

  const _ResolvedRecipient({required this.contact, this.distanceM});
}
