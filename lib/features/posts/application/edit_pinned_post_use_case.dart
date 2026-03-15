import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_pin_delivery_support.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum EditPinnedPostResult {
  success,
  nodeNotRunning,
  postNotFound,
  notAuthor,
  notPinned,
  noRecipients,
  sendFailed,
}

Future<(EditPinnedPostResult, PostPinStateModel?)> editPinnedPost({
  required P2PService p2pService,
  required PostRepository postRepo,
  required String postId,
  required String senderPeerId,
  required String text,
  DateTime Function()? nowProvider,
}) async {
  if (!p2pService.currentState.isStarted) {
    return (EditPinnedPostResult.nodeNotRunning, null);
  }

  final post = await postRepo.getPost(postId);
  if (post == null) {
    return (EditPinnedPostResult.postNotFound, null);
  }
  if (post.authorPeerId != senderPeerId) {
    return (EditPinnedPostResult.notAuthor, null);
  }

  final existingState = await postRepo.getPostPinState(postId);
  if (existingState == null || !existingState.isActive) {
    return (EditPinnedPostResult.notPinned, null);
  }

  final recipientPeerIds = await loadPostPinRecipients(
    postRepo: postRepo,
    postId: postId,
  );
  if (recipientPeerIds.isEmpty) {
    return (EditPinnedPostResult.noRecipients, null);
  }

  final updatedPost = post.copyWith(text: text.trim(), keepAvailable: true);
  final media = await loadRenderablePostPinMedia(
    postRepo: postRepo,
    post: updatedPost,
  );
  final now = (nowProvider ?? DateTime.now).call().toUtc().toIso8601String();
  final pinState = PostPinStateModel(
    postId: updatedPost.id,
    eventId: 'evt_${_uuid.v4()}',
    pinEventId: 'pin_evt_${_uuid.v4()}',
    senderPeerId: senderPeerId,
    state: 'active',
    effectiveAt: now,
    pinnedAt: existingState.pinnedAt ?? now,
    createdAt: now,
  );
  await postRepo.savePost(updatedPost);
  await postRepo.savePostPinState(pinState);

  final envelope = PostPinUpdateEnvelope.buildJson(
    pinState: pinState,
    post: updatedPost,
    media: media,
  );
  final delivered = await sendPostPinEnvelope(
    p2pService: p2pService,
    recipientPeerIds: recipientPeerIds,
    envelope: envelope,
  );
  if (!delivered) {
    return (EditPinnedPostResult.sendFailed, pinState);
  }
  return (EditPinnedPostResult.success, pinState);
}
