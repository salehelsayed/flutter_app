import '../../../shared/fakes/in_memory_post_repository.dart';

/// Snapshot both the parent and its durable child state before a rejected event.
Future<Map<String, Object?>> snapshotLegacyPostState(
  InMemoryPostRepository posts, {
  String postId = 'post-1',
}) async => <String, Object?>{
  'post': (await posts.getPost(postId))?.toMap(),
  'media': (await posts.loadPostMediaAttachments(
    postId,
  )).map((row) => row.toMap()).toList(),
  'passes': (await posts.loadPostPasses(
    postId,
  )).map((row) => row.toMap()).toList(),
  'pin': (await posts.getPostPinState(postId))?.toMap(),
  'dismissed': await posts.loadDismissedPinPostIds(),
  'comments': (await posts.loadComments(
    postId,
  )).map((row) => row.toMap()).toList(),
  'reactions': (await posts.loadPostReactions(
    postId,
  )).map((row) => row.toMap()).toList(),
  'participants': await posts.loadRepostEngagementParticipantPeerIds(postId),
  'recipients': (await posts.getRecipientDeliveries(
    postId,
  )).map((row) => row.toMap()).toList(),
  'pending': (await posts.loadPendingChildEvents(
    postId,
  )).map((row) => row.toMap()).toList(),
  'outbox': (await posts.loadRetryableFollowOnOutboxJobs())
      .map((job) => job.event.toMap())
      .toList(),
  'avatar': await posts.loadPassAvatarSnapshot(postId),
};
