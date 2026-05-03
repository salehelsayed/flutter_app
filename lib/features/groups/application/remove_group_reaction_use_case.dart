import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of removing an emoji reaction from a group message.
enum RemoveGroupReactionResult {
  success,
  groupNotFound,
  groupDissolved,
  notMember,
  publishFailed,
}

const _uuid = Uuid();

/// Sends a "remove" reaction to a group via GossipSub and deletes locally.
Future<RemoveGroupReactionResult> removeGroupReaction({
  required Bridge bridge,
  required GroupRepository groupRepo,
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
    event: 'GROUP_REACTION_REMOVE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  // 1. Validate group exists
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return RemoveGroupReactionResult.groupNotFound;
  }

  if (group.isDissolved) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REMOVE_GROUP_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        if (group.dissolvedAt != null)
          'dissolvedAt': group.dissolvedAt!.toUtc().toIso8601String(),
      },
    );
    return RemoveGroupReactionResult.groupDissolved;
  }

  // 2. Validate sender is a member
  final member = await groupRepo.getMember(groupId, senderPeerId);
  if (member == null) {
    return RemoveGroupReactionResult.notMember;
  }
  final senderDevice = member.firstActiveDeviceForSigningKey(
    senderPublicKey,
    allowLegacyFallback: true,
  );

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
      senderDeviceId: senderDevice?.deviceId,
      senderTransportPeerId: senderDevice?.transportPeerId,
      senderDevicePublicKey: senderDevice?.deviceSigningPublicKey,
      senderKeyPackageId: senderDevice?.keyPackageId,
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
  await _stageRemoveReactionInboxStore(
    bridge: bridge,
    groupRepo: groupRepo,
    reactionReplayOutboxRepo: reactionReplayOutboxRepo,
    groupId: groupId,
    payload: payload,
    senderPublicKey: senderDevice?.deviceSigningPublicKey ?? senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    senderDevice: senderDevice,
  );

  // 6. Delete locally
  await reactionRepo.removeReaction(messageId, senderPeerId);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_REMOVE_SUCCESS',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  return RemoveGroupReactionResult.success;
}

Future<void> _stageRemoveReactionInboxStore({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String groupId,
  required GroupReactionPayload payload,
  required String senderPublicKey,
  required String senderPrivateKey,
  required GroupMemberDeviceIdentity? senderDevice,
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
      senderDeviceId: senderDevice?.deviceId,
      senderTransportPeerId: senderDevice?.transportPeerId,
      senderKeyPackageId: senderDevice?.keyPackageId,
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
    _attemptRemoveReactionInboxStore(
      bridge: bridge,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      reactionId: payload.id,
      inboxRetryPayload: inboxRetryPayload,
      staged: staged,
    ),
  );
}

Future<void> _attemptRemoveReactionInboxStore({
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
