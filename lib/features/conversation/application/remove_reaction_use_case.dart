import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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

/// Sends a "remove" reaction to a contact via P2P (v2 encrypted only)
/// and deletes the local reaction.
Future<RemoveReactionResult> removeReaction({
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
    event: 'REACTION_REMOVE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  // 1. Check P2P node
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REMOVE_NODE_NOT_RUNNING',
      details: {},
    );
    return RemoveReactionResult.nodeNotRunning;
  }

  // 2. Build remove payload
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

  // 4. Send — try direct, fall back to inbox
  try {
    final sent = await p2pService.sendMessage(targetPeerId, jsonString);
    if (!sent) {
      final storedInInbox = await p2pService.storeInInbox(
        targetPeerId,
        jsonString,
      );
      if (!storedInInbox) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REACTION_REMOVE_SEND_FAILED',
          details: {'reason': 'direct_and_inbox_failed'},
        );
        return RemoveReactionResult.sendFailed;
      }
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REMOVE_SEND_FAILED',
      details: {'error': e.toString()},
    );
    return RemoveReactionResult.sendFailed;
  }

  // 5. Delete locally
  await reactionRepo.removeReaction(messageId, senderPeerId);

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
