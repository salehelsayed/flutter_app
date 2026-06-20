import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';

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

  /// Reaction target message is missing or no longer eligible for reactions.
  targetUnavailable,

  /// Stream sender and decrypted payload sender do not agree.
  senderMismatch,
}

/// Parses an incoming P2P ChatMessage for message_reaction type,
/// decrypts (v2 only), validates the sender, and persists.
///
/// Returns (result, ReactionChange?) — change is non-null on success.
Future<(HandleReactionResult, ReactionChange?)> handleIncomingReaction({
  required ChatMessage message,
  required MessageRepository messageRepo,
  required ReactionRepository reactionRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  required String? ownMlKemSecretKey,
  // 127-Bug-C: notify the recipient when a contact reacts to their 1:1 message.
  // All optional — when absent (e.g. unit tests / callers without the push
  // stack) no notification is attempted. Fired only on a genuine ADD upsert.
  NotificationService? notificationService,
  ActiveConversationTracker? conversationTracker,
  AppLifecycleState Function()? getAppLifecycleState,
  NotificationToneTracker? notificationToneTracker,
  ConsumeRecentRemoteNotificationAnnouncement?
  consumeRecentRemoteNotificationAnnouncement,
  MarkRecentRemoteNotificationAnnouncement?
  markRecentRemoteNotificationAnnouncement,
  bool suppressReactionNotification = false,
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
  final envelopeSenderPeerId = v2Envelope?['senderPeerId'] as String?;
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

  final senderMismatch =
      message.from != payload.senderPeerId ||
      envelopeSenderPeerId != payload.senderPeerId;
  if (senderMismatch) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_SENDER_MISMATCH',
      details: {
        'streamFrom': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'envelopeFrom': envelopeSenderPeerId == null
            ? '<missing>'
            : (envelopeSenderPeerId.length > 10
                  ? envelopeSenderPeerId.substring(0, 10)
                  : envelopeSenderPeerId),
        'payloadFrom': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (HandleReactionResult.senderMismatch, null);
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

  // 4. Validate the target message still exists and is not deleted.
  final targetMessage = await messageRepo.getMessage(payload.messageId);
  if (targetMessage == null || targetMessage.isDeleted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_TARGET_UNAVAILABLE',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
        'deleted': targetMessage?.isDeleted == true,
      },
    );
    return (HandleReactionResult.targetUnavailable, null);
  }

  final currentReaction =
      await reactionRepo.getReactionForSenderIncludingRemoved(
    messageId: payload.messageId,
    senderPeerId: payload.senderPeerId,
  );
  if (_isStaleComparedToCurrent(
    incomingTimestamp: payload.timestamp,
    // Comparand is the latest event's timestamp: a tombstone's removed_at when
    // present (always >= the add timestamp), else the add timestamp (INV-T2).
    currentTimestamp: currentReaction == null
        ? null
        : (currentReaction.removedAt ?? currentReaction.timestamp),
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_STALE_IGNORED',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
        'incomingAction': payload.action,
        'incomingEmoji': payload.emoji,
      },
    );
    return (HandleReactionResult.success, null);
  }

  // 5. Process action
  if (payload.action == 'remove') {
    await reactionRepo.removeReaction(
      payload.messageId,
      payload.senderPeerId,
      removedAtTimestamp: payload.timestamp,
    );
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

  // 127-Bug-C: a contact reacting to your 1:1 message now notifies, mirroring
  // the chat path (doc 118). Reuses maybeShowNotification so the same gates
  // apply: viewing-conversation suppression, recent-remote-push dedup, and the
  // 30s-per-conversation tone debounce (so rapid react/unreact never spams a
  // sound). Reached ONLY on a fresh ADD upsert — the remove and stale-ignored
  // branches return earlier, so un-reacts/duplicates stay silent. Fire-and-
  // forget: the OS call must never delay or fail the reaction commit/ack.
  if (notificationService != null &&
      conversationTracker != null &&
      getAppLifecycleState != null) {
    unawaited(
      maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: conversationTracker,
        getAppLifecycleState: getAppLifecycleState,
        contactPeerId: payload.senderPeerId,
        senderUsername: contact.username,
        messageText: 'Reacted ${payload.emoji} to your message',
        messageId: reaction.id,
        suppressNotification: suppressReactionNotification,
        suppressionReason: 'reaction_recovery_replay',
        toneTracker: notificationToneTracker,
        consumeRecentRemoteNotificationAnnouncement:
            consumeRecentRemoteNotificationAnnouncement,
        markRecentRemoteNotificationAnnouncement:
            markRecentRemoteNotificationAnnouncement,
      ),
    );
  }

  return (HandleReactionResult.success, ReactionChange.upsert(reaction));
}

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
