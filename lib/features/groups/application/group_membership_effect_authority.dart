import 'dart:convert';

import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

/// Immutable membership/lifecycle authority captured immediately before one
/// external group effect.
///
/// Metadata fields are intentionally excluded: callers may use the same stamp
/// across a metadata commit, while any lifecycle, role, roster, device, key
/// material, permission, or membership-watermark drift fails exact matching.
class GroupMembershipEffectAuthority {
  GroupMembershipEffectAuthority({
    required this.group,
    required List<GroupMember> members,
    required this.latestKeyGeneration,
  }) : members = List<GroupMember>.unmodifiable(members),
       _fingerprint = _buildFingerprint(group, members, latestKeyGeneration);

  final GroupModel group;
  final List<GroupMember> members;
  final int? latestKeyGeneration;
  final String _fingerprint;

  bool get isActive => !group.isDissolved && group.selfRemovedAt == null;

  GroupMember? singleMember(String peerId) {
    final normalized = peerId.trim();
    GroupMember? found;
    for (final member in members) {
      if (member.peerId.trim() != normalized) continue;
      if (found != null) return null;
      found = member;
    }
    return found;
  }

  bool matches(GroupMembershipEffectAuthority other) =>
      _fingerprint == other._fingerprint;
}

String _buildFingerprint(
  GroupModel group,
  List<GroupMember> members,
  int? latestKeyGeneration,
) {
  final memberRows =
      members
          .map((member) => jsonEncode(member.toConfigJson()))
          .toList(growable: false)
        ..sort();
  return jsonEncode(<String, Object?>{
    'groupId': group.id,
    'groupType': group.type.toValue(),
    'createdBy': group.createdBy,
    'myRole': group.myRole.toValue(),
    'isArchived': group.isArchived,
    'isDissolved': group.isDissolved,
    'selfRemovedAt': group.selfRemovedAt?.toUtc().toIso8601String(),
    'lastMembershipEventAt': group.lastMembershipEventAt
        ?.toUtc()
        .toIso8601String(),
    'lastMembershipEventId': group.lastMembershipEventId,
    'latestKeyGeneration': latestKeyGeneration,
    'members': memberRows,
  });
}
