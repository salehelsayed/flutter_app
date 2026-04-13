import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

String _humanList(List<String> values) {
  if (values.isEmpty) return 'members';
  if (values.length == 1) return values.single;
  if (values.length == 2) {
    return '${values.first} and ${values.last}';
  }
  final head = values.sublist(0, values.length - 1).join(', ');
  return '$head, and ${values.last}';
}

String buildMembersAddedTimelineText(
  String senderUsername,
  List<String?> addedUsernames,
) {
  final actor = senderUsername.trim().isNotEmpty
      ? senderUsername.trim()
      : 'Admin';
  final subjects = addedUsernames
      .map((username) => username?.trim() ?? '')
      .where((username) => username.isNotEmpty)
      .toList(growable: false);
  final subject = subjects.isEmpty ? 'members' : _humanList(subjects);
  return '$actor added $subject';
}

GroupMessage buildMembersAddedTimelineMessage({
  required String groupId,
  required List<({String peerId, String? username})> addedMembers,
  required String senderId,
  required String senderUsername,
  required DateTime eventAt,
}) {
  final normalizedEventAt = eventAt.toUtc();
  final effectiveSenderId = senderId.isNotEmpty ? senderId : 'system';
  final memberKey = addedMembers
      .map((member) => member.peerId.isNotEmpty ? member.peerId : 'unknown')
      .join(',');
  return GroupMessage(
    id:
        'sys-members_added:$groupId:$memberKey:'
        '$effectiveSenderId:${normalizedEventAt.microsecondsSinceEpoch}',
    groupId: groupId,
    senderPeerId: effectiveSenderId,
    senderUsername: senderUsername.isNotEmpty ? senderUsername : null,
    text: buildMembersAddedTimelineText(
      senderUsername,
      addedMembers.map((member) => member.username).toList(growable: false),
    ),
    timestamp: normalizedEventAt,
    status: 'delivered',
    isIncoming: true,
    createdAt: normalizedEventAt,
  );
}

String buildMemberJoinedTimelineText(String? joinedUsername) {
  final subject = joinedUsername != null && joinedUsername.trim().isNotEmpty
      ? joinedUsername.trim()
      : 'A member';
  return '$subject joined the group';
}

GroupMessage buildMemberJoinedTimelineMessage({
  required String groupId,
  required String joinedPeerId,
  String? joinedUsername,
  required DateTime eventAt,
}) {
  final normalizedEventAt = eventAt.toUtc();
  final effectiveJoinedPeerId = joinedPeerId.isNotEmpty
      ? joinedPeerId
      : 'unknown';
  return GroupMessage(
    id:
        'sys-member_joined:$groupId:$effectiveJoinedPeerId:'
        '${normalizedEventAt.microsecondsSinceEpoch}',
    groupId: groupId,
    senderPeerId: effectiveJoinedPeerId,
    senderUsername: joinedUsername?.trim().isNotEmpty == true
        ? joinedUsername!.trim()
        : null,
    text: buildMemberJoinedTimelineText(joinedUsername),
    timestamp: normalizedEventAt,
    status: 'delivered',
    isIncoming: true,
    createdAt: normalizedEventAt,
  );
}

String buildMemberRemovedTimelineText(
  String senderUsername,
  String? removedUsername,
) {
  final actor = senderUsername.trim().isNotEmpty
      ? senderUsername.trim()
      : 'Admin';
  final subject = removedUsername != null && removedUsername.trim().isNotEmpty
      ? removedUsername.trim()
      : 'a member';
  if (actor == subject) {
    return '$actor left the group';
  }
  return '$actor removed $subject';
}

GroupMessage buildMemberRemovedTimelineMessage({
  required String groupId,
  required String removedPeerId,
  String? removedUsername,
  required String senderId,
  required String senderUsername,
  required DateTime eventAt,
}) {
  final normalizedEventAt = eventAt.toUtc();
  final effectiveRemovedPeerId = removedPeerId.isNotEmpty
      ? removedPeerId
      : 'unknown';
  final effectiveSenderId = senderId.isNotEmpty ? senderId : 'system';

  return GroupMessage(
    id:
        'sys-member_removed:$groupId:$effectiveRemovedPeerId:'
        '$effectiveSenderId:${normalizedEventAt.microsecondsSinceEpoch}',
    groupId: groupId,
    senderPeerId: effectiveSenderId,
    senderUsername: senderUsername.isNotEmpty ? senderUsername : null,
    text: buildMemberRemovedTimelineText(senderUsername, removedUsername),
    timestamp: normalizedEventAt,
    status: 'delivered',
    isIncoming: true,
    createdAt: normalizedEventAt,
  );
}

String buildMemberRoleUpdatedTimelineText(
  String senderUsername,
  String? updatedUsername, {
  MemberRole? previousRole,
  required MemberRole newRole,
}) {
  final actor = senderUsername.trim().isNotEmpty
      ? senderUsername.trim()
      : 'Admin';
  final subject = updatedUsername != null && updatedUsername.trim().isNotEmpty
      ? updatedUsername.trim()
      : 'a member';

  if (previousRole == MemberRole.admin && newRole != MemberRole.admin) {
    return '$actor removed admin from $subject';
  }

  if (newRole == MemberRole.admin) {
    return '$actor made $subject an admin';
  }

  if (newRole == MemberRole.reader) {
    return '$actor made $subject read-only';
  }

  return '$actor made $subject a member';
}

GroupMessage buildMemberRoleUpdatedTimelineMessage({
  required String groupId,
  required String updatedPeerId,
  String? updatedUsername,
  MemberRole? previousRole,
  required MemberRole newRole,
  required String senderId,
  required String senderUsername,
  required DateTime eventAt,
}) {
  final normalizedEventAt = eventAt.toUtc();
  final effectiveUpdatedPeerId = updatedPeerId.isNotEmpty
      ? updatedPeerId
      : 'unknown';
  final effectiveSenderId = senderId.isNotEmpty ? senderId : 'system';

  return GroupMessage(
    id:
        'sys-member_role_updated:$groupId:$effectiveUpdatedPeerId:'
        '$effectiveSenderId:${normalizedEventAt.microsecondsSinceEpoch}',
    groupId: groupId,
    senderPeerId: effectiveSenderId,
    senderUsername: senderUsername.isNotEmpty ? senderUsername : null,
    text: buildMemberRoleUpdatedTimelineText(
      senderUsername,
      updatedUsername,
      previousRole: previousRole,
      newRole: newRole,
    ),
    timestamp: normalizedEventAt,
    status: 'delivered',
    isIncoming: true,
    createdAt: normalizedEventAt,
  );
}

String buildGroupMetadataUpdatedTimelineText(String senderUsername) {
  final actor = senderUsername.trim().isNotEmpty
      ? senderUsername.trim()
      : 'Admin';
  return '$actor updated the group details';
}

GroupMessage buildGroupMetadataUpdatedTimelineMessage({
  required String groupId,
  required String senderId,
  required String senderUsername,
  required DateTime eventAt,
}) {
  final normalizedEventAt = eventAt.toUtc();
  final effectiveSenderId = senderId.isNotEmpty ? senderId : 'system';

  return GroupMessage(
    id:
        'sys-group_metadata_updated:$groupId:$effectiveSenderId:'
        '${normalizedEventAt.microsecondsSinceEpoch}',
    groupId: groupId,
    senderPeerId: effectiveSenderId,
    senderUsername: senderUsername.isNotEmpty ? senderUsername : null,
    text: buildGroupMetadataUpdatedTimelineText(senderUsername),
    timestamp: normalizedEventAt,
    status: 'delivered',
    isIncoming: true,
    createdAt: normalizedEventAt,
  );
}

String buildGroupDissolvedTimelineText(String senderUsername) {
  final actor = senderUsername.trim().isNotEmpty
      ? senderUsername.trim()
      : 'Admin';
  return '$actor dissolved the group';
}

GroupMessage buildGroupDissolvedTimelineMessage({
  required String groupId,
  required String senderId,
  required String senderUsername,
  required DateTime eventAt,
}) {
  final normalizedEventAt = eventAt.toUtc();
  final effectiveSenderId = senderId.isNotEmpty ? senderId : 'system';

  return GroupMessage(
    id:
        'sys-group_dissolved:$groupId:$effectiveSenderId:'
        '${normalizedEventAt.microsecondsSinceEpoch}',
    groupId: groupId,
    senderPeerId: effectiveSenderId,
    senderUsername: senderUsername.isNotEmpty ? senderUsername : null,
    text: buildGroupDissolvedTimelineText(senderUsername),
    timestamp: normalizedEventAt,
    status: 'delivered',
    isIncoming: true,
    createdAt: normalizedEventAt,
  );
}
