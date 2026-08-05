import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_connectivity_probe.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Re-uploads any attachment rows with downloadStatus='upload_pending',
/// grouped by messageId, then calls [sendChatMessage] ONCE per message
/// with the full attachment list to complete the original send.
///
/// This mirrors the real send path in `conversation_wired.dart`, which
/// uploads all attachments for a message and then calls `sendChatMessage`
/// once with the complete list. Processing per-attachment would fragment
/// multi-attachment messages into separate single-attachment sends.
///
/// Ordering in [handleAppResumed]:
///   recoverStuckSendingMessages -> retryIncompleteUploads -> retryFailedMessages
///
/// Returns the number of messages successfully sent after re-upload.
/// Non-fatal per-message: errors are caught, logged, and iteration continues
/// to the next message.
///
/// [isUploadInFlight] guards against the 127-Bug-B double-encrypt race: while a
/// foreground send is actively uploading a blob (its row sits `upload_pending`
/// for the whole upload+envelope window), this retrier must NOT re-encrypt and
/// re-upload the SAME blob — a fresh AES-GCM nonce would mint divergent
/// ciphertext that no longer matches the `contentHash` the foreground already
/// advertised in the message envelope, so the recipient's pre-decrypt
/// content-hash gate rejects it (`integrity_failed` / "Couldn't verify this
/// media"). A blob reported in-flight defers the WHOLE message (rows left
/// `upload_pending`, no terminalization) — the foreground send owns it.
Future<int> retryIncompleteUploads({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MessageRepository messageRepo,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  UploadMediaFn uploadMediaFn = uploadMedia,
  MediaFileManager? mediaFileManager,
  bool Function(String blobId) isUploadInFlight = _uploadNeverInFlight,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
  bool requireOsConnectivity = false,
  MediaUploadConnectivityProbe connectivityProbe = probeMediaUploadConnectivity,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
}) async {
  final retryStopwatch = Stopwatch()..start();
  void emitRetryTiming({
    required String outcome,
    required int attachmentCount,
    required int messageCount,
    required int succeeded,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_UPLOADS_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'attachmentCount': attachmentCount,
        'messageCount': messageCount,
        'succeeded': succeeded,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_START',
    details: {},
  );

  if (requireOsConnectivity && !await connectivityProbe()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_UPLOADS_SKIPPED_NO_CONNECTIVITY',
      details: {},
    );
    emitRetryTiming(
      outcome: 'no_connectivity',
      attachmentCount: 0,
      messageCount: 0,
      succeeded: 0,
    );
    return 0;
  }

  final DirectUploadRetryProjectionRepository? projection =
      uploadRetryProjectionRepo ??
      (messageRepo is DirectUploadRetryProjectionRepository
          ? messageRepo as DirectUploadRetryProjectionRepository
          : null);

  final pendingAttachments = await mediaAttachmentRepo
      .getUploadPendingAttachments(owner: MediaOwnerLane.direct);
  if (pendingAttachments.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_UPLOADS_NONE',
      details: {},
    );
    emitRetryTiming(
      outcome: 'none',
      attachmentCount: 0,
      messageCount: 0,
      succeeded: 0,
    );
    return 0;
  }

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_UPLOADS_NO_IDENTITY',
      details: {},
    );
    emitRetryTiming(
      outcome: 'no_identity',
      attachmentCount: pendingAttachments.length,
      messageCount: 0,
      succeeded: 0,
    );
    return 0;
  }

  // Group attachments by messageId so we process all attachments for a
  // single message together and issue ONE sendChatMessage call per message.
  final byMessageId = <String, List<MediaAttachment>>{};
  for (final att in pendingAttachments) {
    byMessageId.putIfAbsent(att.messageId, () => []).add(att);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_FOUND',
    details: {
      'attachmentCount': pendingAttachments.length,
      'messageCount': byMessageId.length,
    },
  );

  var successCount = 0;

  for (final entry in byMessageId.entries) {
    final messageId = entry.key;
    final pendingAttsForMessage = entry.value;

    // E11: production callers atomically claim the complete attachment set.
    // The legacy predicate remains only for lightweight callers/tests that do
    // not yet provide the token-owned seam. A failed all-or-none claim leaves
    // every row untouched.
    MediaUploadLease? uploadLease;
    final privateTransferTokens = <String, Object>{};
    final authorizedPrivatePendingSources = <String, String>{};
    DirectPrivateMediaCleanupRuntime? privateCleanupRuntime;
    DirectPrivateMediaLifecycleRepository? privateLifecycleMessageRepository;
    OutgoingDirectPrivateEnvelopeCustodyRepository? privateEnvelopeRepository;
    OutgoingDirectPrivateMutationCoordinator? privateMutationCoordinator;
    String? inFlightBlob;
    if (tryClaimUploadLease != null) {
      uploadLease = tryClaimUploadLease(
        pendingAttsForMessage.map((attachment) => attachment.id),
      );
      if (uploadLease == null) {
        inFlightBlob = pendingAttsForMessage.first.id;
      }
    } else {
      for (final att in pendingAttsForMessage) {
        if (isUploadInFlight(att.id)) {
          inFlightBlob = att.id;
          break;
        }
      }
    }
    if (inFlightBlob != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_IN_FLIGHT',
        details: {
          'messageId': messageId.length > 8
              ? messageId.substring(0, 8)
              : messageId,
          'attachmentId': inFlightBlob.length > 8
              ? inFlightBlob.substring(0, 8)
              : inFlightBlob,
        },
      );
      continue;
    }

    try {
      // 1. Load and validate the parent message.
      final msg = await messageRepo.getMessage(messageId);
      if (msg == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_NO_MSG',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
          },
        );
        continue;
      }

      if (msg.status != 'sending' && msg.status != 'failed') {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_STATUS',
          details: {'status': msg.status},
        );
        continue;
      }

      // Load ALL attachments for this message (including already-done ones)
      // so we can combine them with newly-uploaded ones for the send call.
      final allAttachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      final isOutgoingPrivateOneMoreLook =
          !msg.isIncoming &&
          msg.privateMediaPolicy.version == 1 &&
          (msg.privateMediaMode == PrivateMediaMode.protected ||
              msg.privateMediaMode == PrivateMediaMode.viewOnce);
      final preUploadEnvelope = msg.wireEnvelope;
      final ordinaryTransportRepository =
          messageRepo is OutgoingTransportMutationRepository
          ? messageRepo as OutgoingTransportMutationRepository
          : null;
      var ordinaryEnvelopeInvalidated =
          preUploadEnvelope == null || preUploadEnvelope.isEmpty;
      var ordinaryEnvelopeInvalidationRefused = false;
      final mutationRepository =
          mediaAttachmentRepo is OutgoingDirectPrivateMutationRepository
          ? mediaAttachmentRepo as OutgoingDirectPrivateMutationRepository
          : null;
      if (isOutgoingPrivateOneMoreLook) {
        final runtime = mediaAttachmentRepo is DirectPrivateMediaCleanupRuntime
            ? mediaAttachmentRepo as DirectPrivateMediaCleanupRuntime
            : null;
        final envelopeRepository =
            messageRepo is OutgoingDirectPrivateEnvelopeCustodyRepository
            ? messageRepo as OutgoingDirectPrivateEnvelopeCustodyRepository
            : null;
        final lifecycleMessageRepository =
            messageRepo is DirectPrivateMediaLifecycleRepository
            ? messageRepo as DirectPrivateMediaLifecycleRepository
            : null;
        if (runtime == null ||
            mutationRepository == null ||
            envelopeRepository == null ||
            lifecycleMessageRepository == null ||
            mediaFileManager == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_PRIVATE_AUTHORITY_UNAVAILABLE',
            details: {'messageId': messageId},
          );
          continue;
        }
        if (!identical(
          mutationRepository
              .outgoingDirectPrivateMutationCoordinator
              .lifecycleLock,
          runtime.directPrivateMediaLifecycleLock,
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_PRIVATE_AUTHORITY_MISMATCH',
            details: {'messageId': messageId},
          );
          continue;
        }
        privateCleanupRuntime = runtime;
        privateLifecycleMessageRepository = lifecycleMessageRepository;
        privateEnvelopeRepository = envelopeRepository;
        privateMutationCoordinator =
            mutationRepository.outgoingDirectPrivateMutationCoordinator;
        var allClaimsAcquired = true;
        final orderedPending = pendingAttsForMessage.toList(growable: false)
          ..sort((left, right) => left.id.compareTo(right.id));
        for (final attachment in orderedPending) {
          final expectedPendingPath = attachment.localPath;
          if (expectedPendingPath == null || expectedPendingPath.isEmpty) {
            allClaimsAcquired = false;
            break;
          }
          final acquired = await runtime.directPrivateMediaLifecycleLock
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
                    directPrivateMediaTransferRegistry.end(
                      attachment.id,
                      token,
                    );
                    return false;
                  }
                  privateTransferTokens[attachment.id] = token;
                  return true;
                } catch (_) {
                  directPrivateMediaTransferRegistry.end(attachment.id, token);
                  rethrow;
                }
              });
          if (!acquired) {
            allClaimsAcquired = false;
            break;
          }
        }
        if (!allClaimsAcquired) {
          await _releaseIncompletePrivateTransferClaims(
            runtime: runtime,
            tokens: privateTransferTokens,
          );
          continue;
        }
      }

      // 2. Re-upload ALL pending attachments for this message.
      //    If any single upload fails, the message is skipped and
      //    sendChatMessage is NOT called (no partial sends).
      var allUploadsSucceeded = true;
      var isNonRetryable = false;
      UploadMediaFailed? uploadFailure;
      MediaAttachment? failedAttachment;
      final carriedPrivateCompletions = <String, MediaAttachment>{};

      for (final attachment in pendingAttsForMessage) {
        var localPath = attachment.localPath;
        if (localPath == null || localPath.isEmpty) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_NO_PATH',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
            },
          );
          allUploadsSucceeded = false;
          isNonRetryable = true;
          failedAttachment = attachment;
          uploadFailure = const UploadMediaFailed(
            stage: UploadMediaStage.localSource,
            disposition: UploadMediaDisposition.terminal,
            errorCode: 'MISSING_LOCAL_SOURCE',
          );
          break;
        }

        // Resolve relative/legacy paths to absolute filesystem paths
        if (mediaFileManager != null) {
          localPath = await mediaFileManager.resolveStoredPath(localPath);
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_START',
          details: {'mime': attachment.mime},
        );

        final uploadOutcome = await runUploadMedia(
          uploadMediaFn: uploadMediaFn,
          bridge: bridge,
          localFilePath: localPath,
          mime: attachment.mime,
          recipientPeerId: msg.contactPeerId,
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
            event: 'RETRY_INCOMPLETE_UPLOAD_REUPLOAD_FAILED',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
            },
          );
          allUploadsSucceeded = false;
          failedAttachment = attachment;
          uploadFailure = uploadOutcome as UploadMediaFailed;
          break;
        }

        final latestBeforeSave = await _latestAttachmentForMessage(
          mediaAttachmentRepo: mediaAttachmentRepo,
          messageId: messageId,
          attachmentId: attachment.id,
        );
        if (latestBeforeSave != null &&
            latestBeforeSave.downloadStatus != 'upload_pending') {
          if (latestBeforeSave.downloadStatus == 'done') {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_ALREADY_DONE',
              details: {
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
              },
            );
            continue;
          }
          allUploadsSucceeded = false;
          isNonRetryable = true;
          failedAttachment = attachment;
          uploadFailure = const UploadMediaFailed(
            stage: UploadMediaStage.consumerBoundary,
            disposition: UploadMediaDisposition.terminal,
            errorCode: 'STALE_ATTACHMENT_STATE',
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_UPLOAD_ABORT_STALE_ATTACHMENT',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
              'status': latestBeforeSave.downloadStatus,
            },
          );
          break;
        }

        final completedAttachment = uploaded.copyWith(
          id: attachment.id,
          messageId: msg.id,
          downloadStatus: 'done',
        );

        // KC-2 (112 Phase 3): the re-upload minted a fresh key/nonce, so a
        // persisted wire envelope (the Section-4 crash-replay contract,
        // replayed verbatim without re-encrypting) would reference the DEAD
        // key — receivers could download the new blob but never decrypt it.
        // Invalidate it BEFORE committing the new attachment keys. This gives
        // a crash a safe direction: null envelope + pending attachment simply
        // re-uploads, while done + new keys + old envelope would be an
        // undecryptable durable replay. The send below (or any later retry
        // path) rebuilds the envelope from the current attachment rows.
        final keyChanged =
            uploaded.encryptionKeyBase64 != attachment.encryptionKeyBase64 ||
            uploaded.encryptionNonce != attachment.encryptionNonce;
        if (keyChanged &&
            !isOutgoingPrivateOneMoreLook &&
            !ordinaryEnvelopeInvalidated) {
          final invalidation = await ordinaryTransportRepository
              ?.invalidateOutgoingOrdinaryEnvelope(
                messageId: messageId,
                expectedContactPeerId: msg.contactPeerId,
                expectedEnvelope: preUploadEnvelope!,
              );
          if (invalidation == null || !invalidation.changed) {
            ordinaryEnvelopeInvalidationRefused = true;
            allUploadsSucceeded = false;
            emitFlowEvent(
              layer: 'FL',
              event:
                  'RETRY_INCOMPLETE_UPLOAD_WIRE_ENVELOPE_INVALIDATION_REFUSED',
              details: {
                'messageId': messageId.length > 8
                    ? messageId.substring(0, 8)
                    : messageId,
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
              },
            );
            break;
          }
          ordinaryEnvelopeInvalidated = true;
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_UPLOAD_WIRE_ENVELOPE_INVALIDATED',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
            },
          );
        }
        if (isOutgoingPrivateOneMoreLook) {
          final expectedPendingPath = attachment.localPath;
          if (expectedPendingPath == null || mutationRepository == null) {
            allUploadsSucceeded = false;
            isNonRetryable = true;
            failedAttachment = attachment;
            uploadFailure = const UploadMediaFailed(
              stage: UploadMediaStage.consumerBoundary,
              disposition: UploadMediaDisposition.terminal,
              errorCode: 'PRIVATE_MUTATION_AUTHORITY_MISSING',
            );
            break;
          }
          final mutation = await mutationRepository
              .outgoingDirectPrivateMutationCoordinator
              .commitCompletion(
                attachment: completedAttachment.copyWith(
                  ownerLane: MediaOwnerLane.direct,
                ),
                expectedPendingLocalPath: expectedPendingPath,
              );
          if (!mutation.authorizesTransportHandoff) {
            allUploadsSucceeded = false;
            isNonRetryable = true;
            failedAttachment = attachment;
            uploadFailure = const UploadMediaFailed(
              stage: UploadMediaStage.consumerBoundary,
              disposition: UploadMediaDisposition.terminal,
              errorCode: 'PRIVATE_MUTATION_REFUSED',
            );
            break;
          }
          // Recheck every authorized outcome after release. A completion that
          // deferred while opening may have committed through pre-frame
          // settlement before this transfer's finally path runs.
          authorizedPrivatePendingSources[attachment.id] = expectedPendingPath;
          carriedPrivateCompletions[attachment.id] = completedAttachment;
        } else {
          await mediaAttachmentRepo.saveAttachment(
            completedAttachment,
            owner: MediaOwnerLane.direct,
          );
        }
      }

      // A crossed/unsupported parent must not learn the freshly uploaded key,
      // project attachment completion, or proceed to transport.
      if (ordinaryEnvelopeInvalidationRefused) {
        continue;
      }

      // Canonical failure handling (G.8.2): transient vs non-retryable
      if (!allUploadsSucceeded) {
        if (projection != null &&
            failedAttachment != null &&
            uploadFailure != null) {
          await projection.projectUploadFailure(
            messageId: messageId,
            attachmentId: failedAttachment.id,
            failure: uploadFailure,
          );
        } else {
          // Compatibility for lightweight repository doubles that predate the
          // atomic capability. Production always takes the branch above.
          for (final att in pendingAttsForMessage) {
            final latest = await _latestAttachmentForMessage(
              mediaAttachmentRepo: mediaAttachmentRepo,
              messageId: messageId,
              attachmentId: att.id,
            );
            final current = latest ?? att;
            if (current.downloadStatus != 'upload_pending') {
              emitFlowEvent(
                layer: 'FL',
                event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_STALE_FAILURE_UPDATE',
                details: {
                  'attachmentId': att.id.length > 8
                      ? att.id.substring(0, 8)
                      : att.id,
                  'status': current.downloadStatus,
                },
              );
              continue;
            }

            final newRetryCount = (current.uploadRetryCount ?? 0) + 1;
            await mediaAttachmentRepo.saveAttachment(
              current.copyWith(
                downloadStatus:
                    isNonRetryable || newRetryCount >= kMaxUploadRetries
                    ? 'upload_failed'
                    : 'upload_pending',
                uploadRetryCount: newRetryCount,
              ),
              owner: MediaOwnerLane.direct,
            );
          }
        }
        emitFlowEvent(
          layer: 'FL',
          event: isNonRetryable
              ? 'RETRY_INCOMPLETE_UPLOAD_MSG_SKIPPED'
              : 'RETRY_INCOMPLETE_UPLOAD_MSG_DEFERRED',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'reason': isNonRetryable
                ? 'non_retryable_failure'
                : 'transient_failure',
            'totalAttachments': pendingAttsForMessage.length,
          },
        );
        continue;
      }

      final refreshedMsg = await messageRepo.getMessage(messageId);
      final refreshedAttachments = await mediaAttachmentRepo
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct);
      final transportAttachments = refreshedAttachments
          .map(
            (attachment) =>
                carriedPrivateCompletions[attachment.id] ?? attachment,
          )
          .toList(growable: false);
      final abortReason = _lateSendAbortReason(
        message: refreshedMsg,
        attachments: transportAttachments,
        expectedAttachmentIds: {
          for (final attachment in allAttachments) attachment.id,
        },
      );
      if (abortReason != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_ABORT_FINAL_SEND',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'reason': abortReason,
          },
        );
        continue;
      }

      // 3. All uploads still belong to a live retryable row — send ONCE with
      // the current completed attachment set.
      final fullAttachmentList = transportAttachments
          .where((attachment) => attachment.downloadStatus == 'done')
          .toList(growable: false);

      final contact = await contactRepo.getContact(refreshedMsg!.contactPeerId);
      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: refreshedMsg.contactPeerId,
        text: refreshedMsg.text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: refreshedMsg.id,
        timestamp: refreshedMsg.timestamp,
        bridge: bridge,
        recipientMlKemPublicKey: contact?.mlKemPublicKey,
        quotedMessageId: refreshedMsg.quotedMessageId,
        dedupKey: refreshedMsg.dedupKey,
        isForwarded: refreshedMsg.isForwarded,
        mediaAttachments: fullAttachmentList,
        privateMediaPolicy: refreshedMsg.privateMediaPolicy,
        mediaAttachmentRepo: mediaAttachmentRepo,
        emitTimingEvent: false,
      );

      if (result == SendChatMessageResult.success) {
        successCount++;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SUCCESS',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'attachmentCount': fullAttachmentList.length,
          },
        );

        // Cleanup durable storage after successful send
        if (mediaFileManager != null && !isOutgoingPrivateOneMoreLook) {
          try {
            await mediaFileManager.deletePendingUploadDir(messageId);
          } catch (_) {}
        }
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SEND_FAILED',
          details: {'result': result.name},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOAD_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      final releasedPrivateTransfer = privateTransferTokens.isNotEmpty;
      if (releasedPrivateTransfer && privateCleanupRuntime != null) {
        await _releaseIncompletePrivateTransferClaims(
          runtime: privateCleanupRuntime,
          tokens: privateTransferTokens,
        );
      }
      if (uploadLease != null) {
        releaseUploadLease?.call(uploadLease);
      }
      if (releasedPrivateTransfer &&
          privateCleanupRuntime != null &&
          privateLifecycleMessageRepository != null &&
          mediaFileManager != null) {
        try {
          final adapter = DirectPrivateMediaLifecycle(
            messageRepository: privateLifecycleMessageRepository,
            mediaAttachmentRepository: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          );
          for (final committed in authorizedPrivatePendingSources.entries) {
            await adapter.cleanupCommittedPendingSource(
              messageId: messageId,
              attachmentId: committed.key,
              expectedPendingLocalPath: committed.value,
            );
          }
          await PrivateMediaLifecycleEngine(
            adapter: adapter,
            lifecycleLock:
                privateCleanupRuntime.directPrivateMediaLifecycleLock,
            nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
          ).cleanupTerminalMessage(messageId);
        } catch (_) {
          // Durable lifecycle state remains a retryable cleanup candidate.
        }
      }
      if (releasedPrivateTransfer &&
          privateEnvelopeRepository != null &&
          privateLifecycleMessageRepository != null &&
          privateMutationCoordinator != null) {
        await reconcileReleasedOutgoingDirectPrivateUploadAttempt(
          messageId: messageId,
          expectedPendingPaths: authorizedPrivatePendingSources,
          coordinator: privateMutationCoordinator,
          envelopeRepository: privateEnvelopeRepository,
          lifecycleRepository: privateLifecycleMessageRepository,
        );
      }
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_COMPLETE',
    details: {
      'totalAttachments': pendingAttachments.length,
      'totalMessages': byMessageId.length,
      'succeeded': successCount,
    },
  );
  emitRetryTiming(
    outcome: 'complete',
    attachmentCount: pendingAttachments.length,
    messageCount: byMessageId.length,
    succeeded: successCount,
  );

  return successCount;
}

Future<void> _releaseIncompletePrivateTransferClaims({
  required DirectPrivateMediaCleanupRuntime runtime,
  required Map<String, Object> tokens,
}) async {
  final ownedTokens = tokens.entries.toList(growable: false);
  for (final token in ownedTokens) {
    await runtime.directPrivateMediaLifecycleLock.synchronized(
      token.key,
      () async {
        directPrivateMediaTransferRegistry.end(token.key, token.value);
      },
    );
  }
  tokens.clear();
}

/// Default [retryIncompleteUploads] in-flight predicate: nothing is in-flight
/// (used in tests and any caller without a foreground upload tracker).
bool _uploadNeverInFlight(String _) => false;

Future<MediaAttachment?> _latestAttachmentForMessage({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required String messageId,
  required String attachmentId,
}) async {
  final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
    messageId,
    owner: MediaOwnerLane.direct,
  );
  for (final attachment in attachments) {
    if (attachment.id == attachmentId) {
      return attachment;
    }
  }
  return null;
}

String? _lateSendAbortReason({
  required ConversationMessage? message,
  required List<MediaAttachment> attachments,
  required Set<String> expectedAttachmentIds,
}) {
  if (message == null) {
    return 'message_missing';
  }
  if (message.hiddenAt != null) {
    return 'message_hidden';
  }
  if (message.deletedAt != null) {
    return 'message_deleted';
  }
  if (message.status != 'sending' && message.status != 'failed') {
    return 'message_status_${message.status}';
  }

  final oneMoreLookPolicy =
      message.privateMediaPolicy.version == 1 &&
      (message.privateMediaMode == PrivateMediaMode.protected ||
          message.privateMediaMode == PrivateMediaMode.viewOnce);
  if (oneMoreLookPolicy) {
    if (message.isIncoming) {
      return 'private_parent_incoming';
    }
    final stateAuthorized = switch (message.privateMediaState) {
      PrivateMediaLifecycleState.available =>
        message.privateMediaRevealedAtMs == null &&
            message.privateMediaTerminalAtMs == null,
      PrivateMediaLifecycleState.opening ||
      PrivateMediaLifecycleState.viewing =>
        message.privateMediaTerminalAtMs == null,
      PrivateMediaLifecycleState.consumed =>
        message.privateMediaTerminalAtMs != null,
      _ => false,
    };
    if (!stateAuthorized) {
      return 'private_state_${message.privateMediaState.name}';
    }
  }

  if (attachments.length != expectedAttachmentIds.length ||
      attachments.any(
        (attachment) => !expectedAttachmentIds.contains(attachment.id),
      )) {
    return 'attachment_set_changed';
  }
  if (attachments.any((attachment) => attachment.downloadStatus != 'done')) {
    return 'attachments_not_done';
  }
  return null;
}
