import 'package:flutter_app/features/groups/domain/models/group_message.dart';

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
