import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Firebase's Android notification renderer posts tagged notifications with
/// id `0`. Local group-invite publications use the same native identity so an
/// unacknowledged direct delivery followed by inbox fallback updates one card
/// instead of creating a second card.
const groupInviteAndroidNotificationId = 0;

const _groupInviteAndroidNotificationTagPrefix = 'mknoon_group_invite_';

String groupInviteAndroidNotificationTag({
  required String groupId,
  required String inviteId,
}) {
  final normalizedGroupId = groupId.trim();
  final normalizedInviteId = inviteId.trim();
  if (normalizedGroupId.isEmpty) {
    throw ArgumentError.value(groupId, 'groupId', 'must not be empty');
  }
  if (normalizedInviteId.isEmpty) {
    throw ArgumentError.value(inviteId, 'inviteId', 'must not be empty');
  }

  final digest = sha256
      .convert(
        utf8.encode(
          'group_invite\u0000$normalizedGroupId\u0000$normalizedInviteId',
        ),
      )
      .toString();
  return '$_groupInviteAndroidNotificationTagPrefix${digest.substring(0, 32)}';
}
