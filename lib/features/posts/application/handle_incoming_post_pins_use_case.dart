import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pending_child_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

enum HandleIncomingPostPinUpdateResult {
  pinApplied,
  stagedPendingParent,
  notPostPinUpdate,
  unknownSender,
  blockedSender,
  unauthorizedSender,
  staleIgnored,
}

enum HandleIncomingPostPinRemoveResult {
  pinRemoved,
  stagedPendingParent,
  notPostPinRemove,
  unknownSender,
  blockedSender,
  unauthorizedSender,
  staleIgnored,
}

Future<(HandleIncomingPostPinUpdateResult, PostPinStateModel?)>
handleIncomingPostPinUpdate({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  bool allowStaging = true,
}) async {
  final envelope = PostPinUpdateEnvelope.fromJson(message.content);
  if (envelope == null) {
    return (HandleIncomingPostPinUpdateResult.notPostPinUpdate, null);
  }
  if (envelope.senderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_PIN_UPDATE_SENDER_MISMATCH',
      details: {
        'transportSender': message.from,
        'payloadSender': envelope.senderPeerId,
      },
    );
    return (HandleIncomingPostPinUpdateResult.notPostPinUpdate, null);
  }

  final sender = await contactRepo.getContact(envelope.senderPeerId);
  if (sender == null) {
    return (HandleIncomingPostPinUpdateResult.unknownSender, null);
  }
  if (sender.isBlocked) {
    return (HandleIncomingPostPinUpdateResult.blockedSender, null);
  }

  final parent = await postRepo.getPost(envelope.postId);
  if (parent == null) {
    if (!allowStaging) {
      return (HandleIncomingPostPinUpdateResult.notPostPinUpdate, null);
    }
    await postRepo.stagePendingChildEvent(
      PostPendingChildEvent(
        postId: envelope.postId,
        eventId: envelope.eventId,
        eventType: 'post_pin_update',
        senderPeerId: envelope.senderPeerId,
        createdAt: envelope.createdAt,
        rawEnvelope: message.content,
      ),
    );
    return (HandleIncomingPostPinUpdateResult.stagedPendingParent, null);
  }

  if (!_isAuthorizedPinUpdate(parent, envelope)) {
    return (HandleIncomingPostPinUpdateResult.unauthorizedSender, null);
  }

  final existingState = await postRepo.getPostPinState(envelope.postId);
  if (_isIncomingPinEventStale(
    existingState: existingState,
    incomingEffectiveAt: envelope.effectiveAt,
    incomingEventId: envelope.eventId,
  )) {
    return (HandleIncomingPostPinUpdateResult.staleIgnored, existingState);
  }

  final mergedMedia = await _mergeSnapshotMedia(
    postRepo: postRepo,
    postId: parent.id,
    snapshotMedia: envelope.snapshot.media,
  );
  final updatedPost = parent.copyWith(
    authorUsername: envelope.snapshot.authorUsername,
    text: envelope.snapshot.text,
    audience: envelope.snapshot.audience,
    expiresAt: envelope.snapshot.expiresAt,
    keepAvailable: envelope.snapshot.keepAvailable,
    mediaKind: envelope.snapshot.mediaKind,
    media: mergedMedia,
  );
  await postRepo.savePost(updatedPost);
  await postRepo.replacePostMediaAttachments(parent.id, mergedMedia);

  final pinState = PostPinStateModel(
    postId: parent.id,
    eventId: envelope.eventId,
    pinEventId: envelope.pinEventId,
    senderPeerId: envelope.senderPeerId,
    state: 'active',
    effectiveAt: envelope.effectiveAt,
    pinnedAt: envelope.pinnedAt,
    createdAt: envelope.createdAt,
  );
  await postRepo.savePostPinState(pinState);
  return (HandleIncomingPostPinUpdateResult.pinApplied, pinState);
}

Future<(HandleIncomingPostPinRemoveResult, PostPinStateModel?)>
handleIncomingPostPinRemove({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  bool allowStaging = true,
}) async {
  final envelope = PostPinRemoveEnvelope.fromJson(message.content);
  if (envelope == null) {
    return (HandleIncomingPostPinRemoveResult.notPostPinRemove, null);
  }
  if (envelope.senderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_PIN_REMOVE_SENDER_MISMATCH',
      details: {
        'transportSender': message.from,
        'payloadSender': envelope.senderPeerId,
      },
    );
    return (HandleIncomingPostPinRemoveResult.notPostPinRemove, null);
  }

  final sender = await contactRepo.getContact(envelope.senderPeerId);
  if (sender == null) {
    return (HandleIncomingPostPinRemoveResult.unknownSender, null);
  }
  if (sender.isBlocked) {
    return (HandleIncomingPostPinRemoveResult.blockedSender, null);
  }

  final parent = await postRepo.getPost(envelope.postId);
  if (parent == null) {
    if (!allowStaging) {
      return (HandleIncomingPostPinRemoveResult.notPostPinRemove, null);
    }
    await postRepo.stagePendingChildEvent(
      PostPendingChildEvent(
        postId: envelope.postId,
        eventId: envelope.eventId,
        eventType: 'post_pin_remove',
        senderPeerId: envelope.senderPeerId,
        createdAt: envelope.createdAt,
        rawEnvelope: message.content,
      ),
    );
    return (HandleIncomingPostPinRemoveResult.stagedPendingParent, null);
  }

  if (parent.authorPeerId != envelope.senderPeerId ||
      envelope.reason != 'removed') {
    return (HandleIncomingPostPinRemoveResult.unauthorizedSender, null);
  }

  final existingState = await postRepo.getPostPinState(envelope.postId);
  if (_isIncomingPinEventStale(
    existingState: existingState,
    incomingEffectiveAt: envelope.removedAt,
    incomingEventId: envelope.eventId,
  )) {
    return (HandleIncomingPostPinRemoveResult.staleIgnored, existingState);
  }

  final pinState = PostPinStateModel(
    postId: parent.id,
    eventId: envelope.eventId,
    pinEventId: envelope.pinEventId,
    senderPeerId: envelope.senderPeerId,
    state: 'removed',
    effectiveAt: envelope.removedAt,
    removedAt: envelope.removedAt,
    reason: envelope.reason,
    createdAt: envelope.createdAt,
  );
  await postRepo.savePostPinState(pinState);
  await postRepo.clearPinDismissal(parent.id);
  return (HandleIncomingPostPinRemoveResult.pinRemoved, pinState);
}

bool _isAuthorizedPinUpdate(PostModel parent, PostPinUpdateEnvelope envelope) {
  if (envelope.state != 'active') {
    return false;
  }
  if (!envelope.snapshot.keepAvailable) {
    return false;
  }
  return parent.authorPeerId == envelope.senderPeerId &&
      envelope.snapshot.authorPeerId == parent.authorPeerId;
}

bool _isIncomingPinEventStale({
  required PostPinStateModel? existingState,
  required String incomingEffectiveAt,
  required String incomingEventId,
}) {
  if (existingState == null) {
    return false;
  }
  final timeCompare = incomingEffectiveAt.compareTo(existingState.effectiveAt);
  if (timeCompare > 0) {
    return false;
  }
  if (timeCompare < 0) {
    return true;
  }
  return incomingEventId.compareTo(existingState.eventId) <= 0;
}

Future<List<PostMediaAttachmentModel>> _mergeSnapshotMedia({
  required PostRepository postRepo,
  required String postId,
  required List<PostMediaAttachmentModel> snapshotMedia,
}) async {
  final existingMedia = await postRepo.loadPostMediaAttachments(postId);
  final existingByMediaId = <String, PostMediaAttachmentModel>{
    for (final attachment in existingMedia) attachment.mediaId: attachment,
  };
  return snapshotMedia
      .map((attachment) {
        final existing = existingByMediaId[attachment.mediaId];
        if (existing == null) {
          return attachment.copyWith(postId: postId);
        }
        return attachment.copyWith(
          postId: postId,
          localPath: existing.localPath,
          downloadStatus: existing.downloadStatus,
          createdAt: existing.createdAt,
        );
      })
      .toList(growable: false);
}
