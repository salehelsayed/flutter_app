import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/incoming_ordinary_text_mutation.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart'
    show shouldMintDeliveryReceipt;
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

enum HandleMessageDeletionResult {
  success,
  notMessageDeletion,
  decryptionFailed,
  unknownSender,
  ignoredMissingMessage,
  unauthorized,
}

typedef SendIncomingDeletionDeliveryReceipt =
    Future<void> Function(String messageId);
typedef SendIncomingDeletionMutationDeliveryReceipt =
    Future<void> Function(String messageId, {required String mutationEventId});

Future<(HandleMessageDeletionResult, ConversationMessage?)>
handleIncomingMessageDeletion({
  required ChatMessage message,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  Bridge? bridge,
  String? ownMlKemSecretKey,
  // 115 P2 (D-3): deletion-apply receipts — without them an 'inboxed'
  // delete-for-everyone tombstone stays pending forever on the sender.
  // Same origin contract as the chat hook (relay-drain arrivals only);
  // duplicate re-application re-invokes (lost-receipt repair loop).
  SendIncomingDeletionDeliveryReceipt? sendDeliveryReceipt,
  SendIncomingDeletionMutationDeliveryReceipt? sendMutationDeliveryReceipt,
  String? stagedEntryId,
  // 361: shared physical->logical reverse authority; null keeps the
  // incumbent transport==logical equality byte-identically.
  DirectTransportAuthorityResolver? transportAuthority,
}) async {
  Future<void> maybeSendDeliveryReceipt(
    String messageId, {
    String? mutationEventId,
  }) async {
    if (sendDeliveryReceipt == null && sendMutationDeliveryReceipt == null) {
      return;
    }
    if (!shouldMintDeliveryReceipt(
      stagedEntryId: stagedEntryId,
      transport: message.transport,
    )) {
      return;
    }
    try {
      if (mutationEventId != null && sendMutationDeliveryReceipt != null) {
        await sendMutationDeliveryReceipt(
          messageId,
          mutationEventId: mutationEventId,
        );
      } else if (sendDeliveryReceipt != null) {
        await sendDeliveryReceipt(messageId);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_HOOK_ERROR',
        details: {
          'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_RECEIVE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  MessageDeletionPayload? payload;
  final v2Envelope = MessageDeletionPayload.parseEncryptedEnvelope(
    message.content,
  );
  final envelopeSenderPeerId = v2Envelope?['senderPeerId'] as String?;
  final envelopeEventId = v2Envelope?['eventId'] as String?;
  if (v2Envelope != null) {
    if (bridge == null || ownMlKemSecretKey == null) {
      return (HandleMessageDeletionResult.decryptionFailed, null);
    }
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
        return (HandleMessageDeletionResult.decryptionFailed, null);
      }
      payload = MessageDeletionPayload.fromDecryptedJson(
        decryptResult['plaintext'] as String,
      );
    } catch (_) {
      return (HandleMessageDeletionResult.decryptionFailed, null);
    }
  } else {
    payload = MessageDeletionPayload.fromJson(message.content);
  }

  if (payload == null) {
    return (HandleMessageDeletionResult.notMessageDeletion, null);
  }

  final payloadEventId = payload.eventId;
  final hasEnvelopeEventId = envelopeEventId != null;
  final hasPayloadEventId = payloadEventId != null;
  final invalidEventIdentity =
      hasEnvelopeEventId != hasPayloadEventId ||
      (hasEnvelopeEventId &&
          (envelopeEventId.trim().isEmpty ||
              payloadEventId!.trim().isEmpty ||
              envelopeEventId != payloadEventId));
  if (invalidEventIdentity) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_EVENT_ID_MISMATCH',
      details: {'reason': 'partial_blank_or_mismatch'},
    );
    return (HandleMessageDeletionResult.unauthorized, null);
  }

  DirectTransportAuthorityResolution? transportResolution;
  bool senderMismatch;
  if (transportAuthority == null) {
    senderMismatch =
        message.from != payload.senderPeerId ||
        (v2Envelope != null && envelopeSenderPeerId != payload.senderPeerId);
  } else {
    transportResolution = await transportAuthority
        .resolveDirectTransportAuthority(message.from);
    senderMismatch =
        (v2Envelope != null && envelopeSenderPeerId != message.from) ||
        !transportResolution.authorized ||
        transportResolution.contactAccountPeerId != payload.senderPeerId;
  }
  final isLinkedTransportOrigin =
      transportResolution?.kind == DirectTransportAuthorityKind.linked;
  if (senderMismatch) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_SENDER_MISMATCH',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
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
    return (HandleMessageDeletionResult.unauthorized, null);
  }

  final contact = await contactRepo.getContact(payload.senderPeerId);
  if (contact == null) {
    return (HandleMessageDeletionResult.unknownSender, null);
  }

  final targetMessage = await messageRepo.getMessage(payload.messageId);
  final blockedSenderOwnsStoredMessage =
      contact.isBlocked &&
      targetMessage != null &&
      targetMessage.senderPeerId == payload.senderPeerId;
  if (contact.isBlocked && !blockedSenderOwnsStoredMessage) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_BLOCKED_IGNORED',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
      },
    );
    return (
      targetMessage == null
          ? HandleMessageDeletionResult.ignoredMissingMessage
          : HandleMessageDeletionResult.unauthorized,
      null,
    );
  }

  if (targetMessage != null &&
      targetMessage.senderPeerId != payload.senderPeerId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_UNAUTHORIZED',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
      },
    );
    return (HandleMessageDeletionResult.unauthorized, null);
  }

  if (hasEnvelopeEventId) {
    // A current event-bearing deletion never routes from this pre-read: the
    // target may be absent, ordinary text, or strict media, and an
    // independently dispatched initial/media stream can change that between
    // the read above and the commit below. One transaction re-reads the exact
    // target, applies durable precedence, and retires any queued display
    // marker for it.
    final directDeletionCapability =
        messageRepo is IncomingDirectDeletionApplyRepository
        ? messageRepo as IncomingDirectDeletionApplyRepository
        : null;
    final directDeletionRepository =
        directDeletionCapability?.supportsIncomingDirectDeletionApply == true
        ? directDeletionCapability
        : null;
    if (directDeletionRepository == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_RECEIVE_CURRENT_AUTHORITY_UNAVAILABLE',
        details: {
          'messageId': payload.messageId.length > 8
              ? payload.messageId.substring(0, 8)
              : payload.messageId,
        },
      );
      return (HandleMessageDeletionResult.unauthorized, null);
    }
    // 356: current-event selection, apply and every marker/presentation-
    // sensitive cleanup run under the SAME repository-wide exclusive private
    // lifecycle lease that strict private receive uses, so the live listener
    // and recovered replay share one seam.
    // 357: local contact reauthorization is INSIDE that lease, because contact
    // deletion holds the very same lease while it removes messages and then the
    // contact. Receipt and network work still begin only after release.
    final leased = await _underPrivateLifecycleAuthority(
      mediaAttachmentRepo,
      () async {
        // The first read above may already be stale: `deleteContactAndMessages`
        // can have won this lease behind it. Re-reading here is what stops the
        // absent-target branch from inserting an orphan tombstone for a contact
        // that no longer exists.
        if (await contactRepo.getContact(payload!.senderPeerId) == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_DELETE_RECEIVE_CONTACT_REVOKED',
            details: {
              'messageId': payload.messageId.length > 8
                  ? payload.messageId.substring(0, 8)
                  : payload.messageId,
            },
          );
          return null;
        }
        IncomingDirectDeletionApplyResult applied;
        final linkedApplyRepository =
            isLinkedTransportOrigin &&
                messageRepo is LinkedTransportIncomingApplyRepository
            ? messageRepo as LinkedTransportIncomingApplyRepository
            : null;
        if (isLinkedTransportOrigin &&
            (linkedApplyRepository == null ||
                !linkedApplyRepository.supportsLinkedTransportIncomingApply)) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_DELETE_RECEIVE_LINKED_APPLY_UNAVAILABLE',
            details: const {},
          );
          return null;
        }
        try {
          applied = linkedApplyRepository != null
              ? await linkedApplyRepository
                    .applyIncomingDirectMessageDeletionWithTransportAuthority(
                      messageId: payload.messageId,
                      senderPeerId: payload.senderPeerId,
                      deletedAt: payload.timestamp,
                      transport: message.transport,
                      authenticatedTransportPeerId: message.from,
                    )
              : await directDeletionRepository
                    .applyIncomingDirectMessageDeletion(
                      messageId: payload.messageId,
                      senderPeerId: payload.senderPeerId,
                      deletedAt: payload.timestamp,
                      transport: message.transport,
                    );
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_DELETE_RECEIVE_CURRENT_APPLY_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
          return null;
        }
        final stored = applied.message;
        if (!applied.isDurable || stored == null) return null;
        // The tombstone alone is deletion authority. Duplicate re-application
        // re-drives the same idempotent best-effort cleanup, and a cleanup
        // failure never revokes durable deletion or withholds its receipt.
        if (stored.privateMediaPolicy.requiresRedaction) {
          await _privateIncomingTerminalCleanupBestEffort(
            message: stored,
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          );
          // Reaction records are a separate best-effort owner: their failure
          // must never revoke the durable deletion or its receipt.
          try {
            await reactionRepo?.deleteReactionsForMessage(stored.id);
          } catch (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CHAT_MSG_DELETE_RECEIVE_REACTION_RETIRE_FAILED',
              details: {'errorType': error.runtimeType.toString()},
            );
          }
        } else {
          await _bestEffortIncomingCleanup(
            message: stored,
            reactionRepo: reactionRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          );
        }
        return (message: stored, outcome: applied.outcome);
      },
    );
    if (leased == null) {
      return (HandleMessageDeletionResult.unauthorized, null);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_SUCCESS',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
        'outcome': leased.outcome.name,
      },
    );
    await maybeSendDeliveryReceipt(
      payload.messageId,
      mutationEventId: payload.eventId,
    );
    return (HandleMessageDeletionResult.success, leased.message);
  }

  var isOrdinaryDirectText =
      targetMessage == null ||
      (targetMessage.privateMediaPolicy.version == 0 &&
          targetMessage.privateMediaPolicy.mode == PrivateMediaMode.ordinary &&
          targetMessage.directMediaCustodyIntentId == null &&
          targetMessage.media.isEmpty);
  if (isOrdinaryDirectText &&
      targetMessage != null &&
      mediaAttachmentRepo != null) {
    try {
      final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        targetMessage.id,
        owner: MediaOwnerLane.direct,
      );
      isOrdinaryDirectText = attachments.isEmpty;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_RECEIVE_ORDINARY_TEXT_CLASSIFY_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return (HandleMessageDeletionResult.unauthorized, null);
    }
  }

  if (isOrdinaryDirectText) {
    final ordinaryTextApplyRepository =
        messageRepo is IncomingOrdinaryTextApplyRepository
        ? messageRepo as IncomingOrdinaryTextApplyRepository
        : null;
    if (ordinaryTextApplyRepository == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_RECEIVE_ORDINARY_TEXT_AUTHORITY_UNAVAILABLE',
        details: {
          'messageId': payload.messageId.length > 8
              ? payload.messageId.substring(0, 8)
              : payload.messageId,
        },
      );
      return (HandleMessageDeletionResult.unauthorized, null);
    }

    final candidate = targetMessage == null
        ? ConversationMessage(
            id: payload.messageId,
            contactPeerId: payload.senderPeerId,
            senderPeerId: payload.senderPeerId,
            text: '',
            timestamp: payload.timestamp,
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.now().toUtc().toIso8601String(),
            deletedAt: payload.timestamp,
            deletedByPeerId: payload.senderPeerId,
            transport: message.transport,
          )
        : buildDeletedMessageTombstone(
            originalMessage: targetMessage,
            deletedAt: payload.timestamp,
            deletedByPeerId: payload.senderPeerId,
            hiddenLocally: false,
            status: targetMessage.status,
            transport: targetMessage.transport,
            wireEnvelope: null,
          );
    IncomingOrdinaryTextApplyResult applied;
    try {
      applied = await ordinaryTextApplyRepository
          .applyIncomingOrdinaryTextMutation(
            incoming: candidate,
            kind: IncomingOrdinaryTextMutationKind.deletion,
          );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_RECEIVE_ORDINARY_TEXT_APPLY_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return (HandleMessageDeletionResult.unauthorized, null);
    }
    final stored = applied.message;
    if (!applied.isDurable || stored == null) {
      return (HandleMessageDeletionResult.unauthorized, null);
    }
    if (applied.changed) {
      await _bestEffortIncomingCleanup(
        message: stored,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );
    }
    await maybeSendDeliveryReceipt(
      payload.messageId,
      mutationEventId: payload.eventId,
    );
    return (HandleMessageDeletionResult.success, stored);
  }

  if (targetMessage == null) {
    final tombstone = ConversationMessage(
      id: payload.messageId,
      contactPeerId: payload.senderPeerId,
      senderPeerId: payload.senderPeerId,
      text: '',
      timestamp: payload.timestamp,
      status: 'delivered',
      isIncoming: true,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      deletedAt: payload.timestamp,
      deletedByPeerId: payload.senderPeerId,
      transport: message.transport,
    );
    await messageRepo.saveMessage(tombstone);
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_STAGED_TOMBSTONE',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
      },
    );
    await maybeSendDeliveryReceipt(
      payload.messageId,
      mutationEventId: payload.eventId,
    );
    return (HandleMessageDeletionResult.success, tombstone);
  }

  if (targetMessage.isDeleted) {
    // Duplicate re-application: the deletion is already durably applied —
    // re-mint the receipt (the sender may have missed the first one).
    await maybeSendDeliveryReceipt(
      payload.messageId,
      mutationEventId: payload.eventId,
    );
    return (HandleMessageDeletionResult.success, targetMessage);
  }

  final tombstone = buildDeletedMessageTombstone(
    originalMessage: targetMessage,
    deletedAt: payload.timestamp,
    deletedByPeerId: payload.senderPeerId,
    hiddenLocally: false,
    status: targetMessage.status,
    transport: targetMessage.transport,
    wireEnvelope: null,
  );
  await messageRepo.saveMessage(tombstone);
  await _bestEffortIncomingCleanup(
    message: tombstone,
    reactionRepo: reactionRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_RECEIVE_SUCCESS',
    details: {
      'messageId': payload.messageId.length > 8
          ? payload.messageId.substring(0, 8)
          : payload.messageId,
    },
  );
  await maybeSendDeliveryReceipt(
    payload.messageId,
    mutationEventId: payload.eventId,
  );
  return (HandleMessageDeletionResult.success, tombstone);
}

/// Runs [action] under the incumbent repository-wide exclusive private
/// lifecycle lease when the repository owns one.
///
/// Nested repository acquisitions inside [action] are reentrant, and the lease
/// is never upgraded from an exact-ID section.
Future<T> _underPrivateLifecycleAuthority<T>(
  MediaAttachmentRepository? mediaAttachmentRepo,
  Future<T> Function() action,
) {
  final runtime = mediaAttachmentRepo;
  if (runtime is DirectPrivateMediaCleanupRuntime) {
    return (runtime as DirectPrivateMediaCleanupRuntime)
        .directPrivateMediaLifecycleLock
        .synchronizedAll(action);
  }
  return action();
}

/// Removes an incoming v1 Protected/View-Once parent's exact artifacts through
/// the incumbent private lifecycle owner.
///
/// Generic attachment deletion is deliberately never used here: it would drop
/// the row without retiring the secure key or the private artifact siblings.
/// A missing optional capability records a bounded failure and leaves the
/// durable tombstone (and its receipt) intact — it never falls back.
Future<void> _privateIncomingTerminalCleanupBestEffort({
  required ConversationMessage message,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required MediaFileManager? mediaFileManager,
}) async {
  final lifecycleRepository =
      messageRepo is DirectPrivateMediaLifecycleRepository
      ? messageRepo as DirectPrivateMediaLifecycleRepository
      : null;
  final cleanupRuntime = mediaAttachmentRepo is DirectPrivateMediaCleanupRuntime
      ? mediaAttachmentRepo as DirectPrivateMediaCleanupRuntime
      : null;
  final cleanupRepository =
      mediaAttachmentRepo is DirectPrivateMediaCleanupRepository
      ? mediaAttachmentRepo as DirectPrivateMediaCleanupRepository
      : null;
  if (lifecycleRepository == null ||
      cleanupRuntime == null ||
      cleanupRepository == null ||
      mediaAttachmentRepo == null ||
      mediaFileManager == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_PRIVATE_CLEANUP_UNAVAILABLE',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
      },
    );
    return;
  }
  final engine = PrivateMediaLifecycleEngine(
    adapter: DirectPrivateMediaLifecycle(
      messageRepository: lifecycleRepository,
      mediaAttachmentRepository: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    ),
    lifecycleLock: cleanupRuntime.directPrivateMediaLifecycleLock,
    nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
  );
  try {
    await engine.cleanupTerminalMessage(message.id);
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_PRIVATE_CLEANUP_RETAINED',
      details: {'errorType': error.runtimeType.toString()},
    );
  }
}

Future<void> _bestEffortIncomingCleanup({
  required ConversationMessage message,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  try {
    await cleanupDeletedMessageArtifacts(
      message: message,
      reactionRepo: reactionRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_CLEANUP_ERROR',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        'error': e.toString(),
      },
    );
  }
}
