import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/reconcile_pending_post_child_events_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
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

  if (await postRepo.postExists(envelope.postId)) {
    return (HandleIncomingPostResult.duplicate, null);
  }

  final post = envelope.toPostModel(
    isIncoming: true,
    deliveryStatus: 'delivered',
  );
  await postRepo.savePost(post);
  for (final recipientPeerId in envelope.recipientPeerIds) {
    await postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: post.id,
        recipientPeerId: recipientPeerId,
        deliveryStatus: 'locked',
        lastAttemptAt: envelope.createdAt,
        deliveryPath: 'post_create',
        createdAt: envelope.createdAt,
        updatedAt: envelope.createdAt,
      ),
    );
  }
  final storedMedia = <PostMediaAttachmentModel>[];
  for (final attachment in envelope.media) {
    final pendingAttachment = attachment.copyWith(
      postId: post.id,
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
        postId: post.id,
      );
      await postRepo.savePostMediaAttachment(hydrated);
      storedMedia.add(hydrated);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_MEDIA_HYDRATE_ERROR',
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
