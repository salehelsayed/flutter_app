import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
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
  HydratePostMediaFn? hydratePostMediaFn,
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
  final storedMedia = <PostMediaAttachmentModel>[];
  for (final attachment in envelope.originalSnapshot.media) {
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
