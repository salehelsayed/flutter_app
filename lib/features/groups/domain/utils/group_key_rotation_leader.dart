import 'dart:async';

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
  final order = groupKeyRotationOrderPeerIds(group: group, members: members);
  return order.isEmpty ? null : order.first;
}

/// Every member allowed to rotate, in rotation order: the leader first, then
/// the members that take over, one after another, while the ones before them
/// stay offline (see `GroupOwedKeyRotationSweeper`).
List<String> groupKeyRotationOrderPeerIds({
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
  eligible.sort((a, b) {
    final aCreator = a.peerId == group.createdBy;
    final bCreator = b.peerId == group.createdBy;
    if (aCreator != bCreator) return aCreator ? -1 : 1;
    final byJoin = a.joinedAt.toUtc().compareTo(b.joinedAt.toUtc());
    return byJoin != 0 ? byJoin : a.peerId.compareTo(b.peerId);
  });
  return [for (final member in eligible) member.peerId];
}

/// Zone key that marks a rotation as a takeover for one group: the owed-key
/// sweeper runs the rotation inside a zone carrying the group id, and the
/// rotation use case then accepts a non-leader that may rotate.
const groupKeyRotationTakeoverZoneKey = #groupKeyRotationTakeover;

/// Whether the current async call chain is an authorized takeover rotation
/// for [groupId].
bool isGroupKeyRotationTakeover(String groupId) =>
    Zone.current[groupKeyRotationTakeoverZoneKey] == groupId;
