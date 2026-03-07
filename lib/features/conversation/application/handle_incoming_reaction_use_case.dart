import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Result of handling an incoming reaction.
enum HandleReactionResult {
  /// Reaction processed (added or removed).
  success,

  /// Not a message_reaction type.
  notReaction,

  /// Sender is not a known contact.
  unknownSender,

  /// Decryption failed (v2 required).
  decryptionFailed,
}

/// Parses an incoming P2P ChatMessage for message_reaction type,
/// decrypts (v2 only), validates the sender, and persists.
///
/// Returns (result, ReactionChange?) — change is non-null on success.
Future<(HandleReactionResult, ReactionChange?)> handleIncomingReaction({
  required ChatMessage message,
  required ReactionRepository reactionRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  required String? ownMlKemSecretKey,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'REACTION_RECEIVE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  // 1. Try v2 encrypted envelope (v1 reactions are rejected — encryption required)
  final v2Envelope = ReactionPayload.parseEncryptedEnvelope(message.content);
  if (v2Envelope == null) {
    // Could be v1 or not a reaction at all
    final v1Payload = ReactionPayload.fromJson(message.content);
    if (v1Payload == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_RECEIVE_NOT_REACTION',
        details: {},
      );
      return (HandleReactionResult.notReaction, null);
    }
    // v1 reactions are rejected — encryption required
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_V1_REJECTED',
      details: {},
    );
    return (HandleReactionResult.notReaction, null);
  }

  // 2. Decrypt
  if (ownMlKemSecretKey == null) {
    emitFlowEvent(layer: 'FL', event: 'REACTION_RECEIVE_NO_KEY', details: {});
    return (HandleReactionResult.decryptionFailed, null);
  }

  ReactionPayload? payload;
  final encrypted = v2Envelope['encrypted'] as Map<String, dynamic>;
  try {
    final decryptResult = await callDecryptMessage(
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
      kem: encrypted['kem'] as String,
      ciphertext: encrypted['ciphertext'] as String,
      nonce: encrypted['nonce'] as String,
    );

    if (decryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_RECEIVE_DECRYPT_FAILED',
        details: {'errorCode': decryptResult['errorCode']},
      );
      return (HandleReactionResult.decryptionFailed, null);
    }

    payload = ReactionPayload.fromDecryptedJson(
      decryptResult['plaintext'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_DECRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return (HandleReactionResult.decryptionFailed, null);
  }

  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_PARSE_FAILED',
      details: {},
    );
    return (HandleReactionResult.notReaction, null);
  }

  // 3. Validate sender is a known contact
  final contact = await contactRepo.getContact(payload.senderPeerId);
  if (contact == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_UNKNOWN_SENDER',
      details: {
        'senderPeerId': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (HandleReactionResult.unknownSender, null);
  }

  // 4. Process action
  if (payload.action == 'remove') {
    await reactionRepo.removeReaction(payload.messageId, payload.senderPeerId);
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_REMOVED',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
        'emoji': payload.emoji,
      },
    );
    return (
      HandleReactionResult.success,
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
    event: 'REACTION_RECEIVE_STORED',
    details: {
      'id': reaction.id.length > 8 ? reaction.id.substring(0, 8) : reaction.id,
      'emoji': reaction.emoji,
    },
  );

  return (HandleReactionResult.success, ReactionChange.upsert(reaction));
}
