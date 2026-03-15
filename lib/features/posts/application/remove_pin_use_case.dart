import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_pin_delivery_support.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum RemovePinResult {
  success,
  nodeNotRunning,
  postNotFound,
  notAuthor,
  notPinned,
  noRecipients,
  sendFailed,
}

Future<(RemovePinResult, PostPinStateModel?)> removePin({
  required P2PService p2pService,
  required PostRepository postRepo,
  required String postId,
  required String senderPeerId,
  DateTime Function()? nowProvider,
}) async {
  if (!p2pService.currentState.isStarted) {
    return (RemovePinResult.nodeNotRunning, null);
  }

  final post = await postRepo.getPost(postId);
  if (post == null) {
    return (RemovePinResult.postNotFound, null);
  }
  if (post.authorPeerId != senderPeerId) {
    return (RemovePinResult.notAuthor, null);
  }

  final existingState = await postRepo.getPostPinState(postId);
  if (existingState == null || !existingState.isActive) {
    return (RemovePinResult.notPinned, null);
  }

  final recipientPeerIds = await loadPostPinRecipients(
    postRepo: postRepo,
    postId: postId,
  );
  if (recipientPeerIds.isEmpty) {
    return (RemovePinResult.noRecipients, null);
  }

  final now = (nowProvider ?? DateTime.now).call().toUtc().toIso8601String();
  final pinState = PostPinStateModel(
    postId: post.id,
    eventId: 'evt_${_uuid.v4()}',
    pinEventId: 'pin_evt_${_uuid.v4()}',
    senderPeerId: senderPeerId,
    state: 'removed',
    effectiveAt: now,
    removedAt: now,
    reason: 'removed',
    createdAt: now,
  );
  await postRepo.savePostPinState(pinState);
  await postRepo.clearPinDismissal(post.id);

  final envelope = PostPinRemoveEnvelope.buildJson(pinState: pinState);
  final delivered = await sendPostPinEnvelope(
    p2pService: p2pService,
    recipientPeerIds: recipientPeerIds,
    envelope: envelope,
  );
  if (!delivered) {
    return (RemovePinResult.sendFailed, pinState);
  }
  return (RemovePinResult.success, pinState);
}
