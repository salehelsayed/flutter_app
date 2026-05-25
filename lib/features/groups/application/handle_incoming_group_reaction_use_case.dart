import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of handling an incoming group reaction.
enum HandleGroupReactionResult {
  success,
  parseError,
  unknownGroup,
  unknownMessage,
  messageGroupMismatch,
  unknownSender,
  senderMismatch,
  ignoredAfterDissolve,
}

/// Handles an incoming group reaction event.
///
/// The Go layer has already decrypted the v3 group_reaction envelope and
/// provides the raw JSON payload. This function parses, validates, and
/// persists the reaction.
///
/// Returns (result, ReactionChange?) — change is non-null on success.
Future<(HandleGroupReactionResult, ReactionChange?)>
handleIncomingGroupReaction({
  required GroupRepository groupRepo,
  required ReactionRepository reactionRepo,
  GroupMessageRepository? msgRepo,
  required String groupId,
  required String senderId,
  required String reactionJson,
  String? transportPeerId,
  String? senderDeviceId,
  String? senderPublicKey,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_RECEIVE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
    },
  );

  // 1. Parse reaction payload
  final payload = GroupReactionPayload.fromDecryptedJson(reactionJson);
  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_PARSE_ERROR',
      details: {},
    );
    return (HandleGroupReactionResult.parseError, null);
  }

  // 2. Validate group exists
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_UNKNOWN_GROUP',
      details: {},
    );
    return (HandleGroupReactionResult.unknownGroup, null);
  }

  final reactionTimestamp = _parseReactionTimestamp(payload.timestamp);
  final dissolvedAt = group.dissolvedAt?.toUtc();
  if (group.isDissolved &&
      (dissolvedAt == null || !reactionTimestamp.isBefore(dissolvedAt))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_IGNORED_AFTER_DISSOLVE',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        if (dissolvedAt != null) 'dissolvedAt': dissolvedAt.toIso8601String(),
      },
    );
    return (HandleGroupReactionResult.ignoredAfterDissolve, null);
  }

  // 3. Bind the decrypted payload sender to the outer transport sender.
  if (payload.senderPeerId != senderId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_SENDER_MISMATCH',
      details: {
        'transportSender': senderId.length > 10
            ? senderId.substring(0, 10)
            : senderId,
        'payloadSender': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (HandleGroupReactionResult.senderMismatch, null);
  }

  // 4. Validate sender is a member before creating visible reaction state.
  final member = await groupRepo.getMember(groupId, senderId);
  if (member == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_UNKNOWN_SENDER',
      details: {
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      },
    );
    return (HandleGroupReactionResult.unknownSender, null);
  }
  if (!_isReactionSenderDeviceBound(
    member: member,
    senderDeviceId: senderDeviceId,
    transportPeerId: transportPeerId,
    senderPublicKey: senderPublicKey,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_UNBOUND_DEVICE_REJECTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      },
    );
    return (HandleGroupReactionResult.senderMismatch, null);
  }

  // 5. Validate target message when the caller can provide local message state.
  if (msgRepo != null) {
    final targetMessage = await msgRepo.getMessage(payload.messageId);
    if (targetMessage == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'messageId': payload.messageId.length > 8
              ? payload.messageId.substring(0, 8)
              : payload.messageId,
        },
      );
      return (HandleGroupReactionResult.unknownMessage, null);
    }
    if (targetMessage.groupId != groupId) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_RECEIVE_MESSAGE_GROUP_MISMATCH',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'targetGroupId': targetMessage.groupId.length > 8
              ? targetMessage.groupId.substring(0, 8)
              : targetMessage.groupId,
          'messageId': payload.messageId.length > 8
              ? payload.messageId.substring(0, 8)
              : payload.messageId,
        },
      );
      return (HandleGroupReactionResult.messageGroupMismatch, null);
    }
  }

  // 6. Process action
  if (payload.action == GroupReactionPayload.actionRemove) {
    await reactionRepo.removeReaction(payload.messageId, payload.senderPeerId);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_REMOVED',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
        'emoji': payload.emoji,
      },
    );
    return (
      HandleGroupReactionResult.success,
      ReactionChange.removed(
        messageId: payload.messageId,
        senderPeerId: payload.senderPeerId,
      ),
    );
  }

  if (payload.action != GroupReactionPayload.actionAdd) {
    return (HandleGroupReactionResult.parseError, null);
  }

  final reaction = payload.toMessageReaction();
  await reactionRepo.saveReaction(reaction);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_RECEIVE_STORED',
    details: {
      'id': reaction.id.length > 8 ? reaction.id.substring(0, 8) : reaction.id,
      'emoji': reaction.emoji,
    },
  );

  return (HandleGroupReactionResult.success, ReactionChange.upsert(reaction));
}

bool _isReactionSenderDeviceBound({
  required GroupMember member,
  required String? senderDeviceId,
  required String? transportPeerId,
  required String? senderPublicKey,
}) {
  final resolvedTransportPeerId = transportPeerId?.trim().isNotEmpty == true
      ? transportPeerId!.trim()
      : member.peerId;
  final resolvedSenderPublicKey = senderPublicKey?.trim();
  if (member.devices.isEmpty) {
    if (resolvedSenderPublicKey != null &&
        resolvedSenderPublicKey.isNotEmpty &&
        member.publicKey?.trim() != resolvedSenderPublicKey) {
      return false;
    }
    return resolvedTransportPeerId == member.peerId;
  }
  final device = senderDeviceId?.trim().isNotEmpty == true
      ? member.findDeviceById(senderDeviceId)
      : member.findDeviceByTransportPeerId(resolvedTransportPeerId);
  return device != null &&
      device.isActive &&
      device.transportPeerId == resolvedTransportPeerId &&
      (resolvedSenderPublicKey == null ||
          resolvedSenderPublicKey.isEmpty ||
          device.deviceSigningPublicKey == resolvedSenderPublicKey);
}

DateTime _parseReactionTimestamp(String timestamp) {
  return DateTime.parse(timestamp).toUtc();
}
