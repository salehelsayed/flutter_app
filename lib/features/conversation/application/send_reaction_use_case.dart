import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

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
/// 1. Checks P2P node is running
/// 2. Enforces v2 encryption
/// 3. Encrypts payload, sends v2 envelope
/// 4. Persists locally (optimistic)
/// 5. Falls back to inbox when peer offline
///
/// Returns (result, MessageReaction?) — reaction is non-null on success.
Future<(SendReactionResult, MessageReaction?)> sendReaction({
  required P2PService p2pService,
  required Bridge bridge,
  required ReactionRepository reactionRepo,
  required String targetPeerId,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String recipientMlKemPublicKey,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'REACTION_SEND_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  // 1. Check P2P node
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    return (SendReactionResult.nodeNotRunning, null);
  }

  // 2. Build payload
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

  // 4. Send — try direct, fall back to inbox
  try {
    final sent = await p2pService.sendMessage(targetPeerId, jsonString);
    if (!sent) {
      await p2pService.storeInInbox(targetPeerId, jsonString);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_SEND_FAILED',
      details: {'error': e.toString()},
    );
    return (SendReactionResult.sendFailed, null);
  }

  // 5. Persist locally
  final reaction = payload.toMessageReaction();
  await reactionRepo.saveReaction(reaction);

  emitFlowEvent(
    layer: 'FL',
    event: 'REACTION_SEND_SUCCESS',
    details: {
      'id': reactionId.substring(0, 8),
      'emoji': emoji,
    },
  );

  return (SendReactionResult.success, reaction);
}
