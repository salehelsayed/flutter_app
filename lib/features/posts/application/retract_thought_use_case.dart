import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/thought_deletion.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
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
  final now = (nowProvider ?? DateTime.now)().toUtc();
  var post = await postRepo.getPost(postId);
  if (post == null) {
    for (final candidate in await postRepo.loadExpiredOwnPosts(
      now.toIso8601String(),
    )) {
      if (candidate.id == postId) {
        post = candidate;
        break;
      }
    }
  }
  if (post == null) {
    return const ThoughtRetraction(RetractThoughtResult.postNotFound);
  }
  if (post.authorPeerId != senderPeerId) {
    return const ThoughtRetraction(RetractThoughtResult.notAuthor);
  }

  final (envelope, queued) = await queueThoughtRetraction(
    postRepo: postRepo,
    post: post,
    senderPeerId: senderPeerId,
    recipientPeerIds: await sentTo(postRepo, postId),
    now: now,
  );

  await deleteStoredThought(
    postRepo: postRepo,
    mediaFileManager: mediaFileManager,
    postId: postId,
  );

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

/// Everyone the user's thought [postId] was sent to.
Future<Set<String>> sentTo(PostRepository postRepo, String postId) async => {
  for (final delivery in await postRepo.getRecipientDeliveries(postId))
    if (delivery.recipientPeerId.isNotEmpty) delivery.recipientPeerId,
};

/// Queues a `post_retract` of [post] for [recipientPeerIds], ahead of any
/// local delete so the follow-on retrier still sends it after a crash.
Future<(PostRetractEnvelope, List<PostFollowOnOutboxRecipientDelivery>)>
queueThoughtRetraction({
  required PostRepository postRepo,
  required PostModel post,
  required String senderPeerId,
  required Set<String> recipientPeerIds,
  required DateTime now,
}) async {
  final envelope = PostRetractEnvelope(
    eventId: 'evt_${_uuid.v4()}',
    createdAt: now,
    postId: post.id,
    postCreatedAt: DateTime.tryParse(post.createdAt)?.toUtc() ?? now,
  );
  if (recipientPeerIds.isEmpty)
    return (envelope, const <PostFollowOnOutboxRecipientDelivery>[]);
  final queued = await queuePostFollowOn(
    postRepo: postRepo,
    eventId: envelope.eventId,
    eventType: PostRetractEnvelope.type,
    postId: post.id,
    senderPeerId: senderPeerId,
    envelope: envelope.toJson(),
    createdAt: now.toIso8601String(),
    recipientPeerIds: recipientPeerIds.toList(growable: false),
  );
  return (envelope, queued);
}
