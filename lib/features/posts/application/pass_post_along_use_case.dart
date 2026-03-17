import 'dart:convert' show base64Decode, base64Encode;
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/post_repost_engagement_support.dart';
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
  mediaPreparationFailed,
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

typedef PrepareRepostMediaFn = Future<RepostMediaPrepResult?> Function({
  required Bridge bridge,
  required List<PostMediaAttachmentModel> originalMedia,
  required String passerPeerId,
  required List<String> recipientPeerIds,
  required String originalAuthorPeerId,
});

typedef LoadAvatarBytesFn = Future<Uint8List?> Function(String peerId);

Future<(PassPostAlongResult, PostPassModel?)> passPostAlong({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String postId,
  required String senderPeerId,
  required String senderUsername,
  required List<String> recipientPeerIds,
  Bridge? bridge,
  DateTime Function()? nowProvider,
  int maxConcurrentRecipients = defaultPostDeliveryConcurrency,
  PrepareRepostMediaFn? prepareRepostMediaFn,
  LoadAvatarBytesFn? loadAvatarBytesFn,
}) async {
  final (createResult, created) = await createLocalPostPass(
    p2pService: p2pService,
    postRepo: postRepo,
    contactRepo: contactRepo,
    postId: postId,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    recipientPeerIds: recipientPeerIds,
    bridge: bridge,
    nowProvider: nowProvider,
    prepareRepostMediaFn: prepareRepostMediaFn,
    loadAvatarBytesFn: loadAvatarBytesFn,
  );
  if (createResult != PassPostAlongResult.success || created == null) {
    return (createResult, created?.pass);
  }

  final deliveryResult = await deliverCreatedLocalPostPass(
    p2pService: p2pService,
    postRepo: postRepo,
    created: created,
    bridge: bridge,
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
  Bridge? bridge,
  DateTime Function()? nowProvider,
  PrepareRepostMediaFn? prepareRepostMediaFn,
  LoadAvatarBytesFn? loadAvatarBytesFn,
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
  final missingEncryptionPeerIds = recipients.values
      .where(
        (contact) =>
            contact.mlKemPublicKey == null || contact.mlKemPublicKey!.isEmpty,
      )
      .map((contact) => contact.peerId)
      .toList(growable: false);
  if (bridge == null || missingEncryptionPeerIds.isNotEmpty) {
    return (PassPostAlongResult.sendFailed, null);
  }

  // Phase 4: Prepare repost-owned encrypted media before building envelope.
  List<PostMediaAttachmentModel> repostMedia = renderablePost.media;
  Map<String, PostMediaCryptoEntry>? mediaKeys;
  if (renderablePost.media.isNotEmpty && bridge != null) {
    final prepareFn = prepareRepostMediaFn ?? _prepareRepostMedia;
    final prepResult = await prepareFn(
      bridge: bridge,
      originalMedia: renderablePost.media,
      passerPeerId: senderPeerId,
      recipientPeerIds: recipients.keys.toList(growable: false),
      originalAuthorPeerId: renderablePost.authorPeerId,
    );
    if (prepResult == null) {
      return (PassPostAlongResult.mediaPreparationFailed, null);
    }
    repostMedia = prepResult.attachments;
    mediaKeys = prepResult.keys;
  }
  final mediaPost = renderablePost.copyWith(media: repostMedia);

  // Phase 5: Load original-author avatar for self-renderable repost card.
  String? avatarBase64;
  if (loadAvatarBytesFn != null) {
    final avatarBytes = await loadAvatarBytesFn!(post.authorPeerId);
    if (avatarBytes != null && avatarBytes.length <= 65536) {
      avatarBase64 = base64Encode(avatarBytes);
    }
  }

  final now = (nowProvider ?? DateTime.now).call().toUtc().toIso8601String();
  final sharedThreadBasePeerIds = await loadPersistedRepostParticipantPeerIds(
    postRepo: postRepo,
    postId: post.id,
    authorPeerId: post.authorPeerId,
    passerPeerId: senderPeerId,
  );
  final hiddenHeartSenderPeerIds = await loadProjectedActiveHeartPeerIds(
    postRepo: postRepo,
    postId: post.id,
  );
  final repostTotalBaseline = await loadProjectedRepostShareCount(
    postRepo: postRepo,
    postId: post.id,
  );
  final draftPass = PostPassModel(
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
  final envelope = PostPassEnvelope.fromPass(
    pass: draftPass,
    post: mediaPost,
    participantPeerIds: sharedThreadBasePeerIds,
    activeHeartPeerIds: hiddenHeartSenderPeerIds,
    repostTotalBaseline: repostTotalBaseline,
    mediaKeys: mediaKeys,
    originalAuthorAvatarBase64: avatarBase64,
  );
  final pass = PostPassModel(
    passId: draftPass.passId,
    eventId: draftPass.eventId,
    postId: post.id,
    senderPeerId: senderPeerId,
    passerPeerId: senderPeerId,
    passerUsername: senderUsername,
    passedAt: now,
    createdAt: now,
    isIncoming: false,
    innerPayloadJson: envelope.toInnerJson(),
  );
  await postRepo.savePostPass(pass);
  final currentLocalPassCount = await postRepo.loadPostPassCount(post.id);
  await seedRepostThreadState(
    postRepo: postRepo,
    postId: post.id,
    participantPeerIds: sharedThreadBasePeerIds,
    activeHeartPeerIds: hiddenHeartSenderPeerIds,
    repostTotalBaseline: repostTotalBaseline,
    currentLocalPassCount: currentLocalPassCount,
    createdAt: now,
  );
  if (avatarBase64 != null) {
    await postRepo.savePassAvatarSnapshot(
      postId: post.id,
      authorPeerId: post.authorPeerId,
      avatarBlob: base64Decode(avatarBase64),
      createdAt: now,
    );
  }
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
      snapshotPost: mediaPost,
      envelope: envelope.toJson(),
      resolvedRecipients: resolvedRecipients,
      allRecipientPeerIds: recipients.keys.toList(growable: false),
    ),
  );
}

Future<(SendPostResult, PostPassModel)> deliverCreatedLocalPostPass({
  required P2PService p2pService,
  required PostRepository postRepo,
  required CreatedLocalPostPass created,
  Bridge? bridge,
  int maxConcurrentRecipients = defaultPostDeliveryConcurrency,
}) {
  return PostDeliveryRunner(
    p2pService: p2pService,
    postRepo: postRepo,
    bridge: bridge,
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

class RepostMediaPrepResult {
  final List<PostMediaAttachmentModel> attachments;
  final Map<String, PostMediaCryptoEntry> keys;

  const RepostMediaPrepResult({
    required this.attachments,
    required this.keys,
  });
}

Future<RepostMediaPrepResult?> _prepareRepostMedia({
  required Bridge bridge,
  required List<PostMediaAttachmentModel> originalMedia,
  required String passerPeerId,
  required List<String> recipientPeerIds,
  required String originalAuthorPeerId,
}) async {
  final repostAcl = <String>{
    passerPeerId,
    ...recipientPeerIds,
    originalAuthorPeerId,
  }.toList(growable: false);

  final attachments = <PostMediaAttachmentModel>[];
  final keys = <String, PostMediaCryptoEntry>{};
  final tempFiles = <String>[];

  try {
    for (final attachment in originalMedia) {
      if (attachment.localPath == null ||
          !File(attachment.localPath!).existsSync()) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REPOST_MEDIA_PREP_MISSING_LOCAL',
          details: {
            'mediaId': attachment.mediaId,
            'localPath': attachment.localPath,
          },
        );
        return null;
      }

      final keyBase64 = await callBlobKeygen(bridge);

      final (:encryptedPath, :nonce) = await callBlobEncrypt(
        bridge,
        filePath: attachment.localPath!,
        keyBase64: keyBase64,
      );
      tempFiles.add(encryptedPath);

      final newBlobId = 'blob_${_uuid.v4()}';

      final uploadResult = await callP2PMediaUpload(
        bridge,
        id: newBlobId,
        toPeerId: passerPeerId,
        mime: attachment.mime,
        filePath: encryptedPath,
        allowedPeers: repostAcl,
      );
      if (uploadResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REPOST_MEDIA_PREP_UPLOAD_FAILED',
          details: {
            'mediaId': attachment.mediaId,
            'error': uploadResult['errorMessage']?.toString(),
          },
        );
        return null;
      }

      attachments.add(attachment.copyWith(
        blobId: newBlobId,
        encryptionKeyBase64: keyBase64,
        encryptionNonce: nonce,
        isEncrypted: true,
      ));

      keys[attachment.mediaId] = PostMediaCryptoEntry(
        keyBase64: keyBase64,
        nonce: nonce,
        blobId: newBlobId,
      );
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REPOST_MEDIA_PREP_ERROR',
      details: {'error': e.toString()},
    );
    return null;
  } finally {
    for (final path in tempFiles) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }

  return RepostMediaPrepResult(attachments: attachments, keys: keys);
}
