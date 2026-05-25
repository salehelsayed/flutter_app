import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of sending an emoji reaction to a group message.
enum SendGroupReactionResult {
  /// Live publish was accepted and local/replay state was queued.
  ///
  /// This is not a remote delivery confirmation.
  success,
  groupNotFound,
  groupDissolved,
  messageNotFound,
  notMember,
  unauthorizedSenderKey,
  publishFailed,
}

/// Sends an emoji reaction to a group message via live publish plus replay outbox.
///
/// 1. Validates group exists and sender is a member
/// 2. Validates the target message exists
/// 3. Builds reaction payload and publishes via bridge
/// 4. Stages replay for offline members
/// 5. Persists locally (optimistic)
///
/// Returns (result, MessageReaction?) — reaction is non-null when the local
/// optimistic state was queued. This is not a delivery receipt.
Future<(SendGroupReactionResult, MessageReaction?)> sendGroupReaction({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required ReactionRepository reactionRepo,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
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
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
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

  if (group.isDissolved) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_GROUP_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        if (group.dissolvedAt != null)
          'dissolvedAt': group.dissolvedAt!.toUtc().toIso8601String(),
      },
    );
    return (SendGroupReactionResult.groupDissolved, null);
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
  final senderDevice = member.firstActiveDeviceForSigningKey(
    senderPublicKey,
    allowLegacyFallback: true,
  );
  if (senderDevice == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_UNAUTHORIZED_SENDER_KEY',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderPeerId.length > 8
            ? senderPeerId.substring(0, 8)
            : senderPeerId,
      },
    );
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }

  // 3. Validate message exists
  final message = await msgRepo.getMessage(messageId);
  if (message == null || message.groupId != groupId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_MSG_NOT_FOUND',
      details: {
        if (message != null) 'reason': 'message_group_mismatch',
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
      },
    );
    return (SendGroupReactionResult.messageNotFound, null);
  }

  // 4. Build reaction payload
  final reactionId = _deterministicAddReactionId(
    groupId: groupId,
    messageId: messageId,
    senderPeerId: senderPeerId,
    emoji: emoji,
  );
  final timestamp = DateTime.now().toUtc().toIso8601String();

  final payload = GroupReactionPayload(
    id: reactionId,
    messageId: messageId,
    emoji: emoji,
    action: GroupReactionPayload.actionAdd,
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
      senderDeviceId: senderDevice.deviceId,
      senderTransportPeerId: senderDevice.transportPeerId,
      senderDevicePublicKey: senderDevice.deviceSigningPublicKey,
      senderKeyPackageId: senderDevice.keyPackageId,
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
  await _stageReactionInboxStore(
    bridge: bridge,
    groupRepo: groupRepo,
    reactionReplayOutboxRepo: reactionReplayOutboxRepo,
    groupId: groupId,
    payload: payload,
    senderPublicKey: senderDevice.deviceSigningPublicKey,
    senderPrivateKey: senderPrivateKey,
    senderDevice: senderDevice,
  );

  // 7. Persist locally
  final reaction = payload.toMessageReaction();
  await reactionRepo.saveReaction(reaction);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_SEND_QUEUED',
    details: {
      'id': reactionId.substring(0, 8),
      'emoji': emoji,
      'deliveryMode': 'live_publish_replay_queued',
      'deliveryConfirmed': false,
      'localState': 'optimistic',
      'replayStatus': 'pending',
    },
  );

  return (SendGroupReactionResult.success, reaction);
}

String _deterministicAddReactionId({
  required String groupId,
  required String messageId,
  required String senderPeerId,
  required String emoji,
}) {
  final canonical = jsonEncode({
    'action': GroupReactionPayload.actionAdd,
    'emoji': emoji,
    'groupId': groupId,
    'messageId': messageId,
    'senderPeerId': senderPeerId,
  });
  final digest = sha256.convert(utf8.encode(canonical)).toString();
  return 'group-reaction-add-${digest.substring(0, 32)}';
}

/// Wraps inbox store in try/catch so failures don't propagate.
Future<void> _stageReactionInboxStore({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String groupId,
  required GroupReactionPayload payload,
  required String senderPublicKey,
  required String senderPrivateKey,
  required GroupMemberDeviceIdentity senderDevice,
}) async {
  late final String inboxRetryPayload;
  try {
    inboxRetryPayload = await buildGroupOfflineReplayInboxRetryPayload(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeReaction,
      plaintext: payload.toInnerJson(),
      senderPeerId: payload.senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      messageId: payload.id,
      senderDeviceId: senderDevice.deviceId,
      senderTransportPeerId: senderDevice.transportPeerId,
      senderKeyPackageId: senderDevice.keyPackageId,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_OUTBOX_STAGE_FAILED',
      details: {'error': e.toString()},
    );
    return;
  }
  final nowIso = DateTime.now().toUtc().toIso8601String();
  final entry = GroupReactionReplayOutboxEntry(
    reactionId: payload.id,
    groupId: groupId,
    messageId: payload.messageId,
    senderPeerId: payload.senderPeerId,
    emoji: payload.emoji,
    action: payload.action,
    inboxRetryPayload: inboxRetryPayload,
    deliveryStatus: GroupReactionReplayOutboxStatus.pending,
    createdAt: nowIso,
    updatedAt: nowIso,
  );

  var staged = false;
  try {
    await reactionReplayOutboxRepo.saveEntry(entry);
    staged = true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_OUTBOX_STAGE_FAILED',
      details: {'error': e.toString()},
    );
  }

  unawaited(
    _attemptReactionInboxStore(
      bridge: bridge,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      reactionId: payload.id,
      inboxRetryPayload: inboxRetryPayload,
      staged: staged,
    ),
  );
}

Future<void> _attemptReactionInboxStore({
  required Bridge bridge,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String reactionId,
  required String inboxRetryPayload,
  required bool staged,
}) async {
  try {
    await storeGroupOfflineReplayFromRetryPayload(
      bridge: bridge,
      inboxRetryPayload: inboxRetryPayload,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_INBOX_STORE_FAILED',
      details: {'error': e.toString()},
    );
    if (staged) {
      await reactionReplayOutboxRepo.updateEntryStatus(
        reactionId,
        deliveryStatus: GroupReactionReplayOutboxStatus.failed,
        lastError: e.toString(),
      );
    }
    return;
  }

  if (!staged) return;

  try {
    await reactionReplayOutboxRepo.updateEntryStatus(
      reactionId,
      deliveryStatus: GroupReactionReplayOutboxStatus.stored,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_OUTBOX_STORE_MARK_FAILED',
      details: {'error': e.toString()},
    );
  }
}
