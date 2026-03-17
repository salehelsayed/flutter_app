import 'dart:convert' show base64Decode;

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/post_repost_engagement_support.dart';
import 'package:flutter_app/features/posts/application/reconcile_pending_post_child_events_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

enum HandleIncomingPassedPostResult {
  passAccepted,
  notPostPass,
  unknownSender,
  blockedSender,
  duplicate,
}

typedef HydratePostMediaFn =
    Future<PostMediaAttachmentModel> Function({
      required PostMediaAttachmentModel attachment,
      required String postId,
    });

Future<(HandleIncomingPassedPostResult, PostModel?)> handleIncomingPassedPost({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  Bridge? bridge,
  String? ownMlKemSecretKey,
  HydratePostMediaFn? hydratePostMediaFn,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_PASS_RECEIVE_START',
    details: {'from': message.from},
  );

  PostPassEnvelope? envelope;
  final isEncrypted =
      PostPassEnvelope.parseEncryptedEnvelope(message.content) != null;

  if (isEncrypted) {
    if (bridge == null || ownMlKemSecretKey == null) {
      return (HandleIncomingPassedPostResult.notPostPass, null);
    }
    envelope = await PostPassEnvelope.fromEncryptedJson(
      jsonString: message.content,
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
    );
  } else {
    envelope = PostPassEnvelope.fromJson(message.content);
  }
  if (envelope == null) {
    return (HandleIncomingPassedPostResult.notPostPass, null);
  }

  if (envelope.senderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_PASS_RECEIVE_SENDER_MISMATCH',
      details: {
        'transportSender': message.from,
        'payloadSender': envelope.senderPeerId,
      },
    );
    return (HandleIncomingPassedPostResult.notPostPass, null);
  }

  final sender = await contactRepo.getContact(envelope.passerPeerId);
  if (sender == null) {
    return (HandleIncomingPassedPostResult.unknownSender, null);
  }
  if (sender.isBlocked) {
    return (HandleIncomingPassedPostResult.blockedSender, null);
  }

  if (await postRepo.postPassExists(envelope.passId)) {
    return (HandleIncomingPassedPostResult.duplicate, null);
  }

  final pass = PostPassModel(
    passId: envelope.passId,
    eventId: envelope.eventId,
    postId: envelope.postId,
    senderPeerId: envelope.senderPeerId,
    passerPeerId: envelope.passerPeerId,
    passerUsername: envelope.passerUsername,
    passedAt: envelope.passedAt,
    createdAt: envelope.createdAt,
    innerPayloadJson: envelope.toInnerJson(),
  );
  await postRepo.savePostPass(pass);
  final currentLocalPassCount = await postRepo.loadPostPassCount(
    envelope.postId,
  );
  await seedRepostThreadState(
    postRepo: postRepo,
    postId: envelope.postId,
    participantPeerIds: envelope.participantPeerIds.isNotEmpty
        ? envelope.participantPeerIds
        : <String>[
            envelope.originalSnapshot.authorPeerId,
            envelope.passerPeerId,
          ],
    activeHeartPeerIds: envelope.activeHeartPeerIds,
    repostTotalBaseline: envelope.repostTotalBaseline ?? 0,
    currentLocalPassCount: currentLocalPassCount,
    createdAt: envelope.passedAt,
  );
  await _persistPassAvatarSnapshotIfPresent(
    postRepo: postRepo,
    postId: envelope.postId,
    originalSnapshot: envelope.originalSnapshot,
    createdAt: envelope.passedAt,
  );

  final existingPost = await postRepo.getPost(envelope.postId);
  if (existingPost != null) {
    final existingOrigin = await postRepo.getPostOrigin(envelope.postId);
    final resurfacedPost = existingPost.copyWith(
      visibleAt: _laterTimestamp(existingPost.visibleAt, envelope.passedAt),
    );
    if (resurfacedPost.visibleAt != existingPost.visibleAt) {
      await postRepo.savePost(resurfacedPost);
    }
    await postRepo.savePostOrigin(
      _mergePassOrigin(
        existingPost: resurfacedPost,
        existingOrigin: existingOrigin,
        envelope: envelope,
      ),
    );
    await reconcilePendingPostChildEvents(
      postId: envelope.postId,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );
    return (
      HandleIncomingPassedPostResult.passAccepted,
      await postRepo.getPost(envelope.postId),
    );
  }

  final post = envelope.toPostModel();
  await postRepo.savePost(post);

  final storedMedia = <PostMediaAttachmentModel>[];
  for (final attachment in envelope.originalSnapshot.media) {
    final cryptoEntry = envelope.mediaKeys?[attachment.mediaId];
    final pendingAttachment = attachment.copyWith(
      postId: post.id,
      downloadStatus: 'pending',
      localPath: null,
      encryptionKeyBase64: cryptoEntry?.keyBase64,
      encryptionNonce: cryptoEntry?.nonce,
      isEncrypted: cryptoEntry != null ? true : null,
    );
    await postRepo.savePostMediaAttachment(pendingAttachment);
    if (hydratePostMediaFn == null) {
      storedMedia.add(pendingAttachment);
      continue;
    }
    try {
      final hydrated = await hydratePostMediaFn(
        attachment: pendingAttachment,
        postId: post.id,
      );
      await postRepo.savePostMediaAttachment(hydrated);
      storedMedia.add(hydrated);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_PASS_MEDIA_HYDRATE_ERROR',
        details: {
          'postId': post.id,
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
  await postRepo.savePostOrigin(
    PostOriginModel(
      postId: envelope.postId,
      originKind: PostOriginKind.pass,
      passId: envelope.passId,
      passerPeerId: envelope.passerPeerId,
      passerUsername: envelope.passerUsername,
      passCreatedAt: envelope.passedAt,
    ),
  );
  await reconcilePendingPostChildEvents(
    postId: post.id,
    postRepo: postRepo,
    contactRepo: contactRepo,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_PASS_RECEIVE_STORED',
    details: {'postId': post.id, 'sender': post.senderPeerId},
  );
  final storedPost = await postRepo.getPost(post.id);
  return (
    HandleIncomingPassedPostResult.passAccepted,
    storedPost?.copyWith(media: storedMedia) ??
        post.copyWith(
          media: storedMedia,
          passedByPeerId: envelope.passerPeerId,
          passedByUsername: envelope.passerUsername,
          passedAt: envelope.passedAt,
          shareCount: 1,
        ),
  );
}

Future<void> _persistPassAvatarSnapshotIfPresent({
  required PostRepository postRepo,
  required String postId,
  required RenderablePostSnapshot originalSnapshot,
  required String createdAt,
}) async {
  final avatarBase64 = originalSnapshot.originalAuthorAvatarBase64;
  if (avatarBase64 == null || avatarBase64.isEmpty) {
    return;
  }
  try {
    await postRepo.savePassAvatarSnapshot(
      postId: postId,
      authorPeerId: originalSnapshot.authorPeerId,
      avatarBlob: base64Decode(avatarBase64),
      createdAt: createdAt,
    );
  } catch (_) {
    // Corrupted avatar base64 — continue without avatar snapshot.
  }
}

String _laterTimestamp(String currentIso, String candidateIso) {
  final current = DateTime.tryParse(currentIso);
  final candidate = DateTime.tryParse(candidateIso);
  if (current == null || candidate == null) {
    return candidateIso;
  }
  return candidate.isAfter(current) ? candidateIso : currentIso;
}

PostOriginModel _mergePassOrigin({
  required PostModel existingPost,
  required PostOriginModel? existingOrigin,
  required PostPassEnvelope envelope,
}) {
  final incomingIsNewest = _isNewerTimestamp(
    existingOrigin?.passCreatedAt,
    envelope.passedAt,
  );
  final prefersDirectOrigin =
      existingPost.senderPeerId == existingPost.authorPeerId ||
      existingOrigin?.originKind == PostOriginKind.direct;

  return PostOriginModel(
    postId: envelope.postId,
    originKind: prefersDirectOrigin
        ? PostOriginKind.direct
        : PostOriginKind.pass,
    passId: incomingIsNewest ? envelope.passId : existingOrigin?.passId,
    passerPeerId: incomingIsNewest
        ? envelope.passerPeerId
        : existingOrigin?.passerPeerId,
    passerUsername: incomingIsNewest
        ? envelope.passerUsername
        : existingOrigin?.passerUsername,
    passCreatedAt: incomingIsNewest
        ? envelope.passedAt
        : existingOrigin?.passCreatedAt,
  );
}

bool _isNewerTimestamp(String? currentIso, String candidateIso) {
  if (currentIso == null) {
    return true;
  }
  final current = DateTime.tryParse(currentIso);
  final candidate = DateTime.tryParse(candidateIso);
  if (current == null || candidate == null) {
    return currentIso != candidateIso;
  }
  return candidate.isAfter(current);
}
