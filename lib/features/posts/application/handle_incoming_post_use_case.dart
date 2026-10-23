import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/reconcile_pending_post_child_events_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart'
    show PostMediaCryptoEntry;
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

enum HandleIncomingPostResult {
  postCreated,
  notPostCreate,
  unknownSender,
  blockedSender,
  duplicate,
  expired,
}

typedef HydratePostMediaFn =
    Future<PostMediaAttachmentModel> Function({
      required PostMediaAttachmentModel attachment,
      required String postId,
    });

Future<(HandleIncomingPostResult, PostModel?)> handleIncomingPost({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  Bridge? bridge,
  String? ownMlKemSecretKey,
  HydratePostMediaFn? hydratePostMediaFn,
  MediaFileManager? mediaFileManager,
  DateTime Function()? nowProvider,
  /// Runs once the thought and every media row (with its keys) are saved,
  /// before any media download.
  Future<void> Function()? onDurablyStored,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_RECEIVE_START',
    details: {'from': message.from},
  );

  PostCreateEnvelope? envelope;
  final isEncrypted =
      PostCreateEnvelope.parseEncryptedEnvelope(message.content) != null;

  if (isEncrypted) {
    if (bridge == null || ownMlKemSecretKey == null) {
      return (HandleIncomingPostResult.notPostCreate, null);
    }
    envelope = await PostCreateEnvelope.fromEncryptedJson(
      jsonString: message.content,
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
    );
  } else {
    envelope = PostCreateEnvelope.fromJson(message.content);
  }

  if (envelope == null) {
    return (HandleIncomingPostResult.notPostCreate, null);
  }

  if (envelope.senderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_RECEIVE_SENDER_MISMATCH',
      details: {
        'transportSender': message.from,
        'payloadSender': envelope.senderPeerId,
      },
    );
    return (HandleIncomingPostResult.notPostCreate, null);
  }

  final sender = await contactRepo.getContact(envelope.senderPeerId);
  if (sender == null) {
    return (HandleIncomingPostResult.unknownSender, null);
  }
  if (sender.isBlocked) {
    return (HandleIncomingPostResult.blockedSender, null);
  }

  final now = (nowProvider?.call() ?? DateTime.now()).toUtc();
  final suppliedCreatedAt = DateTime.parse(envelope.createdAt).toUtc();
  final createdAt = suppliedCreatedAt.isAfter(now) ? now : suppliedCreatedAt;
  if (ThoughtLifetime.isExpired(createdAt, now)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_RECEIVE_EXPIRED',
      details: {'postId': envelope.postId},
    );
    return (HandleIncomingPostResult.expired, null);
  }
  final incomingPost = _sanitizeIncomingPost(
    envelope
        .toPostModel(isIncoming: true, deliveryStatus: 'delivered')
        .copyWith(
          createdAt: createdAt.toIso8601String(),
          visibleAt: createdAt.toIso8601String(),
          expiresAt: ThoughtLifetime.expiresAt(createdAt).toIso8601String(),
          keepAvailable: false,
        ),
  );

  Future<bool> isStillEligible() async =>
      !ThoughtLifetime.isExpired(
        createdAt,
        nowProvider?.call() ?? DateTime.now(),
      ) &&
      await postRepo.getPost(envelope!.postId) != null;

  final existingPost = await postRepo.getPost(envelope.postId);
  if (existingPost != null) {
    final existingOrigin = await postRepo.getPostOrigin(envelope.postId);
    final canMergeExistingRepost =
        existingPost.senderPeerId != existingPost.authorPeerId ||
        existingOrigin?.originKind == PostOriginKind.pass;
    if (!canMergeExistingRepost) {
      return (HandleIncomingPostResult.duplicate, null);
    }

    final mergedPost = _mergeExistingRepostedCopy(
      existingPost: existingPost,
      incomingPost: incomingPost,
    );
    await postRepo.savePost(mergedPost);
    final storedMedia = await _storeIncomingMedia(
      postRepo: postRepo,
      postId: mergedPost.id,
      incomingMedia: envelope.media,
      mediaKeys: envelope.mediaKeys,
      hydratePostMediaFn: hydratePostMediaFn,
      existingMedia: await postRepo.loadPostMediaAttachments(mergedPost.id),
      hydrateErrorEvent: 'POST_MEDIA_HYDRATE_ERROR',
      isStillEligible: isStillEligible,
      mediaFileManager: mediaFileManager,
      onDurablyStored: onDurablyStored,
    );
    if (!await isStillEligible()) {
      await postRepo.deletePostCascade(mergedPost.id);
      return (HandleIncomingPostResult.expired, null);
    }
    await postRepo.savePostOrigin(
      PostOriginModel(
        postId: mergedPost.id,
        originKind: PostOriginKind.direct,
        passId: existingOrigin?.passId,
        passerPeerId: existingOrigin?.passerPeerId,
        passerUsername: existingOrigin?.passerUsername,
        passCreatedAt: existingOrigin?.passCreatedAt,
      ),
    );
    await reconcilePendingPostChildEvents(
      postId: mergedPost.id,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_RECEIVE_STORED',
      details: {'postId': mergedPost.id, 'sender': mergedPost.senderPeerId},
    );
    final storedPost = await postRepo.getPost(mergedPost.id);
    return (
      HandleIncomingPostResult.duplicate,
      storedPost?.copyWith(media: storedMedia) ??
          mergedPost.copyWith(media: storedMedia),
    );
  }

  final post = incomingPost;
  await postRepo.savePost(post);
  final storedMedia = await _storeIncomingMedia(
    postRepo: postRepo,
    postId: post.id,
    incomingMedia: envelope.media,
    mediaKeys: envelope.mediaKeys,
    hydratePostMediaFn: hydratePostMediaFn,
    hydrateErrorEvent: 'POST_MEDIA_HYDRATE_ERROR',
    isStillEligible: isStillEligible,
    mediaFileManager: mediaFileManager,
    onDurablyStored: onDurablyStored,
  );
  if (!await isStillEligible()) {
    await postRepo.deletePostCascade(post.id);
    return (HandleIncomingPostResult.expired, null);
  }
  await reconcilePendingPostChildEvents(
    postId: post.id,
    postRepo: postRepo,
    contactRepo: contactRepo,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'POST_RECEIVE_STORED',
    details: {'postId': post.id, 'sender': post.senderPeerId},
  );
  return (
    HandleIncomingPostResult.postCreated,
    post.copyWith(media: storedMedia),
  );
}

String _laterTimestamp(String currentIso, String candidateIso) {
  final current = DateTime.tryParse(currentIso);
  final candidate = DateTime.tryParse(candidateIso);
  if (current == null || candidate == null) {
    return candidateIso;
  }
  return candidate.isAfter(current) ? candidateIso : currentIso;
}

PostModel _mergeExistingRepostedCopy({
  required PostModel existingPost,
  required PostModel incomingPost,
}) {
  return existingPost.copyWith(
    eventId: incomingPost.eventId,
    senderPeerId: incomingPost.senderPeerId,
    authorPeerId: incomingPost.authorPeerId,
    authorUsername: incomingPost.authorUsername,
    text: incomingPost.text,
    audience: incomingPost.audience,
    createdAt: incomingPost.createdAt,
    visibleAt: _laterTimestamp(existingPost.visibleAt, incomingPost.visibleAt),
    expiresAt: incomingPost.expiresAt,
    keepAvailable: incomingPost.keepAvailable,
    mediaKind: incomingPost.mediaKind,
    nearbyDistanceM: incomingPost.nearbyDistanceM,
    nearbySenderLatE3: incomingPost.nearbySenderLatE3,
    nearbySenderLngE3: incomingPost.nearbySenderLngE3,
    nearbySenderCapturedAt: incomingPost.nearbySenderCapturedAt,
    nearbySenderAccuracyM: incomingPost.nearbySenderAccuracyM,
    isIncoming: true,
    deliveryStatus: 'delivered',
  );
}

PostModel _sanitizeIncomingPost(PostModel post) {
  return post.copyWith(
    authorUsername: sanitizeUsername(post.authorUsername),
    text: sanitizeMessageText(post.text),
  );
}

Future<List<PostMediaAttachmentModel>> _storeIncomingMedia({
  required PostRepository postRepo,
  required String postId,
  required List<PostMediaAttachmentModel> incomingMedia,
  required String hydrateErrorEvent,
  required Future<bool> Function() isStillEligible,
  MediaFileManager? mediaFileManager,
  Map<String, PostMediaCryptoEntry>? mediaKeys,
  HydratePostMediaFn? hydratePostMediaFn,
  List<PostMediaAttachmentModel> existingMedia =
      const <PostMediaAttachmentModel>[],
  Future<void> Function()? onDurablyStored,
}) async {
  final existingById = <String, PostMediaAttachmentModel>{
    for (final attachment in existingMedia) attachment.mediaId: attachment,
  };
  final storedMedia = <PostMediaAttachmentModel>[];
  final pendingAttachments = <PostMediaAttachmentModel>[];
  for (final attachment in incomingMedia) {
    if (!await isStillEligible()) return const [];
    final preservedAttachment = existingById[attachment.mediaId];
    if (preservedAttachment != null) {
      storedMedia.add(preservedAttachment);
      continue;
    }

    final cryptoEntry = mediaKeys?[attachment.mediaId];
    final pendingAttachment = attachment.copyWith(
      postId: postId,
      downloadStatus: 'pending',
      localPath: null,
      encryptionKeyBase64: cryptoEntry?.keyBase64,
      encryptionNonce: cryptoEntry?.nonce,
      encryptionScheme: cryptoEntry?.scheme,
      contentHash: cryptoEntry?.contentHash,
      isEncrypted: cryptoEntry != null ? true : null,
    );
    await postRepo.savePostMediaAttachment(pendingAttachment);
    pendingAttachments.add(pendingAttachment);
  }
  await onDurablyStored?.call();

  for (final pendingAttachment in pendingAttachments) {
    if (!await isStillEligible()) return const [];
    if (hydratePostMediaFn == null) {
      storedMedia.add(pendingAttachment);
      continue;
    }
    try {
      final hydrated = await hydratePostMediaFn(
        attachment: pendingAttachment,
        postId: postId,
      );
      if (!await isStillEligible()) {
        await _removeLateHydratedMedia(hydrated.localPath, mediaFileManager);
        return const [];
      }
      await postRepo.savePostMediaAttachment(hydrated);
      storedMedia.add(hydrated);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: hydrateErrorEvent,
        details: {
          'postId': postId,
          'mediaId': pendingAttachment.mediaId,
          'error': e.toString(),
        },
      );
      if (!await isStillEligible()) return const [];
      final failedAttachment = pendingAttachment.copyWith(
        downloadStatus: 'failed',
      );
      await postRepo.savePostMediaAttachment(failedAttachment);
      storedMedia.add(failedAttachment);
    }
  }

  for (final attachment in existingMedia) {
    if (storedMedia.any((item) => item.mediaId == attachment.mediaId)) {
      continue;
    }
    storedMedia.add(attachment);
  }
  storedMedia.sort((a, b) {
    final positionCompare = a.position.compareTo(b.position);
    if (positionCompare != 0) {
      return positionCompare;
    }
    final createdCompare = a.createdAt.compareTo(b.createdAt);
    if (createdCompare != 0) {
      return createdCompare;
    }
    return a.mediaId.compareTo(b.mediaId);
  });
  return storedMedia;
}

Future<void> _removeLateHydratedMedia(
  String? localPath,
  MediaFileManager? mediaFileManager,
) async {
  if (localPath == null) return;
  try {
    final resolvedPath = await (mediaFileManager ?? MediaFileManager())
        .resolveStoredPath(localPath);
    final file = File(resolvedPath);
    if (await file.exists()) await file.delete();
    final parent = file.parent;
    if (await parent.exists() && await parent.list().isEmpty) {
      await parent.delete();
    }
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_EXPIRED_MEDIA_CLEANUP_ERROR',
      details: {'error': error.toString()},
    );
  }
}
