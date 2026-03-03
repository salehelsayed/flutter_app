import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of sending a group message.
enum SendGroupMessageResult {
  success,
  groupNotFound,
  unauthorized,
  error,
}

/// Sends a message to a group.
///
/// Verifies the group exists and the sender has write permission.
/// Publishes via the bridge and saves locally.
///
/// Go's GroupPublish handles encryption and signing internally,
/// so it needs the sender's public and private keys.
Future<(SendGroupMessageResult, GroupMessage?)> sendGroupMessage({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SEND_MSG_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'textLength': text.length,
    },
  );

  // 1. Load group from repo (verify exists)
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_NOT_FOUND',
      details: {},
    );
    return (SendGroupMessageResult.groupNotFound, null);
  }

  // 2. Check role authorization (announcement: only admin can send)
  if (group.type == GroupType.announcement && group.myRole != GroupRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNAUTHORIZED',
      details: {'type': group.type.toValue(), 'role': group.myRole.toValue()},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }

  // 3. Publish via bridge (Go handles encryption + signing internally)
  final now = DateTime.now().toUtc();

  try {
    final result = await callGroupPublish(
      bridge,
      groupId: groupId,
      text: text,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderUsername: senderUsername,
    );

    if (result['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_PUBLISH_ERROR',
        details: {'errorCode': result['errorCode']},
      );
      return (SendGroupMessageResult.error, null);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_ERROR',
      details: {'error': e.toString()},
    );
    return (SendGroupMessageResult.error, null);
  }

  // 4. Fire-and-forget: store message in relay inbox for offline members
  final latestKey = await groupRepo.getLatestKey(groupId);
  try {
    final inboxPayload = jsonEncode({
      'groupId': groupId,
      'senderId': senderPeerId,
      'senderUsername': senderUsername,
      'keyEpoch': latestKey?.keyGeneration ?? 0,
      'text': text,
      'timestamp': now.toIso8601String(),
    });
    await callGroupInboxStore(bridge, groupId, inboxPayload);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_INBOX_STORE_FAILED',
      details: {'error': e.toString()},
    );
  }

  // 5. Create GroupMessage (isIncoming: false, status: 'sent')
  final messageId = const Uuid().v4();

  final message = GroupMessage(
    id: messageId,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    text: text,
    timestamp: now,
    keyGeneration: latestKey?.keyGeneration ?? 0,
    status: 'sent',
    isIncoming: false,
    createdAt: now,
  );

  // 6. Save to repo
  await msgRepo.saveMessage(message);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  return (SendGroupMessageResult.success, message);
}
