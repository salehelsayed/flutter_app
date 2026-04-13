import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of handling an incoming group reaction.
enum HandleGroupReactionResult {
  success,
  parseError,
  unknownGroup,
  unknownSender,
  senderMismatch,
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
  required String groupId,
  required String senderId,
  required String reactionJson,
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

  // 4. Validate sender is a member (optional — member list may be stale)
  final member = await groupRepo.getMember(groupId, senderId);
  if (member == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_RECEIVE_UNKNOWN_SENDER',
      details: {
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      },
    );
    // Still process — member list may be stale
  }

  // 5. Process action
  if (payload.action == 'remove') {
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

  // action == 'add'
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
