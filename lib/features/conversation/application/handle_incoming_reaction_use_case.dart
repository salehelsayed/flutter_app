import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
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

  /// Optional clear notification metadata disagrees with decrypted content.
  metadataMismatch,

  /// The sender is a known but blocked contact.
  blockedSender,
}

typedef StageDirectReactionNotificationDisplayCustody =
    Future<void> Function({
      required ReactionPayload payload,
      required ConversationMessage targetMessage,
    });
typedef CommitDirectReactionNotificationRemove =
    Future<void> Function({
      required String peerId,
      required String messageId,
      required String actorPeerId,
    });
typedef PromoteDirectReactionNotificationDisplayCustody =
    Future<void> Function({
      required ReactionPayload payload,
      required ConversationMessage targetMessage,
    });

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
  AppVisibilitySuppressionReader? appVisibility,
  NotificationToneTracker? notificationToneTracker,
  ConsumeRecentRemoteNotificationAnnouncement?
  consumeRecentRemoteNotificationAnnouncement,
  MarkRecentRemoteNotificationAnnouncement?
  markRecentRemoteNotificationAnnouncement,
  ResolveDurableNotificationCoordinator? durableNotificationCoordinatorResolver,
  LoadConversationNotificationSnapshot? loadConversationNotificationSnapshot,
  bool suppressReactionNotification = false,
  bool forceSilentReactionNotification = false,
  StageDirectReactionNotificationDisplayCustody?
  stageNotificationDisplayCustody,
  PromoteDirectReactionNotificationDisplayCustody?
  promoteNotificationDisplayCustody,
  CommitDirectReactionNotificationRemove? commitNotificationRemove,
  Future<void> Function()? retryNotificationDisplays,
  // 361: shared physical->logical reverse authority; null keeps the incumbent
  // transport==logical equality byte-identically.
  DirectTransportAuthorityResolver? transportAuthority,
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
  final envelopeEventId = v2Envelope?['eventId'] as String?;
  final envelopeAction = v2Envelope?['action'] as String?;
  final envelopeTargetMessageId = v2Envelope?['targetMessageId'] as String?;
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

  DirectTransportAuthorityResolution? transportResolution;
  bool senderMismatch;
  if (transportAuthority == null) {
    senderMismatch =
        message.from != payload.senderPeerId ||
        envelopeSenderPeerId != payload.senderPeerId;
  } else {
    transportResolution = await transportAuthority
        .resolveDirectTransportAuthority(message.from);
    senderMismatch =
        envelopeSenderPeerId != message.from ||
        !transportResolution.authorized ||
        transportResolution.contactAccountPeerId != payload.senderPeerId;
  }
  final isLinkedTransportOrigin =
      transportResolution?.kind == DirectTransportAuthorityKind.linked;
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

  final metadataMismatch =
      (envelopeEventId != null && envelopeEventId != payload.id) ||
      (envelopeAction != null && envelopeAction != payload.action) ||
      (envelopeTargetMessageId != null &&
          envelopeTargetMessageId != payload.messageId);
  if (metadataMismatch) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_METADATA_MISMATCH',
      details: {},
    );
    return (HandleReactionResult.metadataMismatch, null);
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
  if (contact.isBlocked) {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_RECEIVE_BLOCKED_SENDER',
      details: {},
    );
    return (HandleReactionResult.blockedSender, null);
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

  final isLocallyAuthoredNotificationTarget =
      _targetWasAuthoredByLocalRecipient(
        targetMessage: targetMessage,
        incomingEnvelope: message,
      );
  if (payload.action == ReactionPayload.addAction &&
      isLocallyAuthoredNotificationTarget) {
    await stageNotificationDisplayCustody?.call(
      payload: payload,
      targetMessage: targetMessage,
    );
  }

  // 5. Process action
  if (payload.action == ReactionPayload.removeAction) {
    final atomicRepository =
        reactionRepo is AtomicIncomingReactionMutationRepository
        ? reactionRepo as AtomicIncomingReactionMutationRepository
        : null;
    if (atomicRepository != null) {
      final linkedApplyRepository =
          isLinkedTransportOrigin &&
              reactionRepo is LinkedTransportReactionApplyRepository
          ? reactionRepo as LinkedTransportReactionApplyRepository
          : null;
      if (isLinkedTransportOrigin &&
          (linkedApplyRepository == null ||
              !linkedApplyRepository.supportsLinkedTransportReactionApply)) {
        return (HandleReactionResult.senderMismatch, null);
      }
      final applyResult = linkedApplyRepository != null
          ? await linkedApplyRepository
                .applyIncomingRemoveWithTransportAuthority(
                  payload.toMessageReaction(),
                  authenticatedTransportPeerId: message.from,
                )
          : await atomicRepository.applyIncomingRemove(
              payload.toMessageReaction(),
            );
      if (applyResult == ReactionRemoveApplyResult.stale) {
        _emitStaleReaction(payload);
        return (HandleReactionResult.success, null);
      }
      if (applyResult == ReactionRemoveApplyResult.exactReplay) {
        // Canonical mutation can survive a process death that happened before
        // notification-terminal cleanup. Replay must repair that second half.
        await commitNotificationRemove?.call(
          peerId: payload.senderPeerId,
          messageId: payload.messageId,
          actorPeerId: payload.senderPeerId,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'REACTION_RECEIVE_EXACT_REPLAY_IGNORED',
          details: {},
        );
        return (HandleReactionResult.success, null);
      }
    } else {
      final currentReaction = await reactionRepo
          .getReactionForSenderIncludingRemoved(
            messageId: payload.messageId,
            senderPeerId: payload.senderPeerId,
          );
      if (_isStaleComparedToCurrent(
        incomingTimestamp: payload.timestamp,
        currentTimestamp: currentReaction == null
            ? null
            : (currentReaction.removedAt ?? currentReaction.timestamp),
      )) {
        _emitStaleReaction(payload);
        return (HandleReactionResult.success, null);
      }
      await reactionRepo.removeReaction(
        payload.messageId,
        payload.senderPeerId,
        removedAtTimestamp: payload.timestamp,
      );
    }
    await commitNotificationRemove?.call(
      peerId: payload.senderPeerId,
      messageId: payload.messageId,
      actorPeerId: payload.senderPeerId,
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
  final linkedAddRepository =
      isLinkedTransportOrigin &&
          reactionRepo is LinkedTransportReactionApplyRepository
      ? reactionRepo as LinkedTransportReactionApplyRepository
      : null;
  if (isLinkedTransportOrigin &&
      (linkedAddRepository == null ||
          !linkedAddRepository.supportsLinkedTransportReactionApply)) {
    return (HandleReactionResult.senderMismatch, null);
  }
  final applyResult = linkedAddRepository != null
      ? await linkedAddRepository.applyIncomingAddWithTransportAuthority(
          reaction,
          authenticatedTransportPeerId: message.from,
        )
      : await reactionRepo.applyIncomingAdd(reaction);
  if (applyResult == ReactionAddApplyResult.exactReplay ||
      applyResult == ReactionAddApplyResult.stale) {
    await promoteNotificationDisplayCustody?.call(
      payload: payload,
      targetMessage: targetMessage,
    );
    _retryNotificationDisplaysAfterCommit(retryNotificationDisplays);
    if (applyResult == ReactionAddApplyResult.stale) {
      _emitStaleReaction(payload);
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_RECEIVE_EXACT_REPLAY_IGNORED',
        details: {},
      );
    }
    return (HandleReactionResult.success, null);
  }

  await promoteNotificationDisplayCustody?.call(
    payload: payload,
    targetMessage: targetMessage,
  );

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
  // branches return earlier, so un-reacts/duplicates stay silent.
  // Canonical state and display custody already committed. Observe display
  // errors separately so publication/transport completion cannot wait on the
  // notification sink; the existing projection owner retains its retry work.
  if (retryNotificationDisplays != null) {
    _retryNotificationDisplaysAfterCommit(retryNotificationDisplays);
  } else if (notificationService != null &&
      appVisibility != null &&
      isLocallyAuthoredNotificationTarget) {
    try {
      await maybeShowNotification(
        notificationService: notificationService,
        appVisibility: appVisibility,
        contactPeerId: payload.senderPeerId,
        senderUsername: contact.username,
        messageText: 'Reacted ${payload.emoji} to your message',
        messageId: reaction.id,
        notificationEventIdentity: boundedReactionEventIdentity(reaction.id),
        notificationEventType: 'message_reaction',
        suppressNotification: suppressReactionNotification,
        forceSilent: forceSilentReactionNotification,
        suppressionReason: 'reaction_recovery_replay',
        toneTracker: notificationToneTracker,
        consumeRecentRemoteNotificationAnnouncement:
            consumeRecentRemoteNotificationAnnouncement,
        markRecentRemoteNotificationAnnouncement:
            markRecentRemoteNotificationAnnouncement,
        durableNotificationCoordinatorResolver:
            durableNotificationCoordinatorResolver,
        loadConversationNotificationSnapshot:
            loadConversationNotificationSnapshot,
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_NOTIFICATION_PROJECTION_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  return (HandleReactionResult.success, ReactionChange.upsert(reaction));
}

void _retryNotificationDisplaysAfterCommit(Future<void> Function()? retry) {
  if (retry == null) return;
  unawaited(() async {
    try {
      await retry();
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_NOTIFICATION_PROJECTION_ERROR',
        details: {'reason': 'display_retry_failed'},
      );
    }
  }());
}

bool _targetWasAuthoredByLocalRecipient({
  required ConversationMessage targetMessage,
  required ChatMessage incomingEnvelope,
}) {
  // The incoming stream's `to` is the local transport identity. Requiring the
  // stored outgoing target to name the same author makes missing identity data
  // fail closed while keeping persistence independent from notification.
  return targetMessage.isIncoming == false &&
      incomingEnvelope.to.isNotEmpty &&
      targetMessage.senderPeerId == incomingEnvelope.to;
}

void _emitStaleReaction(ReactionPayload payload) {
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
