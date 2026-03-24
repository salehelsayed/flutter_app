import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/reconcile_pending_post_child_events_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

enum HandleIncomingPostResult {
  postCreated,
  notPostCreate,
  unknownSender,
  blockedSender,
  duplicate,
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
      envelope: envelope,
    );
    await postRepo.savePost(mergedPost);
    await _saveRecipientDeliveries(
      postRepo: postRepo,
      postId: mergedPost.id,
      recipientPeerIds: envelope.recipientPeerIds,
      createdAt: envelope.createdAt,
    );
    final storedMedia = await _storeIncomingMedia(
      postRepo: postRepo,
      postId: mergedPost.id,
      incomingMedia: envelope.media,
      hydratePostMediaFn: hydratePostMediaFn,
      existingMedia: await postRepo.loadPostMediaAttachments(mergedPost.id),
      hydrateErrorEvent: 'POST_MEDIA_HYDRATE_ERROR',
    );
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

  final post = _sanitizeIncomingPost(
    envelope.toPostModel(
      isIncoming: true,
      deliveryStatus: 'delivered',
    ),
  );
  await postRepo.savePost(post);
  await _saveRecipientDeliveries(
    postRepo: postRepo,
    postId: post.id,
    recipientPeerIds: envelope.recipientPeerIds,
    createdAt: envelope.createdAt,
  );
  final storedMedia = await _storeIncomingMedia(
    postRepo: postRepo,
    postId: post.id,
    incomingMedia: envelope.media,
    hydratePostMediaFn: hydratePostMediaFn,
    hydrateErrorEvent: 'POST_MEDIA_HYDRATE_ERROR',
  );
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
  required PostCreateEnvelope envelope,
}) {
  final incomingPost = _sanitizeIncomingPost(
    envelope.toPostModel(
      isIncoming: true,
      deliveryStatus: 'delivered',
    ),
  );
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

Future<void> _saveRecipientDeliveries({
  required PostRepository postRepo,
  required String postId,
  required List<String> recipientPeerIds,
  required String createdAt,
}) async {
  for (final recipientPeerId in recipientPeerIds) {
    await postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: postId,
        recipientPeerId: recipientPeerId,
        deliveryStatus: 'locked',
        lastAttemptAt: createdAt,
        deliveryPath: 'post_create',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
  }
}

Future<List<PostMediaAttachmentModel>> _storeIncomingMedia({
  required PostRepository postRepo,
  required String postId,
  required List<PostMediaAttachmentModel> incomingMedia,
  required String hydrateErrorEvent,
  HydratePostMediaFn? hydratePostMediaFn,
  List<PostMediaAttachmentModel> existingMedia =
      const <PostMediaAttachmentModel>[],
}) async {
  final existingById = <String, PostMediaAttachmentModel>{
    for (final attachment in existingMedia) attachment.mediaId: attachment,
  };
  final storedMedia = <PostMediaAttachmentModel>[];
  for (final attachment in incomingMedia) {
    final preservedAttachment = existingById[attachment.mediaId];
    if (preservedAttachment != null) {
      storedMedia.add(preservedAttachment);
      continue;
    }

    final pendingAttachment = attachment.copyWith(
      postId: postId,
      downloadStatus: 'pending',
      localPath: null,
    );
    await postRepo.savePostMediaAttachment(pendingAttachment);
    if (hydratePostMediaFn == null) {
      storedMedia.add(pendingAttachment);
      continue;
    }
    try {
      final hydrated = await hydratePostMediaFn(
        attachment: pendingAttachment,
        postId: postId,
      );
      await postRepo.savePostMediaAttachment(hydrated);
      storedMedia.add(hydrated);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: hydrateErrorEvent,
        details: {
          'postId': postId,
          'mediaId': attachment.mediaId,
          'error': e.toString(),
        },
      );
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
