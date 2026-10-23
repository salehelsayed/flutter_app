import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/domain/models/post_retract_envelope.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

enum HandleIncomingPostRetractResult {
  thoughtDeleted,
  notPostRetract,
  unknownPost,
  unauthorizedSender,
}

/// Deletes the local copy of a thought when its author retracts it.
///
/// Only the transport's authenticated sender counts, and it must equal the
/// stored thought's author. A retraction for a thought this phone never
/// stored is dropped without a trace: the copy, if it ever arrives, still
/// expires on its own.
Future<(HandleIncomingPostRetractResult, String?)> handleIncomingPostRetract({
  required ChatMessage message,
  required PostRepository postRepo,
  MediaFileManager? mediaFileManager,
}) async {
  final envelope = PostRetractEnvelope.fromJson(message.content);
  if (envelope == null) {
    _drop('invalid_envelope');
    return (HandleIncomingPostRetractResult.notPostRetract, null);
  }
  final post = await postRepo.getPost(envelope.postId);
  if (post == null) {
    _drop('unknown_post');
    return (HandleIncomingPostRetractResult.unknownPost, envelope.postId);
  }
  if (post.authorPeerId != message.from) {
    _drop('unauthorized_sender');
    return (HandleIncomingPostRetractResult.unauthorizedSender, post.id);
  }

  await mediaFileManager?.deleteMediaForPost(post.id);
  await postRepo.deletePostCascade(post.id);
  return (HandleIncomingPostRetractResult.thoughtDeleted, post.id);
}

void _drop(String reason) {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_RETRACT_DROP',
    details: <String, dynamic>{'reason': reason},
  );
}
