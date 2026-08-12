import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/direct_inbox_event_envelope.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart'
    show DirectMediaBlobCustodyRow;
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/outbound_envelope_policy.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/outgoing_direct_private_transport_settlement.dart';
import 'package:flutter_app/features/conversation/application/outgoing_live_deadline.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
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
  mediaCustodyProjectionMismatch,
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
/// [retryDirectInboxCustody] defaults to true so standalone bulk callers retain
/// the historical exact-custody retry behavior. A caller that has just run the
/// fair global custody drain may set it to false; pending custody is still
/// detected as the sole retry authority, but is not stored a second time and
/// never falls through to envelope rebuild or re-encryption.
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
  DirectMediaBlobArtifactStore? directMediaBlobArtifactStore,
  PreparedDirectMediaBlobCustodyCoordinator? directMediaBlobCustodyCoordinator,
  bool retryDirectInboxCustody = true,
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
    directMediaBlobArtifactStore: directMediaBlobArtifactStore,
    directMediaBlobCustodyCoordinator: directMediaBlobCustodyCoordinator,
    uploadRetryProjectionRepo: null,
    manualRetry: false,
    retryDirectInboxCustody: retryDirectInboxCustody,
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
  DirectMediaBlobArtifactStore? directMediaBlobArtifactStore,
  PreparedDirectMediaBlobCustodyCoordinator? directMediaBlobCustodyCoordinator,
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
    directMediaBlobArtifactStore: directMediaBlobArtifactStore,
    directMediaBlobCustodyCoordinator: directMediaBlobCustodyCoordinator,
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
    retryDirectInboxCustody: true,
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
  DirectMediaBlobArtifactStore? directMediaBlobArtifactStore,
  PreparedDirectMediaBlobCustodyCoordinator? directMediaBlobCustodyCoordinator,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  DirectManualUploadRetryRearmRepository? uploadRetryRearmRepo,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
  required bool manualRetry,
  required bool retryDirectInboxCustody,
}) async {
  final retryStopwatch = clock.stopwatch()..start();
  final effectiveUploadFn = uploadMediaFn ?? uploadMedia;
  final ackCustodyInboxStore = p2pService is AckOrExpiryInboxStore
      ? p2pService as AckOrExpiryInboxStore
      : null;
  Future<InboxStoreOutcome> storeExactCustody(
    String toPeerId,
    String envelope, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    if (ackCustodyInboxStore != null) {
      return ackCustodyInboxStore.storeInAckCustodyInboxDetailed(
        toPeerId,
        envelope,
        custodyKind: custodyKind,
        timeoutMs: timeoutMs,
      );
    }
    return const InboxStoreOutcome(
      status: InboxStoreStatus.failed,
      errorCode: 'ACK_OR_EXPIRY_STORE_UNAVAILABLE',
    );
  }

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
      directMediaBlobArtifactStore: directMediaBlobArtifactStore,
      directMediaBlobCustodyCoordinator: directMediaBlobCustodyCoordinator,
      uploadRetryProjectionRepo: uploadRetryProjectionRepo,
      uploadRetryRearmRepo: uploadRetryRearmRepo,
      tryClaimUploadLease: tryClaimUploadLease,
      releaseUploadLease: releaseUploadLease,
      manualRetry: manualRetry,
      retryDirectInboxCustody: retryDirectInboxCustody,
      storeExactCustody: storeExactCustody,
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
  DirectMediaBlobArtifactStore? directMediaBlobArtifactStore,
  PreparedDirectMediaBlobCustodyCoordinator? directMediaBlobCustodyCoordinator,
  MediaAttachmentRepository? mediaAttachmentRepo,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  DirectManualUploadRetryRearmRepository? uploadRetryRearmRepo,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
  required bool manualRetry,
  required bool retryDirectInboxCustody,
  required StoreInAckCustodyInboxDetailedFn storeExactCustody,
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
    final loadedMutationOwner = await _retryOwnedDirectMutationIfPresent(
      message: msg,
      messageRepo: messageRepo,
      storeExactCustody: storeExactCustody,
      attemptOwnedCustody: retryDirectInboxCustody,
    );
    if (loadedMutationOwner.handled) {
      return loadedMutationOwner.success;
    }

    // A v108 immutable custody row is the sole retry authority for its initial
    // direct event. Resolve it from the list-loaded identity before re-reading
    // the weaker parent: settlement or physical deletion may win between list
    // load and execution without revoking the retained outbox row. Either this
    // caller attempts the exact bytes, or a bulk pass following the global
    // drain recognizes the retained row and stops. Neither path may fall
    // through to upload, cached-envelope, or re-encryption work.
    final loadedMessageId = msg.id;
    if (messageRepo is OutgoingDirectTextInboxCustodyRepository) {
      final custodyRepository =
          messageRepo as OutgoingDirectTextInboxCustodyRepository;
      DirectInboxCustodyOutboxEntry? owner;
      try {
        owner = await custodyRepository.loadDirectInboxCustodyOwnerForMessageId(
          messageId: loadedMessageId,
        );
      } on StateError {
        // 361: plural/fanout-owned custody has no single owner. The exact
        // surviving siblings are drained by the global custody drain; this
        // single-target wrapper refuses before any legacy work.
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_DIRECT_INBOX_CUSTODY_FANOUT_OWNED',
          details: <String, Object?>{
            'id': loadedMessageId.length > 8
                ? loadedMessageId.substring(0, 8)
                : loadedMessageId,
          },
        );
        return false;
      }
      if (owner != null) {
        if (!retryDirectInboxCustody) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_DIRECT_INBOX_CUSTODY_SKIPPED_AFTER_DRAIN',
            details: <String, Object?>{
              'id': loadedMessageId.length > 8
                  ? loadedMessageId.substring(0, 8)
                  : loadedMessageId,
            },
          );
          return false;
        }
        final custodyAttempt = await drainOwnedDirectInboxCustodyOutboxEntry(
          entry: owner,
          custodyRepository: custodyRepository,
          storeInAckCustodyInboxDetailed: storeExactCustody,
          storeInMediaExpiryBoundedInboxDetailed:
              p2pService is MediaExpiryBoundedInboxStore
              ? (p2pService as MediaExpiryBoundedInboxStore)
                    .storeInMediaExpiryBoundedInboxDetailed
              : null,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_DIRECT_INBOX_CUSTODY_OWNED',
          details: <String, Object?>{
            'id': loadedMessageId.length > 8
                ? loadedMessageId.substring(0, 8)
                : loadedMessageId,
            'completed': custodyAttempt.completed,
          },
        );
        return custodyAttempt.completed;
      }
    }

    // 116 EF-3 settled-recheck: when no immutable custody exists, the loaded
    // list may hold a stale snapshot of a row that settled between load and
    // execution. Re-fetch and use the FRESH row for every weaker retry path.
    final fresh = await messageRepo.getMessage(loadedMessageId);
    if (fresh == null || fresh.isIncoming || fresh.status != 'failed') {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MESSAGE_SKIPPED_SETTLED',
        details: {
          'id': loadedMessageId.length > 8
              ? loadedMessageId.substring(0, 8)
              : loadedMessageId,
        },
      );
      return false;
    }
    if (fresh.directEventFanoutGenerationId != null &&
        fresh.directMediaCustodyIntentId == null) {
      // 361: zero surviving siblings with a nonnull generation marker is a
      // terminal no-remint fact. Re-encrypting or re-sending here would
      // manufacture a single logical-account target the fanout batch never
      // authorized. (362: a marker WITH a live v110 intent is a pre-v108
      // linked MEDIA generation — its persisted v114 rows are validated as
      // the exclusive retry authority below.)
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_SKIPPED_FANOUT_GENERATION',
        details: {
          'id': loadedMessageId.length > 8
              ? loadedMessageId.substring(0, 8)
              : loadedMessageId,
        },
      );
      return false;
    }
    msg = fresh;

    final freshMutationOwner = await _retryOwnedDirectMutationIfPresent(
      message: msg,
      messageRepo: messageRepo,
      storeExactCustody: storeExactCustody,
      attemptOwnedCustody: retryDirectInboxCustody,
    );
    if (freshMutationOwner.handled) {
      return freshMutationOwner.success;
    }

    // A persisted fresh-media intent is exclusive provenance. Validate its
    // complete current projection before any retry path can rebuild blobs,
    // rotate keys, encrypt an event, or fall through to generic storage.
    final directMediaIntent = msg.directMediaCustodyIntentId;
    _RetryAttachmentResolution? strictBlobResolution;
    DirectLinkedMediaFanoutContext? linkedMediaFanout;
    if (directMediaIntent != null) {
      if (mediaAttachmentRepo == null) return false;
      try {
        final currentAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(msg.id, owner: MediaOwnerLane.direct);
        DirectMediaBlobCustodyRepository? blobRepository;
        var blobCustodyRows = const <DirectMediaBlobCustodyRow>[];
        var hasDirectMediaBlobGeneration = false;
        if (kDirectMediaBlobCustodyClientEnabled &&
            mediaAttachmentRepo is DirectMediaBlobCustodyRepository) {
          final candidateRepository =
              mediaAttachmentRepo as DirectMediaBlobCustodyRepository;
          if (candidateRepository.supportsDirectMediaBlobCustody) {
            blobRepository = candidateRepository;
            blobCustodyRows = await candidateRepository
                .loadDirectMediaBlobCustodyForMessage(msg.id);
            hasDirectMediaBlobGeneration = blobCustodyRows.isNotEmpty;
          }
        }
        // 362: a fanout-marked media parent is owned by its persisted linked
        // rows. Marker without linked rows (terminal, unlinked contradiction,
        // or unreadable authority) skips — never the single-target lanes.
        final hasLinkedFanoutRows = blobCustodyRows.any(
          (row) => row.isLinkedFanoutRow,
        );
        if (msg.directEventFanoutGenerationId != null && !hasLinkedFanoutRows) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_SKIPPED_FANOUT_GENERATION',
            details: {'id': _messageIdPreview(msg.id)},
          );
          return false;
        }
        if (!_isExactDirectMediaCustodyProjectionBeforeFailedRetry(
          message: msg,
          expectedSenderPeerId: identity.peerId,
          attachments: currentAttachments,
          manualRetry: manualRetry,
          allowPublishedPending: hasDirectMediaBlobGeneration,
        )) {
          return false;
        }
        if (blobRepository != null && hasDirectMediaBlobGeneration) {
          final coordinator =
              directMediaBlobCustodyCoordinator ??
              PreparedDirectMediaBlobCustodyCoordinator(
                repository: blobRepository,
                artifactStore:
                    directMediaBlobArtifactStore ??
                    DirectMediaBlobArtifactStore(),
              );
          if (hasLinkedFanoutRows) {
            // 362: survivors are retry authority — replay the exact
            // persisted per-target uploads without a roster read, then let
            // the send below author the atomic per-target v108 batch against
            // the live snapshot.
            final fanoutRepository =
                mediaAttachmentRepo
                    is OutgoingDirectLinkedMediaBlobFanoutRepository
                ? mediaAttachmentRepo
                      as OutgoingDirectLinkedMediaBlobFanoutRepository
                : null;
            final rowContactAccountPeerId = blobCustodyRows
                .firstWhere((row) => row.isLinkedFanoutRow)
                .contactAccountPeerId;
            if (fanoutRepository == null ||
                !fanoutRepository.supportsDirectLinkedMediaBlobFanout ||
                rowContactAccountPeerId == null ||
                rowContactAccountPeerId != msg.contactPeerId) {
              return false;
            }
            final strictResult = await coordinator
                .retryPersistedFanoutGeneration(
                  bridge: bridge,
                  identityPeerId: identity.peerId,
                  expectedParent: msg,
                  expectedAttachments: currentAttachments,
                );
            if (!strictResult.isComplete) return false;
            final snapshot = await fanoutRepository
                .readDirectContactFanoutSnapshotForMedia(
                  rowContactAccountPeerId,
                );
            if (snapshot == null || snapshot.targets.isEmpty) return false;
            linkedMediaFanout = DirectLinkedMediaFanoutContext(
              contactAccountPeerId: rowContactAccountPeerId,
              snapshot: snapshot,
              targetRows: strictResult.targetRows,
            );
            strictBlobResolution = _RetryAttachmentResolution(
              attachments: strictResult.attachments,
              skipReason: _RetryFailedMessageSkipReason.none,
              didUpload: true,
            );
          } else {
            final strictResult = await coordinator.reopenAndUpload(
              bridge: bridge,
              identityPeerId: identity.peerId,
              recipientPeerId: msg.contactPeerId,
              expectedParent: msg,
              expectedAttachments: currentAttachments,
            );
            if (!strictResult.isComplete) return false;
            strictBlobResolution = _RetryAttachmentResolution(
              attachments: strictResult.attachments,
              skipReason: _RetryFailedMessageSkipReason.none,
              didUpload: true,
            );
          }
        }
      } catch (_) {
        return false;
      }
    }

    if (msg.isDeleted) {
      return _retryFailedDeletedTombstone(
        msg: msg,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        retryDirectInboxCustody: retryDirectInboxCustody,
        storeExactCustody: storeExactCustody,
      );
    }

    // Resolve media authority before replaying a cached envelope. Automatic
    // retries are envelope-only for completed media; pending/terminal rows are
    // owned by the incomplete/manual lanes and must never be uploaded here.
    final resolution =
        strictBlobResolution ??
        await _resolveAttachmentsForRetry(
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
          expectedSenderPeerId: identity.peerId,
          directMediaBlobCustodyCoordinator: directMediaBlobCustodyCoordinator,
          directMediaBlobArtifactStore: directMediaBlobArtifactStore,
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
        case _RetryFailedMessageSkipReason.mediaCustodyProjectionMismatch:
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MEDIA_CUSTODY_PROJECTION_REFUSED',
            details: details,
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

      final cachedEditEventId = _cachedEditEventId(msg);
      final unsafeLegacyEnvelope =
          isUnsafeLegacyOutboundEnvelope(msg.wireEnvelope!) ||
          (deriveRetryAction(msg) == MessagePayload.actionEdit &&
              cachedEditEventId == null);
      if (!unsafeLegacyEnvelope) {
        final preEgressMutationOwner = await _retryOwnedDirectMutationIfPresent(
          message: msg,
          messageRepo: messageRepo,
          storeExactCustody: storeExactCustody,
          attemptOwnedCustody: retryDirectInboxCustody,
        );
        if (preEgressMutationOwner.handled) {
          return preEgressMutationOwner.success;
        }
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
          // The exact custody attempt remains durably retryable below.
        }
        if (cachedEditEventId != null) {
          // A current edit envelope is one immutable logical event. If STORE
          // committed remotely but its response was lost, re-encrypting under
          // the same event id would let relay `duplicate` retire custody for
          // different bytes (and potentially an obsolete recipient key).
          // Retain this exact envelope for the next retry instead. Only a
          // legacy edit without an event id may take the one-time rebuild path.
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_EDIT_EXACT_ENVELOPE_RETAINED',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
            },
          );
          return false;
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
      directLinkedMediaFanout: linkedMediaFanout,
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

Future<({bool handled, bool success})> _retryOwnedDirectMutationIfPresent({
  required ConversationMessage message,
  required MessageRepository messageRepo,
  required StoreInAckCustodyInboxDetailedFn storeExactCustody,
  required bool attemptOwnedCustody,
}) async {
  final envelope = message.wireEnvelope;
  if (envelope == null || envelope.isEmpty) {
    return (handled: false, success: false);
  }
  final classified = classifyDirectInboxEventEnvelope(envelope);
  if (classified == null || !classified.isMutation) {
    return (handled: false, success: false);
  }
  // 356: ownership is a property of the shared v109 outbox, not of whichever
  // owner staged the event. A private deletion is staged by the private owner,
  // so casting through the text-stage capability would miss it entirely.
  final lifecycleCapability =
      messageRepo is DirectMutationInboxCustodyLifecycleRepository
      ? messageRepo as DirectMutationInboxCustodyLifecycleRepository
      : null;
  final repository =
      lifecycleCapability?.supportsDirectMutationInboxCustodyLifecycle == true
      ? lifecycleCapability
      : null;
  final owner = repository == null
      ? null
      : await repository.loadDirectTextMutationInboxCustodyForEvent(
          recipientPeerId: message.contactPeerId,
          eventId: classified.eventId,
        );
  if (owner == null) {
    // An ownerless event-bearing edit may predate Plan 349 and keeps its exact
    // historical cached-envelope fallback. Event-bearing deletions did not
    // exist before this contract, so missing authority is corruption.
    return classified.kind == DirectInboxEventEnvelopeKind.deletion
        ? (handled: true, success: false)
        : (handled: false, success: false);
  }
  if (!attemptOwnedCustody) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_DIRECT_MUTATION_CUSTODY_SKIPPED_AFTER_DRAIN',
      details: {'id': _messageIdPreview(message.id)},
    );
    return (handled: true, success: false);
  }
  final completed = await drainOwnedDirectMutationInboxCustodyOutboxEntry(
    entry: owner,
    custodyRepository: repository!,
    storeInAckCustodyInboxDetailed: storeExactCustody,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_DIRECT_MUTATION_CUSTODY_OWNED',
    details: {'id': _messageIdPreview(message.id), 'completed': completed},
  );
  return (handled: true, success: completed);
}

/// Returns the immutable event identity from a cached v2 edit envelope.
///
/// The message id remains the edit target. A missing/blank/malformed identity
/// identifies a legacy edit: its cached bytes must not enter the relay inbox,
/// and the full-send path will mint and atomically persist one before transport.
String? _cachedEditEventId(ConversationMessage message) {
  if (deriveRetryAction(message) != MessagePayload.actionEdit) return null;
  final wireEnvelope = message.wireEnvelope;
  if (wireEnvelope == null || wireEnvelope.isEmpty) return null;
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic> ||
        decoded['type'] != 'chat_message' ||
        decoded['version'].toString() != '2' ||
        decoded['id'] != message.id) {
      return null;
    }
    final eventId = decoded['eventId'];
    if (eventId is! String) return null;
    final normalized = eventId.trim();
    return normalized.isEmpty ? null : normalized;
  } catch (_) {
    return null;
  }
}

Future<bool> _retryFailedDeletedTombstone({
  required ConversationMessage msg,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required bool retryDirectInboxCustody,
  required StoreInAckCustodyInboxDetailedFn storeExactCustody,
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
      retryDirectInboxCustody: retryDirectInboxCustody,
      storeExactCustody: storeExactCustody,
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
    retryDirectInboxCustody: retryDirectInboxCustody,
    storeExactCustody: storeExactCustody,
  );
}

Future<bool> _storeOrReplayDeleteEnvelope({
  required ConversationMessage msg,
  required MessageRepository messageRepo,
  required P2PService p2pService,
  required String wireEnvelope,
  required bool rebuilt,
  required bool retryDirectInboxCustody,
  required StoreInAckCustodyInboxDetailedFn storeExactCustody,
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
  final preEgressMutationOwner = await _retryOwnedDirectMutationIfPresent(
    message: msg,
    messageRepo: messageRepo,
    storeExactCustody: storeExactCustody,
    attemptOwnedCustody: retryDirectInboxCustody,
  );
  if (preEgressMutationOwner.handled) {
    return preEgressMutationOwner.success;
  }

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
    // Inbox custody owns the first attempt. Only after it fails do we create a
    // live-delivery T0, so relay latency cannot consume a leg that did not yet
    // exist while the eventual direct replay remains absolutely bounded.
    final liveStopwatch = clock.stopwatch()..start();
    final liveDeadline = OutgoingLiveDeadline(() => liveStopwatch.elapsed);
    final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
    if (timeoutMs == null) {
      _emitDeleteTombstoneStillFailed(msg, reason: 'send_deadline_exhausted');
      return false;
    }
    sendResult = await p2pService.sendMessageWithReply(
      msg.contactPeerId,
      wireEnvelope,
      timeoutMs: timeoutMs,
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
  required String expectedSenderPeerId,
  MediaFileManager? mediaFileManager,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  DirectManualUploadRetryRearmRepository? uploadRetryRearmRepo,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
  PreparedDirectMediaBlobCustodyCoordinator? directMediaBlobCustodyCoordinator,
  DirectMediaBlobArtifactStore? directMediaBlobArtifactStore,
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

  final tokenBearingPreparation = message.directMediaCustodyIntentId != null;
  if (tokenBearingPreparation &&
      !_isExactDirectMediaCustodyProjectionBeforeFailedRetry(
        message: message,
        expectedSenderPeerId: expectedSenderPeerId,
        attachments: persistedAttachments,
        manualRetry: manualRetry,
        allowPublishedPending: false,
      )) {
    return const _RetryAttachmentResolution(
      attachments: null,
      skipReason: _RetryFailedMessageSkipReason.mediaCustodyProjectionMismatch,
    );
  }

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

    ConversationMessage? mediaCustodyFailureParent;
    List<MediaAttachment> mediaCustodyFailureAttachments = const [];
    if (tokenBearingPreparation) {
      final currentParent = await messageRepo.getMessage(messageId);
      final currentProjection =
          await mediaAttachmentRepo?.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          ) ??
          const <MediaAttachment>[];
      if (currentParent == null ||
          !isExactDirectMediaCustodyRetryProjection(
            message: currentParent,
            expectedSenderPeerId: expectedSenderPeerId,
            attachments: currentProjection,
          )) {
        return const _RetryAttachmentResolution(
          attachments: null,
          skipReason:
              _RetryFailedMessageSkipReason.mediaCustodyProjectionMismatch,
        );
      }
      mediaCustodyFailureParent = currentParent;
      mediaCustodyFailureAttachments = currentProjection;
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

    // 354: an already-published protected/View-Once generation is reopened
    // byte-identically here too. It never reaches the legacy upload helper
    // below, so no re-encryption, key rotation or envelope invalidation can
    // occur; a crossed or partial strict projection fails closed instead.
    final strictPrivate = await _reopenStrictPrivateFailedRetryAttachments(
      message: message,
      unfinished: unfinished,
      bridge: bridge,
      expectedSenderPeerId: expectedSenderPeerId,
      targetPeerId: targetPeerId,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      privateMutationRepository: isOutgoingPrivate
          ? privateMutationRepository
          : null,
      directMediaBlobCustodyCoordinator: directMediaBlobCustodyCoordinator,
      directMediaBlobArtifactStore: directMediaBlobArtifactStore,
      tokenBearingPreparation: tokenBearingPreparation,
    );
    if (strictPrivate.owned && strictPrivate.attachments == null) {
      leaseHandedOff = true;
      return _RetryAttachmentResolution(
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.uploadFailed,
        uploadLease: lease,
        privateCustody: privateCustody,
      );
    }
    final reuploadedAttachments =
        strictPrivate.attachments ??
        await _reuploadAttachments(
          attachments: unfinished,
          resolvedPaths: resolvedPaths,
          bridge: bridge,
          targetPeerId: targetPeerId,
          uploadFn: uploadFn,
          messageId: messageId,
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          uploadRetryProjectionRepo: uploadRetryProjectionRepo,
          privateMutationRepository: isOutgoingPrivate
              ? privateMutationRepository
              : null,
          carryToDirectMediaCustody: tokenBearingPreparation,
          mediaCustodyFailureParent: mediaCustodyFailureParent,
          mediaCustodyFailureAttachments: mediaCustodyFailureAttachments,
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

/// Exact token-bearing projection admitted before a failed manual retry CAS.
///
/// The shared validator deliberately accepts only prepared (`upload_pending`)
/// and completed rows. A user-triggered retry may also start from the one
/// terminal state that the atomic rearm capability owns: an exact prepared row
/// at the bounded retry ceiling. Model only that CAS result here; the real
/// parent and attachments are reloaded and checked by the strict validator
/// after rearm, before any upload can begin.
bool _isExactDirectMediaCustodyProjectionBeforeFailedRetry({
  required ConversationMessage message,
  required String expectedSenderPeerId,
  required List<MediaAttachment> attachments,
  required bool manualRetry,
  required bool allowPublishedPending,
}) {
  if (isExactDirectMediaCustodyRetryProjection(
    message: message,
    expectedSenderPeerId: expectedSenderPeerId,
    attachments: attachments,
    allowPublishedPending: allowPublishedPending,
  )) {
    return true;
  }
  if (!manualRetry) return false;

  var hasAtCeilingTerminal = false;
  final modeledRearm = attachments
      .map((attachment) {
        final retryCount = attachment.uploadRetryCount ?? 0;
        if (attachment.downloadStatus != 'upload_failed' ||
            retryCount < kMaxUploadRetries) {
          return attachment;
        }
        hasAtCeilingTerminal = true;
        return attachment.copyWith(
          downloadStatus: 'upload_pending',
          uploadRetryCount: 0,
        );
      })
      .toList(growable: false);

  return hasAtCeilingTerminal &&
      isExactDirectMediaCustodyRetryProjection(
        message: message,
        expectedSenderPeerId: expectedSenderPeerId,
        attachments: modeledRearm,
      );
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
  required MessageRepository messageRepo,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  OutgoingDirectPrivateMutationRepository? privateMutationRepository,
  bool carryToDirectMediaCustody = false,
  ConversationMessage? mediaCustodyFailureParent,
  List<MediaAttachment> mediaCustodyFailureAttachments = const [],
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
      final failure = uploadOutcome as UploadMediaFailed;
      if (carryToDirectMediaCustody) {
        final failureRepository =
            mediaAttachmentRepo is OutgoingDirectMediaCustodyFailureRepository
            ? mediaAttachmentRepo as OutgoingDirectMediaCustodyFailureRepository
            : null;
        var projected = const UploadRetryProjectionResult.notApplied();
        final expectedParent = mediaCustodyFailureParent;
        if (failureRepository != null &&
            failureRepository.supportsDirectMediaCustodyFailureProjection &&
            expectedParent != null &&
            mediaCustodyFailureAttachments.isNotEmpty) {
          try {
            final freshParent = await messageRepo.getMessage(messageId);
            final freshAttachments = await mediaAttachmentRepo!
                .getAttachmentsForMessage(
                  messageId,
                  owner: MediaOwnerLane.direct,
                );
            if (freshParent != null &&
                _sameRetryFailureDatabaseMap(
                  expectedParent.toMap(),
                  freshParent.toMap(),
                ) &&
                _sameRetryFailureAttachmentProjection(
                  mediaCustodyFailureAttachments,
                  freshAttachments,
                )) {
              projected = await failureRepository
                  .projectDirectMediaCustodyUploadFailure(
                    expectedParent: freshParent,
                    expectedAttachments: freshAttachments,
                    failedAttachmentId: attachment.id,
                    failure: failure,
                  );
            }
          } catch (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_REUPLOAD_MEDIA_CUSTODY_FAILURE_ERROR',
              details: {'errorType': error.runtimeType.toString()},
            );
          }
        }
        emitFlowEvent(
          layer: 'FL',
          event: projected.applied
              ? 'RETRY_REUPLOAD_MEDIA_CUSTODY_FAILURE_PROJECTED'
              : 'RETRY_REUPLOAD_MEDIA_CUSTODY_FAILURE_REFUSED',
          details: {'messageId': messageId},
        );
      } else {
        await uploadRetryProjectionRepo?.projectUploadFailure(
          messageId: messageId,
          attachmentId: attachment.id,
          failure: failure,
        );
      }
      return null;
    }

    final completed = carryToDirectMediaCustody
        ? completeDirectMediaCustodyRetryAttachment(
            prepared: attachment,
            uploaded: uploaded,
          )
        : uploaded.copyWith(
            id: attachment.id,
            messageId: messageId,
            downloadStatus: 'done',
            uploadRetryCount: 0,
            ownerLane: MediaOwnerLane.direct,
          );
    if (completed == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_REUPLOAD_MEDIA_CUSTODY_COMPLETION_REFUSED',
        details: {
          'attachmentId': attachment.id.length > 8
              ? attachment.id.substring(0, 8)
              : attachment.id,
        },
      );
      return null;
    }
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
    } else if (!carryToDirectMediaCustody) {
      await mediaAttachmentRepo?.saveAttachment(
        completed,
        owner: MediaOwnerLane.direct,
      );
    }
    result.add(completed);
  }

  return result;
}

bool _sameRetryFailureAttachmentProjection(
  List<MediaAttachment> expected,
  List<MediaAttachment> current,
) {
  if (expected.length != current.length) return false;
  final currentById = <String, MediaAttachment>{
    for (final attachment in current) attachment.id: attachment,
  };
  return currentById.length == current.length &&
      expected.every((attachment) {
        final fresh = currentById[attachment.id];
        return fresh != null &&
            _sameRetryFailureDatabaseMap(attachment.toMap(), fresh.toMap());
      });
}

bool _sameRetryFailureDatabaseMap(
  Map<String, Object?> expected,
  Map<String, Object?> current,
) =>
    expected.length == current.length &&
    expected.entries.every((entry) => current[entry.key] == entry.value);

bool _isOutgoingOneMoreLookPrivate(ConversationMessage message) =>
    !message.isIncoming &&
    message.privateMediaPolicy.version == 1 &&
    (message.privateMediaMode == PrivateMediaMode.protected ||
        message.privateMediaMode == PrivateMediaMode.viewOnce);

String _messageIdPreview(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// 354: outcome of the strict private failed-retry reopen.
///
/// [owned] is true only when a durable protected/View-Once v111 generation
/// exists for this parent, which permanently excludes the legacy upload lane.
/// A null [attachments] under [owned] therefore means "retain custody and fail
/// closed", never "fall back and re-encrypt".
typedef _StrictPrivateFailedRetry = ({
  bool owned,
  List<MediaAttachment>? attachments,
});

Future<_StrictPrivateFailedRetry> _reopenStrictPrivateFailedRetryAttachments({
  required ConversationMessage message,
  required List<MediaAttachment> unfinished,
  required Bridge bridge,
  required String expectedSenderPeerId,
  required String targetPeerId,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required MediaFileManager? mediaFileManager,
  required OutgoingDirectPrivateMutationRepository? privateMutationRepository,
  required PreparedDirectMediaBlobCustodyCoordinator?
  directMediaBlobCustodyCoordinator,
  required DirectMediaBlobArtifactStore? directMediaBlobArtifactStore,
  required bool tokenBearingPreparation,
}) async {
  const notOwned = (owned: false, attachments: null);
  if (!kDirectMediaBlobCustodyClientEnabled ||
      tokenBearingPreparation ||
      privateMutationRepository == null ||
      mediaAttachmentRepo == null ||
      mediaFileManager == null ||
      mediaAttachmentRepo is! DirectMediaBlobCustodyRepository) {
    return notOwned;
  }
  final blobRepository =
      mediaAttachmentRepo as DirectMediaBlobCustodyRepository;
  if (!blobRepository.supportsDirectMediaBlobCustody) return notOwned;
  final rows = await blobRepository.loadDirectMediaBlobCustodyForMessage(
    message.id,
  );
  if (rows.isEmpty) return notOwned;

  const failClosed = (owned: true, attachments: null);
  final pending = unfinished.length == 1 ? unfinished.single : null;
  final pendingPath = pending?.localPath?.trim();
  if (rows.length != 1 ||
      pending == null ||
      pendingPath == null ||
      pendingPath.isEmpty ||
      rows.single.attachmentId != pending.id ||
      message.senderPeerId != expectedSenderPeerId ||
      message.contactPeerId != targetPeerId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_PRIVATE_STRICT_RETAINED',
      details: {'id': _messageIdPreview(message.id)},
    );
    return failClosed;
  }

  final coordinator =
      directMediaBlobCustodyCoordinator ??
      PreparedDirectMediaBlobCustodyCoordinator(
        repository: blobRepository,
        artifactStore:
            directMediaBlobArtifactStore ?? DirectMediaBlobArtifactStore(),
      );
  final strictResult = await coordinator.reopenAndUploadPrivate(
    bridge: bridge,
    identityPeerId: expectedSenderPeerId,
    recipientPeerId: targetPeerId,
    expectedParent: message,
    expectedAttachment: pending,
  );
  if (!strictResult.isComplete || strictResult.attachments.length != 1) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_PRIVATE_STRICT_RETAINED',
      details: {'id': _messageIdPreview(message.id)},
    );
    return failClosed;
  }

  final canonical = await canonicalizeStrictPrivateRetryCompletion(
    mediaFileManager: mediaFileManager,
    contactPeerId: targetPeerId,
    messageId: message.id,
    pendingLocalPath: pendingPath,
    strict: strictResult.attachments.single,
  );
  if (canonical == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_PRIVATE_STRICT_CANONICALIZE_REFUSED',
      details: {'id': _messageIdPreview(message.id)},
    );
    return failClosed;
  }
  final mutation = await privateMutationRepository
      .outgoingDirectPrivateMutationCoordinator
      .commitCompletion(
        attachment: canonical,
        expectedPendingLocalPath: pendingPath,
      );
  if (!mutation.authorizesTransportHandoff) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_PRIVATE_STRICT_COMPLETION_REFUSED',
      details: {'id': _messageIdPreview(message.id)},
    );
    return failClosed;
  }
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_PRIVATE_STRICT_REOPENED',
    details: {'id': _messageIdPreview(message.id)},
  );
  return (owned: true, attachments: <MediaAttachment>[canonical]);
}
