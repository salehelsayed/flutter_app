import 'dart:convert' show base64Decode;
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
import 'package:flutter_app/features/posts/application/helpers/repost_avatar_snapshot_preparer.dart';
import 'package:flutter_app/features/posts/application/post_repost_engagement_support.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

const _uuid = Uuid();
const _maxPassAvatarBytes = 65536;

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

typedef PrepareRepostMediaFn =
    Future<RepostMediaPrepResult?> Function({
      required Bridge bridge,
      required List<PostMediaAttachmentModel> originalMedia,
      required String passerPeerId,
      required List<String> recipientPeerIds,
      required String originalAuthorPeerId,
    });

typedef LoadAvatarBytesFn = Future<Uint8List?> Function(String peerId);
typedef ResolveStoredPathFn = Future<String> Function(String storedPath);

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
  AvatarNormalizationHelper? avatarNormalizer,
  ResolveStoredPathFn? resolveStoredPathFn,
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
    avatarNormalizer: avatarNormalizer,
    resolveStoredPathFn: resolveStoredPathFn,
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
  AvatarNormalizationHelper? avatarNormalizer,
  ResolveStoredPathFn? resolveStoredPathFn,
}) async {
  if (!p2pService.currentState.isStarted) {
    _emitRepostCreateAbort(postId: postId, reason: 'node_not_running');
    return (PassPostAlongResult.nodeNotRunning, null);
  }

  final post = await postRepo.getPost(postId);
  if (post == null) {
    _emitRepostCreateAbort(postId: postId, reason: 'post_not_found');
    return (PassPostAlongResult.postNotFound, null);
  }
  if (post.audience.kind == PostAudienceKind.pickPeople) {
    _emitRepostCreateAbort(postId: postId, reason: 'pick_people_not_allowed');
    return (PassPostAlongResult.pickPeopleNotAllowed, null);
  }
  if (post.senderPeerId != post.authorPeerId) {
    _emitRepostCreateAbort(postId: postId, reason: 'one_hop_limit_reached');
    return (PassPostAlongResult.oneHopLimitReached, null);
  }

  final snapshotMedia = post.media.isNotEmpty
      ? post.media
      : await postRepo.loadPostMediaAttachments(post.id);
  final resolvedSnapshotMedia = resolveStoredPathFn == null
      ? snapshotMedia
      : await _resolveStoredMediaPaths(
          snapshotMedia,
          resolveStoredPathFn: resolveStoredPathFn,
        );
  final renderablePost = post.copyWith(
    mediaKind: resolvedSnapshotMedia.isEmpty
        ? post.mediaKind
        : PostMediaAttachmentModel.deriveMediaKind(resolvedSnapshotMedia),
    media: resolvedSnapshotMedia,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'REPOST_CREATE_START',
    details: {
      'postId': post.id,
      'senderPeerId': senderPeerId,
      'authorPeerId': post.authorPeerId,
      'mediaCount': renderablePost.media.length,
      'mediaKind': renderablePost.mediaKind,
      'bridgePresent': bridge != null,
      'requestedRecipientCount': recipientPeerIds.length,
    },
  );
  if (!PostMediaAttachmentModel.isValidSnapshotMedia(
    mediaKind: renderablePost.mediaKind,
    media: renderablePost.media,
  )) {
    _emitRepostCreateAbort(
      postId: post.id,
      reason: 'invalid_snapshot_media',
      details: {
        'mediaKind': renderablePost.mediaKind,
        'mediaCount': renderablePost.media.length,
      },
    );
    return (PassPostAlongResult.sendFailed, null);
  }

  final explicitRecipients = await _resolveRecipients(
    contactRepo: contactRepo,
    peerIds: recipientPeerIds,
  );
  if (explicitRecipients.isEmpty) {
    _emitRepostCreateAbort(postId: post.id, reason: 'no_eligible_recipients');
    return (PassPostAlongResult.noEligibleRecipients, null);
  }
  final explicitRecipientCount = explicitRecipients
      .map((contact) => contact.peerId)
      .where((peerId) => peerId != post.authorPeerId)
      .toSet()
      .length;

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
    _emitRepostCreateAbort(
      postId: post.id,
      reason: 'missing_bridge_or_encryption_keys',
      details: {
        'bridgePresent': bridge != null,
        'missingEncryptionPeerIds': missingEncryptionPeerIds,
      },
    );
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
      _emitRepostCreateAbort(
        postId: post.id,
        reason: 'media_preparation_failed',
        details: {'mediaCount': renderablePost.media.length},
      );
      return (PassPostAlongResult.mediaPreparationFailed, null);
    }
    repostMedia = prepResult.attachments;
    mediaKeys = prepResult.keys;
  }
  final mediaPost = renderablePost.copyWith(media: repostMedia);

  // Phase 5: Load original-author avatar for self-renderable repost card.
  String? avatarBase64;
  int? avatarByteLength;
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_PASS_AVATAR_LOAD_START',
    details: {
      'postId': post.id,
      'authorPeerId': post.authorPeerId,
      'loaderPresent': loadAvatarBytesFn != null,
      'maxBytes': _maxPassAvatarBytes,
    },
  );
  if (loadAvatarBytesFn == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_PASS_AVATAR_LOAD_SKIPPED_NO_LOADER',
      details: {'postId': post.id, 'authorPeerId': post.authorPeerId},
    );
  } else {
    Uint8List? avatarBytes;
    var avatarLoadFailed = false;
    try {
      avatarBytes = await loadAvatarBytesFn(post.authorPeerId);
    } catch (e) {
      avatarLoadFailed = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_PASS_AVATAR_LOAD_FAILED',
        details: {
          'postId': post.id,
          'authorPeerId': post.authorPeerId,
          'error': e.toString(),
        },
      );
    }
    if (avatarBytes == null) {
      if (!avatarLoadFailed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'POST_PASS_AVATAR_LOAD_MISSING',
          details: {'postId': post.id, 'authorPeerId': post.authorPeerId},
        );
      }
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_PASS_AVATAR_LOAD_SUCCESS',
        details: {
          'postId': post.id,
          'authorPeerId': post.authorPeerId,
          'avatarByteLength': avatarBytes.length,
        },
      );
      final preparedAvatar = await prepareRepostAvatarSnapshot(
        postId: post.id,
        authorPeerId: post.authorPeerId,
        avatarBytes: avatarBytes,
        avatarNormalizer: avatarNormalizer,
        maxBytes: _maxPassAvatarBytes,
      );
      if (preparedAvatar != null) {
        avatarByteLength = preparedAvatar.avatarByteLength;
        avatarBase64 = preparedAvatar.avatarBase64;
      }
    }
  }

  final now = (nowProvider ?? DateTime.now).call().toUtc().toIso8601String();
  final sharedThreadBasePeerIds = await loadPersistedRepostParticipantPeerIds(
    postRepo: postRepo,
    postId: post.id,
    authorPeerId: post.authorPeerId,
    passerPeerId: senderPeerId,
  );
  final localParticipantPeerIds = <String>{
    ...sharedThreadBasePeerIds,
    ...explicitRecipients.map((contact) => contact.peerId),
  }.toList(growable: false)..sort();
  final hiddenHeartSenderPeerIds = await loadProjectedActiveHeartPeerIds(
    postRepo: postRepo,
    postId: post.id,
  );
  final repostTotalBaseline = await loadProjectedRepostShareCount(
    postRepo: postRepo,
    postId: post.id,
  );
  final sharedToCountBaseline = await loadProjectedRepostSharedToCount(
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
    recipientCount: explicitRecipientCount,
  );
  final envelope = PostPassEnvelope.fromPass(
    pass: draftPass,
    post: mediaPost,
    participantPeerIds: localParticipantPeerIds,
    participantBasePeerIds: sharedThreadBasePeerIds,
    activeHeartPeerIds: hiddenHeartSenderPeerIds,
    repostTotalBaseline: repostTotalBaseline,
    sharedToCountBaseline: sharedToCountBaseline,
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
    recipientCount: explicitRecipientCount,
    innerPayloadJson: envelope.toInnerJson(),
  );
  await postRepo.savePostPass(pass);
  final currentLocalPassCount = await postRepo.loadPostPassCount(post.id);
  final currentLocalSharedToCount = await loadLocalRepostSharedToCount(
    postRepo: postRepo,
    postId: post.id,
  );
  await seedRepostThreadState(
    postRepo: postRepo,
    postId: post.id,
    participantPeerIds: localParticipantPeerIds,
    activeHeartPeerIds: hiddenHeartSenderPeerIds,
    repostTotalBaseline: repostTotalBaseline,
    sharedToCountBaseline: sharedToCountBaseline,
    currentLocalPassCount: currentLocalPassCount,
    currentLocalSharedToCount: currentLocalSharedToCount,
    currentPassRecipientCount: explicitRecipientCount,
    createdAt: now,
  );
  if (avatarBase64 != null) {
    await postRepo.savePassAvatarSnapshot(
      postId: post.id,
      authorPeerId: post.authorPeerId,
      avatarBlob: base64Decode(avatarBase64),
      createdAt: now,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_PASS_AVATAR_SNAPSHOT_STORED',
      details: {
        'postId': post.id,
        'authorPeerId': post.authorPeerId,
        'avatarByteLength': avatarByteLength,
      },
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
  emitFlowEvent(
    layer: 'FL',
    event: 'REPOST_CREATE_LOCAL_SUCCESS',
    details: {
      'postId': post.id,
      'passId': pass.passId,
      'explicitRecipientCount': explicitRecipientCount,
      'deliveryRecipientCount': resolvedRecipients.length,
      'mediaCount': mediaPost.media.length,
    },
  );
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

  const RepostMediaPrepResult({required this.attachments, required this.keys});
}

Future<RepostMediaPrepResult?> _prepareRepostMedia({
  required Bridge bridge,
  required List<PostMediaAttachmentModel> originalMedia,
  required String passerPeerId,
  required List<String> recipientPeerIds,
  required String originalAuthorPeerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'REPOST_MEDIA_PREP_START',
    details: {
      'attachmentCount': originalMedia.length,
      'recipientCount': recipientPeerIds.length,
      'passerPeerId': passerPeerId,
      'originalAuthorPeerId': originalAuthorPeerId,
    },
  );
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
      emitFlowEvent(
        layer: 'FL',
        event: 'REPOST_MEDIA_PREP_ATTACHMENT',
        details: {
          'mediaId': attachment.mediaId,
          'blobId': attachment.blobId,
          'localPath': attachment.localPath,
          'downloadStatus': attachment.downloadStatus,
          'isEncrypted': attachment.isEncrypted,
        },
      );
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

      attachments.add(
        attachment.copyWith(
          blobId: newBlobId,
          encryptionKeyBase64: keyBase64,
          encryptionNonce: nonce,
          isEncrypted: true,
        ),
      );

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
      details: {'error': e.toString(), 'errorType': e.runtimeType.toString()},
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

  emitFlowEvent(
    layer: 'FL',
    event: 'REPOST_MEDIA_PREP_SUCCESS',
    details: {'attachmentCount': attachments.length},
  );
  return RepostMediaPrepResult(attachments: attachments, keys: keys);
}

Future<List<PostMediaAttachmentModel>> _resolveStoredMediaPaths(
  List<PostMediaAttachmentModel> attachments, {
  required ResolveStoredPathFn resolveStoredPathFn,
}) async {
  return Future.wait(
    attachments.map((attachment) async {
      final localPath = attachment.localPath;
      if (localPath == null || localPath.isEmpty) {
        return attachment;
      }
      final resolvedPath = await resolveStoredPathFn(localPath);
      if (resolvedPath != localPath) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REPOST_MEDIA_PATH_RESOLVED',
          details: {
            'mediaId': attachment.mediaId,
            'storedPath': localPath,
            'resolvedPath': resolvedPath,
          },
        );
      }
      return attachment.copyWith(localPath: resolvedPath);
    }),
  );
}

void _emitRepostCreateAbort({
  required String postId,
  required String reason,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'REPOST_CREATE_ABORT',
    details: {'postId': postId, 'reason': reason, ...details},
  );
}
