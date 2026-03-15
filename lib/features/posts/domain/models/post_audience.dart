enum PostAudienceKind { allFriends, peopleNearby, pickPeople }

class PostAudience {
  final PostAudienceKind kind;
  final int? radiusM;
  final List<String> selectedPeerIds;
  final String? scopeLabel;

  const PostAudience({
    required this.kind,
    this.radiusM,
    this.selectedPeerIds = const <String>[],
    this.scopeLabel,
  });

  factory PostAudience.allFriends() {
    return const PostAudience(kind: PostAudienceKind.allFriends);
  }

  factory PostAudience.peopleNearby({required int radiusM}) {
    return PostAudience(
      kind: PostAudienceKind.peopleNearby,
      radiusM: radiusM,
      scopeLabel: 'Shared nearby',
    );
  }

  factory PostAudience.pickPeople(List<String> peerIds) {
    return PostAudience(
      kind: PostAudienceKind.pickPeople,
      selectedPeerIds: List<String>.unmodifiable(peerIds),
      scopeLabel: 'Shared with you',
    );
  }

  factory PostAudience.fromMap(Map<String, Object?> map) {
    final kindValue = (map['audience_kind'] as String? ?? 'all_friends').trim();
    final selected = (map['selected_peer_ids'] as String? ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final radiusM = (map['audience_radius_m'] as num?)?.toInt() ??
        (map['radius_m'] as num?)?.toInt();
    return PostAudience(
      kind: switch (kindValue) {
        'pick_people' => PostAudienceKind.pickPeople,
        'people_nearby' => PostAudienceKind.peopleNearby,
        _ => PostAudienceKind.allFriends,
      },
      radiusM: radiusM,
      selectedPeerIds: selected,
      scopeLabel:
          map['scope_label'] as String? ??
          map['audience_scope_label'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'audience_kind': kind.toWireValue(),
      'audience_radius_m': radiusM,
      'selected_peer_ids': selectedPeerIds.join(','),
      'scope_label': scopeLabel,
    };
  }
}

extension PostAudienceKindWireValue on PostAudienceKind {
  String toWireValue() {
    return switch (this) {
      PostAudienceKind.allFriends => 'all_friends',
      PostAudienceKind.peopleNearby => 'people_nearby',
      PostAudienceKind.pickPeople => 'pick_people',
    };
  }
}
