import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/outbound_envelope_policy.dart';
import 'package:flutter_app/features/conversation/application/outgoing_direct_private_transport_settlement.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

enum _RetryFailedMessageSkipReason {
  none,
  localFileMissing,
  uploadCancelled,
  unfinishedAutomatic,
  manualRearmNotEligible,
  uploadOwnershipUnavailable,
  uploadFailed,
}

class _RetryAttachmentResolution {
  const _RetryAttachmentResolution({
    required this.attachments,
    required this.skipReason,
    this.uploadLease,
    this.didUpload = false,
    this.privateCustody,
  });

  final List<MediaAttachment>? attachments;
  final _RetryFailedMessageSkipReason skipReason;
  final MediaUploadLease? uploadLease;
  final bool didUpload;
  final _DirectPrivateManualRetryCustody? privateCustody;
}

/// Ownership handed from the manual re-upload phase to the durable envelope
/// handoff. The direct-private transfer claim remains active for that entire
/// interval, so terminal cleanup cannot remove sender-local plaintext while
/// the upload/send attempt still owns it.
class _DirectPrivateManualRetryCustody {
  _DirectPrivateManualRetryCustody({
    required this.messageId,
    required this.tokens,
    required this.expectedPendingPaths,
    required this.lifecycleRepository,
    required this.envelopeRepository,
    required this.mediaAttachmentRepository,
    required this.cleanupRuntime,
    required this.mediaFileManager,
  });

  final String messageId;
  final Map<String, Object> tokens;
  final Map<String, String> expectedPendingPaths;
  final DirectPrivateMediaLifecycleRepository lifecycleRepository;
  final OutgoingDirectPrivateEnvelopeCustodyRepository envelopeRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final DirectPrivateMediaCleanupRuntime cleanupRuntime;
  final MediaFileManager mediaFileManager;
  bool _released = false;

  Future<void> releaseClaims() async {
    if (_released) return;
    _released = true;
    final ownedTokens = tokens.entries.toList(growable: false);
    for (final token in ownedTokens) {
      await cleanupRuntime.directPrivateMediaLifecycleLock.synchronized(
        token.key,
        () async {
          directPrivateMediaTransferRegistry.end(token.key, token.value);
        },
      );
    }
    tokens.clear();
  }

  /// Remove a positively committed redundant pending source, or clean a parent
  /// that is already durably terminal. A broad startup reconciliation would
  /// consume a legitimate in-process `opening` viewer; the manual retry lane
  /// must never make that recovery decision.
  Future<void> cleanupAfterRelease() async {
    if (!_released) {
      throw StateError('private retry cleanup requires released ownership');
    }
    final adapter = DirectPrivateMediaLifecycle(
      messageRepository: lifecycleRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
    );
    for (final pending in expectedPendingPaths.entries) {
      try {
        await adapter.cleanupCommittedPendingSource(
          messageId: messageId,
          attachmentId: pending.key,
          expectedPendingLocalPath: pending.value,
        );
      } catch (_) {
        // Exact committed residue remains safe and independently retryable.
      }
    }
    try {
      await PrivateMediaLifecycleEngine(
        adapter: adapter,
        lifecycleLock: cleanupRuntime.directPrivateMediaLifecycleLock,
        nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
      ).cleanupTerminalMessage(messageId);
    } catch (_) {
      // Durable terminal residue remains eligible for startup reconciliation.
    }
    final mutationRepository = mediaAttachmentRepository;
    if (mutationRepository is OutgoingDirectPrivateMutationRepository) {
      await reconcileReleasedOutgoingDirectPrivateUploadAttempt(
        messageId: messageId,
        expectedPendingPaths: expectedPendingPaths,
        coordinator:
            (mutationRepository as OutgoingDirectPrivateMutationRepository)
                .outgoingDirectPrivateMutationCoordinator,
        envelopeRepository: envelopeRepository,
        lifecycleRepository: lifecycleRepository,
      );
    }
  }
}

/// 116 EF-1 (row-derived action): the semantic action of a retried row comes
/// from the DB row, never from caller defaults — an `editedAt`-bearing row
/// goes back out as an EDIT with its original metadata. Shared by the
/// full-send fallback below, the tombstone route (116 P3), and the 115
/// custody sweep.
String deriveRetryAction(ConversationMessage msg) {
  if (msg.editedAt != null && !msg.isDeleted) {
    return MessagePayload.actionEdit;
  }
  return MessagePayload.actionSend;
}

/// Retries all failed outgoing messages.
///
/// Loads identity, queries failed messages, then re-sends each via
/// [sendChatMessage] with the original messageId + timestamp so the
/// DB row is updated in-place (INSERT OR REPLACE).
///
/// When [mediaAttachmentRepo] is provided, loads persisted attachment rows
/// to determine whether a CDN re-upload is needed before re-sending.
///
/// When [uploadMediaFn] is provided, uses that function for media uploads
/// instead of the production [uploadMedia] symbol (for testability).
///
/// Returns the count of successfully retried messages.
/// Non-fatal: catches errors per-message and continues with the next.
Future<int> retryFailedMessages({
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  MediaAttachmentRepository? mediaAttachmentRepo,
  UploadMediaFn? uploadMediaFn,
  MediaFileManager? mediaFileManager,
}) {
  return _retryFailedMessagesInternal(
    messageRepo: messageRepo,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    p2pService: p2pService,
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    uploadMediaFn: uploadMediaFn,
    mediaFileManager: mediaFileManager,
    uploadRetryProjectionRepo: null,
    manualRetry: false,
    loadFailedMessages: messageRepo.getFailedOutgoingMessages,
  );
}

/// Retries one failed outgoing message in place.
Future<int> retryFailedMessage({
  required String messageId,
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  MediaAttachmentRepository? mediaAttachmentRepo,
  UploadMediaFn? uploadMediaFn,
  MediaFileManager? mediaFileManager,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  DirectManualUploadRetryRearmRepository? uploadRetryRearmRepo,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
}) {
  return _retryFailedMessagesInternal(
    messageRepo: messageRepo,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    p2pService: p2pService,
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    uploadMediaFn: uploadMediaFn,
    mediaFileManager: mediaFileManager,
    uploadRetryProjectionRepo:
        uploadRetryProjectionRepo ??
        (messageRepo is DirectUploadRetryProjectionRepository
            ? messageRepo as DirectUploadRetryProjectionRepository
            : null),
    uploadRetryRearmRepo:
        uploadRetryRearmRepo ??
        (messageRepo is DirectManualUploadRetryRearmRepository
            ? messageRepo as DirectManualUploadRetryRearmRepository
            : null),
    tryClaimUploadLease: tryClaimUploadLease,
    releaseUploadLease: releaseUploadLease,
    manualRetry: true,
    loadFailedMessages: () async {
      final message = await messageRepo.getMessage(messageId);
      if (message == null || message.isIncoming || message.status != 'failed') {
        return const <ConversationMessage>[];
      }
      return <ConversationMessage>[message];
    },
  );
}

Future<int> _retryFailedMessagesInternal({
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required Future<List<ConversationMessage>> Function() loadFailedMessages,
  MediaAttachmentRepository? mediaAttachmentRepo,
  UploadMediaFn? uploadMediaFn,
  MediaFileManager? mediaFileManager,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  DirectManualUploadRetryRearmRepository? uploadRetryRearmRepo,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
  required bool manualRetry,
}) async {
  final retryStopwatch = Stopwatch()..start();
  final effectiveUploadFn = uploadMediaFn ?? uploadMedia;
  void emitRetryTiming({
    required String outcome,
    required int total,
    required int succeeded,
    Map<String, dynamic> details = const {},
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGES_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'total': total,
        'succeeded': succeeded,
        ...details,
      },
    );
  }

  emitFlowEvent(layer: 'FL', event: 'RETRY_FAILED_MESSAGES_START', details: {});

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGES_NO_IDENTITY',
      details: {},
    );
    emitRetryTiming(outcome: 'no_identity', total: 0, succeeded: 0);
    return 0;
  }

  final failedMessages = await loadFailedMessages();
  if (failedMessages.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGES_NONE',
      details: {},
    );
    emitRetryTiming(outcome: 'none', total: 0, succeeded: 0);
    return 0;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_MESSAGES_FOUND',
    details: {'count': failedMessages.length},
  );

  var successCount = 0;

  for (final msg in failedMessages) {
    final retried = await _retryFailedMessageCandidate(
      msg: msg,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      identity: identity,
      mediaAttachmentRepo: mediaAttachmentRepo,
      uploadFn: effectiveUploadFn,
      mediaFileManager: mediaFileManager,
      uploadRetryProjectionRepo: uploadRetryProjectionRepo,
      uploadRetryRearmRepo: uploadRetryRearmRepo,
      tryClaimUploadLease: tryClaimUploadLease,
      releaseUploadLease: releaseUploadLease,
      manualRetry: manualRetry,
    );
    if (retried) {
      successCount++;
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_MESSAGES_COMPLETE',
    details: {'total': failedMessages.length, 'succeeded': successCount},
  );
  emitRetryTiming(
    outcome: 'complete',
    total: failedMessages.length,
    succeeded: successCount,
  );

  return successCount;
}

/// 116 EF-3 single-flight: at most one in-flight retry per message id across
/// all four triggers (PendingMessageRetrier periodic, reconnect debounce,
/// app-resume 8c, UI retry button). File-private top-level set — every
/// trigger funnels through [_retryFailedMessageCandidate] in the same
/// isolate. If retries ever move to a background isolate, this guard must
/// move with them.
final Set<String> _retryInFlightMessageIds = {};

Future<bool> _retryFailedMessageCandidate({
  required ConversationMessage msg,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required dynamic identity,
  required UploadMediaFn uploadFn,
  MediaFileManager? mediaFileManager,
  MediaAttachmentRepository? mediaAttachmentRepo,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  DirectManualUploadRetryRearmRepository? uploadRetryRearmRepo,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
  required bool manualRetry,
}) async {
  if (!_retryInFlightMessageIds.add(msg.id)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGE_SKIPPED_IN_FLIGHT',
      details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
    );
    return false;
  }
  MediaUploadLease? uploadLease;
  _DirectPrivateManualRetryCustody? privateCustody;
  try {
    // 116 EF-3 settled-recheck: the loaded list may hold a stale snapshot of
    // a row that settled between load and execution — re-fetch and use the
    // FRESH row for all subsequent derivation.
    final fresh = await messageRepo.getMessage(msg.id);
    if (fresh == null || fresh.isIncoming || fresh.status != 'failed') {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MESSAGE_SKIPPED_SETTLED',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      return false;
    }
    msg = fresh;

    if (msg.isDeleted) {
      return _retryFailedDeletedTombstone(
        msg: msg,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );
    }

    // Resolve media authority before replaying a cached envelope. Automatic
    // retries are envelope-only for completed media; pending/terminal rows are
    // owned by the incomplete/manual lanes and must never be uploaded here.
    final resolution = await _resolveAttachmentsForRetry(
      message: msg,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      bridge: bridge,
      targetPeerId: msg.contactPeerId,
      uploadFn: uploadFn,
      mediaFileManager: mediaFileManager,
      uploadRetryProjectionRepo: uploadRetryProjectionRepo,
      uploadRetryRearmRepo: uploadRetryRearmRepo,
      tryClaimUploadLease: tryClaimUploadLease,
      releaseUploadLease: releaseUploadLease,
      manualRetry: manualRetry,
    );
    uploadLease = resolution.uploadLease;
    privateCustody = resolution.privateCustody;
    if (resolution.skipReason != _RetryFailedMessageSkipReason.none) {
      final details = {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
      };
      switch (resolution.skipReason) {
        case _RetryFailedMessageSkipReason.localFileMissing:
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MEDIA_LOCAL_FILE_MISSING',
            details: details,
          );
          break;
        case _RetryFailedMessageSkipReason.uploadCancelled:
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MEDIA_UPLOAD_CANCELLED',
            details: details,
          );
          break;
        case _RetryFailedMessageSkipReason.unfinishedAutomatic:
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MEDIA_AUTOMATIC_UPLOAD_SKIPPED',
            details: details,
          );
          break;
        case _RetryFailedMessageSkipReason.manualRearmNotEligible:
        case _RetryFailedMessageSkipReason.uploadOwnershipUnavailable:
        case _RetryFailedMessageSkipReason.uploadFailed:
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MEDIA_MANUAL_RETRY_SKIPPED',
            details: {...details, 'reason': resolution.skipReason.name},
          );
          break;
        case _RetryFailedMessageSkipReason.none:
          break;
      }
      return false;
    }

    Future<void> cleanupSettledMediaStaging() async {
      if (resolution.attachments == null ||
          mediaFileManager == null ||
          _isOutgoingOneMoreLookPrivate(msg)) {
        return;
      }
      try {
        await mediaFileManager.deletePendingUploadDir(msg.id);
      } catch (_) {}
    }

    Future<void> cleanupSettledPrivateTerminalMedia() async {
      if (!_isOutgoingOneMoreLookPrivate(msg) || mediaFileManager == null) {
        return;
      }
      final lifecycleRepository = messageRepo;
      final cleanupRepository = mediaAttachmentRepo;
      if (lifecycleRepository is! DirectPrivateMediaLifecycleRepository ||
          cleanupRepository is! DirectPrivateMediaCleanupRepository ||
          cleanupRepository is! DirectPrivateMediaCleanupRuntime ||
          cleanupRepository is! OutgoingDirectPrivateMutationRepository) {
        return;
      }
      final runtime = cleanupRepository as DirectPrivateMediaCleanupRuntime;
      final coordinator =
          (cleanupRepository as OutgoingDirectPrivateMutationRepository)
              .outgoingDirectPrivateMutationCoordinator;
      if (!identical(
        runtime.directPrivateMediaLifecycleLock,
        coordinator.lifecycleLock,
      )) {
        return;
      }
      try {
        final adapter = DirectPrivateMediaLifecycle(
          messageRepository:
              lifecycleRepository as DirectPrivateMediaLifecycleRepository,
          mediaAttachmentRepository:
              cleanupRepository as MediaAttachmentRepository,
          mediaFileManager: mediaFileManager,
        );
        await PrivateMediaLifecycleEngine(
          adapter: adapter,
          lifecycleLock: runtime.directPrivateMediaLifecycleLock,
          nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
        ).cleanupTerminalMessage(msg.id);
      } catch (_) {
        // Durable terminal residue remains a startup/resume cleanup candidate.
      }
    }

    // Prefer wire_envelope -> inbox-only only when this attempt did not mint
    // new attachment keys. Manual upload rearm clears the durable envelope in
    // the same transaction, and the stale in-memory snapshot must not replay it.
    if (!resolution.didUpload &&
        msg.wireEnvelope != null &&
        msg.wireEnvelope!.isNotEmpty) {
      final ordinaryTransportRepository =
          messageRepo is OutgoingTransportMutationRepository
          ? messageRepo as OutgoingTransportMutationRepository
          : null;
      if (!_isOutgoingOneMoreLookPrivate(msg) &&
          ordinaryTransportRepository == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_ORDINARY_SETTLEMENT_CAPABILITY_MISSING',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
        return false;
      }

      Future<bool> persistCachedEnvelopeTransport({
        required String status,
        required String? transport,
      }) async {
        if (_isOutgoingOneMoreLookPrivate(msg)) {
          final outcome =
              await settleOutgoingDirectPrivateTransportUnderLifecycleLock(
                messageRepository: messageRepo,
                mediaAttachmentRepository: mediaAttachmentRepo,
                attachments: resolution.attachments,
                messageId: msg.id,
                expectedEnvelope: msg.wireEnvelope!,
                status: status,
                transport: transport,
                relayExpiresAt: null,
              );
          if (!outcome.accepted) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_FAILED_PRIVATE_TRANSPORT_SETTLEMENT_REFUSED',
              details: {
                'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
                'status': status,
              },
            );
          }
          return outcome.accepted;
        }
        final outcome = await ordinaryTransportRepository!
            .settleOutgoingOrdinaryTransport(
              messageId: msg.id,
              expectedContactPeerId: msg.contactPeerId,
              expectedEnvelope: msg.wireEnvelope!,
              status: status,
              transport: transport,
              relayExpiresAt: null,
              mode: OutgoingOrdinarySettlementMode.live,
            );
        return outcome.outcome.authorizesTransport;
      }

      if (msg.transport == 'inbox') {
        // Already in the relay inbox — that is custody, not receiver delivery
        // (F6). Keep it 'inboxed' (envelope retained) so the custody sweep +
        // DeliveryReceiptListener flip it to 'delivered' only on the receiver's
        // confirmation; a false terminal 'delivered' here is uncorrectable.
        if (!await persistCachedEnvelopeTransport(
          status: 'inboxed',
          transport: 'inbox',
        )) {
          return false;
        }
        await cleanupSettledPrivateTerminalMedia();
        await cleanupSettledMediaStaging();
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGE_ALREADY_INBOX',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
        return true;
      }

      final unsafeLegacyEnvelope = isUnsafeLegacyOutboundEnvelope(
        msg.wireEnvelope!,
      );
      if (!unsafeLegacyEnvelope) {
        try {
          final stored = await p2pService.storeInInbox(
            msg.contactPeerId,
            msg.wireEnvelope!,
          );
          if (stored) {
            // Relay STORE success alone is custody, not receiver delivery (F6):
            // no peer ack, no delivery receipt. Persist 'inboxed' and RETAIN the
            // wire envelope so the custody sweep + receipt repair can advance it
            // to 'delivered' on the receiver's confirmation.
            if (!await persistCachedEnvelopeTransport(
              status: 'inboxed',
              transport: 'inbox',
            )) {
              return false;
            }
            await cleanupSettledPrivateTerminalMedia();
            await cleanupSettledMediaStaging();
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_FAILED_MESSAGE_SUCCESS',
              details: {
                'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
                'via': 'wire_envelope',
              },
            );
            return true;
          }
        } catch (_) {
          // Wire envelope inbox failed -- fall through to full send
        }
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
      }
    }

    // Look up contact for ML-KEM public key
    final contact = await contactRepo.getContact(msg.contactPeerId);
    final mlKemPk = contact?.mlKemPublicKey;

    final attachments = resolution.attachments;

    // 116 EF-1: the fallback derives action/editedAt/createdAt from the ROW
    // so a failed edit goes back out as an EDIT (the row's ORIGINAL editedAt
    // preserves the receiver staleness-gate ordering), and plain rows keep
    // their original createdAt instead of re-minting it.
    final retryAction = deriveRetryAction(msg);
    final (result, _) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: msg.contactPeerId,
      text: msg.text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      action: retryAction,
      editedAt: msg.editedAt,
      messageId: msg.id,
      timestamp: msg.timestamp,
      createdAt: msg.createdAt,
      bridge: bridge,
      recipientMlKemPublicKey: mlKemPk,
      quotedMessageId: msg.quotedMessageId,
      dedupKey: msg.dedupKey,
      isForwarded: msg.isForwarded,
      mediaAttachments: attachments,
      privateMediaPolicy: msg.privateMediaPolicy,
      mediaAttachmentRepo: mediaAttachmentRepo,
      emitTimingEvent: false,
    );

    if (result == SendChatMessageResult.success) {
      await cleanupSettledPrivateTerminalMedia();
      await cleanupSettledMediaStaging();
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MESSAGE_SUCCESS',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
          'action': retryAction,
        },
      );
      return true;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGE_STILL_FAILED',
      details: {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        'reason': result.name,
        'action': retryAction,
      },
    );
    return false;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGE_ERROR',
      details: {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        'error': e.toString(),
      },
    );
    return false;
  } finally {
    try {
      await privateCustody?.releaseClaims();
    } finally {
      try {
        if (uploadLease != null) {
          releaseUploadLease?.call(uploadLease);
        }
      } finally {
        await privateCustody?.cleanupAfterRelease();
        _retryInFlightMessageIds.remove(msg.id);
      }
    }
  }
}

Future<bool> _retryFailedDeletedTombstone({
  required ConversationMessage msg,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
}) async {
  if (!p2pService.currentState.isStarted) {
    _emitDeleteTombstoneStillFailed(msg, reason: 'node_not_running');
    return false;
  }

  final isOutgoingPrivate = _isOutgoingOneMoreLookPrivate(msg);
  final ordinaryTransportRepository =
      messageRepo is OutgoingTransportMutationRepository
      ? messageRepo as OutgoingTransportMutationRepository
      : null;
  final privateDeleteRepository =
      messageRepo is DirectPrivateDeleteForEveryoneRepository
      ? messageRepo as DirectPrivateDeleteForEveryoneRepository
      : null;
  if (isOutgoingPrivate && privateDeleteRepository == null) {
    _emitDeleteTombstoneStillFailed(
      msg,
      reason: 'private_delete_capability_missing',
    );
    return false;
  }
  if (!isOutgoingPrivate && ordinaryTransportRepository == null) {
    _emitDeleteTombstoneStillFailed(
      msg,
      reason: 'ordinary_transport_capability_missing',
    );
    return false;
  }

  final existingEnvelope = msg.wireEnvelope?.trim();
  if (existingEnvelope != null &&
      existingEnvelope.isNotEmpty &&
      _isV2DeletionWireEnvelope(existingEnvelope)) {
    return _storeOrReplayDeleteEnvelope(
      msg: msg,
      messageRepo: messageRepo,
      p2pService: p2pService,
      wireEnvelope: existingEnvelope,
      rebuilt: false,
    );
  }

  final contact = await contactRepo.getContact(msg.contactPeerId);
  final recipientKey = contact?.mlKemPublicKey?.trim();
  if (recipientKey == null || recipientKey.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE',
      details: {
        'id': _messageIdPreview(msg.id),
        'reason': 'missing_recipient_key',
      },
    );
    return false;
  }

  String rebuiltEnvelope;
  try {
    rebuiltEnvelope = await buildDeletionWireEnvelope(
      bridge: bridge,
      originalMessage: msg,
      deletedAt: msg.deletedAt ?? msg.timestamp,
      recipientMlKemPublicKey: recipientKey,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE',
      details: {
        'id': _messageIdPreview(msg.id),
        'reason': 'encrypt_failed',
        'error': e.toString(),
      },
    );
    return false;
  }

  if (isOutgoingPrivate) {
    final staged = await privateDeleteRepository!
        .stagePrivateDeleteForEveryoneRetryEnvelope(
          tombstone: msg,
          expectedEnvelope: msg.wireEnvelope,
          envelope: rebuiltEnvelope,
        );
    if (staged == null) {
      _emitDeleteTombstoneStillFailed(
        msg,
        reason: 'private_delete_envelope_stage_refused',
      );
      return false;
    }
    msg = staged;
  } else {
    final staged = await ordinaryTransportRepository!
        .stageOutgoingOrdinaryAttempt(
          expected: msg,
          staged: msg.copyWith(
            status: 'sending',
            transport: null,
            wireEnvelope: rebuiltEnvelope,
            relayExpiresAt: null,
            custodyCheckedAt: null,
          ),
          kind: OutgoingOrdinaryAttemptKind.tombstoneRetry,
        );
    if (!staged.authorizesTransport) {
      _emitDeleteTombstoneStillFailed(
        msg,
        reason: 'ordinary_delete_envelope_stage_refused',
      );
      return false;
    }
    msg = staged.message!;
  }

  return _storeOrReplayDeleteEnvelope(
    msg: msg,
    messageRepo: messageRepo,
    p2pService: p2pService,
    wireEnvelope: rebuiltEnvelope,
    rebuilt: true,
  );
}

Future<bool> _storeOrReplayDeleteEnvelope({
  required ConversationMessage msg,
  required MessageRepository messageRepo,
  required P2PService p2pService,
  required String wireEnvelope,
  required bool rebuilt,
}) async {
  final isOutgoingPrivate = _isOutgoingOneMoreLookPrivate(msg);
  final privateDeleteRepository =
      messageRepo is DirectPrivateDeleteForEveryoneRepository
      ? messageRepo as DirectPrivateDeleteForEveryoneRepository
      : null;
  final ordinaryTransportRepository =
      messageRepo is OutgoingTransportMutationRepository
      ? messageRepo as OutgoingTransportMutationRepository
      : null;
  if (!isOutgoingPrivate && ordinaryTransportRepository == null) return false;
  Future<bool> persistSettlement(ConversationMessage target) async {
    if (isOutgoingPrivate) {
      if (privateDeleteRepository == null) return false;
      return await privateDeleteRepository
              .settlePrivateDeleteForEveryoneTombstone(
                tombstone: target,
                expectedEnvelope: wireEnvelope,
              ) !=
          null;
    }
    final outcome = await ordinaryTransportRepository!
        .settleOutgoingOrdinaryDeleteTombstone(
          messageId: target.id,
          expectedContactPeerId: target.contactPeerId,
          expectedEnvelope: wireEnvelope,
          status: target.status,
          transport: target.transport,
          relayExpiresAt: target.relayExpiresAt,
          mode: OutgoingOrdinarySettlementMode.live,
        );
    return outcome.outcome.authorizesTransport;
  }

  // Genuine deletion-envelope inbox custody is persisted as `inboxed`.
  // A `failed` tombstone carrying `transport == inbox` can be legacy state
  // inherited from the original chat envelope, so it must reacquire custody.
  try {
    final stored = await p2pService.storeInInbox(
      msg.contactPeerId,
      wireEnvelope,
    );
    if (stored) {
      final persisted = await persistSettlement(
        normalizeOutgoingDeleteTombstoneVisibility(
          msg.copyWith(
            status: 'inboxed',
            transport: 'inbox',
            wireEnvelope: wireEnvelope,
          ),
        ),
      );
      if (!persisted) {
        _emitDeleteTombstoneStillFailed(
          msg,
          reason: 'private_delete_settlement_refused',
        );
        return false;
      }
      _emitDeleteTombstoneSuccess(
        msg,
        via: 'inbox',
        status: 'inboxed',
        rebuilt: rebuilt,
      );
      return true;
    }
  } catch (_) {
    // Inbox custody failed; fall through to direct deletion-envelope replay.
  }

  SendMessageResult sendResult;
  try {
    sendResult = await p2pService.sendMessageWithReply(
      msg.contactPeerId,
      wireEnvelope,
      timeoutMs: interactiveDirectBudget.inMilliseconds,
    );
  } catch (e) {
    _emitDeleteTombstoneStillFailed(msg, reason: 'send_error', error: e);
    return false;
  }

  if (!sendResult.sent) {
    _emitDeleteTombstoneStillFailed(msg, reason: 'send_failed');
    return false;
  }

  final via = _resolveRetryDeleteTransport(
    p2pService,
    msg.contactPeerId,
    sendResult,
  );
  final provesDeviceDelivery = sendResult.acked == true;
  final status = provesDeviceDelivery ? 'delivered' : 'sent';
  final persisted = await persistSettlement(
    normalizeOutgoingDeleteTombstoneVisibility(
      msg.copyWith(
        status: status,
        transport: via,
        wireEnvelope: provesDeviceDelivery ? null : wireEnvelope,
      ),
    ),
  );
  if (!persisted) {
    _emitDeleteTombstoneStillFailed(
      msg,
      reason: 'private_delete_settlement_refused',
    );
    return false;
  }
  _emitDeleteTombstoneSuccess(msg, via: via, status: status, rebuilt: rebuilt);
  return true;
}

bool _isV2DeletionWireEnvelope(String wireEnvelope) {
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    return decoded['type'] == 'message_deletion' &&
        decoded['version'].toString() == '2';
  } catch (_) {
    return false;
  }
}

String _resolveRetryDeleteTransport(
  P2PService p2pService,
  String peerId,
  SendMessageResult sendResult,
) {
  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection ? 'relay' : 'direct';
}

void _emitDeleteTombstoneSuccess(
  ConversationMessage msg, {
  required String via,
  required String status,
  required bool rebuilt,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_DELETE_TOMBSTONE_SUCCESS',
    details: {
      'id': _messageIdPreview(msg.id),
      'via': via,
      'status': status,
      'rebuilt': rebuilt,
    },
  );
}

void _emitDeleteTombstoneStillFailed(
  ConversationMessage msg, {
  required String reason,
  Object? error,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_MESSAGE_STILL_FAILED',
    details: {
      'id': _messageIdPreview(msg.id),
      'reason': reason,
      'type': 'message_deletion',
      if (error != null) 'error': error.toString(),
    },
  );
}

/// Resolves which attachments (if any) should be passed to [sendChatMessage]
/// for a retry.
///
/// Returns [attachments] = null for text-only messages, or the list of
/// [MediaAttachment] objects (either reused from Part C or re-uploaded).
/// Returns [skipReason] when the message cannot be recovered or should remain
/// terminal (e.g. local file missing or user-cancelled upload).
Future<_RetryAttachmentResolution> _resolveAttachmentsForRetry({
  required ConversationMessage message,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required Bridge bridge,
  required String targetPeerId,
  required UploadMediaFn uploadFn,
  required bool manualRetry,
  MediaFileManager? mediaFileManager,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  DirectManualUploadRetryRearmRepository? uploadRetryRearmRepo,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
}) async {
  final messageId = message.id;
  final isOutgoingPrivate = _isOutgoingOneMoreLookPrivate(message);
  // Load any persisted attachments for this message
  final persistedAttachments =
      await mediaAttachmentRepo?.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      ) ??
      const <MediaAttachment>[];

  if (persistedAttachments.isEmpty) {
    return const _RetryAttachmentResolution(
      attachments: null,
      skipReason: _RetryFailedMessageSkipReason.none,
    );
  }

  // Use `every` not `any` -- if a message has 2 attachments, one 'done'
  // and one 'upload_pending', `any` would return true and the Part C path
  // would silently drop the incomplete attachment.
  final allUploaded =
      persistedAttachments.isNotEmpty &&
      persistedAttachments.every((a) => a.downloadStatus == 'done');

  if (allUploaded) {
    // CDN blobs already exist for ALL attachments -- reuse them (Part C path).
    return _RetryAttachmentResolution(
      attachments: persistedAttachments,
      skipReason: _RetryFailedMessageSkipReason.none,
    );
  }

  if (persistedAttachments.any(
    (attachment) => attachment.downloadStatus == 'upload_cancelled',
  )) {
    return const _RetryAttachmentResolution(
      attachments: null,
      skipReason: _RetryFailedMessageSkipReason.uploadCancelled,
    );
  }

  // Bulk/reconnect/resume retry is envelope-only. It must not steal pending
  // media from incomplete retry or bypass a terminal upload budget.
  if (!manualRetry) {
    return const _RetryAttachmentResolution(
      attachments: null,
      skipReason: _RetryFailedMessageSkipReason.unfinishedAutomatic,
    );
  }

  final unfinished = persistedAttachments
      .where((attachment) => attachment.downloadStatus != 'done')
      .toList(growable: false);

  final privateCleanupRuntime =
      mediaAttachmentRepo is DirectPrivateMediaCleanupRuntime
      ? mediaAttachmentRepo as DirectPrivateMediaCleanupRuntime
      : null;
  final privateMutationRepository =
      mediaAttachmentRepo is OutgoingDirectPrivateMutationRepository
      ? mediaAttachmentRepo as OutgoingDirectPrivateMutationRepository
      : null;
  final privateEnvelopeRepository =
      messageRepo is OutgoingDirectPrivateEnvelopeCustodyRepository
      ? messageRepo as OutgoingDirectPrivateEnvelopeCustodyRepository
      : null;
  final privateLifecycleRepository =
      messageRepo is DirectPrivateMediaLifecycleRepository
      ? messageRepo as DirectPrivateMediaLifecycleRepository
      : null;
  if (isOutgoingPrivate) {
    if (mediaFileManager == null ||
        privateCleanupRuntime == null ||
        privateMutationRepository == null ||
        privateEnvelopeRepository == null ||
        privateLifecycleRepository == null ||
        !identical(
          privateMutationRepository
              .outgoingDirectPrivateMutationCoordinator
              .lifecycleLock,
          privateCleanupRuntime.directPrivateMediaLifecycleLock,
        )) {
      return const _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.uploadOwnershipUnavailable,
      );
    }
  }
  if (unfinished.length > kReuploadMaxAttachmentsPerMessage) {
    return const _RetryAttachmentResolution(
      attachments: null,
      skipReason: _RetryFailedMessageSkipReason.manualRearmNotEligible,
    );
  }
  final resolvedPaths = <String, String>{};
  final expectations = <ManualUploadRetryAttachmentExpectation>[];
  for (final attachment in unfinished) {
    final retryCount = attachment.uploadRetryCount ?? 0;
    final pending = attachment.downloadStatus == 'upload_pending';
    final boundedExhausted =
        attachment.downloadStatus == 'upload_failed' &&
        retryCount >= kMaxUploadRetries;
    if (!pending && !boundedExhausted) {
      return const _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.manualRearmNotEligible,
      );
    }

    final storedPath = attachment.localPath?.trim();
    if (storedPath == null || storedPath.isEmpty) {
      return const _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.localFileMissing,
      );
    }
    String absolutePath;
    try {
      absolutePath = mediaFileManager == null
          ? storedPath
          : await mediaFileManager.resolveStoredPath(storedPath);
      if (!await File(absolutePath).exists()) {
        return const _RetryAttachmentResolution(
          attachments: null,
          skipReason: _RetryFailedMessageSkipReason.localFileMissing,
        );
      }
    } catch (_) {
      return const _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.localFileMissing,
      );
    }
    resolvedPaths[attachment.id] = absolutePath;
    expectations.add(
      ManualUploadRetryAttachmentExpectation(
        attachmentId: attachment.id,
        storedLocalPath: storedPath,
        downloadStatus: attachment.downloadStatus,
        uploadRetryCount: retryCount,
      ),
    );
  }

  MediaUploadLease? lease;
  var leaseHandedOff = false;
  _DirectPrivateManualRetryCustody? privateCustody;
  try {
    if (tryClaimUploadLease == null ||
        releaseUploadLease == null ||
        uploadRetryRearmRepo == null) {
      return const _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.uploadOwnershipUnavailable,
      );
    }

    lease = tryClaimUploadLease(unfinished.map((attachment) => attachment.id));
    if (lease == null) {
      return const _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.uploadOwnershipUnavailable,
      );
    }

    final rearmed = await uploadRetryRearmRepo.rearmUploadRetryForManualRetry(
      messageId: messageId,
      attachments: expectations,
    );
    if (!rearmed) {
      return const _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.manualRearmNotEligible,
      );
    }

    if (isOutgoingPrivate) {
      privateCustody = await _claimDirectPrivateManualRetryCustody(
        messageId: messageId,
        attachments: unfinished,
        cleanupRuntime: privateCleanupRuntime!,
        lifecycleRepository: privateLifecycleRepository!,
        envelopeRepository: privateEnvelopeRepository!,
        mediaAttachmentRepository: mediaAttachmentRepo!,
        mediaFileManager: mediaFileManager!,
      );
      if (privateCustody == null) {
        return const _RetryAttachmentResolution(
          attachments: null,
          skipReason: _RetryFailedMessageSkipReason.uploadOwnershipUnavailable,
        );
      }
    }

    final reuploadedAttachments = await _reuploadAttachments(
      attachments: unfinished,
      resolvedPaths: resolvedPaths,
      bridge: bridge,
      targetPeerId: targetPeerId,
      uploadFn: uploadFn,
      messageId: messageId,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      uploadRetryProjectionRepo: uploadRetryProjectionRepo,
      privateMutationRepository: isOutgoingPrivate
          ? privateMutationRepository
          : null,
    );
    if (reuploadedAttachments == null) {
      leaseHandedOff = true;
      return _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.uploadFailed,
        uploadLease: lease,
        privateCustody: privateCustody,
      );
    }

    final uploadedById = <String, MediaAttachment>{
      for (final attachment in reuploadedAttachments) attachment.id: attachment,
    };
    final complete = persistedAttachments
        .map((attachment) => uploadedById[attachment.id] ?? attachment)
        .toList(growable: false);
    leaseHandedOff = true;
    return _RetryAttachmentResolution(
      attachments: complete,
      skipReason: _RetryFailedMessageSkipReason.none,
      uploadLease: lease,
      didUpload: true,
      privateCustody: privateCustody,
    );
  } finally {
    if (!leaseHandedOff && lease != null) {
      try {
        await privateCustody?.releaseClaims();
      } finally {
        try {
          releaseUploadLease?.call(lease);
        } finally {
          await privateCustody?.cleanupAfterRelease();
        }
      }
    }
  }
}

Future<_DirectPrivateManualRetryCustody?>
_claimDirectPrivateManualRetryCustody({
  required String messageId,
  required List<MediaAttachment> attachments,
  required DirectPrivateMediaCleanupRuntime cleanupRuntime,
  required DirectPrivateMediaLifecycleRepository lifecycleRepository,
  required OutgoingDirectPrivateEnvelopeCustodyRepository envelopeRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
}) async {
  final tokens = <String, Object>{};
  var handedOff = false;
  try {
    final ordered = attachments.toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    for (final attachment in ordered) {
      final expectedPendingPath = attachment.localPath?.trim();
      if (expectedPendingPath == null || expectedPendingPath.isEmpty) {
        return null;
      }
      final acquired = await cleanupRuntime.directPrivateMediaLifecycleLock
          .synchronized(attachment.id, () async {
            final token = directPrivateMediaTransferRegistry.tryBegin(
              attachment.id,
              messageId: messageId,
            );
            if (token == null) return false;
            try {
              final invalidated = await envelopeRepository
                  .invalidateWireEnvelopeBeforePrivateUpload(
                    messageId: messageId,
                    attachmentId: attachment.id,
                    expectedPendingLocalPath: expectedPendingPath,
                  );
              if (!invalidated) {
                directPrivateMediaTransferRegistry.end(attachment.id, token);
                return false;
              }
              tokens[attachment.id] = token;
              return true;
            } catch (_) {
              directPrivateMediaTransferRegistry.end(attachment.id, token);
              rethrow;
            }
          });
      if (!acquired) return null;
    }
    handedOff = true;
    return _DirectPrivateManualRetryCustody(
      messageId: messageId,
      tokens: tokens,
      expectedPendingPaths: <String, String>{
        for (final attachment in attachments)
          attachment.id: attachment.localPath!.trim(),
      },
      lifecycleRepository: lifecycleRepository,
      envelopeRepository: envelopeRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      cleanupRuntime: cleanupRuntime,
      mediaFileManager: mediaFileManager,
    );
  } finally {
    if (!handedOff) {
      await _releaseManualPrivateTransferClaims(
        cleanupRuntime: cleanupRuntime,
        tokens: tokens,
      );
    }
  }
}

Future<void> _releaseManualPrivateTransferClaims({
  required DirectPrivateMediaCleanupRuntime cleanupRuntime,
  required Map<String, Object> tokens,
}) async {
  final ownedTokens = tokens.entries.toList(growable: false);
  for (final token in ownedTokens) {
    await cleanupRuntime.directPrivateMediaLifecycleLock.synchronized(
      token.key,
      () async {
        directPrivateMediaTransferRegistry.end(token.key, token.value);
      },
    );
  }
  tokens.clear();
}

/// Re-uploads each attachment whose local file still exists on disk.
///
/// Returns the re-uploaded [MediaAttachment] list on full success, or null
/// if any local file is missing or any CDN upload returns null. In the null
/// case the caller skips the message and leaves it as 'failed'.
///
/// NOTE: Re-upload produces a new blob ID (UUID v4 inside uploadMedia)
/// unless the Stable-ID contract is used (blobId: attachment.id).
/// The old blob ID in media_attachments is orphaned on the relay;
/// relay blobs expire after 7 days so orphaned blobs are self-cleaning.
Future<List<MediaAttachment>?> _reuploadAttachments({
  required List<MediaAttachment> attachments,
  required Map<String, String> resolvedPaths,
  required Bridge bridge,
  required String targetPeerId,
  required UploadMediaFn uploadFn,
  required String messageId,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  OutgoingDirectPrivateMutationRepository? privateMutationRepository,
}) async {
  // Defensive ceiling: skip messages with too many attachments
  if (attachments.length > kReuploadMaxAttachmentsPerMessage) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_REUPLOAD_TOO_MANY_ATTACHMENTS',
      details: {'count': attachments.length},
    );
    return null;
  }

  final result = <MediaAttachment>[];

  for (final attachment in attachments) {
    final localPath = resolvedPaths[attachment.id]!;

    final uploadOutcome = await runUploadMedia(
      uploadMediaFn: uploadFn,
      bridge: bridge,
      localFilePath: localPath,
      mime: attachment.mime,
      recipientPeerId: targetPeerId,
      mediaFileManager: mediaFileManager,
      durationMs: attachment.durationMs,
      waveform: attachment.waveform,
      width: attachment.width,
      height: attachment.height,
      blobId: attachment.id, // Stable-ID contract (F.7.1)
    );
    final uploaded = uploadOutcome.attachmentOrNull;

    if (uploaded == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_REUPLOAD_FAILED',
        details: {'localPath': localPath},
      );
      await uploadRetryProjectionRepo?.projectUploadFailure(
        messageId: messageId,
        attachmentId: attachment.id,
        failure: uploadOutcome as UploadMediaFailed,
      );
      return null;
    }

    final completed = uploaded.copyWith(
      id: attachment.id,
      messageId: messageId,
      downloadStatus: 'done',
      uploadRetryCount: 0,
      ownerLane: MediaOwnerLane.direct,
    );
    if (privateMutationRepository != null) {
      final expectedPendingPath = attachment.localPath?.trim();
      if (expectedPendingPath == null || expectedPendingPath.isEmpty) {
        return null;
      }
      final mutation = await privateMutationRepository
          .outgoingDirectPrivateMutationCoordinator
          .commitCompletion(
            attachment: completed,
            expectedPendingLocalPath: expectedPendingPath,
          );
      if (!mutation.authorizesTransportHandoff) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_REUPLOAD_PRIVATE_MUTATION_REFUSED',
          details: {
            'attachmentId': attachment.id.length > 8
                ? attachment.id.substring(0, 8)
                : attachment.id,
          },
        );
        return null;
      }
    } else {
      await mediaAttachmentRepo?.saveAttachment(
        completed,
        owner: MediaOwnerLane.direct,
      );
    }
    result.add(completed);
  }

  return result;
}

bool _isOutgoingOneMoreLookPrivate(ConversationMessage message) =>
    !message.isIncoming &&
    message.privateMediaPolicy.version == 1 &&
    (message.privateMediaMode == PrivateMediaMode.protected ||
        message.privateMediaMode == PrivateMediaMode.viewOnce);

String _messageIdPreview(String id) => id.length > 8 ? id.substring(0, 8) : id;
