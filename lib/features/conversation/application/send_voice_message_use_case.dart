import 'dart:io';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/application/direct_media_fanout_admission.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart'
    show isExactV2DirectChatInitialEnvelope;
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

enum SendVoiceMessageResult {
  success,
  invalidRecording,
  uploadFailed,
  uploadQueued,
  sendFailed,
}

/// Largest voice recording a fresh send accepts (100 MB).
///
/// 362: also consumed by the composer's admission boundary, which pulls
/// this read-only validation ahead of every send-owned durable write.
const kMaxVoiceRecordingBytes = 100 * 1024 * 1024;

/// Orchestrates sending a voice message:
/// 1. Validate recording
/// 2. Upload via bridge
/// 3. Send via sendChatMessage with audio MediaAttachment
///
/// Returns (result, message) — message is non-null on success.
Future<(SendVoiceMessageResult, ConversationMessage?)> sendVoiceMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String senderPeerId,
  required String senderUsername,
  required AudioRecording recording,
  required Bridge bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  String? text,
  String? quotedMessageId,
  List<double>? waveform,
  String? messageId,
  bool preassignedMessageIdIsFresh = false,
  String? timestamp,
  String? blobId,
  // 112 Phase 4 "encrypt once": the composer's LAN leg already streamed
  // this artifact; the relay upload must reuse the same key/ciphertext.
  EncryptedMediaArtifact? preparedArtifact,
  UploadMediaFn uploadMediaFn = uploadMedia,
  DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  DirectMediaBlobArtifactStore? directMediaBlobArtifactStore,
  PreparedDirectMediaBlobCustodyCoordinator? directMediaBlobCustodyCoordinator,
  bool directMediaBlobCustodyClientEnabled =
      kDirectMediaBlobCustodyClientEnabled,
}) async {
  final sendStopwatch = Stopwatch()..start();
  void emitVoiceTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'durationMs': recording.durationMs,
        'sizeBytes': recording.sizeBytes,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'VOICE_SEND_START',
    details: {
      'durationMs': recording.durationMs,
      'sizeBytes': recording.sizeBytes,
    },
  );

  Future<(SendVoiceMessageResult, ConversationMessage?)>
  sendCompletedVoiceProjection({
    required List<MediaAttachment> attachments,
    required int uploadMs,
    required bool cleanupPreparedSource,
  }) async {
    final voiceSendStopwatch = Stopwatch()..start();
    final (result, message) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: text ?? '',
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      quotedMessageId: quotedMessageId,
      mediaAttachments: attachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      messageId: messageId,
      preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
      timestamp: timestamp,
      emitTimingEvent: false,
    );

    voiceSendStopwatch.stop();
    final voiceSendMs = voiceSendStopwatch.elapsedMilliseconds;

    // The prepared source is the only durable copy until the combined media
    // custody transaction consumes its manifest token. Upload completion is
    // not that authority: re-read after sendChatMessage and clean up only
    // after the durable parent proves the token was consumed.
    if (cleanupPreparedSource && messageId != null) {
      try {
        final durableParent = await messageRepo.getMessage(messageId);
        if (durableParent != null &&
            durableParent.directMediaCustodyIntentId == null) {
          await mediaFileManager?.deletePendingUploadDir(messageId);
        }
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'VOICE_PREPARED_SOURCE_CLEANUP_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
      }
    }

    if (result == SendChatMessageResult.success) {
      emitFlowEvent(layer: 'FL', event: 'VOICE_SEND_SUCCESS', details: {});
      emitVoiceTiming(
        outcome: 'success',
        details: {'uploadMs': uploadMs, 'sendMs': voiceSendMs},
      );
      return (SendVoiceMessageResult.success, message);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_FAILED',
      details: {'result': result.name},
    );
    emitVoiceTiming(
      outcome: 'send_failed',
      details: {
        'result': result.name,
        'uploadMs': uploadMs,
        'sendMs': voiceSendMs,
      },
    );
    return (SendVoiceMessageResult.sendFailed, null);
  }

  // A v108 row means a prior combined transaction already owns the exact
  // encrypted envelope. When its mutable parent/media projection still
  // matches, sendChatMessage replays that durable projection. If those rows
  // were removed or changed, the immutable outbox row instead uses the narrow
  // ACK-or-expiry drain. Neither route touches the recorder source, uploads,
  // re-encrypts, or derives delivery authority from mutable message state.
  final directCustodyRepository =
      messageRepo is OutgoingDirectTextInboxCustodyRepository
      ? messageRepo as OutgoingDirectTextInboxCustodyRepository
      : null;
  if (messageId != null &&
      directCustodyRepository?.supportsDirectTextInboxCustody == true) {
    try {
      final custody = await directCustodyRepository!
          .loadDirectInboxCustodyOwnerForMessageId(messageId: messageId);
      if (custody != null) {
        if (!_isExactVoiceCustodyAuthority(
          custody: custody,
          messageId: messageId,
          senderPeerId: senderPeerId,
        )) {
          emitVoiceTiming(outcome: 'custody_replay_refused');
          return (SendVoiceMessageResult.sendFailed, null);
        }
        ConversationMessage? durableParent;
        var durableAttachments = const <MediaAttachment>[];
        try {
          durableParent = await messageRepo.getMessage(messageId);
          if (mediaAttachmentRepo != null) {
            durableAttachments = await mediaAttachmentRepo
                .getAttachmentsForMessage(
                  messageId,
                  owner: MediaOwnerLane.direct,
                );
          }
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'VOICE_CUSTODY_REPLAY_PROJECTION_READ_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
          durableParent = null;
          durableAttachments = const <MediaAttachment>[];
        }
        final exactVoiceReplay =
            custody.recipientPeerId == targetPeerId &&
            durableParent != null &&
            _isExactDurableVoiceReplayProjection(
              parent: durableParent,
              attachments: durableAttachments,
              messageId: messageId,
              attachmentId: blobId,
              targetPeerId: targetPeerId,
              senderPeerId: senderPeerId,
              text: text ?? '',
              timestamp: timestamp,
              quotedMessageId: quotedMessageId,
              recording: recording,
              waveform: waveform,
            );
        if (!exactVoiceReplay) {
          final ackCustodyStore = p2pService is AckOrExpiryInboxStore
              ? p2pService as AckOrExpiryInboxStore
              : null;
          if (ackCustodyStore == null) {
            emitVoiceTiming(outcome: 'custody_replay_retained');
            return (SendVoiceMessageResult.sendFailed, null);
          }
          // The drain owns immutable outbox bytes and exact-incarnation
          // completion. It deliberately does not require or rewrite a parent.
          final attempt = await drainOwnedDirectInboxCustodyOutboxEntry(
            entry: custody,
            custodyRepository: directCustodyRepository,
            storeInAckCustodyInboxDetailed:
                ackCustodyStore.storeInAckCustodyInboxDetailed,
            storeInMediaExpiryBoundedInboxDetailed:
                p2pService is MediaExpiryBoundedInboxStore
                ? (p2pService as MediaExpiryBoundedInboxStore)
                      .storeInMediaExpiryBoundedInboxDetailed
                : null,
          );
          if (!attempt.completed) {
            emitVoiceTiming(outcome: 'custody_replay_retained');
            return (SendVoiceMessageResult.sendFailed, null);
          }
          // If exact completion observes absence, the owned-row drain treats
          // that as convergence rather than resurrecting upload work.
          emitFlowEvent(
            layer: 'FL',
            event: 'VOICE_SEND_SUCCESS',
            details: const {'custodyDrain': true},
          );
          emitVoiceTiming(
            outcome: 'success',
            details: const {'uploadMs': 0, 'custodyDrain': true},
          );
          return (SendVoiceMessageResult.success, null);
        }
        return sendCompletedVoiceProjection(
          attachments: durableAttachments,
          uploadMs: 0,
          cleanupPreparedSource: false,
        );
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'VOICE_CUSTODY_REPLAY_READ_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      emitVoiceTiming(outcome: 'custody_replay_read_error');
      return (SendVoiceMessageResult.sendFailed, null);
    }
  }

  // 1. Validate only when no immutable v108 authority exists. A custody row
  // can outlive the recorder source and every mutable media projection, so
  // stale caller-side recording metadata must never strand its exact bytes.
  if (recording.sizeBytes <= 0 ||
      recording.sizeBytes > kMaxVoiceRecordingBytes) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_INVALID',
      details: {'sizeBytes': recording.sizeBytes},
    );
    emitVoiceTiming(outcome: 'invalid_recording');
    return (SendVoiceMessageResult.invalidRecording, null);
  }

  final file = File(recording.filePath);
  if (!file.existsSync()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_FILE_NOT_FOUND',
      details: {'filePath': recording.filePath},
    );
    emitVoiceTiming(outcome: 'file_not_found');
    return (SendVoiceMessageResult.invalidRecording, null);
  }

  if (recipientMlKemPublicKey == null ||
      recipientMlKemPublicKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_ENCRYPTION_REQUIRED',
      details: {},
    );
    emitVoiceTiming(outcome: 'encryption_required');
    return (SendVoiceMessageResult.sendFailed, null);
  }

  // A v110-prepared voice row owns an authored pending identity. Qualify and
  // capture that exact identity before upload can delete its pending source;
  // the uploaded result contributes completion fields only. The combined DB
  // transaction repeats the same identity check after envelope serialization.
  ConversationMessage? preparedVoiceParent;
  MediaAttachment? preparedVoiceAttachment;
  bool preparedVoiceHasStrictGeneration = false;
  if (messageId != null) {
    try {
      final preparedParent = await messageRepo.getMessage(messageId);
      if (preparedParent?.directMediaCustodyIntentId != null) {
        final attachmentId = blobId;
        final repository = mediaAttachmentRepo;
        if (attachmentId == null || repository == null) {
          emitVoiceTiming(outcome: 'prepared_identity_refused');
          return (SendVoiceMessageResult.sendFailed, null);
        }
        final projection = await repository.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        final expectedIntent = computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: projection.map((attachment) => attachment.id),
        );
        final expectedPendingPath =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: recording.mime,
            );
        final strictRepository = directMediaBlobCustodyClientEnabled
            ? _directMediaBlobRepository(repository)
            : null;
        final strictRows = strictRepository == null
            ? const <DirectMediaBlobCustodyRow>[]
            : await strictRepository.loadDirectMediaBlobCustodyForMessage(
                messageId,
              );
        final hasCompleteStrictGeneration =
            projection.length == 1 &&
            strictRows.length == 1 &&
            strictRows.single.attachmentId == attachmentId &&
            strictRows.single.messageId == messageId &&
            strictRows.single.direction ==
                DirectMediaBlobCustodyDirection.outgoing &&
            const <DirectMediaBlobCustodyState>{
              DirectMediaBlobCustodyState.outgoingPrepared,
              DirectMediaBlobCustodyState.outgoingStored,
            }.contains(strictRows.single.state) &&
            strictRows.single.recipientPeerId == targetPeerId &&
            projection.single.contentHash == strictRows.single.contentHash &&
            projection.single.encryptionKeyBase64 != null &&
            projection.single.encryptionNonce != null &&
            projection.single.encryptionScheme ==
                kMediaAttachmentEncryptionSchemeBlobAesGcmV1;
        final hasFreshCryptoProjection =
            projection.length == 1 &&
            projection.single.contentHash == null &&
            projection.single.thumbnailHash == null &&
            projection.single.encryptionKeyBase64 == null &&
            projection.single.encryptionNonce == null &&
            projection.single.encryptionScheme == null;
        final exactPreparedIdentity =
            projection.length == 1 &&
            preparedParent != null &&
            !preparedParent.isIncoming &&
            preparedParent.contactPeerId == targetPeerId &&
            preparedParent.senderPeerId == senderPeerId &&
            preparedParent.text == (text ?? '') &&
            (timestamp == null || preparedParent.timestamp == timestamp) &&
            preparedParent.timestamp.trim().isNotEmpty &&
            preparedParent.createdAt.trim().isNotEmpty &&
            preparedParent.quotedMessageId == quotedMessageId &&
            !preparedParent.isForwarded &&
            const <String>{
              'sending',
              'failed',
            }.contains(preparedParent.status) &&
            preparedParent.editedAt == null &&
            preparedParent.deletedAt == null &&
            preparedParent.deletedByPeerId == null &&
            preparedParent.hiddenAt == null &&
            preparedParent.wireEnvelope == null &&
            preparedParent.transport == null &&
            preparedParent.relayExpiresAt == null &&
            preparedParent.custodyCheckedAt == null &&
            preparedParent.privateMediaPolicy.version == 0 &&
            preparedParent.privateMediaMode == PrivateMediaMode.ordinary &&
            preparedParent.privateMediaDurationSeconds == null &&
            preparedParent.privateMediaState ==
                PrivateMediaLifecycleState.none &&
            preparedParent.privateMediaReceivedAtMs == null &&
            preparedParent.privateMediaExpiresAtMs == null &&
            preparedParent.privateMediaRevealedAtMs == null &&
            preparedParent.privateMediaTerminalAtMs == null &&
            preparedParent.privateMediaClockHighWaterMs == null &&
            preparedParent.directMediaCustodyIntentId == expectedIntent &&
            projection.single.id == attachmentId &&
            projection.single.messageId == messageId &&
            projection.single.ownerLane == MediaOwnerLane.direct &&
            projection.single.downloadStatus == 'upload_pending' &&
            projection.single.localPath == expectedPendingPath &&
            projection.single.mime == recording.mime &&
            projection.single.mediaType == 'audio' &&
            projection.single.mediaType ==
                MediaAttachment.mediaTypeFromMime(projection.single.mime) &&
            projection.single.size == recording.sizeBytes &&
            projection.single.width == null &&
            projection.single.height == null &&
            projection.single.durationMs == recording.durationMs &&
            projection.single.createdAt == preparedParent.createdAt &&
            _sameVoiceWaveform(projection.single.waveform, waveform) &&
            (hasFreshCryptoProjection || hasCompleteStrictGeneration);
        if (!exactPreparedIdentity) {
          emitVoiceTiming(outcome: 'prepared_identity_refused');
          return (SendVoiceMessageResult.sendFailed, null);
        }
        preparedVoiceParent = preparedParent;
        preparedVoiceAttachment = projection.single;
        preparedVoiceHasStrictGeneration = hasCompleteStrictGeneration;
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'VOICE_PREPARED_IDENTITY_READ_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      emitVoiceTiming(outcome: 'prepared_identity_read_error');
      return (SendVoiceMessageResult.sendFailed, null);
    }
  }

  // 362 ADMISSION BOUNDARY (voice use case). Hoisted ABOVE the strict-custody
  // selector so it governs the legacy singular lane too: with the incumbent
  // custody selector off, `strictRepository` below is null and control used to
  // fall straight through to a single-target `runUploadMedia` without ever
  // reading the roster.
  //
  // Fresh voice has no plural fanout owner, so an initialized roster refuses
  // rather than reaching one target. Survivors are exempt by contract — a
  // committed generation replays exact persisted bytes and must never
  // re-resolve the roster. `preparedVoiceHasStrictGeneration` is itself
  // selector-derived, but a rolled-back persisted generation cannot reach here
  // in a selector-off build: it fails the exact-prepared-identity gate above
  // first, so the survivor carve-out cannot be silently widened by the flag.
  if (!preparedVoiceHasStrictGeneration) {
    final voiceAdmission = await resolveDirectMediaFanoutAdmission(
      mediaAttachmentRepository: mediaAttachmentRepo,
      contactAccountPeerId: targetPeerId,
      canServeLinkedFanout: false,
    );
    if (voiceAdmission.refuses) {
      emitFlowEvent(
        layer: 'FL',
        event: 'VOICE_SEND_MEDIA_FANOUT_SINGULAR_REFUSED',
        details: {
          'reason': voiceAdmission.reason,
          'target': targetPeerId.length > 10
              ? targetPeerId.substring(0, 10)
              : targetPeerId,
        },
      );
      emitVoiceTiming(outcome: 'media_fanout_singular_refused');
      return (SendVoiceMessageResult.sendFailed, null);
    }
  }

  // 2. Upload
  emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_START', details: {});

  final uploadStopwatch = Stopwatch()..start();
  final strictRepository =
      directMediaBlobCustodyClientEnabled &&
          preparedVoiceParent != null &&
          preparedVoiceAttachment != null
      ? _directMediaBlobRepository(mediaAttachmentRepo)
      : null;
  if (strictRepository != null) {
    final coordinator =
        directMediaBlobCustodyCoordinator ??
        PreparedDirectMediaBlobCustodyCoordinator(
          repository: strictRepository,
          artifactStore:
              directMediaBlobArtifactStore ?? DirectMediaBlobArtifactStore(),
        );
    final parent = preparedVoiceParent!;
    final attachment = preparedVoiceAttachment!;
    // 362: the fanout admission boundary above now governs BOTH this strict
    // lane and the legacy singular lane, so the old flag-gated guard that
    // used to sit here is gone.
    final strictResult = preparedVoiceHasStrictGeneration
        ? await coordinator.reopenAndUpload(
            bridge: bridge,
            identityPeerId: senderPeerId,
            recipientPeerId: targetPeerId,
            expectedParent: parent,
            expectedAttachments: <MediaAttachment>[attachment],
            onGenerationReady: p2pService.isLocalPeer(targetPeerId)
                ? (artifacts) => _sendStrictVoiceOverLan(
                    p2pService: p2pService,
                    senderPeerId: senderPeerId,
                    targetPeerId: targetPeerId,
                    durationMs: recording.durationMs,
                    artifacts: artifacts,
                  )
                : null,
          )
        : await coordinator.prepareAndUploadFresh(
            bridge: bridge,
            identityPeerId: senderPeerId,
            recipientPeerId: targetPeerId,
            expectedParent: parent,
            sources: <PreparedDirectMediaBlobSource>[
              PreparedDirectMediaBlobSource(
                attachment: attachment,
                plaintextPath: recording.filePath,
                preparedArtifact: preparedArtifact,
              ),
            ],
            onGenerationReady: p2pService.isLocalPeer(targetPeerId)
                ? (artifacts) => _sendStrictVoiceOverLan(
                    p2pService: p2pService,
                    senderPeerId: senderPeerId,
                    targetPeerId: targetPeerId,
                    durationMs: recording.durationMs,
                    artifacts: artifacts,
                  )
                : null,
          );
    uploadStopwatch.stop();
    if (strictResult.isComplete) {
      return sendCompletedVoiceProjection(
        attachments: strictResult.attachments,
        uploadMs: uploadStopwatch.elapsedMilliseconds,
        cleanupPreparedSource: false,
      );
    }
    emitVoiceTiming(
      outcome: strictResult.state == PreparedDirectMediaBlobUploadState.retained
          ? 'strict_upload_queued'
          : 'strict_generation_refused',
    );
    return (
      strictResult.state == PreparedDirectMediaBlobUploadState.retained
          ? SendVoiceMessageResult.uploadQueued
          : SendVoiceMessageResult.sendFailed,
      null,
    );
  }
  final uploadOutcome = await runUploadMedia(
    uploadMediaFn: uploadMediaFn,
    bridge: bridge,
    localFilePath: recording.filePath,
    mime: recording.mime,
    recipientPeerId: targetPeerId,
    mediaFileManager: mediaFileManager,
    durationMs: recording.durationMs,
    waveform: waveform,
    blobId: blobId,
    // The recorder temp is plaintext residue once the durable copy is the
    // render source. Safe: the voice LAN send is awaited BEFORE this
    // use case runs (conversation_wired voice flow).
    deleteSourceWhenDone: preparedVoiceAttachment == null,
    preparedArtifact: preparedArtifact,
  );
  final uploaded = uploadOutcome.attachmentOrNull;
  uploadStopwatch.stop();
  final uploadMs = uploadStopwatch.elapsedMilliseconds;

  if (uploaded == null) {
    // 117 Session 4 (finding #3c): the relay upload failed (e.g. a LAN-only
    // delivery or transient relay outage), but the sender's OWN voice note
    // must remain playable. uploadMedia only makes its durable owned copy on
    // upload success, so on failure the optimistic row still points at the
    // recorder temp — which the OS can evict, flipping the message to
    // pending→failed→"Media unavailable" and triggering a relay download for
    // a blob that was never uploaded. Persist a durable owned copy + a 'done'
    // attachment row here so display resolution finds it locally. (Delivery
    // truthfulness — the message status — is a separate concern handled by the
    // caller.)
    if (preparedVoiceAttachment == null) {
      await _persistDurableVoiceCopyOnUploadFailure(
        recording: recording,
        targetPeerId: targetPeerId,
        blobId: blobId,
        messageId: messageId,
        waveform: waveform,
        mediaFileManager: mediaFileManager,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
    }
    UploadRetryProjectionResult projected =
        const UploadRetryProjectionResult.notApplied();
    final failure = uploadOutcome as UploadMediaFailed;
    if (preparedVoiceAttachment != null) {
      // A manifest-bound preparation must not pass through the legacy
      // single-row upload-failure writer. Re-read the complete projection after
      // the upload attempt, compare it with the exact pre-upload snapshot, then
      // let the media repository revalidate that same snapshot and global v108
      // absence in one transaction. Missing/crossed authority fails closed.
      final failureAuthority =
          mediaAttachmentRepo is OutgoingDirectMediaCustodyFailureRepository &&
              (mediaAttachmentRepo
                      as OutgoingDirectMediaCustodyFailureRepository)
                  .supportsDirectMediaCustodyFailureProjection
          ? mediaAttachmentRepo as OutgoingDirectMediaCustodyFailureRepository
          : null;
      final expectedParent = preparedVoiceParent;
      if (failureAuthority != null &&
          expectedParent != null &&
          messageId != null &&
          blobId != null) {
        try {
          final freshParent = await messageRepo.getMessage(messageId);
          final freshAttachments = await mediaAttachmentRepo!
              .getAttachmentsForMessage(
                messageId,
                owner: MediaOwnerLane.direct,
              );
          if (freshParent != null &&
              _sameVoicePreparationParent(expectedParent, freshParent) &&
              _sameVoicePreparationAttachments(<MediaAttachment>[
                preparedVoiceAttachment,
              ], freshAttachments)) {
            projected = await failureAuthority
                .projectDirectMediaCustodyUploadFailure(
                  expectedParent: freshParent,
                  expectedAttachments: freshAttachments,
                  failedAttachmentId: blobId,
                  failure: failure,
                );
          }
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'VOICE_MEDIA_CUSTODY_FAILURE_PROJECTION_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
        }
      }
      if (!projected.applied) {
        emitFlowEvent(
          layer: 'FL',
          event: 'VOICE_MEDIA_CUSTODY_FAILURE_PROJECTION_REFUSED',
          details: const {},
        );
      }
    } else {
      final projection =
          uploadRetryProjectionRepo ??
          (messageRepo is DirectUploadRetryProjectionRepository
              ? messageRepo as DirectUploadRetryProjectionRepository
              : null);
      if (projection != null && messageId != null && blobId != null) {
        projected = await projection.projectUploadFailure(
          messageId: messageId,
          attachmentId: blobId,
          failure: failure,
        );
      }
    }
    if (projected.applied && !projected.isTerminal) {
      emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_QUEUED', details: {});
      emitVoiceTiming(
        outcome: 'upload_queued',
        details: {'uploadMs': uploadMs},
      );
      return (SendVoiceMessageResult.uploadQueued, null);
    }
    emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_FAILED', details: {});
    emitVoiceTiming(outcome: 'upload_failed', details: {'uploadMs': uploadMs});
    return (SendVoiceMessageResult.uploadFailed, null);
  }

  if (preparedVoiceAttachment != null &&
      !_isExactPreparedVoiceUploadResult(
        prepared: preparedVoiceAttachment,
        uploaded: uploaded,
      )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_PREPARED_UPLOAD_IDENTITY_REFUSED',
      details: const {},
    );
    emitVoiceTiming(
      outcome: 'prepared_upload_identity_refused',
      details: {'uploadMs': uploadMs},
    );
    return (SendVoiceMessageResult.sendFailed, null);
  }

  emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_DONE', details: {});

  final completedVoiceAttachment = preparedVoiceAttachment == null
      ? uploaded
      : preparedVoiceAttachment.copyWith(
          localPath: uploaded.localPath,
          downloadStatus: 'done',
          contentHash: uploaded.contentHash,
          thumbnailHash: uploaded.thumbnailHash,
          encryptionKeyBase64: uploaded.encryptionKeyBase64,
          encryptionNonce: uploaded.encryptionNonce,
          encryptionScheme: uploaded.encryptionScheme,
          ownerLane: MediaOwnerLane.direct,
        );

  // 3. Send via existing sendChatMessage with the uploaded attachment.
  return sendCompletedVoiceProjection(
    attachments: <MediaAttachment>[completedVoiceAttachment],
    uploadMs: uploadMs,
    cleanupPreparedSource: preparedVoiceAttachment != null,
  );
}

final RegExp _voiceCustodySha256 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _voiceCustodyIncarnation = RegExp(r'^[0-9a-f]{32}$');

bool _isExactVoiceCustodyAuthority({
  required DirectInboxCustodyOutboxEntry custody,
  required String messageId,
  required String senderPeerId,
}) =>
    custody.recipientPeerId.trim().isNotEmpty &&
    custody.messageId == messageId &&
    _voiceCustodyIncarnation.hasMatch(custody.incarnationId) &&
    isExactV2DirectChatInitialEnvelope(
      custody.wireEnvelope,
      messageId: messageId,
      senderPeerId: senderPeerId,
    );

bool _isExactPreparedVoiceUploadResult({
  required MediaAttachment prepared,
  required MediaAttachment uploaded,
}) =>
    uploaded.id == prepared.id &&
    uploaded.messageId.isEmpty &&
    uploaded.mime == prepared.mime &&
    uploaded.size == prepared.size &&
    uploaded.mediaType == prepared.mediaType &&
    uploaded.width == prepared.width &&
    uploaded.height == prepared.height &&
    uploaded.durationMs == prepared.durationMs &&
    _sameVoiceWaveform(uploaded.waveform, prepared.waveform) &&
    uploaded.downloadStatus == 'done';

bool _sameVoicePreparationParent(
  ConversationMessage expected,
  ConversationMessage current,
) => _sameVoiceDatabaseMap(expected.toMap(), current.toMap());

bool _sameVoicePreparationAttachments(
  List<MediaAttachment> expected,
  List<MediaAttachment> current,
) {
  if (expected.length != current.length) return false;
  final currentById = <String, MediaAttachment>{
    for (final attachment in current) attachment.id: attachment,
  };
  if (currentById.length != current.length) return false;
  return expected.every((attachment) {
    final fresh = currentById[attachment.id];
    return fresh != null &&
        _sameVoiceDatabaseMap(attachment.toMap(), fresh.toMap());
  });
}

bool _sameVoiceDatabaseMap(
  Map<String, Object?> expected,
  Map<String, Object?> current,
) =>
    expected.length == current.length &&
    expected.entries.every((entry) => current[entry.key] == entry.value);

bool _isExactDurableVoiceReplayProjection({
  required ConversationMessage parent,
  required List<MediaAttachment> attachments,
  required String messageId,
  required String? attachmentId,
  required String targetPeerId,
  required String senderPeerId,
  required String text,
  required String? timestamp,
  required String? quotedMessageId,
  required AudioRecording recording,
  required List<double>? waveform,
}) {
  if (attachmentId == null || attachments.length != 1) return false;
  final attachment = attachments.single;
  final localPath = attachment.localPath?.trim().replaceAll('\\', '/');
  return parent.id == messageId &&
      !parent.isIncoming &&
      parent.contactPeerId == targetPeerId &&
      parent.senderPeerId == senderPeerId &&
      parent.text == text &&
      (timestamp == null || parent.timestamp == timestamp) &&
      parent.timestamp.trim().isNotEmpty &&
      parent.createdAt.trim().isNotEmpty &&
      parent.quotedMessageId == quotedMessageId &&
      !parent.isForwarded &&
      const <String>{
        'sending',
        'sent',
        'failed',
        'delivered',
      }.contains(parent.status) &&
      parent.editedAt == null &&
      parent.deletedAt == null &&
      parent.deletedByPeerId == null &&
      parent.hiddenAt == null &&
      parent.directMediaCustodyIntentId == null &&
      parent.privateMediaPolicy.version == 0 &&
      parent.privateMediaMode == PrivateMediaMode.ordinary &&
      parent.privateMediaDurationSeconds == null &&
      parent.privateMediaState == PrivateMediaLifecycleState.none &&
      parent.privateMediaReceivedAtMs == null &&
      parent.privateMediaExpiresAtMs == null &&
      parent.privateMediaRevealedAtMs == null &&
      parent.privateMediaTerminalAtMs == null &&
      parent.privateMediaClockHighWaterMs == null &&
      attachment.id == attachmentId &&
      attachment.messageId == messageId &&
      attachment.ownerLane == MediaOwnerLane.direct &&
      attachment.mime == recording.mime &&
      attachment.mediaType == 'audio' &&
      attachment.mediaType ==
          MediaAttachment.mediaTypeFromMime(attachment.mime) &&
      attachment.size == recording.sizeBytes &&
      attachment.width == null &&
      attachment.height == null &&
      attachment.durationMs == recording.durationMs &&
      attachment.createdAt == parent.createdAt &&
      _sameVoiceWaveform(attachment.waveform, waveform) &&
      attachment.downloadStatus == 'done' &&
      localPath != null &&
      localPath.isNotEmpty &&
      !localPath.startsWith('pending_uploads/') &&
      !localPath.contains('/pending_uploads/') &&
      _voiceCustodySha256.hasMatch(attachment.contentHash ?? '') &&
      (attachment.thumbnailHash == null ||
          _voiceCustodySha256.hasMatch(attachment.thumbnailHash!)) &&
      (attachment.encryptionKeyBase64?.trim().isNotEmpty ?? false) &&
      (attachment.encryptionNonce?.trim().isNotEmpty ?? false) &&
      attachment.encryptionScheme ==
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1;
}

bool _sameVoiceWaveform(List<double>? left, List<double>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

DirectMediaBlobCustodyRepository? _directMediaBlobRepository(Object? value) {
  if (value is! DirectMediaBlobCustodyRepository ||
      !value.supportsDirectMediaBlobCustody) {
    return null;
  }
  return value;
}

Future<void> _sendStrictVoiceOverLan({
  required P2PService p2pService,
  required String senderPeerId,
  required String targetPeerId,
  required int durationMs,
  required List<PreparedDirectMediaBlobArtifact> artifacts,
}) async {
  for (final artifact in artifacts) {
    await p2pService.sendLocalMedia(
      peerId: targetPeerId,
      filePath: artifact.absoluteCiphertextPath,
      mime: kOpaqueMediaTransportMime,
      mediaId: artifact.attachment.id,
      fromPeerId: senderPeerId,
      durationMs: durationMs,
      enc: true,
      encScheme: artifact.attachment.encryptionScheme,
    );
  }
}

/// 117 Session 4: copies the recorder temp into the durable owned media dir
/// (`media/<peer>/<blobId>.<ext>`) and persists a `done` attachment row so the
/// sender's voice note survives a failed relay upload + OS temp eviction.
///
/// Best-effort: requires [blobId] + a [mediaFileManager] + a
/// [mediaAttachmentRepo]; otherwise it degrades to the prior behavior. Never
/// throws into the send path — failures are logged and swallowed.
Future<void> _persistDurableVoiceCopyOnUploadFailure({
  required AudioRecording recording,
  required String targetPeerId,
  String? blobId,
  String? messageId,
  List<double>? waveform,
  MediaFileManager? mediaFileManager,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (blobId == null ||
      messageId == null ||
      mediaFileManager == null ||
      mediaAttachmentRepo == null) {
    return;
  }
  try {
    final source = File(recording.filePath);
    if (!source.existsSync()) return;

    final durableRelative =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: blobId,
          mime: recording.mime,
        );
    final durableAbsolute = await mediaFileManager.resolveStoredPath(
      durableRelative,
    );
    if (durableAbsolute != recording.filePath) {
      await mediaFileManager.copyToDurableStorage(
        sourceFilePath: recording.filePath,
        messageId: messageId,
        attachmentId: blobId,
        mime: recording.mime,
      );
    }

    // Persist as 'upload_pending' — NOT 'done'. 'done' is the
    // relay-blob-exists signal that retryIncompleteUploads keys on
    // (_resolveAttachmentsForRetry reuses 'done' attachments instead of
    // re-uploading); since the relay upload just FAILED, marking 'done' would
    // make a retry reference a blob that was never uploaded → permanent
    // "Media unavailable" on the recipient. 'upload_pending' keeps the row
    // re-uploadable while the durable local copy (absolute path, so the
    // retry's File(localPath).existsSync() check resolves it, and survives OS
    // temp eviction) keeps the sender's own message off the
    // done→pending→download→unavailable path (upload_pending is never flipped
    // by _resolveAttachmentForDisplay nor recovered by _recoverVisibleMedia).
    await mediaAttachmentRepo.saveAttachment(
      MediaAttachment(
        id: blobId,
        messageId: messageId,
        mime: recording.mime,
        size: recording.sizeBytes,
        mediaType: 'audio',
        durationMs: recording.durationMs,
        localPath: durableRelative,
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        waveform: waveform,
      ),
      owner: MediaOwnerLane.direct,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_DURABLE_COPY_ON_UPLOAD_FAILURE',
      details: {'blobId': blobId, 'storedPath': durableAbsolute},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_DURABLE_COPY_FAILED',
      details: {'error': e.toString()},
    );
  }
}
