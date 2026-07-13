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

  // 4. Send — FDC-18: fire the durable inbox copy CONCURRENTLY with the live
  //    send for an unknown-presence (non-connected) peer, mirroring FDC-03 onto
  //    the reaction path. A slow/offline peer's toggle takes custody immediately
  //    (not on a late serial tail); an online peer's toggle is still delivered
  //    live, the inbox copy a deduped parallel safety net (NOT demoted to
  //    inbox-only). The SAME [jsonString] envelope is deposited, so the drained
  //    copy is byte-identical and the receiver's last-writer-wins tombstone
  //    dedups it. A live-connected peer keeps a single live path
  //    (confirmed-path => single-path). Exactly one storeInInbox per toggle.
  final unknownPresence = !p2pService.isConnectedToPeer(targetPeerId);

  Future<bool>? concurrentInbox;
  if (unknownPresence) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_SEND_CONCURRENT_INBOX_BEGIN',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
      },
    );
    concurrentInbox = p2pService
        .storeInInbox(targetPeerId, jsonString)
        .catchError((_) => false);
  }

  bool delivered;
  try {
    final sent = await p2pService.sendMessage(targetPeerId, jsonString);
    if (sent) {
      // Live win (connected single-path OR unknown-presence live win). Do NOT
      // await the concurrent deposit — it lands in background custody and is
      // deduped on receive.
      delivered = true;
    } else if (concurrentInbox != null) {
      // Unknown presence + live miss: the SAME concurrent deposit is the
      // delivery tier. Await it — do NOT start a fresh serial store.
      delivered = await concurrentInbox;
    } else {
      // Connected-but-failed edge: the only path that starts a fresh serial
      // store (preserves exactly-one for a confirmed peer whose live leg died).
      delivered = await p2pService.storeInInbox(targetPeerId, jsonString);
    }
  } catch (e) {
    // Live send threw. For unknown presence the concurrent deposit may already
    // hold custody — honor it. For a connected peer (no concurrent arm) preserve
    // today's catch behaviour: sendFailed with no deposit.
    if (concurrentInbox != null) {
      delivered = await concurrentInbox;
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_SEND_FAILED',
        details: {'error': e.toString()},
      );
      return (SendReactionResult.sendFailed, null);
    }
  }

  if (!delivered) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_SEND_FAILED',
      details: {'reason': 'direct_and_inbox_failed'},
    );
    return (SendReactionResult.sendFailed, null);
  }

  // 5. Persist locally
  final reaction = payload.toMessageReaction();
  await reactionRepo.saveReaction(reaction);

  emitFlowEvent(
    layer: 'FL',
    event: 'REACTION_SEND_SUCCESS',
    details: {'id': reactionId.substring(0, 8), 'emoji': emoji},
  );

  return (SendReactionResult.success, reaction);
}
