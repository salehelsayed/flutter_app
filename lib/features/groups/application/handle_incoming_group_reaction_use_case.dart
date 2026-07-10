import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_reaction.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Per-group cap on the durable pending-reaction buffer (oldest-first eviction).
const kMaxBufferedGroupReactionsPerGroup = 50;

/// How long a buffered reaction is retained before TTL eviction.
const kBufferedGroupReactionTtl = Duration(days: 7);

/// Result of handling an incoming group reaction.
enum HandleGroupReactionResult {
  success,
  parseError,
  unknownGroup,
  unknownMessage,

  /// The reaction is fully validated but its target message has not arrived
  /// yet, so it was durably buffered for replay when the message lands
  /// (INV-R4) instead of being dropped as [unknownMessage].
  bufferedPendingMessage,

  /// 235: the exact `(groupId, messageId)` target was locally deleted
  /// (migration-069 tombstone). The reaction is discarded — never buffered
  /// into `group_pending_reactions` or a retry path — so a Delete-for-me
  /// cannot be refilled by late reactions.
  discardedLocallyDeleted,
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
  GroupPendingReactionRepository? pendingReactionRepo,
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
      // 235: a locally tombstoned exact (groupId, messageId) target is
      // DELETED, not merely late — discard instead of buffering so a
      // Delete-for-me cannot be refilled by later reactions. A tombstone
      // belonging to another group does not discard (that message id was
      // never this group's deletion).
      final tombstoneGroupId = await msgRepo.getLocalDeletionGroupId(
        payload.messageId,
      );
      if (tombstoneGroupId != null && tombstoneGroupId == groupId) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REACTION_DISCARDED_LOCALLY_DELETED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'messageId': payload.messageId.length > 8
                ? payload.messageId.substring(0, 8)
                : payload.messageId,
          },
        );
        return (HandleGroupReactionResult.discardedLocallyDeleted, null);
      }
      // The reaction is fully validated but its target message has not landed
      // yet. When a durable buffer is wired, retain it for replay on message
      // arrival (INV-R4) instead of dropping it as unknownMessage. Buffering
      // here covers BOTH the live-listener and offline-drain call sites.
      if (pendingReactionRepo != null) {
        await _bufferPendingReaction(
          pendingReactionRepo: pendingReactionRepo,
          groupId: groupId,
          payload: payload,
          reactionJson: reactionJson,
          transportPeerId: transportPeerId,
          senderDeviceId: senderDeviceId,
          senderPublicKey: senderPublicKey,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REACTION_BUFFERED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'messageId': payload.messageId.length > 8
                ? payload.messageId.substring(0, 8)
                : payload.messageId,
          },
        );
        return (HandleGroupReactionResult.bufferedPendingMessage, null);
      }
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

  // 5b. Last-writer-wins: drop an event older than the currently-stored
  //     reaction for this (messageId, senderPeerId). Mirrors the 1:1 guard in
  //     handle_incoming_reaction_use_case.dart so concurrent add/remove can't
  //     commit out of order (INV-R7). Compares parsed DateTimes, not the raw
  //     ISO-8601 strings. Gated BEFORE the add/remove branch so the remove
  //     direction is covered while the add row still carries a comparand.
  final currentReaction =
      await reactionRepo.getReactionForSenderIncludingRemoved(
    messageId: payload.messageId,
    senderPeerId: payload.senderPeerId,
  );
  if (_isStaleComparedToCurrent(
    incomingTimestamp: payload.timestamp,
    // Comparand is the latest event's timestamp: a tombstone's removed_at when
    // present, else the add timestamp (INV-T2). This is what lets a remove be
    // defended from a later stale add.
    currentTimestamp: currentReaction == null
        ? null
        : (currentReaction.removedAt ?? currentReaction.timestamp),
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_STALE_IGNORED',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
        'incomingAction': payload.action,
        'incomingEmoji': payload.emoji,
      },
    );
    return (HandleGroupReactionResult.success, null);
  }

  // 6. Process action
  if (payload.action == GroupReactionPayload.actionRemove) {
    await reactionRepo.removeReaction(
      payload.messageId,
      payload.senderPeerId,
      removedAtTimestamp: payload.timestamp,
    );
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

/// Durably buffers a validated reaction whose target message is absent, then
/// bounds the buffer (TTL, then per-group oldest-first cap). Dedup is handled
/// by the deterministic reaction id (the buffer row PK).
Future<void> _bufferPendingReaction({
  required GroupPendingReactionRepository pendingReactionRepo,
  required String groupId,
  required GroupReactionPayload payload,
  required String reactionJson,
  required String? transportPeerId,
  required String? senderDeviceId,
  required String? senderPublicKey,
}) async {
  final now = DateTime.now().toUtc();
  await pendingReactionRepo.savePendingReaction(
    GroupPendingReaction(
      id: payload.id,
      groupId: groupId,
      messageId: payload.messageId,
      senderPeerId: payload.senderPeerId,
      transportPeerId: transportPeerId,
      senderDeviceId: senderDeviceId,
      senderPublicKey: senderPublicKey,
      reactionJson: reactionJson,
      receivedAt: now,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await pendingReactionRepo.deleteExpired(
    olderThan: now.subtract(kBufferedGroupReactionTtl),
  );
  await pendingReactionRepo.pruneGroup(
    groupId,
    maxRows: kMaxBufferedGroupReactionsPerGroup,
  );
}

/// True when [incomingTimestamp] is strictly older than [currentTimestamp].
/// Parses both ISO-8601 strings to [DateTime]; never treats a missing or
/// unparseable comparand as stale (fail-open). Mirrors the 1:1 guard.
bool _isStaleComparedToCurrent({
  required String incomingTimestamp,
  required String? currentTimestamp,
}) {
  if (currentTimestamp == null) return false;

  final incomingTime = DateTime.tryParse(incomingTimestamp);
  final currentTime = DateTime.tryParse(currentTimestamp);
  if (incomingTime == null || currentTime == null) return false;

  return incomingTime.isBefore(currentTime);
}
