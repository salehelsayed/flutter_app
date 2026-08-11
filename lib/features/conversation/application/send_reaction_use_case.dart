import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/deliver_outgoing_direct_reaction_custody.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

/// 361: the shared blob-free reaction fanout tail for ADD/REMOVE. Returns null
/// when the incumbent single-target path should continue unchanged.
Future<(SendReactionResult, MessageReaction?)?> authorDirectReactionFanout({
  required DirectEventFanoutAuthoring directEventFanout,
  required P2PService p2pService,
  required OutgoingDirectReactionInboxCustodyRepository custodyRepo,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
  required String targetPeerId,
  required String messageId,
  required String action,
  required ReactionPayload payload,
  required String flowPrefix,
}) async {
  final routing = await directEventFanout.decideRoute(targetPeerId);
  switch (routing.route) {
    case DirectEventFanoutRoute.incumbentLegacy:
      return null;
    case DirectEventFanoutRoute.refusedSelectorOff:
    case DirectEventFanoutRoute.refusedUnavailable:
      emitFlowEvent(
        layer: 'FL',
        event: '${flowPrefix}_FANOUT_REFUSED',
        details: {'reason': routing.route.name},
      );
      return (SendReactionResult.sendFailed, null);
    case DirectEventFanoutRoute.fanout:
      break;
  }
  final snapshot = routing.snapshot!;
  final candidates = await directEventFanout.buildCandidates(
    snapshot: snapshot,
    innerPayloadJson: payload.toInnerJson(),
    buildEnvelope: ({required kem, required ciphertext, required nonce}) =>
        ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: directEventFanout.senderTransportPeerId,
          eventId: payload.id,
          action: action,
          targetMessageId: messageId,
          kem: kem,
          ciphertext: ciphertext,
          nonce: nonce,
        ),
  );
  if (candidates == null) {
    return (SendReactionResult.encryptionFailed, null);
  }
  final authoredReaction = action == ReactionPayload.removeAction
      ? payload.toMessageReaction().copyWith(removedAt: payload.timestamp)
      : payload.toMessageReaction();
  final staged = await directEventFanout.stageReactionFanout(
    reactionRow: authoredReaction.toMap(),
    action: action,
    parentMessageId: messageId,
    contactAccountPeerId: targetPeerId,
    senderTransportPeerId: directEventFanout.senderTransportPeerId,
    expectedSnapshot: snapshot,
    candidates: candidates,
  );
  switch (staged.outcome) {
    case DirectEventFanoutStageOutcome.refused:
      emitFlowEvent(
        layer: 'FL',
        event: '${flowPrefix}_FANOUT_STAGE_REFUSED',
        details: const {},
      );
      return (SendReactionResult.sendFailed, null);
    case DirectEventFanoutStageOutcome.terminal:
      return (SendReactionResult.success, authoredReaction);
    case DirectEventFanoutStageOutcome.survivorReplay:
    case DirectEventFanoutStageOutcome.applied:
      break;
  }
  if (!p2pService.currentState.isStarted) {
    return (SendReactionResult.nodeNotRunning, authoredReaction);
  }
  var allDelivered = true;
  for (final row in staged.rows ?? const <Map<String, Object?>>[]) {
    final delivery = await deliverOutgoingDirectReactionCustody(
      p2pService: p2pService,
      storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
      custodyRepository: custodyRepo,
      custody: DirectReactionInboxCustodyOutboxEntry.fromMap(row),
      flowPrefix: flowPrefix,
    );
    allDelivered = allDelivered && delivery.delivered;
  }
  return (
    allDelivered ? SendReactionResult.success : SendReactionResult.sendFailed,
    authoredReaction,
  );
}

/// Result of sending an emoji reaction.
enum SendReactionResult {
  success,
  nodeNotRunning,
  encryptionRequired,
  encryptionFailed,
  sendFailed,
}

const _uuid = Uuid();

/// Sends an emoji reaction to a contact via P2P (v2 encrypted only).
///
/// 1. Enforces v2 encryption
/// 2. Atomically stages the canonical ADD and exact encrypted custody row
/// 3. Returns a committed diagnostic when the node is stopped
/// 4. Otherwise races live delivery with one typed inbox handoff
///
/// The reaction is non-null after any successful local stage, even when the
/// immediate transport diagnostic is `nodeNotRunning` or `sendFailed`.
Future<(SendReactionResult, MessageReaction?)> sendReaction({
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
    event: 'REACTION_SEND_START',
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
      event: 'REACTION_SEND_CUSTODY_CAPABILITY_REFUSED',
      details: {
        'reason': custodyRepo == null
            ? 'missing_reaction_custody_repository'
            : 'missing_ack_or_expiry_inbox_store',
      },
    );
    return (SendReactionResult.sendFailed, null);
  }

  // Build and encrypt before consulting node state. A stopped node still owns
  // the exact authored transition once its atomic local custody stage commits.
  final reactionId = _uuid.v4();
  final timestamp = DateTime.now().toUtc().toIso8601String();

  final payload = ReactionPayload(
    id: reactionId,
    messageId: messageId,
    emoji: emoji,
    action: 'add',
    senderPeerId: senderPeerId,
    timestamp: timestamp,
  );

  // 361: the v113 fanout owner may claim this ADD before any single-target
  // crypto. `null` means the incumbent path continues byte-for-byte.
  if (directEventFanout != null) {
    final fanout = await authorDirectReactionFanout(
      directEventFanout: directEventFanout,
      p2pService: p2pService,
      custodyRepo: custodyRepo,
      storeInAckCustodyInboxDetailed: effectiveStoreInAckCustodyInboxDetailed,
      targetPeerId: targetPeerId,
      messageId: messageId,
      action: ReactionPayload.addAction,
      payload: payload,
      flowPrefix: 'REACTION_SEND',
    );
    if (fanout != null) return fanout;
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
        event: 'REACTION_SEND_ENCRYPT_FAILED',
        details: {'errorCode': encryptResult['errorCode']},
      );
      return (SendReactionResult.encryptionFailed, null);
    }
    jsonString = ReactionPayload.buildEncryptedEnvelope(
      senderPeerId: senderPeerId,
      eventId: reactionId,
      action: ReactionPayload.addAction,
      targetMessageId: messageId,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_SEND_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return (SendReactionResult.encryptionFailed, null);
  }

  final authoredReaction = payload.toMessageReaction();
  late MessageReaction committedReaction;
  late DirectReactionInboxCustodyOutboxEntry custody;
  try {
    final staged = await custodyRepo.stageOutgoingDirectReactionInboxCustody(
      reaction: authoredReaction,
      recipientPeerId: targetPeerId,
      action: ReactionPayload.addAction,
      wireEnvelope: jsonString,
    );
    final stagedReaction = staged.reaction;
    final stagedCustody = staged.custody;
    if (!staged.authorizesTransport ||
        stagedReaction == null ||
        stagedCustody == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_SEND_CUSTODY_STAGE_REFUSED',
        details: {'reason': staged.outcome.name},
      );
      return (SendReactionResult.sendFailed, null);
    }
    committedReaction = stagedReaction;
    custody = stagedCustody;
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_SEND_CUSTODY_STAGE_ERROR',
      details: {'errorType': error.runtimeType.toString()},
    );
    return (SendReactionResult.sendFailed, null);
  }

  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_SEND_NODE_NOT_RUNNING',
      details: const {'custodyStaged': true},
    );
    return (SendReactionResult.nodeNotRunning, committedReaction);
  }

  final delivery = await deliverOutgoingDirectReactionCustody(
    p2pService: p2pService,
    storeInAckCustodyInboxDetailed: effectiveStoreInAckCustodyInboxDetailed,
    custodyRepository: custodyRepo,
    custody: custody,
    flowPrefix: 'REACTION_SEND',
  );
  if (!delivery.delivered) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_SEND_FAILED',
      details: const {'reason': 'direct_and_inbox_failed'},
    );
    return (SendReactionResult.sendFailed, committedReaction);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'REACTION_SEND_SUCCESS',
    details: {'id': reactionId.substring(0, 8), 'emoji': emoji},
  );

  return (SendReactionResult.success, committedReaction);
}
