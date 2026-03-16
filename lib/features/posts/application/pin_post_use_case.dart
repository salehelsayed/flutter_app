import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/post_pin_delivery_support.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum PinPostResult {
  success,
  partiallySettled,
  queuedForRetry,
  nodeNotRunning,
  postNotFound,
  notAuthor,
  noRecipients,
  sendFailed,
}

Future<(PinPostResult, PostPinStateModel?)> pinPost({
  required P2PService p2pService,
  required PostRepository postRepo,
  required String postId,
  required String senderPeerId,
  DateTime Function()? nowProvider,
}) async {
  if (!p2pService.currentState.isStarted) {
    return (PinPostResult.nodeNotRunning, null);
  }

  final post = await postRepo.getPost(postId);
  if (post == null) {
    return (PinPostResult.postNotFound, null);
  }
  if (post.authorPeerId != senderPeerId) {
    return (PinPostResult.notAuthor, null);
  }

  final recipientPeerIds = await loadPostPinRecipients(
    postRepo: postRepo,
    postId: postId,
  );
  if (recipientPeerIds.isEmpty) {
    return (PinPostResult.noRecipients, null);
  }

  final now = (nowProvider ?? DateTime.now).call().toUtc().toIso8601String();
  final pinState = PostPinStateModel(
    postId: post.id,
    eventId: 'evt_${_uuid.v4()}',
    pinEventId: 'pin_evt_${_uuid.v4()}',
    senderPeerId: senderPeerId,
    state: 'active',
    effectiveAt: now,
    pinnedAt: now,
    createdAt: now,
  );
  final media = await loadRenderablePostPinMedia(
    postRepo: postRepo,
    post: post,
  );
  final updatedPost = post.copyWith(
    keepAvailable: true,
    mediaKind: media.isEmpty ? post.mediaKind : null,
    media: media,
  );
  await postRepo.savePost(updatedPost);
  await postRepo.savePostPinState(pinState);

  final envelope = PostPinUpdateEnvelope.buildJson(
    pinState: pinState,
    post: updatedPost,
    media: media,
  );
  final deliveryResult = await queueAndSendPostPinFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: pinState.eventId,
    eventType: postPinUpdateFollowOnEventType,
    postId: updatedPost.id,
    senderPeerId: senderPeerId,
    envelope: envelope,
    createdAt: pinState.createdAt,
    recipientPeerIds: recipientPeerIds,
  );
  return (_pinPostResultForSettlement(deliveryResult.settlement), pinState);
}

PinPostResult _pinPostResultForSettlement(PostFollowOnSettlement settlement) {
  return switch (settlement) {
    PostFollowOnSettlement.fullySettled => PinPostResult.success,
    PostFollowOnSettlement.partiallySettled => PinPostResult.partiallySettled,
    PostFollowOnSettlement.notSettled => PinPostResult.queuedForRetry,
  };
}
