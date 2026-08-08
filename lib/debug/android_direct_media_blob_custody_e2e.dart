import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/debug/android_direct_media_blob_custody_e2e_protocol.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

export 'package:flutter_app/core/debug/android_direct_media_blob_custody_e2e_protocol.dart';

const String _installedSimsBuildProfile = String.fromEnvironment(
  'SIMS_BUILD_PROFILE_ID',
);

typedef AndroidDirectMediaBlobCustodyProgressWriter =
    Future<void> Function(Map<String, Object?> progress);

/// Strict request accepted only by the selector-only Plan 347 APK.
final class AndroidDirectMediaBlobCustodyE2ERequest {
  const AndroidDirectMediaBlobCustodyE2ERequest({
    required this.role,
    required this.phase,
    required this.runId,
    required this.nonce,
    required this.contactPeerId,
    required this.messageId,
    required this.attachmentId,
    required this.fixtureIdentitySha256,
    required this.expectedCiphertextSha256,
    required this.timeout,
  });

  factory AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(
    Map<String, dynamic> config,
  ) {
    if (config['schema'] != androidDirectMediaBlobCustodyE2ERequestSchema ||
        config['transport_action'] != androidDirectMediaBlobCustodyE2EAction ||
        config['scenario'] != androidDirectMediaBlobCustodyE2EScenario ||
        config['buildProfile'] !=
            androidDirectMediaBlobCustodyE2EBuildProfile) {
      throw const FormatException('direct-media custody request rejected');
    }
    final role = _requiredToken(config, 'role', maxLength: 16);
    final phase = _requiredToken(config, 'phase', maxLength: 32);
    final validPhase = switch ((role, phase)) {
      (
        androidDirectMediaBlobCustodySenderRole,
        androidDirectMediaBlobCustodySenderPreparePhase,
      ) ||
      (
        androidDirectMediaBlobCustodySenderRole,
        androidDirectMediaBlobCustodySenderResumePhase,
      ) ||
      (
        androidDirectMediaBlobCustodyReceiverRole,
        androidDirectMediaBlobCustodyReceiverArmPhase,
      ) ||
      (
        androidDirectMediaBlobCustodyReceiverRole,
        androidDirectMediaBlobCustodyReceiverReopenPhase,
      ) => true,
      _ => false,
    };
    if (!validPhase) {
      throw const FormatException('direct-media custody role/phase rejected');
    }
    final runId = _requiredToken(config, 'runId', maxLength: 80);
    if (config['stepId'] !=
        androidDirectMediaBlobCustodyStepId(
          role: role,
          phase: phase,
          runId: runId,
        )) {
      throw const FormatException('direct-media custody step binding rejected');
    }
    final expectedHash = config['expectedCiphertextSha256'];
    final expectsHash =
        phase == androidDirectMediaBlobCustodySenderResumePhase ||
        phase == androidDirectMediaBlobCustodyReceiverReopenPhase;
    if (expectsHash != (expectedHash != null) ||
        (expectedHash != null && !_sha256.hasMatch('$expectedHash'))) {
      throw const FormatException(
        'direct-media custody expected hash rejected',
      );
    }
    final fixtureIdentity = config['fixtureIdentitySha256'];
    if (fixtureIdentity is! String || !_sha256.hasMatch(fixtureIdentity)) {
      throw const FormatException(
        'direct-media custody fixture binding rejected',
      );
    }
    final timeoutMs = ((config['timeoutMs'] as num?)?.toInt() ?? 180000)
        .clamp(30000, 240000)
        .toInt();
    return AndroidDirectMediaBlobCustodyE2ERequest(
      role: role,
      phase: phase,
      runId: runId,
      nonce: _requiredToken(config, 'nonce', maxLength: 128),
      contactPeerId: _requiredToken(config, 'contactPeerId', maxLength: 160),
      messageId: _requiredToken(config, 'messageId', maxLength: 160),
      attachmentId: _requiredToken(config, 'attachmentId', maxLength: 160),
      fixtureIdentitySha256: fixtureIdentity,
      expectedCiphertextSha256: expectedHash as String?,
      timeout: Duration(milliseconds: timeoutMs),
    );
  }

  final String role;
  final String phase;
  final String runId;
  final String nonce;
  final String contactPeerId;
  final String messageId;
  final String attachmentId;
  final String fixtureIdentitySha256;
  final String? expectedCiphertextSha256;
  final Duration timeout;

  bool get isSender => role == androidDirectMediaBlobCustodySenderRole;

  Map<String, Object?> receipt({
    required String status,
    required bool success,
    Map<String, Object?> fields = const <String, Object?>{},
  }) => <String, Object?>{
    'schema': androidDirectMediaBlobCustodyE2EEndpointResultSchema,
    'scenario': androidDirectMediaBlobCustodyE2EScenario,
    'buildProfile': androidDirectMediaBlobCustodyE2EBuildProfile,
    'role': role,
    'phase': phase,
    'stepId': androidDirectMediaBlobCustodyStepId(
      role: role,
      phase: phase,
      runId: runId,
    ),
    'runId': runId,
    'nonce': nonce,
    'fixtureIdentitySha256': fixtureIdentitySha256,
    'messageId': messageId,
    'attachmentId': attachmentId,
    'status': status,
    'success': success,
    ...fields,
  };
}

Map<String, Object?> androidDirectMediaBlobCustodyE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  final request = AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(config);
  return request.receipt(
    status: 'failed',
    success: false,
    fields: <String, Object?>{
      'errorType': error.runtimeType.toString(),
      'errorCode': _directMediaBlobCustodyFailureCode(error),
    },
  );
}

String _directMediaBlobCustodyFailureCode(Object error) {
  if (error is! StateError) return 'unexpected_error';
  return switch (error.message) {
    'restart did not reopen the exact sender generation' =>
      'sender_generation_reopen_refused',
    'restart sender authority is incomplete or crossed' =>
      'sender_authority_incomplete_or_crossed',
    'restart did not reopen byte-identical ciphertext' =>
      'sender_ciphertext_reopen_failed',
    'durable voice render source is absent after restart' =>
      'sender_render_source_absent',
    'restart did not complete the production voice send' =>
      'sender_production_send_failed',
    'restart envelope is not bound to the strict blob proof' =>
      'sender_envelope_binding_failed',
    'receiver did not persist the complete strict authority' =>
      'receiver_authority_not_observed',
    'receiver persisted a crossed strict commitment' =>
      'receiver_authority_crossed',
    'receiver strict download window expired' =>
      'receiver_download_window_expired',
    'production strict receiver download did not complete' =>
      'receiver_strict_download_failed',
    'receiver local commit is not durable' =>
      'receiver_local_commit_not_durable',
    'source-pinned ACK proof crossed the expiry boundary' =>
      'receiver_ack_expiry_crossed',
    'source-pinned ACK obligation did not retire' => 'receiver_ack_not_retired',
    _ => 'state_error',
  };
}

/// Bounded, durable facts proving that one sender envelope was atomically
/// bound to its exact v111 blob generation before accepted relay custody.
final class AndroidDirectMediaBlobCustodySenderBindingEvidence {
  const AndroidDirectMediaBlobCustodySenderBindingEvidence({
    required this.ciphertextSha256,
    required this.blobExpiresAtMs,
    required this.envelopeExpiresAtMs,
  });

  final String ciphertextSha256;
  final int blobExpiresAtMs;
  final int envelopeExpiresAtMs;
}

enum AndroidDirectMediaBlobCustodyReceiverAuthority {
  directOwner,
  pendingAckOwner,
  durableStrictCompletion,
}

/// One exact receiver-side authority observation.
///
/// [directOwner] carries the live v111 commitment that this action may hand to
/// the sole strict download owner. [pendingAckOwner] adopts an already-durable,
/// exact source-pinned ACK retry through that same owner.
/// [durableStrictCompletion] instead observes the production bootstrap owner
/// after its atomic local commit and v111 retirement. The latter does not claim
/// that this action's ACK callback ran; the campaign combines it with the
/// disposable fixture's protected 1 -> 0 transition before the sender's blob
/// expiry.
final class AndroidDirectMediaBlobCustodyReceiverEvidence {
  const AndroidDirectMediaBlobCustodyReceiverEvidence._({
    required this.authority,
    required this.attachment,
    required this.ciphertextSha256,
    required this.commitment,
  });

  final AndroidDirectMediaBlobCustodyReceiverAuthority authority;
  final MediaAttachment attachment;
  final String ciphertextSha256;
  final DirectMediaBlobCustodyCommitment? commitment;

  bool get requiresDirectOwner =>
      authority !=
      AndroidDirectMediaBlobCustodyReceiverAuthority.durableStrictCompletion;

  bool get strictLifecycleCompletionObserved =>
      authority ==
      AndroidDirectMediaBlobCustodyReceiverAuthority.durableStrictCompletion;
}

/// Classifies only the three strict receiver projections usable by the campaign.
///
/// A DB-hydrated attachment must never retain the wire-only `blobCustody`
/// projection. Before download, its one-way fingerprint must bind the exact
/// live v111 commitment. After bootstrap wins, the same strict fingerprint,
/// exact durable completion projection, and absence of v111 are observable;
/// the fixture supplies the external protected-blob retirement boundary.
AndroidDirectMediaBlobCustodyReceiverEvidence?
verifyAndroidDirectMediaBlobCustodyReceiverAuthority({
  required AndroidDirectMediaBlobCustodyE2ERequest request,
  required ConversationMessage? authoritativeParent,
  required List<MediaAttachment> attachments,
  required DirectMediaBlobCustodyRow? custodyRow,
  required int nowMs,
}) {
  if (request.role != androidDirectMediaBlobCustodyReceiverRole ||
      request.phase != androidDirectMediaBlobCustodyReceiverArmPhase ||
      authoritativeParent == null ||
      authoritativeParent.id != request.messageId ||
      !authoritativeParent.isIncoming ||
      authoritativeParent.contactPeerId != request.contactPeerId ||
      authoritativeParent.senderPeerId != request.contactPeerId ||
      authoritativeParent.status != 'delivered' ||
      authoritativeParent.transport != 'inbox' ||
      authoritativeParent.deletedAt != null ||
      authoritativeParent.hiddenAt != null ||
      authoritativeParent.directMediaCustodyIntentId != null ||
      authoritativeParent.privateMediaPolicy.requiresRedaction ||
      attachments.length != 1) {
    return null;
  }
  final attachment = attachments.single;
  final fingerprint = attachment.directMediaBlobCustodyFingerprint;
  final contentHash = attachment.contentHash;
  final exactAttachment =
      attachment.id == request.attachmentId &&
      attachment.messageId == request.messageId &&
      attachment.ownerLane == MediaOwnerLane.direct &&
      attachment.blobCustody == null &&
      attachment.size > 0 &&
      attachment.mime.trim().isNotEmpty &&
      attachment.hasEncryptionMetadata &&
      contentHash != null &&
      _sha256.hasMatch(contentHash) &&
      fingerprint != null &&
      _sha256.hasMatch(fingerprint);
  if (!exactAttachment) return null;

  if (custodyRow == null) {
    final path = attachment.localPath;
    if (attachment.downloadStatus != 'done' ||
        attachment.downloadRetryCount != 0 ||
        path == null ||
        path.isEmpty ||
        path != path.trim()) {
      return null;
    }
    return AndroidDirectMediaBlobCustodyReceiverEvidence._(
      authority: AndroidDirectMediaBlobCustodyReceiverAuthority
          .durableStrictCompletion,
      attachment: attachment,
      ciphertextSha256: contentHash,
      commitment: null,
    );
  }

  final expiry = custodyRow.expiresAtMs;
  final commitment = DirectMediaBlobCustodyCommitment(
    contentHash: custodyRow.contentHash,
    ciphertextSize: custodyRow.ciphertextSize,
    expiresAtMs: expiry ?? 0,
  );
  final exactRowIdentity =
      custodyRow.attachmentId == request.attachmentId &&
      custodyRow.messageId == request.messageId &&
      custodyRow.direction == DirectMediaBlobCustodyDirection.incoming &&
      expiry != null &&
      expiry > nowMs &&
      commitment.isValid &&
      contentHash == commitment.contentHash &&
      fingerprint ==
          computeDirectMediaBlobCommitmentFingerprint(
            attachmentId: attachment.id,
            commitment: commitment,
          );
  if (!exactRowIdentity) return null;
  if (custodyRow.state == DirectMediaBlobCustodyState.incomingAckPending) {
    final source = custodyRow.custodyRelayPeerId;
    final path = attachment.localPath;
    if (source == null ||
        source.isEmpty ||
        source != source.trim() ||
        attachment.downloadStatus != 'done' ||
        attachment.downloadRetryCount != 0 ||
        path == null ||
        path.isEmpty ||
        path != path.trim()) {
      return null;
    }
    return AndroidDirectMediaBlobCustodyReceiverEvidence._(
      authority: AndroidDirectMediaBlobCustodyReceiverAuthority.pendingAckOwner,
      attachment: attachment,
      ciphertextSha256: contentHash,
      commitment: commitment,
    );
  }
  if (custodyRow.state != DirectMediaBlobCustodyState.incomingCommitted ||
      custodyRow.custodyRelayPeerId != null ||
      attachment.downloadStatus == 'done' ||
      attachment.localPath != null) {
    return null;
  }
  return AndroidDirectMediaBlobCustodyReceiverEvidence._(
    authority: AndroidDirectMediaBlobCustodyReceiverAuthority.directOwner,
    attachment: attachment,
    ciphertextSha256: contentHash,
    commitment: commitment,
  );
}

/// Verifies the post-send authority rather than the returned attachment model.
///
/// `blobCustody` is intentionally wire-only and is absent after repository DB
/// hydration. The bound `outgoing_cleanup_pending` row is the durable success
/// witness: only exact v108 completion can delete the outbox owner and publish
/// that transition after recomputing the v111 manifest and expiry ceiling.
AndroidDirectMediaBlobCustodySenderBindingEvidence?
verifyAndroidDirectMediaBlobCustodySenderBinding({
  required AndroidDirectMediaBlobCustodyE2ERequest request,
  required String senderPeerId,
  required DirectMediaBlobCustodyRow beforeSend,
  required ConversationMessage? authoritativeParent,
  required List<DirectMediaBlobCustodyRow> afterSendRows,
  required bool retainedV108Owner,
}) {
  if (retainedV108Owner || afterSendRows.length != 1) return null;
  final afterSend = afterSendRows.single;
  final incarnation = afterSend.inboxCustodyIncarnationId;
  final relayPeerId = beforeSend.custodyRelayPeerId;
  final blobExpiry = beforeSend.expiresAtMs;
  final envelopeExpiry = authoritativeParent?.relayExpiresAt;
  final exactBefore =
      beforeSend.attachmentId == request.attachmentId &&
      beforeSend.messageId == request.messageId &&
      beforeSend.direction == DirectMediaBlobCustodyDirection.outgoing &&
      beforeSend.state == DirectMediaBlobCustodyState.outgoingStored &&
      beforeSend.inboxCustodyIncarnationId == null &&
      beforeSend.recipientPeerId == request.contactPeerId &&
      beforeSend.contentHash == request.expectedCiphertextSha256 &&
      beforeSend.ciphertextRelativePath != null &&
      blobExpiry != null &&
      blobExpiry > 0 &&
      relayPeerId != null &&
      relayPeerId.isNotEmpty &&
      relayPeerId.trim() == relayPeerId;
  final exactBoundCompletion =
      incarnation != null &&
      afterSend.attachmentId == beforeSend.attachmentId &&
      afterSend.messageId == beforeSend.messageId &&
      afterSend.direction == beforeSend.direction &&
      afterSend.state == DirectMediaBlobCustodyState.outgoingCleanupPending &&
      afterSend.recipientPeerId == beforeSend.recipientPeerId &&
      afterSend.ciphertextRelativePath == beforeSend.ciphertextRelativePath &&
      afterSend.custodyKind == beforeSend.custodyKind &&
      afterSend.custodyContract == beforeSend.custodyContract &&
      afterSend.contentHash == beforeSend.contentHash &&
      afterSend.ciphertextSize == beforeSend.ciphertextSize &&
      afterSend.transportMime == beforeSend.transportMime &&
      afterSend.expiresAtMs == beforeSend.expiresAtMs &&
      afterSend.custodyRelayPeerId == beforeSend.custodyRelayPeerId &&
      afterSend.retryCount == beforeSend.retryCount &&
      afterSend.lastAttemptAt == beforeSend.lastAttemptAt &&
      afterSend.nextAttemptAt == beforeSend.nextAttemptAt &&
      afterSend.createdAt == beforeSend.createdAt;
  final wireEnvelope = authoritativeParent?.wireEnvelope;
  final exactParent =
      authoritativeParent != null &&
      authoritativeParent.id == request.messageId &&
      !authoritativeParent.isIncoming &&
      authoritativeParent.contactPeerId == request.contactPeerId &&
      authoritativeParent.senderPeerId == senderPeerId &&
      authoritativeParent.status == 'inboxed' &&
      authoritativeParent.transport == 'inbox' &&
      authoritativeParent.directMediaCustodyIntentId == null &&
      wireEnvelope != null &&
      wireEnvelope.isNotEmpty &&
      wireEnvelope.trim() == wireEnvelope &&
      envelopeExpiry != null &&
      envelopeExpiry > 0 &&
      blobExpiry != null &&
      envelopeExpiry <= blobExpiry;
  if (!exactBefore || !exactBoundCompletion || !exactParent) return null;
  return AndroidDirectMediaBlobCustodySenderBindingEvidence(
    ciphertextSha256: afterSend.contentHash,
    blobExpiresAtMs: blobExpiry,
    envelopeExpiresAtMs: envelopeExpiry,
  );
}

/// Runs one phase inside the normal production dependency graph. No raw path,
/// relay identity, key, nonce material, or ciphertext is written to a receipt.
Future<Map<String, Object?>> runAndroidDirectMediaBlobCustodyE2EAction({
  required Map<String, dynamic> config,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required AudioRecorderService audioRecorderService,
  required AndroidDirectMediaBlobCustodyProgressWriter writeProgress,
  bool? isAndroidOverride,
  String? installedProfileOverride,
  Duration recordingDuration = const Duration(seconds: 2),
}) async {
  final request = AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(config);
  if ((installedProfileOverride ?? _installedSimsBuildProfile) !=
      androidDirectMediaBlobCustodyE2EBuildProfile) {
    throw StateError('direct-media custody E2E requires its selector-only APK');
  }
  if (!(isAndroidOverride ?? Platform.isAndroid)) {
    throw StateError('direct-media custody E2E requires Android');
  }
  final custodyRepository =
      mediaAttachmentRepo is DirectMediaBlobCustodyRepository
      ? mediaAttachmentRepo as DirectMediaBlobCustodyRepository
      : null;
  if (custodyRepository == null ||
      !custodyRepository.supportsDirectMediaBlobCustody) {
    throw StateError('direct-media custody repository is unavailable');
  }
  await _waitForProductionTransport(p2pService, request.timeout);
  if (request.isSender) {
    return request.phase == androidDirectMediaBlobCustodySenderPreparePhase
        ? _prepareSenderAndPause(
            request: request,
            p2pService: p2pService,
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            custodyRepository: custodyRepository,
            mediaFileManager: mediaFileManager,
            audioRecorderService: audioRecorderService,
            writeProgress: writeProgress,
            recordingDuration: recordingDuration,
          )
        : _resumeSender(
            request: request,
            p2pService: p2pService,
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            custodyRepository: custodyRepository,
            mediaFileManager: mediaFileManager,
          );
  }
  return request.phase == androidDirectMediaBlobCustodyReceiverArmPhase
      ? _armReceiver(
          request: request,
          p2pService: p2pService,
          bridge: bridge,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          custodyRepository: custodyRepository,
          mediaFileManager: mediaFileManager,
          writeProgress: writeProgress,
        )
      : _reopenReceiver(
          request: request,
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          custodyRepository: custodyRepository,
          mediaFileManager: mediaFileManager,
        );
}

Future<Map<String, Object?>> _prepareSenderAndPause({
  required AndroidDirectMediaBlobCustodyE2ERequest request,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required DirectMediaBlobCustodyRepository custodyRepository,
  required MediaFileManager mediaFileManager,
  required AudioRecorderService audioRecorderService,
  required AndroidDirectMediaBlobCustodyProgressWriter writeProgress,
  required Duration recordingDuration,
}) async {
  final identity = await identityRepo.loadIdentity();
  final contact = await contactRepo.getContact(request.contactPeerId);
  if (identity == null ||
      contact == null ||
      contact.mlKemPublicKey == null ||
      contact.mlKemPublicKey!.trim().isEmpty) {
    throw StateError('sender identity/contact is not ready');
  }
  if (!await audioRecorderService.hasPermission()) {
    throw StateError('RECORD_AUDIO was not pregranted');
  }

  File? recorderFile;
  try {
    await audioRecorderService.start(outputPath: '');
    await Future<void>.delayed(recordingDuration);
    final recorded = await audioRecorderService.stop();
    if (recorded == null ||
        recorded.durationMs < 1500 ||
        recorded.sizeBytes <= 0 ||
        recorded.mime != 'audio/mp4') {
      throw StateError('production recorder returned invalid media');
    }
    recorderFile = File(recorded.filePath);
    final storedPath = await mediaFileManager.copyToDurableStorage(
      sourceFilePath: recorded.filePath,
      messageId: request.messageId,
      attachmentId: request.attachmentId,
      mime: recorded.mime,
    );
    final uploadPath = await mediaFileManager.resolveStoredPath(storedPath);
    if (uploadPath != recorded.filePath && await recorderFile.exists()) {
      await recorderFile.delete();
      recorderFile = null;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final attachment = MediaAttachment(
      id: request.attachmentId,
      messageId: request.messageId,
      mime: recorded.mime,
      size: recorded.sizeBytes,
      mediaType: 'audio',
      durationMs: recorded.durationMs,
      localPath: storedPath,
      downloadStatus: 'upload_pending',
      createdAt: now,
    );
    final parent = ConversationMessage(
      id: request.messageId,
      contactPeerId: contact.peerId,
      senderPeerId: identity.peerId,
      text: '',
      timestamp: now,
      status: 'sending',
      isIncoming: false,
      createdAt: now,
      directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
        messageId: request.messageId,
        attachmentIds: <String>[request.attachmentId],
      ),
      media: <MediaAttachment>[attachment.copyWith(localPath: uploadPath)],
    );
    await messageRepo.saveMessage(parent);
    await mediaAttachmentRepo.saveAttachment(
      attachment,
      owner: MediaOwnerLane.direct,
    );

    final artifactStore = DirectMediaBlobArtifactStore();
    final pausingRepository = _PauseAfterStoredRepository(
      delegate: custodyRepository,
      onStored: (row) async {
        final path = row.ciphertextRelativePath;
        if (path == null ||
            row.expiresAtMs == null ||
            row.custodyRelayPeerId == null) {
          throw StateError('persisted strict upload proof is incomplete');
        }
        final artifact = await artifactStore.verifyOwnedArtifact(
          identityPeerId: identity.peerId,
          relativePath: path,
          expectedContentHash: row.contentHash,
          expectedCiphertextSize: row.ciphertextSize,
        );
        final strictCommitmentVerified = artifact != null;
        if (!strictCommitmentVerified) {
          throw StateError('persisted ciphertext failed exact verification');
        }
        await writeProgress(
          request.receipt(
            status: 'blob_stored',
            success: true,
            fields: <String, Object?>{
              'attachmentCount': 1,
              'ciphertextSha256': row.contentHash,
              'blobExpiresAtMs': row.expiresAtMs,
              'strictCommitmentVerified': strictCommitmentVerified,
            },
          ),
        );
        // The host must kill this process. Returning would allow v108 staging
        // in the same process and make the restart proof vacuous.
        await Completer<void>().future;
      },
    );
    final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
      repository: pausingRepository,
      artifactStore: artifactStore,
    );
    final recording = AudioRecording(
      filePath: uploadPath,
      durationMs: recorded.durationMs,
      mime: recorded.mime,
      sizeBytes: recorded.sizeBytes,
    );
    await sendVoiceMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: contact.peerId,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      recording: recording,
      bridge: bridge,
      recipientMlKemPublicKey: contact.mlKemPublicKey,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      messageId: request.messageId,
      timestamp: now,
      preassignedMessageIdIsFresh: true,
      blobId: request.attachmentId,
      directMediaBlobCustodyCoordinator: coordinator,
    );
    throw StateError('sender pause boundary returned unexpectedly');
  } finally {
    if (audioRecorderService.isRecording) {
      await audioRecorderService.cancel();
    }
    await audioRecorderService.dispose();
    if (recorderFile != null && await recorderFile.exists()) {
      await recorderFile.delete();
    }
  }
}

Future<Map<String, Object?>> _resumeSender({
  required AndroidDirectMediaBlobCustodyE2ERequest request,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required DirectMediaBlobCustodyRepository custodyRepository,
  required MediaFileManager mediaFileManager,
}) async {
  final identity = await identityRepo.loadIdentity();
  final contact = await contactRepo.getContact(request.contactPeerId);
  final parent = await messageRepo.getMessage(request.messageId);
  final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
    request.messageId,
    owner: MediaOwnerLane.direct,
  );
  final rows = await custodyRepository.loadDirectMediaBlobCustodyForMessage(
    request.messageId,
  );
  if (identity == null ||
      contact == null ||
      contact.mlKemPublicKey == null ||
      parent == null ||
      attachments.length != 1 ||
      rows.length != 1) {
    throw StateError('restart did not reopen the exact sender generation');
  }
  final attachment = attachments.single;
  final row = rows.single;
  if (attachment.id != request.attachmentId ||
      row.attachmentId != request.attachmentId ||
      row.state != DirectMediaBlobCustodyState.outgoingStored ||
      row.contentHash != request.expectedCiphertextSha256 ||
      row.expiresAtMs == null ||
      row.custodyRelayPeerId == null ||
      row.ciphertextRelativePath == null ||
      attachment.localPath == null ||
      attachment.durationMs == null) {
    throw StateError('restart sender authority is incomplete or crossed');
  }
  final artifactStore = DirectMediaBlobArtifactStore();
  final artifact = await artifactStore.verifyOwnedArtifact(
    identityPeerId: identity.peerId,
    relativePath: row.ciphertextRelativePath!,
    expectedContentHash: row.contentHash,
    expectedCiphertextSize: row.ciphertextSize,
  );
  if (artifact == null) {
    throw StateError('restart did not reopen byte-identical ciphertext');
  }
  final sourcePath = await mediaFileManager.resolveStoredPath(
    attachment.localPath!,
  );
  if (!await File(sourcePath).exists()) {
    throw StateError('durable voice render source is absent after restart');
  }
  final (result, sentMessage) = await sendVoiceMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: contact.peerId,
    senderPeerId: identity.peerId,
    senderUsername: identity.username,
    recording: AudioRecording(
      filePath: sourcePath,
      durationMs: attachment.durationMs!,
      mime: attachment.mime,
      sizeBytes: attachment.size,
    ),
    bridge: bridge,
    recipientMlKemPublicKey: contact.mlKemPublicKey,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
    messageId: request.messageId,
    timestamp: parent.timestamp,
    preassignedMessageIdIsFresh: true,
    blobId: request.attachmentId,
  );
  if (result != SendVoiceMessageResult.success || sentMessage == null) {
    throw StateError('restart did not complete the production voice send');
  }
  final inboxCustodyRepository =
      messageRepo is OutgoingDirectTextInboxCustodyRepository
      ? messageRepo as OutgoingDirectTextInboxCustodyRepository
      : null;
  final authoritativeParent = await messageRepo.getMessage(request.messageId);
  final afterSendRows = await custodyRepository
      .loadDirectMediaBlobCustodyForMessage(request.messageId);
  final retainedV108Owner =
      inboxCustodyRepository == null ||
      await inboxCustodyRepository.loadDirectInboxCustodyOwnerForMessageId(
            messageId: request.messageId,
          ) !=
          null;
  final evidence = verifyAndroidDirectMediaBlobCustodySenderBinding(
    request: request,
    senderPeerId: identity.peerId,
    beforeSend: row,
    authoritativeParent: authoritativeParent,
    afterSendRows: afterSendRows,
    retainedV108Owner: retainedV108Owner,
  );
  final strictCommitmentVerified = evidence != null;
  final envelopeExpiryWithinBlobBound =
      evidence != null &&
      evidence.envelopeExpiresAtMs > 0 &&
      evidence.envelopeExpiresAtMs <= evidence.blobExpiresAtMs;
  if (!strictCommitmentVerified || !envelopeExpiryWithinBlobBound) {
    throw StateError('restart envelope is not bound to the strict blob proof');
  }
  return request.receipt(
    status: 'complete',
    success: true,
    fields: <String, Object?>{
      'attachmentCount': 1,
      'ciphertextSha256': evidence.ciphertextSha256,
      'blobExpiresAtMs': evidence.blobExpiresAtMs,
      'envelopeExpiresAtMs': evidence.envelopeExpiresAtMs,
      'strictCommitmentVerified': strictCommitmentVerified,
    },
  );
}

Future<Map<String, Object?>> _armReceiver({
  required AndroidDirectMediaBlobCustodyE2ERequest request,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required DirectMediaBlobCustodyRepository custodyRepository,
  required MediaFileManager mediaFileManager,
  required AndroidDirectMediaBlobCustodyProgressWriter writeProgress,
}) async {
  final identity = await identityRepo.loadIdentity();
  if (identity == null) throw StateError('receiver identity is not ready');
  await writeProgress(request.receipt(status: 'armed', success: true));

  final deadline = DateTime.now().add(request.timeout);
  AndroidDirectMediaBlobCustodyReceiverEvidence? evidence;
  while (DateTime.now().isBefore(deadline)) {
    await p2pService.drainOfflineInbox();
    evidence = await _loadReceiverAuthorityEvidence(
      request: request,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      custodyRepository: custodyRepository,
    );
    if (evidence != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (evidence == null) {
    throw StateError('receiver did not persist the complete strict authority');
  }
  var ackSourcePinnedObserved = false;
  final directCommitment = evidence.commitment;
  if (evidence.requiresDirectOwner) {
    if (directCommitment == null) {
      throw StateError('receiver persisted a crossed strict commitment');
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw StateError('receiver strict download window expired');
    }
    final strictDownloadAckOwner = StrictDirectMediaBlobDownloadAckOwner(
      bridge: bridge,
      mediaAttachmentRepository: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      beforeSourcePinnedAck: (row) async {
        final source = row.custodyRelayPeerId;
        if (row.attachmentId != request.attachmentId ||
            row.messageId != request.messageId ||
            row.state != DirectMediaBlobCustodyState.incomingAckPending ||
            source == null ||
            source.isEmpty ||
            source != source.trim() ||
            row.contentHash != directCommitment.contentHash ||
            row.ciphertextSize != directCommitment.ciphertextSize ||
            row.expiresAtMs != directCommitment.expiresAtMs) {
          throw StateError('durable source-pinned ACK authority was crossed');
        }
        ackSourcePinnedObserved = true;
      },
    );
    await strictDownloadAckOwner.downloadAndAcknowledge(
      attachment: evidence.attachment.copyWith(blobCustody: directCommitment),
      contactPeerId: request.contactPeerId,
    );
    // The bootstrap owner may have won immediately before this call, or its
    // process-wide single-flight may have supplied the shared result. Reload
    // durable authority instead of attributing its ACK callback to this owner.
    evidence = await _waitForReceiverLifecycleCompletion(
      request: request,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      custodyRepository: custodyRepository,
      deadline: deadline,
    );
  }
  if (!evidence.strictLifecycleCompletionObserved) {
    throw StateError('production strict receiver download did not complete');
  }
  final completed = evidence.attachment;
  final relativePath = completed.localPath;
  final expectedRelativePath = mediaFileManager.relativePathForAttachment(
    contactPeerId: request.contactPeerId,
    blobId: request.attachmentId,
    mime: completed.mime,
  );
  if (relativePath == null || relativePath != expectedRelativePath) {
    throw StateError('receiver local commit is not durable');
  }
  final localPath = await mediaFileManager.resolveStoredPath(relativePath);
  final localFile = File(localPath);
  final durableLocalCommit =
      await localFile.exists() && await localFile.length() == completed.size;
  if (!durableLocalCommit) {
    throw StateError('receiver local commit is not durable');
  }
  final plaintextSha256 = await directMediaBlobCustodyE2EFileSha256(localFile);
  // When this action's owner won, prove its callback ran before exact expiry.
  // A bootstrap win deliberately leaves ackSourcePinned=false; the host derives
  // that claim from strictLifecycleCompletionObserved plus the fixture's
  // protected 1 -> 0 transition before the sender-reported blob expiry.
  if (ackSourcePinnedObserved &&
      (directCommitment == null ||
          DateTime.now().toUtc().millisecondsSinceEpoch >=
              directCommitment.expiresAtMs)) {
    throw StateError('source-pinned ACK proof crossed the expiry boundary');
  }
  return request.receipt(
    status: 'complete',
    success: true,
    fields: <String, Object?>{
      'attachmentCount': 1,
      'ciphertextSha256': evidence.ciphertextSha256,
      'plaintextSha256': plaintextSha256,
      'durableLocalCommit': durableLocalCommit,
      'ackSourcePinned': ackSourcePinnedObserved,
      'strictLifecycleCompletionObserved':
          evidence.strictLifecycleCompletionObserved,
    },
  );
}

Future<Map<String, Object?>> _reopenReceiver({
  required AndroidDirectMediaBlobCustodyE2ERequest request,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required DirectMediaBlobCustodyRepository custodyRepository,
  required MediaFileManager mediaFileManager,
}) async {
  final message = await messageRepo.getMessage(request.messageId);
  final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
    request.messageId,
    owner: MediaOwnerLane.direct,
  );
  final exact = attachments
      .where((item) => item.id == request.attachmentId)
      .toList(growable: false);
  if (message == null ||
      !message.isIncoming ||
      exact.length != 1 ||
      exact.single.downloadStatus != 'done' ||
      exact.single.localPath == null ||
      exact.single.contentHash != request.expectedCiphertextSha256) {
    throw StateError('receiver durable projection did not reopen exactly');
  }
  final localPath = await mediaFileManager.resolveStoredPath(
    exact.single.localPath!,
  );
  final file = File(localPath);
  final durableLocalCommit =
      await file.exists() && await file.length() == exact.single.size;
  if (!durableLocalCommit) {
    throw StateError('receiver durable bytes did not survive process restart');
  }
  final plaintextSha256 = await directMediaBlobCustodyE2EFileSha256(file);
  if (await custodyRepository.loadDirectMediaBlobCustodyForAttachment(
        request.attachmentId,
      ) !=
      null) {
    throw StateError('receiver ACK obligation survived successful ACK');
  }
  return request.receipt(
    status: 'complete',
    success: true,
    fields: <String, Object?>{
      'attachmentCount': 1,
      'ciphertextSha256': exact.single.contentHash,
      'plaintextSha256': plaintextSha256,
      'durableLocalCommit': durableLocalCommit,
    },
  );
}

Future<AndroidDirectMediaBlobCustodyReceiverEvidence?>
_loadReceiverAuthorityEvidence({
  required AndroidDirectMediaBlobCustodyE2ERequest request,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required DirectMediaBlobCustodyRepository custodyRepository,
}) async {
  final parent = await messageRepo.getMessage(request.messageId);
  final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
    request.messageId,
    owner: MediaOwnerLane.direct,
  );
  final row = await custodyRepository.loadDirectMediaBlobCustodyForAttachment(
    request.attachmentId,
  );
  return verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
    request: request,
    authoritativeParent: parent,
    attachments: attachments,
    custodyRow: row,
    nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
  );
}

Future<AndroidDirectMediaBlobCustodyReceiverEvidence>
_waitForReceiverLifecycleCompletion({
  required AndroidDirectMediaBlobCustodyE2ERequest request,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required DirectMediaBlobCustodyRepository custodyRepository,
  required DateTime deadline,
}) async {
  while (DateTime.now().isBefore(deadline)) {
    final evidence = await _loadReceiverAuthorityEvidence(
      request: request,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      custodyRepository: custodyRepository,
    );
    if (evidence?.strictLifecycleCompletionObserved ?? false) return evidence!;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('source-pinned ACK obligation did not retire');
}

final class _PauseAfterStoredRepository
    implements DirectMediaBlobCustodyRepository {
  const _PauseAfterStoredRepository({
    required this.delegate,
    required this.onStored,
  });

  final DirectMediaBlobCustodyRepository delegate;
  final Future<void> Function(DirectMediaBlobCustodyRow row) onStored;

  @override
  bool get supportsDirectMediaBlobCustody =>
      delegate.supportsDirectMediaBlobCustody;

  @override
  Future<T> runDirectMediaBlobCustodyLifecycle<T>(
    Future<T> Function() action,
  ) => delegate.runDirectMediaBlobCustodyLifecycle(action);

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) => delegate.stageOutgoingDirectMediaBlobGeneration(
    expectedParent: expectedParent,
    expectedAttachments: expectedAttachments,
    preparedAttachments: preparedAttachments,
    custodyRows: custodyRows,
  );

  @override
  Future<DirectMediaBlobCustodyRow?> loadDirectMediaBlobCustodyForAttachment(
    String attachmentId,
  ) => delegate.loadDirectMediaBlobCustodyForAttachment(attachmentId);

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) => delegate.loadDirectMediaBlobCustodyForMessage(messageId);

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) => delegate.loadDirectMediaBlobCustodyByStates(states, limit: limit);

  @override
  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    final transitioned = await delegate.transitionDirectMediaBlobCustodyIfExact(
      expected: expected,
      next: next,
    );
    if (transitioned &&
        expected.state == DirectMediaBlobCustodyState.outgoingPrepared &&
        next.state == DirectMediaBlobCustodyState.outgoingStored) {
      await onStored(next);
    }
    return transitioned;
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) => delegate.deleteDirectMediaBlobCleanupPendingIfExact(expected);
}

Future<void> _waitForProductionTransport(
  P2PService p2pService,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = p2pService.currentState;
    if (state.isStarted &&
        (state.listenAddresses.isNotEmpty ||
            state.circuitAddresses.isNotEmpty ||
            state.relayState == 'online')) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('production transport did not become ready');
}

String _requiredToken(
  Map<String, dynamic> config,
  String key, {
  required int maxLength,
}) {
  final value = config[key];
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    throw FormatException('direct-media custody request has invalid $key');
  }
  return value;
}

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

Future<String> directMediaBlobCustodyE2EFileSha256(File file) async {
  if (!await file.exists()) throw StateError('custody proof file is absent');
  return (await sha256.bind(file.openRead()).first).toString();
}
