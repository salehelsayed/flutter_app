import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_retract_envelope.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const _uuid = Uuid();

enum RetractThoughtResult { deleted, postNotFound, notAuthor }

class ThoughtRetraction {
  const ThoughtRetraction(this.result, {this.delivery});

  final RetractThoughtResult result;

  /// The first send to every friend who was sent the thought. Null when nobody
  /// was. Friends not reached stay queued for the follow-on retrier.
  final Future<PostFollowOnDeliveryResult>? delivery;
}

/// Deletes the author's thought here at once and asks every friend who was
/// sent it to delete their copy.
///
/// The retraction is queued before the local delete so a crash in between
/// still reaches the friends on the next retry.
Future<ThoughtRetraction> retractThought({
  required PostRepository postRepo,
  required P2PService p2pService,
  required MediaFileManager mediaFileManager,
  required String postId,
  required String senderPeerId,
  DateTime Function()? nowProvider,
}) async {
  final post = await postRepo.getPost(postId);
  if (post == null) {
    return const ThoughtRetraction(RetractThoughtResult.postNotFound);
  }
  if (post.authorPeerId != senderPeerId) {
    return const ThoughtRetraction(RetractThoughtResult.notAuthor);
  }

  final recipients = <String>{
    for (final delivery in await postRepo.getRecipientDeliveries(postId))
      if (delivery.recipientPeerId.isNotEmpty) delivery.recipientPeerId,
  }.toList(growable: false);
  final now = (nowProvider ?? DateTime.now)().toUtc();
  final envelope = PostRetractEnvelope(
    eventId: 'evt_${_uuid.v4()}',
    createdAt: now,
    postId: postId,
    postCreatedAt: DateTime.tryParse(post.createdAt)?.toUtc() ?? now,
  );
  var queued = const <PostFollowOnOutboxRecipientDelivery>[];
  if (recipients.isNotEmpty) {
    queued = await queuePostFollowOn(
      postRepo: postRepo,
      eventId: envelope.eventId,
      eventType: PostRetractEnvelope.type,
      postId: postId,
      senderPeerId: senderPeerId,
      envelope: envelope.toJson(),
      createdAt: now.toIso8601String(),
      recipientPeerIds: recipients,
    );
  }

  await mediaFileManager.deleteMediaForPost(postId);
  await postRepo.deletePostCascade(postId);

  if (queued.isEmpty) {
    return const ThoughtRetraction(RetractThoughtResult.deleted);
  }
  return ThoughtRetraction(
    RetractThoughtResult.deleted,
    delivery: deliverQueuedPostFollowOn(
      postRepo: postRepo,
      p2pService: p2pService,
      eventId: envelope.eventId,
      envelope: envelope.toJson(),
      deliveries: queued,
    ),
  );
}
