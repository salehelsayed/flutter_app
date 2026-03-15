import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
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

Future<(HandleIncomingPassedPostResult, PostModel?)> handleIncomingPassedPost({
  required ChatMessage message,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_PASS_RECEIVE_START',
    details: {'from': message.from},
  );

  final envelope = PostPassEnvelope.fromJson(message.content);
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
  );
  await postRepo.savePostPass(pass);

  final existingPost = await postRepo.getPost(envelope.postId);
  if (existingPost != null) {
    final existingOrigin = await postRepo.getPostOrigin(envelope.postId);
    if (existingOrigin == null &&
        existingPost.senderPeerId != existingPost.authorPeerId) {
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
    }
    return (
      HandleIncomingPassedPostResult.passAccepted,
      await postRepo.getPost(envelope.postId),
    );
  }

  final post = envelope.toPostModel();
  await postRepo.savePost(post);
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
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_PASS_RECEIVE_STORED',
    details: {'postId': post.id, 'sender': post.senderPeerId},
  );
  return (
    HandleIncomingPassedPostResult.passAccepted,
    await postRepo.getPost(post.id),
  );
}
