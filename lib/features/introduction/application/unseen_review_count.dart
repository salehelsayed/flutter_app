String introReviewKeyForIntroTarget(String targetPeerId) =>
    'intro:$targetPeerId';

String introReviewKeyForGroupInvite(String groupId) => 'invite:$groupId';

Set<String> computeUnseenReviewKeys({
  required Set<String> currentKeys,
  required Set<String> seenKeys,
}) {
  return currentKeys.difference(seenKeys);
}
