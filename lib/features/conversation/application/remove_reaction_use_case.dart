import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/deliver_outgoing_direct_reaction_custody.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

/// Result of removing an emoji reaction.
enum RemoveReactionResult {
  success,
  nodeNotRunning,
  encryptionRequired,
  encryptionFailed,
  sendFailed,
}

const _uuid = Uuid();

/// Authors a v2 encrypted REMOVE, atomically stages its complete local
/// tombstone plus exact custody row, then races live and typed inbox delivery.
Future<RemoveReactionResult> removeReaction({
  required P2PService p2pService,
  required Bridge bridge,
  required ReactionRepository reactionRepo,
  required String targetPeerId,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String recipientMlKemPublicKey,
  StoreInAckCustodyInboxDetailedFn? storeInAckCustodyInboxDetailed,
  DirectEventFanoutAuthoring? directEventFanout,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'REACTION_REMOVE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  final custodyCapability =
      reactionRepo is OutgoingDirectReactionInboxCustodyRepository
      ? reactionRepo as OutgoingDirectReactionInboxCustodyRepository
      : null;
  final custodyRepo =
      custodyCapability?.supportsDirectReactionInboxCustody == true
      ? custodyCapability
      : null;
  final ackCustodyInboxStore = p2pService is AckOrExpiryInboxStore
      ? p2pService as AckOrExpiryInboxStore
      : null;
  final effectiveStoreInAckCustodyInboxDetailed =
      storeInAckCustodyInboxDetailed ??
      ackCustodyInboxStore?.storeInAckCustodyInboxDetailed;
  if (custodyRepo == null || effectiveStoreInAckCustodyInboxDetailed == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REMOVE_CUSTODY_CAPABILITY_REFUSED',
      details: {
        'reason': custodyRepo == null
            ? 'missing_reaction_custody_repository'
            : 'missing_ack_or_expiry_inbox_store',
      },
    );
    return RemoveReactionResult.sendFailed;
  }

  // Build and encrypt before consulting node state so a stopped node still
  // leaves one exact durable REMOVE obligation.
  final reactionId = _uuid.v4();
  final timestamp = DateTime.now().toUtc().toIso8601String();

  final payload = ReactionPayload(
    id: reactionId,
    messageId: messageId,
    emoji: emoji,
    action: 'remove',
    senderPeerId: senderPeerId,
    timestamp: timestamp,
  );

  // 361: the v113 fanout owner may claim this REMOVE before any
  // single-target crypto. `null` means the incumbent path continues.
  if (directEventFanout != null) {
    final fanout = await authorDirectReactionFanout(
      directEventFanout: directEventFanout,
      p2pService: p2pService,
      custodyRepo: custodyRepo,
      storeInAckCustodyInboxDetailed: effectiveStoreInAckCustodyInboxDetailed,
      targetPeerId: targetPeerId,
      messageId: messageId,
      action: ReactionPayload.removeAction,
      payload: payload,
      flowPrefix: 'REACTION_REMOVE',
    );
    if (fanout != null) {
      return switch (fanout.$1) {
        SendReactionResult.success => RemoveReactionResult.success,
        SendReactionResult.nodeNotRunning =>
          RemoveReactionResult.nodeNotRunning,
        SendReactionResult.encryptionRequired =>
          RemoveReactionResult.encryptionRequired,
        SendReactionResult.encryptionFailed =>
          RemoveReactionResult.encryptionFailed,
        SendReactionResult.sendFailed => RemoveReactionResult.sendFailed,
      };
    }
  }

  // 3. Encrypt
  String jsonString;
  try {
    final innerJson = payload.toInnerJson();
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      plaintext: innerJson,
    );
    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_REMOVE_ENCRYPT_FAILED',
        details: {'errorCode': encryptResult['errorCode']},
      );
      return RemoveReactionResult.encryptionFailed;
    }
    jsonString = ReactionPayload.buildEncryptedEnvelope(
      senderPeerId: senderPeerId,
      eventId: reactionId,
      action: ReactionPayload.removeAction,
      targetMessageId: messageId,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REMOVE_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return RemoveReactionResult.encryptionFailed;
  }

  final authoredTombstone = payload.toMessageReaction().copyWith(
    removedAt: timestamp,
  );
  late DirectReactionInboxCustodyOutboxEntry custody;
  try {
    final staged = await custodyRepo.stageOutgoingDirectReactionInboxCustody(
      reaction: authoredTombstone,
      recipientPeerId: targetPeerId,
      action: ReactionPayload.removeAction,
      wireEnvelope: jsonString,
    );
    final stagedCustody = staged.custody;
    if (!staged.authorizesTransport ||
        staged.reaction == null ||
        stagedCustody == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_REMOVE_CUSTODY_STAGE_REFUSED',
        details: {'reason': staged.outcome.name},
      );
      return RemoveReactionResult.sendFailed;
    }
    custody = stagedCustody;
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REMOVE_CUSTODY_STAGE_ERROR',
      details: {'errorType': error.runtimeType.toString()},
    );
    return RemoveReactionResult.sendFailed;
  }

  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REMOVE_NODE_NOT_RUNNING',
      details: const {'custodyStaged': true},
    );
    return RemoveReactionResult.nodeNotRunning;
  }

  final delivery = await deliverOutgoingDirectReactionCustody(
    p2pService: p2pService,
    storeInAckCustodyInboxDetailed: effectiveStoreInAckCustodyInboxDetailed,
    custodyRepository: custodyRepo,
    custody: custody,
    flowPrefix: 'REACTION_REMOVE',
  );
  if (!delivery.delivered) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REMOVE_SEND_FAILED',
      details: const {'reason': 'direct_and_inbox_failed'},
    );
    return RemoveReactionResult.sendFailed;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'REACTION_REMOVE_SUCCESS',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  return RemoveReactionResult.success;
}
