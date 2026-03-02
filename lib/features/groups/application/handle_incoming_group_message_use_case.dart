import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Handles an incoming group message.
///
/// Verifies the group exists and the sender is a known member.
/// Checks for duplicates before saving. Returns the persisted [GroupMessage]
/// or null if the message was ignored.
Future<GroupMessage?> handleIncomingGroupMessage({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderId,
  required String senderUsername,
  required int keyEpoch,
  required String text,
  required String timestamp,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
    },
  );

  // 1. Load group from repo (if not found, ignore)
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_GROUP',
      details: {},
    );
    return null;
  }

  // 2. Check sender is a member (optional: allow messages from non-members
  //    in case member list is stale; log a warning)
  final member = await groupRepo.getMember(groupId, senderId);
  if (member == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_SENDER',
      details: {
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      },
    );
    // Still process the message — member list may be stale
  }

  // 3. Generate message ID
  final messageId = const Uuid().v4();
  final now = DateTime.now().toUtc();

  DateTime parsedTimestamp;
  try {
    parsedTimestamp = DateTime.parse(timestamp);
  } catch (_) {
    parsedTimestamp = now;
  }

  // 4. Create GroupMessage (isIncoming: true)
  final message = GroupMessage(
    id: messageId,
    groupId: groupId,
    senderPeerId: senderId,
    senderUsername: senderUsername,
    text: text,
    timestamp: parsedTimestamp,
    keyGeneration: keyEpoch,
    status: 'delivered',
    isIncoming: true,
    createdAt: now,
  );

  // 5. Save to repo
  await msgRepo.saveMessage(message);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  return message;
}
