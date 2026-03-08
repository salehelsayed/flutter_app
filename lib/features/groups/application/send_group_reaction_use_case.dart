import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of sending an emoji reaction to a group message.
enum SendGroupReactionResult {
  success,
  groupNotFound,
  messageNotFound,
  notMember,
  publishFailed,
}

const _uuid = Uuid();

/// Sends an emoji reaction to a group message via GossipSub.
///
/// 1. Validates group exists and sender is a member
/// 2. Validates the target message exists
/// 3. Builds reaction payload and publishes via bridge
/// 4. Persists locally (optimistic)
/// 5. Stores in relay inbox for offline members
///
/// Returns (result, MessageReaction?) — reaction is non-null on success.
Future<(SendGroupReactionResult, MessageReaction?)> sendGroupReaction({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required ReactionRepository reactionRepo,
  required String groupId,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_SEND_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageId':
          messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  // 1. Validate group exists
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_GROUP_NOT_FOUND',
      details: {},
    );
    return (SendGroupReactionResult.groupNotFound, null);
  }

  // 2. Validate sender is a member (any member can react, even in announcement groups)
  final member = await groupRepo.getMember(groupId, senderPeerId);
  if (member == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_NOT_MEMBER',
      details: {},
    );
    return (SendGroupReactionResult.notMember, null);
  }

  // 3. Validate message exists
  final message = await msgRepo.getMessage(messageId);
  if (message == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_MSG_NOT_FOUND',
      details: {},
    );
    return (SendGroupReactionResult.messageNotFound, null);
  }

  // 4. Build reaction payload
  final reactionId = _uuid.v4();
  final timestamp = DateTime.now().toUtc().toIso8601String();

  final payload = GroupReactionPayload(
    id: reactionId,
    messageId: messageId,
    emoji: emoji,
    action: 'add',
    senderPeerId: senderPeerId,
    timestamp: timestamp,
  );

  // 5. Publish via bridge (Go encrypts + signs)
  try {
    final result = await callGroupPublishReaction(
      bridge,
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      reactionPayload: payload.toInnerJson(),
    );

    if (result['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_SEND_PUBLISH_FAILED',
        details: {'errorCode': result['errorCode']},
      );
      return (SendGroupReactionResult.publishFailed, null);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_ERROR',
      details: {'error': e.toString()},
    );
    return (SendGroupReactionResult.publishFailed, null);
  }

  // 6. Store in relay inbox for offline members
  _safeReactionInboxStore(
    bridge: bridge,
    groupId: groupId,
    payload: payload,
  );

  // 7. Persist locally
  final reaction = payload.toMessageReaction();
  await reactionRepo.saveReaction(reaction);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_SEND_SUCCESS',
    details: {
      'id': reactionId.substring(0, 8),
      'emoji': emoji,
    },
  );

  return (SendGroupReactionResult.success, reaction);
}

/// Wraps inbox store in try/catch so failures don't propagate.
Future<void> _safeReactionInboxStore({
  required Bridge bridge,
  required String groupId,
  required GroupReactionPayload payload,
}) async {
  try {
    final inboxPayload = jsonEncode({
      'type': 'group_reaction',
      'reaction': payload.toInnerJson(),
    });
    await callGroupInboxStore(bridge, groupId, inboxPayload);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_INBOX_STORE_FAILED',
      details: {'error': e.toString()},
    );
  }
}
