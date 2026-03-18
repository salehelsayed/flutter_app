import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<List<String>> loadProjectedActiveHeartPeerIds({
  required PostRepository postRepo,
  required String postId,
}) async {
  final activePeerIds = await postRepo.loadRepostHeartBaselinePeerIds(postId);
  final reactions = await postRepo.loadPostReactions(postId);
  for (final reaction in reactions) {
    if (reaction.senderPeerId.isEmpty) {
      continue;
    }
    if (reaction.isActive) {
      activePeerIds.add(reaction.senderPeerId);
    } else {
      activePeerIds.remove(reaction.senderPeerId);
    }
  }
  final sortedPeerIds = activePeerIds.toList(growable: false)..sort();
  return sortedPeerIds;
}

Future<int> loadProjectedRepostShareCount({
  required PostRepository postRepo,
  required String postId,
}) async {
  final localPassCount = await postRepo.loadPostPassCount(postId);
  final repostTotalBaseline = await postRepo.loadRepostTotalBaseline(postId);
  return localPassCount + repostTotalBaseline;
}

Future<int> loadLocalRepostSharedToCount({
  required PostRepository postRepo,
  required String postId,
}) async {
  final passes = await postRepo.loadPostPasses(postId);
  var total = 0;
  for (final pass in passes) {
    total += pass.recipientCount ?? 1;
  }
  return total;
}

Future<int> loadProjectedRepostSharedToCount({
  required PostRepository postRepo,
  required String postId,
}) async {
  final localSharedToCount = await loadLocalRepostSharedToCount(
    postRepo: postRepo,
    postId: postId,
  );
  final sharedToBaseline = await postRepo.loadRepostSharedToBaseline(postId);
  return localSharedToCount + sharedToBaseline;
}

Future<List<String>> loadPersistedRepostParticipantPeerIds({
  required PostRepository postRepo,
  required String postId,
  required String authorPeerId,
  required String passerPeerId,
}) async {
  final peerIds = <String>{
    authorPeerId,
    passerPeerId,
    ...await postRepo.loadRepostEngagementParticipantPeerIds(postId),
  }..removeWhere((peerId) => peerId.isEmpty);
  final sortedPeerIds = peerIds.toList(growable: false)..sort();
  return sortedPeerIds;
}

Future<bool> hasRepostThreadState({
  required PostRepository postRepo,
  required String postId,
}) async {
  if (await postRepo.loadPostPassCount(postId) > 0) {
    return true;
  }
  if (await postRepo.loadRepostTotalBaseline(postId) > 0) {
    return true;
  }
  if (await postRepo.loadRepostSharedToBaseline(postId) > 0) {
    return true;
  }
  if ((await postRepo.loadRepostEngagementParticipantPeerIds(
    postId,
  )).isNotEmpty) {
    return true;
  }
  final origin = await postRepo.getPostOrigin(postId);
  return _isRepostOrigin(origin);
}

Future<void> persistRepostEngagementParticipantIfNeeded({
  required PostRepository postRepo,
  required String postId,
  required String participantPeerId,
  required String createdAt,
}) async {
  if (participantPeerId.isEmpty) {
    return;
  }
  if (!await hasRepostThreadState(postRepo: postRepo, postId: postId)) {
    return;
  }
  await postRepo.saveRepostEngagementParticipant(
    postId: postId,
    participantPeerId: participantPeerId,
    createdAt: createdAt,
  );
}

Future<void> seedRepostThreadState({
  required PostRepository postRepo,
  required String postId,
  required Iterable<String> participantPeerIds,
  required Iterable<String> activeHeartPeerIds,
  required int repostTotalBaseline,
  required int sharedToCountBaseline,
  required int currentLocalPassCount,
  required int currentLocalSharedToCount,
  required int currentPassRecipientCount,
  required String createdAt,
}) async {
  final sortedParticipantPeerIds =
      participantPeerIds
          .where((peerId) => peerId.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  for (final participantPeerId in sortedParticipantPeerIds) {
    await postRepo.saveRepostEngagementParticipant(
      postId: postId,
      participantPeerId: participantPeerId,
      createdAt: createdAt,
    );
  }
  await postRepo.saveRepostHeartBaselinePeerIds(
    postId: postId,
    peerIds: activeHeartPeerIds,
    createdAt: createdAt,
  );
  await postRepo.seedRepostTotalBaseline(
    postId: postId,
    repostTotalBaseline: repostTotalBaseline,
    existingLocalPassCount: currentLocalPassCount,
    createdAt: createdAt,
  );
  await postRepo.seedRepostSharedToBaseline(
    postId: postId,
    sharedToCountBaseline: sharedToCountBaseline,
    existingLocalSharedToCount: currentLocalSharedToCount,
    currentPassRecipientCount: currentPassRecipientCount,
    createdAt: createdAt,
  );
}

bool isRepostOrigin(PostOriginModel? origin) {
  return _isRepostOrigin(origin);
}

bool _isRepostOrigin(PostOriginModel? origin) {
  if (origin == null) {
    return false;
  }
  if (origin.originKind == PostOriginKind.pass) {
    return true;
  }
  return (origin.passId?.isNotEmpty ?? false) ||
      (origin.passerPeerId?.isNotEmpty ?? false);
}
