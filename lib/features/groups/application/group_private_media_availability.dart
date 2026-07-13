import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';

/// Immutable rollout switch for group private media.
///
/// Production is enabled only after the complete lifecycle, viewer,
/// notification, and native-protection boundaries have landed. Tests may still
/// compose either state without introducing mutable global rollout state.
class GroupPrivateMediaAvailability {
  const GroupPrivateMediaAvailability.disabled() : isEnabled = false;

  const GroupPrivateMediaAvailability.enabled() : isEnabled = true;

  const GroupPrivateMediaAvailability.enabledForTesting() : isEnabled = true;

  final bool isEnabled;

  /// Private authoring belongs to discussion groups and announcements, and is
  /// unavailable whenever the explicit availability switch is disabled.
  /// Role qualification remains a separate current-state decision below.
  bool canAuthorPrivateMedia(GroupType groupType) =>
      isEnabled &&
      (groupType == GroupType.chat || groupType == GroupType.announcement);

  /// Qualifies the current local/member role pair for one private send.
  ///
  /// Discussion groups admit every active writer. Announcements remain
  /// admin-only at both the local group row and roster member boundary, so a
  /// stale composer cannot turn a demotion into a private publication.
  bool canCurrentMemberAuthorPrivateMedia({
    required GroupType groupType,
    required GroupRole localRole,
    required MemberRole memberRole,
  }) {
    if (!canAuthorPrivateMedia(groupType)) return false;
    return hasEligibleCurrentAuthorRole(
      groupType: groupType,
      localRole: localRole,
      memberRole: memberRole,
    );
  }

  /// Role-only half of [canCurrentMemberAuthorPrivateMedia], for durable
  /// retry/re-drive qualification after rollout availability was already
  /// checked by the caller.
  static bool hasEligibleCurrentAuthorRole({
    required GroupType groupType,
    required GroupRole localRole,
    required MemberRole memberRole,
  }) {
    return switch (groupType) {
      GroupType.chat => memberRole != MemberRole.reader,
      GroupType.announcement =>
        localRole == GroupRole.admin && memberRole == MemberRole.admin,
      GroupType.qa => false,
    };
  }

  /// Ordinary legacy media always keeps its existing derivatives. Valid
  /// private media gains its dedicated derivatives only after rollout
  /// enablement; unsupported input is permanently fail-closed.
  bool allowsMediaDerivatives(GroupPrivateMediaPolicy policy) =>
      policy.isOrdinary || (isEnabled && policy.isPrivate);
}

const productionGroupPrivateMediaAvailability =
    GroupPrivateMediaAvailability.enabled();
