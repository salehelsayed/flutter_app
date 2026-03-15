import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

enum HandleIncomingPostResult {
  postCreated,
  notPostCreate,
  unknownSender,
  blockedSender,
  duplicate,
}

Future<(HandleIncomingPostResult, PostModel?)> handleIncomingPost({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  Bridge? bridge,
  String? ownMlKemSecretKey,
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

  final post = PostModel(
    id: envelope.postId,
    eventId: envelope.eventId,
    senderPeerId: envelope.senderPeerId,
    authorPeerId: envelope.authorPeerId,
    authorUsername: envelope.authorUsername,
    text: envelope.text,
    audience: envelope.audience,
    createdAt: envelope.createdAt,
    visibleAt: envelope.createdAt,
    expiresAt: envelope.expiresAt,
    keepAvailable: envelope.keepAvailable,
    isIncoming: true,
    deliveryStatus: 'delivered',
  );
  await postRepo.savePost(post);

  emitFlowEvent(
    layer: 'FL',
    event: 'POST_RECEIVE_STORED',
    details: {'postId': post.id, 'sender': post.senderPeerId},
  );
  return (HandleIncomingPostResult.postCreated, post);
}
