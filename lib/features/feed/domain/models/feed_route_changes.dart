class FeedRouteChanges {
  final Set<String> changedContactPeerIds;
  final Set<String> changedGroupIds;
  final bool reloadAllContacts;
  final bool reloadAllGroups;

  const FeedRouteChanges({
    this.changedContactPeerIds = const <String>{},
    this.changedGroupIds = const <String>{},
    this.reloadAllContacts = false,
    this.reloadAllGroups = false,
  });

  bool get hasChanges =>
      changedContactPeerIds.isNotEmpty ||
      changedGroupIds.isNotEmpty ||
      reloadAllContacts ||
      reloadAllGroups;

  FeedRouteChanges merge(FeedRouteChanges? other) {
    if (other == null) return this;

    return FeedRouteChanges(
      changedContactPeerIds: {
        ...changedContactPeerIds,
        ...other.changedContactPeerIds,
      },
      changedGroupIds: {...changedGroupIds, ...other.changedGroupIds},
      reloadAllContacts: reloadAllContacts || other.reloadAllContacts,
      reloadAllGroups: reloadAllGroups || other.reloadAllGroups,
    );
  }
}
