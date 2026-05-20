import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';

String resolveGroupSenderDisplayName({
  required String senderPeerId,
  String? wireSenderUsername,
  GroupMember? member,
  bool preferMemberName = false,
}) {
  final memberName = _cleanDisplayName(member?.username);
  if (preferMemberName && memberName != null) {
    return memberName;
  }

  final wireName = _cleanDisplayName(wireSenderUsername);
  if (wireName != null) {
    return wireName;
  }

  if (memberName != null) {
    return memberName;
  }

  return groupPeerFallbackLabel(senderPeerId);
}

String groupPeerFallbackLabel(String peerId) {
  final trimmed = peerId.trim();
  if (trimmed.isEmpty) {
    return 'Member';
  }
  final shortPeerId = trimmed.length <= 8 ? trimmed : trimmed.substring(0, 8);
  return 'Member $shortPeerId';
}

String? _cleanDisplayName(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final sanitized = sanitizeUsername(trimmed).trim();
  return sanitized.isEmpty ? null : sanitized;
}
