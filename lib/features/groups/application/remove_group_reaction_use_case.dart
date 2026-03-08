import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of removing an emoji reaction from a group message.
enum RemoveGroupReactionResult {
  success,
  groupNotFound,
  notMember,
  publishFailed,
}

const _uuid = Uuid();

/// Sends a "remove" reaction to a group via GossipSub and deletes locally.
Future<RemoveGroupReactionResult> removeGroupReaction({
  required Bridge bridge,
  required GroupRepository groupRepo,
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
    event: 'GROUP_REACTION_REMOVE_START',
    details: {
      'messageId':
          messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  // 1. Validate group exists
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return RemoveGroupReactionResult.groupNotFound;
  }

  // 2. Validate sender is a member
  final member = await groupRepo.getMember(groupId, senderPeerId);
  if (member == null) {
    return RemoveGroupReactionResult.notMember;
  }

  // 3. Build remove payload
  final reactionId = _uuid.v4();
  final timestamp = DateTime.now().toUtc().toIso8601String();

  final payload = GroupReactionPayload(
    id: reactionId,
    messageId: messageId,
    emoji: emoji,
    action: 'remove',
    senderPeerId: senderPeerId,
    timestamp: timestamp,
  );

  // 4. Publish via bridge
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
      return RemoveGroupReactionResult.publishFailed;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REMOVE_ERROR',
      details: {'error': e.toString()},
    );
    return RemoveGroupReactionResult.publishFailed;
  }

  // 5. Store remove in relay inbox for offline members
  try {
    final inboxPayload = jsonEncode({
      'type': 'group_reaction',
      'reaction': payload.toInnerJson(),
    });
    await callGroupInboxStore(bridge, groupId, inboxPayload);
  } catch (_) {
    // Best-effort
  }

  // 6. Delete locally
  await reactionRepo.removeReaction(messageId, senderPeerId);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_REMOVE_SUCCESS',
    details: {
      'messageId':
          messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  return RemoveGroupReactionResult.success;
}
