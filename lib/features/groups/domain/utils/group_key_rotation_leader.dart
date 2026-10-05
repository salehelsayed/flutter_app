import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

/// The one member that rotates the group key after a removal or a leave.
///
/// Every device computes the same answer from the shared member config, so
/// exactly one member rotates and two admins never fork the key epoch:
/// - the creator, while they are a member whose role allows `rotateKeys`;
/// - otherwise the member allowed to rotate who joined first (ties broken by
///   the lowest peer ID).
///
/// Returns null when no current member may rotate. Before this rule only the
/// creator could rotate, so a demoted or departed creator left the group
/// unable to replace its key after any later removal.
String? groupKeyRotationLeaderPeerId({
  required GroupModel group,
  required List<GroupMember> members,
}) {
  final eligible = members
      .where(
        (member) => member.permissions.allows(
          GroupMemberPermission.rotateKeys,
          member.role,
        ),
      )
      .toList();
  if (eligible.isEmpty) return null;
  for (final member in eligible) {
    if (member.peerId == group.createdBy) return member.peerId;
  }
  eligible.sort((a, b) {
    final byJoin = a.joinedAt.toUtc().compareTo(b.joinedAt.toUtc());
    return byJoin != 0 ? byJoin : a.peerId.compareTo(b.peerId);
  });
  return eligible.first.peerId;
}
