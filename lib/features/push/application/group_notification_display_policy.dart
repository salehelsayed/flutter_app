/// Recipient-owned facts shared by every group notification display path.
///
/// Transport authorization, sender/device binding, key selection, reaction
/// target authorization, and notification deduplication are deliberately not
/// part of this policy. Those remain path-specific prerequisites; this value
/// answers only whether the current local group state permits attention.
class GroupNotificationDisplayPolicyInput {
  const GroupNotificationDisplayPolicyInput({
    required this.groupExists,
    required this.hasCurrentLocalMembership,
    required this.groupType,
    this.isMuted = false,
    this.isArchived = false,
    this.isDissolved = false,
    this.hasDissolvedAt = false,
    this.hasSelfRemovedAt = false,
  });

  final bool groupExists;
  final bool hasCurrentLocalMembership;
  final String? groupType;
  final bool isMuted;
  final bool isArchived;
  final bool isDissolved;
  final bool hasDissolvedAt;
  final bool hasSelfRemovedAt;

  GroupNotificationDisplayPolicyInput copyWith({
    bool? groupExists,
    bool? hasCurrentLocalMembership,
    String? groupType,
    bool clearGroupType = false,
    bool? isMuted,
    bool? isArchived,
    bool? isDissolved,
    bool? hasDissolvedAt,
    bool? hasSelfRemovedAt,
  }) => GroupNotificationDisplayPolicyInput(
    groupExists: groupExists ?? this.groupExists,
    hasCurrentLocalMembership:
        hasCurrentLocalMembership ?? this.hasCurrentLocalMembership,
    groupType: clearGroupType ? null : (groupType ?? this.groupType),
    isMuted: isMuted ?? this.isMuted,
    isArchived: isArchived ?? this.isArchived,
    isDissolved: isDissolved ?? this.isDissolved,
    hasDissolvedAt: hasDissolvedAt ?? this.hasDissolvedAt,
    hasSelfRemovedAt: hasSelfRemovedAt ?? this.hasSelfRemovedAt,
  );
}

class GroupMessageNotificationDisplayEligibility {
  final bool shouldDisplay;
  final String reason;

  const GroupMessageNotificationDisplayEligibility._({
    required this.shouldDisplay,
    required this.reason,
  });

  const GroupMessageNotificationDisplayEligibility.allowCurrentMember()
    : this._(shouldDisplay: true, reason: 'current_member');

  const GroupMessageNotificationDisplayEligibility.suppressed(String reason)
    : this._(shouldDisplay: false, reason: reason);
}

/// Reaction-specific recipient facts layered on the canonical group policy.
///
/// A reaction is attention-worthy only when its target is still an ordinary
/// outgoing message authored by the current local account. Private or
/// unsupported target-media policy is suppressed rather than reduced to a
/// semantic media noun.
class GroupReactionNotificationDisplayPolicyInput {
  const GroupReactionNotificationDisplayPolicyInput({
    required this.group,
    required this.hasCurrentLocalAuthoredTarget,
    required this.targetRequiresRedaction,
  });

  final GroupNotificationDisplayPolicyInput group;
  final bool hasCurrentLocalAuthoredTarget;
  final bool targetRequiresRedaction;
}

/// Canonical, fail-closed group notification display decision.
///
/// QA groups remain valid storage/conversation state, but do not participate
/// in the notification projection. This mirrors the shared/iOS projection and
/// prevents one producer from widening the attention surface independently.
GroupMessageNotificationDisplayEligibility
evaluateGroupNotificationDisplayPolicy(
  GroupNotificationDisplayPolicyInput input,
) {
  if (!input.groupExists) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'group_missing',
    );
  }
  if (!input.hasCurrentLocalMembership) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'local_member_missing',
    );
  }
  if (input.groupType != 'chat' && input.groupType != 'announcement') {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'unsupported_group_type',
    );
  }
  if (input.isMuted) {
    return const GroupMessageNotificationDisplayEligibility.suppressed('muted');
  }
  if (input.isArchived) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'archived',
    );
  }
  if (input.isDissolved || input.hasDissolvedAt) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'dissolved',
    );
  }
  if (input.hasSelfRemovedAt) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'self_removed',
    );
  }
  return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
}

GroupMessageNotificationDisplayEligibility
evaluateGroupReactionNotificationDisplayPolicy(
  GroupReactionNotificationDisplayPolicyInput input,
) {
  final groupDecision = evaluateGroupNotificationDisplayPolicy(input.group);
  if (!groupDecision.shouldDisplay) return groupDecision;
  if (!input.hasCurrentLocalAuthoredTarget) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'reaction_target_not_local_authored',
    );
  }
  if (input.targetRequiresRedaction) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'reaction_target_private_media',
    );
  }
  return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
}
